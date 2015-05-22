require_relative 'dsl/manager'
require_relative 'defaults'

module Mech
  class Manager
    HOST = `hostname`.chomp

    ID = "#{ENV['ID']}"
    if ID == nil || ID == ""
      puts '++++++ ERROR: COULD NOT READ ID FROM ENV'
      puts '++++++ EXITING...'
      exit 1
    end

    include Mech::Defaults
    include Mech::DSL

    def restart_worker
      $restart_worker = true
      if !worker_shutdown_procedure
        `docker stop #{TASK}-#{ID}-worker`
      end
      puts '++++++ Waiting for worker shutdown'
      _, $worker_exit = Process.wait($worker_process)
      worker_exited
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

      # puts "++++++ Aquiring lock for #{TASK}-#{ID}"
      # lock = `etcdctl mk /managers/#{TASK}/ids/#{ID} '#{HOST}'`.chomp
      # if lock != "#{HOST}" # Check if we could set the lock
      #   puts "++++++ ERROR: COULD NOT AQUIRE LOCK: /managers/#{TASK}/ids/#{ID}"
      #   puts '++++++ EXITING...'
      #   exit 1
      # end

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
        etcd_watcher = IO.popen("etcdctl -o json watch /signals/ --recursive --forever", "r:utf-8")
        while true

          begin
            _, $worker_exit = Process.waitpid2($worker_process, Process::WNOHANG)
          rescue SystemCallError
            puts '++++++ ERROR: WORKER PROCESS DOES NOT EXIST'
            raise
          end
          if $worker_exit
            worker_exited # Clean up config

            worker_exit_status = $worker_exit.exitstatus
            if worker_exit_status == 0
              puts '++++++ Worker task exited with status code 0'
              if task_completed? || !recover_worker # Stop if we completed our task, or if we cannot recover
                break
              end
            elsif worker_exit_status != nil
              puts "++++++ Error: Worker exited with status code: #{$worker_exit.exitstatus}"
              if !recover_worker
                break
              end
            elsif worker_exit.signaled?
              puts "++++++ Error: Worker got killed with signal: #{$worker_exit.to_i}"
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

          begin
            while IO.select([etcd_watcher],[],[],0) # etcd_watcher is readable
              etcd_line = etcd_watcher.readline
              begin
                etcd_json = JSON.parse(etcd_line)
                if etcd_json['node']
                  etcd_config_change(etcd_json['node']['key'])
                end
              rescue JSON::ParserError
                puts "++++++ Error: Invalid JSON from etcd watch: #{etcd_line}"
              end
            end
          rescue EOFError => e # etcd watch is broken
            puts '++++++ ERROR: ETCD WATCH IS BROKEN. EXITING'
            break
          end

          sleep(1)
        end
      ensure
        puts '++++++ Initiating shutdown sequence'
        if !$worker_exit && $worker_process
          puts '++++++ Killing worker process'
          if !worker_shutdown_procedure
            `docker stop #{TASK}-#{ID}-worker`
          end
          puts '++++++ Waiting for worker shutdown'
          Process.wait($worker_process)
          worker_exited
        end

        if etcd_watcher && !etcd_watcher.closed?
          puts '++++++ Killing etcd process'
          Process.kill('TERM', etcd_watcher.pid)
          puts '++++++ Waiting for etcd shutdown'
          etcd_watcher.close
        end

        puts "++++++ Releasing lock for #{TASK}-#{ID}"
        `etcdctl rm /managers/#{TASK}/ids/#{ID}`

        if worker_exit_status == 0 && task_completed?
          puts '++++++ Worker task completed. Exiting'
        else
          puts '++++++ Exiting'
        end
      end

      # TODO: Catch docker stop from parent and adjust exit status and message accordingly.
      puts '++++++ Unexpected termination. Exiting'
      exit 1
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
      options = configure_worker
      if !options.is_a?(Hash) || !options[:image]
        puts '++++++ Fatal: No image returned by configure_worker.'
        puts '++++++ Exiting...'
        exit 1
      end
      env = options[:env].map { |var,value| "-e #{var}=#{value} "}.join if options[:env]
      volumes = options[:volumes].map { |host,container| "-v #{host}:#{container} "}.join if options[:volumes]
      ports = options[:ports].map { |host,container| "-p #{host}:#{container} "}.join if options[:ports]
      hostname = "-h #{options[:hostname]} " if options[:hostname]
      `docker rm #{TASK}-#{ID}-worker 2>/dev/null`
      command = "docker run --rm #{env}#{volumes}#{ports}#{hostname}--name=#{TASK}-#{ID}-worker #{options[:image]}"
      puts "++++++ Starting worker process: #{command}"
      $worker_process = Process.spawn(command)
      sleep 1
      worker_started
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