module Mech
  module Defaults

    # This is called when a worker exits.
    # Clean up etcd configuration here.
    # Do not forget to bump the internal and external signals if needed.
    def worker_exited
    end


    # This is called when a worker is started.
    # Add etcd configuration here.
    # Do not forget to bump the internal and external signals if needed.
    def worker_started
    end

    # This is called when a worker wants to start.
    # It is expected to return:
    # - The image of the worker
    # - A hash with env variables to set {"variable" => "value"}
    # - A hash with the volumes to mount {"mountdir on host" => "mountpoint in container"}
    # - A hash with ports to bind {"port on host" => "port in container"}
    # - The name of the image to be started
    # Only the image name is not optional, all other options can be nil.
    def configure_worker
      return { image: task }
    end

    # This is called whenever a configuration changes in etcd.
    # The `etcd_key` parameter is a string of the key being changed in etcd.
    # Most likely you will check if this key is the internal signal for this task,
    # or an external signal for a dependency,
    # You may call `restart_worker` to restart the worker
    # You may also decide to `exit 0` here.
    def config_changed(key)
    end

    # If the worker needs a specific shutdown procedure, such as calling an exec command on the worker container
    # it can be performed here.
    # Return true if a custom shutdown procedure is performed here.
    # Return false if no custom procedure is run, the manager will fall back to simply trying to stop the container.
    def worker_shutdown_procedure
      puts "++++++ Stopping #{task}-#{id}-worker"
      `docker stop #{task}-#{id}-worker`
    end

    # This is called when the worker exits with code 0.
    # If this means the task is complete, return true.
    # If the task always needs to be restarted, return false.
    def task_completed?
      return false
    end
  end
end
