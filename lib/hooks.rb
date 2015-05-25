require_relative 'defaults'

module Mech
  class Hooks
    include Mech::Defaults

    def initialize(manager)
      @manager = manager
    end

    def method_missing(method_sym, *arguments, &block)
      if @manager.respond_to?(method_sym, false)
        @manager.send(method_sym, *arguments, &block)
      else
        super
      end
    end
  end
end