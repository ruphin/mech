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
      @hooks = Mech::Hooks.new(self)
      # TODO: a better way to do this
      if $USE_ETCD
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
      @restart_worker = true
      @hooks.worker_shutdown_procedure
      puts '++++++ Waiting for worker shutdown'
      _, @worker_exit = Process.wait(@worker_process)
      @hooks.worker_exited
      puts '++++++ Starting new worker in 5...'
      sleep 5 # Small timeout to allow configs to propagate
      start_worker
    end

    def start
      ####################################
      # Aquire the lock for this manager
      ##
      #
      # This attempts to set a specific value in etcd
      # If the value is already set, the lock cannot be aquired
      # In this case, exit with an error

      if !aquire_lock('/managers/#{@task_name}/ids/#{@id}', Mech::HOST)
        puts "++++++ Fatal: Could not aquire task lock with this id"
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
        start_worker
        while true

          begin
            _, @worker_exit = Process.waitpid2(@worker_process, Process::WNOHANG)
          rescue SystemCallError
            puts '++++++ ERROR: WORKER PROCESS DOES NOT EXIST'
            raise
          end
          if @worker_exit
            @hooks.worker_exited # Clean up config

            worker_exit_status = @worker_exit.exitstatus
            if worker_exit_status == 0
              puts '++++++ Worker task exited with status code 0'
              if @hooks.task_completed? || !recover_worker # Stop if we completed our task, or if we cannot recover
                break
              end
            elsif worker_exit_status != nil
              puts "++++++ Error: Worker exited with status code: #{@worker_exit.exitstatus}"
              if !recover_worker
                break
              end
            elsif @worker_exit.signaled?
              puts "++++++ Error: Worker got killed with signal: #{@worker_exit.to_i}"
              if !recover_worker
                break
              end
            else
              # This shouldn't happen, but it's here just in case
              puts '++++++ ERROR: WORKER EXITED WITH UNKNOWN REASON'
              if !recover_worker
                break
              end
            end
          end

          @config_watcher.changes do |change|
            @hooks.config_changed(change)
          end

          sleep(1)
        end
      ensure
        puts '++++++ Initiating shutdown sequence'
        if !@worker_exit && @worker_process
          puts '++++++ Killing worker process'
          @hooks.worker_shutdown_procedure
          puts '++++++ Waiting for worker shutdown'
          Process.wait(@worker_process)
          @hooks.worker_exited
        end

        @config_watcher.close

        puts "++++++ Releasing lock for #{@task_name}-#{@id}"
        if !release_lock("/managers/#{@task_name}/ids/#{@id}")
          puts '++++++ Error: Failed to release lock'
        end

        if worker_exit_status == 0 && @hooks.task_completed?
          puts '++++++ Worker task completed. Exiting'
        else
          puts '++++++ Exiting'
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
      end
      env = configuration[:env].map { |var,value| "-e #{var}=#{value} "}.join if configuration[:env]
      volumes = configuration[:volumes].map { |host,container| "-v #{host}:#{container} "}.join if configuration[:volumes]
      ports = configuration[:ports].map { |host,container| "-p #{host}:#{container} "}.join if configuration[:ports]
      hostname = "-h #{configuration[:hostname]} " if configuration[:hostname]
      `docker rm #{@task_name}-#{@id}-worker 2>/dev/null`
      command = "docker run --rm #{env}#{volumes}#{ports}#{hostname}--name=#{@task_name}-#{@id}-worker #{configuration[:image]}"
      puts "++++++ Starting worker process: #{command}"
      @worker_process = Process.spawn(command)
      sleep 1
      # TODO: Check if container didn't die during startup?
      @current_config = configuration
      @hooks.worker_started
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
  end
end