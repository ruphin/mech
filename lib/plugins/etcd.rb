require 'json'

module Mech
  module Plugins
    module ETCD

      class Watcher

        def initialize
          if @etcd_watcher
            puts '++++++ Error: etcd watcher process already started'
          else
            puts '++++++ Starting etcd watcher process'
            @etcd_watcher = IO.popen("etcdctl -o json watch /signals/ --recursive --forever", "r:utf-8")
          end
        end

        def close
          if @etcd_watcher && !@etcd_watcher.closed?
            puts '++++++ Stopping etcd watcher process'
            Process.kill('TERM', @etcd_watcher.pid)
            puts '++++++ Waiting for etcd watcher process to close'
            @etcd_watcher.close
            puts '++++++ ETCD watcher process closed succesfully'
          end
        end

        def changes
          begin
            while IO.select([@etcd_watcher],[],[],0) # etcd_watcher has readable changes
              etcd_line = @etcd_watcher.readline
              begin
                etcd_json = JSON.parse(etcd_line)
                if etcd_json['node']
                  yield etcd_json['node']['key']
                end
              rescue JSON::ParserError
                puts "++++++ Error: Invalid JSON from etcd watch: #{etcd_line}"
              end
            end
          rescue EOFError => e # etcd watch is broken
            puts '++++++ Fatal: ETCD watch is broken'
            puts '++++++ Exiting...'
            exit 1
          end
        end
      end

      module Utilities
        def aquire_lock(key, value)
          puts "++++++ Attempting to aquire lock: #{key} -> #{value}"
          lock = `etcdctl mk /managers/#{@task_name}/ids/#{@id} '#{value}'`.chomp
          if lock == "#{value}"
            puts "++++++ Successfully aquired lock: #{key} -> #{value}"
            return true
          else
            puts "++++++ Error: Could not aquire lock: #{key} -> #{value}"
            return false
          end
        end

        def release_lock(key, value)
          puts "++++++ Releasing lock: #{key}"
          if system('etcdctl rm /managers/#{@task_name}/ids/#{@id}')
            puts "++++++ Successfully released lock: #{key}"
            return true
          else
            puts "++++++ Error: Could not release lock: #{key}"
            return false
          end
        end

        def signal(key)
          puts "++++++ Signaling #{key}"
          `etcdctl set /signals/#{TASK} true`
        end
      end
    end
  end
end