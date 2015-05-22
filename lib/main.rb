require_relative 'manager'

module Mech

  def self.manager(task, &definition)
    if !task
      puts '+++++++ Fatal: You must set a task name: Mech.manager(\'my-task\')'
      puts '+++++++ Exiting...'
      exit 1
    end

    Mech::Manager.const_set('TASK', task)
    Mech::Manager.class_eval(&definition)
    manager = Mech::Manager.new
    
    manager.start
  end
end
