require_relative 'manager'

if $USE_ETCD
  require_relative 'plugins/etcd'
else
  require_relative 'watcher'
end

module Mech
  HOST = `hostname`.chomp
  ENVIRONMENT = ENV['ENVIRONMENT']
  ID = ENV['ID']

  def self.manager(task_name, id=nil, &definition)
    manager = Mech::Manager.new(task_name, id || ID)
    manager.hooks.instance_eval(&definition)

    # TODO: Start managers in a multithreaded way
    # Currently a manager loops until it exits the ruby process.
    # If we want to multithread things, managers will have to exit in less harmful way, 
    # and signal the other managers to shut down.
    manager.start
  end
end
