require 'json'
require_relative 'hooks'

module Mech
  class Manager

    def initialize(task_name=nil, id=nil)
      if !task_name
        puts '++++++ Fatal: You must assign a task name'
        puts '++++++ Mech.manager(\'my-task\')'
        puts '++++++ Exiting...'
        exit 1
      else
        @task_name = task_name
      end
      if id == nil || id == ""
        puts '++++++ Fatal: You must assign a task id'
        puts '++++++ Mech.manager(\'my-task\', id) OR start the container with an ID env variable'
        puts '++++++ Exiting...'
        exit 1
      else
        @id = id
      end
      if !ENVIRONMENT || ENVIRONMENT == ''
        puts '++++++ Warning: No environment set'
        puts '++++++ You should start this container with an \'ENVIRONMENT\' env variable'
        puts '++++++ Defaulting to \'production\''
        @environment = 'production'
      else
        @environment = ENVIRONMENT
      end

      @hooks = Mech::Hooks.new(self)
      # TODO: a better way to do this
      if $USE_ETCD
        require_relative 'plugins/etcd'
        @config_watcher = Mech::Plugins::ETCD::Watcher.new
        extend Mech::Plugins::ETCD::Utilities
      else
        @config_watcher = Mech::Storage::Watcher.new
        extend Mech::Storage::Utilities
      end
    end

    def task
      return @task_name
    end

    def id
      return @id
    end

    def hooks
      return @hooks
    end

    def restart_worker
      @worker_restarting = true
      @hooks.worker_shutdown_procedure
      sleep 2
      while (status = worker_status)[:running]
        puts '++++++ Waiting for worker shutdown'
        sleep 2
      end
      @hooks.worker_exited
      puts '++++++ Starting new worker in 5...'
      sleep 5 # Small timeout to allow configs to propagate
      start_worker
      @worker_restarting = false
    end

    def start
      ####################################
      # Acquire the lock for this manager
      ##
      #
      # This attempts to set a specific value in etcd
      # If the value is already set, the lock cannot be acquired
      # In this case, exit with an error

      if !acquire_lock("/managers/#{@task_name}/ids/#{@id}", Mech::HOST)
        puts "++++++ Fatal: Could not acquire task lock with this id"
        puts '++++++ Exiting...'
        exit 1
      end

      ####################################
      # Main loop
      ##
      #
      # Start a worker and an etcd watcher
      #
      # Whenever the worker exits, call the `worker_exited` hook to clean up configs.
      # An additional action is performed depending on exit status:
      # - Restart flag set true       => Restart the worker
      # - Exit with status code 0     => Check if this means task is complete so we can exit. If not, attempt to recover the worker
      # - Exit with status code not 0 => Attempt to recover the worker
      # - Worker was killed by signal => Attempt to recover the worker
      # - Other ??                    => Attempt to recover the worker
      #
      # When recovering the worker, we will attempt to restart it
      # If the worker has already recovered from failure within the last minute, exit with error
      #
      # Whenever the etcd watcher exits, exit manager with error


      begin # Main
        puts "++++++ STARTING MAIN"
        if !worker_status[:running]
          start_worker
        end

        while true

          worker = worker_status
          if worker[:exited]
            @hooks.worker_exited # Clean up config

            worker_exit_code = worker[:exit_code]
            if worker_exit_code == 0
              puts '++++++ Worker exited with exit code: 0'
              if @hooks.task_completed? || !recover_worker # Stop if we completed our task, or if we cannot recover
                break
              end
            else
              puts "++++++ Error: Worker exited with exit code: #{worker_exit_code}"
              if !recover_worker
                break
              end
            end
          end

          @config_watcher.changes do |change|
            @hooks.config_changed(change)
          end

          sleep 1
        end
      rescue SignalException => e
        puts "++++++ Received signal: #{e}"
        @external_shutdown = true
      rescue Mech::Plugins::ETCD::WatchException => e
        puts "++++++ ETCD watch failure"
        @keepalive_worker = true
      rescue => e
        puts '++++++ Fatal Exception'
        puts e.message
        puts e.backtrace.join("\n")
      ensure
        puts '++++++ Initiating shutdown sequence'

        if !@keepalive_worker && (status = worker_status)[:running]
          puts '++++++ Killing worker process'
          @hooks.worker_shutdown_procedure
          sleep 2
          while (status = worker_status)[:running]
            puts '++++++ Waiting for worker shutdown'
            sleep 2
          end
          @hooks.worker_exited
        end

        @config_watcher.close

        puts "++++++ Releasing lock for #{@task_name}-#{@id}"
        release_lock("/managers/#{@task_name}/ids/#{@id}")

        if !@external_shutdown
          if status[:exit_code] == 0 && @hooks.task_completed?
            puts '++++++ Worker task completed. Exiting'
            exit 0
          else
            puts '++++++ Exiting due to some failure'
            exit 1
          end
        end
      end
    end

    private

    ####################################
    # Start a worker
    ##
    #
    # This starts a new worker according to the configuration passed by `configure_worker`
    # If the worker is started, it calls the `worker_started` hook
    #
    # *NOTE*
    # THE DOCKER COMMAND MAY NOT CONTAIN ' OR " SYMBOLS
    # If it does, ruby will start the command with a `sh -c` wrapper, causing Process.kill to fail
    #
    def start_worker
      configuration = @hooks.configure_worker
      if !configuration.is_a?(Hash) || !configuration[:image]
        puts '++++++ Fatal: No image returned by configure_worker.'
        puts '++++++ Exiting...'
        exit 1
      elsif !configuration[:image].include?(':')
        configuration[:image] += ":#{@environment}"
      end
      (configuration[:env] ||= {})['ENVIRONMENT'] = @environment
      env =        configuration[:env].map { |var,value| "-e #{var}='#{value}' "}.join
      volumes =   (configuration[:volumes] || {}).map { |host,container| "-v #{host}:#{container} "}.join
      ports =     (configuration[:ports] || {}).map { |host,container| "-p #{host}:#{container} "}.join
      hostname =   configuration[:hostname] ? "-h #{configuration[:hostname]} " : "-h #{task}-#{id} "
      flags =     (configuration[:flags] || {}).map { |flag, value| value ? "--#{flag}=#{value} " : "--#{flag} "}.join
      image =      configuration[:image]
      command =    configuration[:command]
      arguments = (configuration[:arguments] || []).join(' ')
      name = "#{task}-#{id}"
      `docker rm -v #{name} 2>/dev/null`
      `docker pull #{image} 2>&1 2>/dev/null`
      command = "docker run --log-driver=syslog --log-opt syslog-tag=#{name} -d #{flags}#{env}#{volumes}#{ports}#{hostname}--name=#{name} #{image} #{command} #{arguments}"
      puts "++++++ Starting worker process: #{command}"
      `#{command}`

      count = 1
      while (status = worker_status; status[:exists] == false && status[:started] == false)
        puts "++++++ Waiting for worker #{name} to start"
        count += 1
        if count > 10 # Waited over 65 seconds
          puts "++++++ Fatal: Worker #{name} won't start"
          exit 1
        end
        sleep count
      end

      if status[:running] == true
        puts "++++++ Worker #{name} started successfully"
        @current_config = configuration
        @hooks.worker_started
      elsif status[:exited] == true
        puts "++++++ Worker #{name} exited prematurely with exit code: #{status[:exit_code]}"
        sleep 5 # Sleep for a short period to avoid restarting immediately
        recover_worker
      else
        puts "++++++ Fatal: Worker #{name} failed to start coherently"
        exit 1
      end
    end

    def recover_worker
      puts '++++++ Attempting to recover worker'
      time_now = Time.now
      if @last_recovery && (@last_recovery + 60 > time_now) # Already performed a recovery in the last minute
        puts '++++++ Fatal: Worker task failed too often.'
        puts '++++++ Exiting...'
        return false
      else
        puts '++++++ Restarting worker'
        @last_recovery = Time.now
        start_worker
      end
      return true
    end

    def worker_status
      name = "#{task}-#{id}"
      status_json = `docker inspect --format '{{ json .State }}' #{name} 2>/dev/null`
      begin
        status = JSON.parse(status_json)
      rescue JSON::ParserError
        puts "++++++ Could not parse worker status"
        return {
          exists: false
        }
      end
      if status['StartedAt'] == '0001-01-01T00:00:00Z'
        # Container is being created, but has not been started
        return {
          exists: true,
          started: false
        }
      elsif status['Running']
        return {
          exists: true,
          started: true,
          running: true,
        }
      elsif status['Running'] == false && status['FinishedAt'] != '0001-01-01T00:00:00Z'
        return {
          exists: true,
          started: true,
          exited: true,
          exit_code: status['ExitCode']
        }
      else
        puts "++++++ Fatal: Incoherent status result for #{name}"
        puts "++++++ Status: #{status_json}"
        exit 1
      end
    end
  end
end