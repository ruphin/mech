module Mech
  module Storage

    # TODO: Make a basic etcd-like key value store
    STORE = {}

    class Watcher

      def initialize
        @@mutex ||= Mutex.new
        # TODO: configurable
        @path ||= 'signals'
        @cache ||= STORE
      end

      def close
        @path = nil
        @cache = nil
      end

      def changes
        # TODO
        # yield changes
      end
    end

    module Utilities
      def acquire_lock(key, value)
        if Mech::Storage::STORE[key]
          return false
        else
          Mech::Storage::STORE[key] = value
          return true
        end
      end

      def release_lock(key)
        Mech::Storage::STORE.delete(key)
        return true
      end
    end
  end
end