require 'net/http'
require 'json'

module Mech
  module Plugins
    module ETCD

      class << self
        def get(key, options={})
          res = make_request 'GET', get_path(key, options), [200,404]
          json = parse_response res

          if json.nil? || json.key?('errorCode')
            return nil
          elsif json.key?('node') && json['node']['dir']
            raise 'get does not support directories, use ls instead'
          else
            return json['node']['value']
          end
        end

        def ls(key, options={}, keys_only = false)
          res = make_request 'GET', get_path(key, options), [200,404]
          json = parse_response res

          if json.nil? || json.key?('errorCode')
            return []
          elsif json.key?('node') && json['node']['dir']
            # json['node']['nodes'].map { |k| k['key'] }
            return get_ls_result_recursive json['node']['nodes'], keys_only
          else
            raise 'ls only supports directories, use get instead'
          end
        end

        def get_ls_result_recursive(nodes, keys_only = false)
          if nodes.nil?
            return []
          else
            result = []
            nodes.each do |node|
              result << node['key'] unless keys_only && is_dir?(node)
              if is_dir? node
                result += get_ls_result_recursive node['nodes'], keys_only
              end
            end
            return result
          end
        end

        def set(key, value, options={})
          options['value'] = value.to_s.strip
          path = get_path key, options
          res = make_request 'PUT', path, [200,201]
          json = parse_response res
          return value
        end

        def make(key, value, options={})
          options['value'] = value
          options['prevExist'] = false
          path = get_path key, options
          res = make_request 'PUT', path, [201,412]
          json = parse_response res
          # return true only if the write succeeded
          if json.nil? || json.key?('errorCode')
            return false
          else
            return true
          end
        end

        def delete(key, options={})
          res = make_request 'DELETE', get_path(key, options), [200,404]
          # don't be bothered with the response
          return true
        end

        def watch(path)
          watch_reader, watch_writer = IO.pipe
          watch_url = "http://127.0.0.1:2379/v2/keys/#{path}?wait=true&recursive=true"
          watch_thread = Thread.new do
            begin
              next_index = ''
              while true
                begin
                  uri = URI.parse(watch_url + next_index)
                  response = Net::HTTP.get_response(uri)
                  if response.code == '200'
                    json = JSON.parse(response.body)

                    if json['node']
                      index = json['node']['modifiedIndex']
                      watch_writer.puts(json['node']['key'])
                    else
                      index = response['X-Etcd-Index'].to_i
                    end
                  elsif response.code == '400' && (json = JSON.parse(response.body))['message'] == "The event in requested index is outdated and cleared"
                    puts "++++++ Watching outdated changes, refreshing watch index"
                    index = response['X-Etcd-Index'].to_i
                  else
                    puts "++++++ ETCD Watch recieved non-200 response code: #{response.code}"
                    puts "++++++ Response body: #{response.body}"
                    raise 'Response code != 200'
                  end
                  next_index = "&waitIndex=#{index + 1}"
                rescue Net::ReadTimeout
                  puts "++++++ Timeout when watching for changes, retrying"
                rescue Exception => e
                  puts "++++++ Fatal: Something went wrong with etcd watch: #{e.message}"
                  break
                end
              end
            ensure
              puts "++++++ Closing write socket"
              watch_writer.close
            end
          end

          return watch_thread, watch_reader
        end

        private

        def is_dir?(node)
          node['dir'] && node['nodes']
        end

        def make_request(method, path, expected_codes)
          succeeded = false
          times = 0
          res = nil
          while !succeeded
            begin
              http ||= Net::HTTP.new('127.0.0.1', 2379)
              sleep [times, 10].min # sleep max ten seconds
              times += 1
              res = http.send_request(method, path)
              succeeded = expected_codes.include? res.code.to_i
              if times > 10
                break
              end
            rescue => e
              puts "#{e.message}"
            end
          end
          if !succeeded
            raise "Fatal: Cannot complete request - #{method} #{path}"
          end
          return res
        end

        def parse_response(res)
          JSON.parse(res.body)
        end

        def get_path(key, options = {})
          key = '/' + key unless key.start_with? '/'
          path = "/v2/keys" + key.chomp
          path += '?' + URI.encode_www_form(options) unless options.empty?
          return path
        end
      end

      class Watcher

        def initialize
          if @watch_thread
            puts '++++++ Error: etcd watcher process already started'
          else
            puts '++++++ Starting etcd watcher process'
            @watch_thread, @watch_reader = Mech::Plugins::ETCD.watch("signals/")
          end
        end

        def close
          if @watch_thread
            puts '++++++ Stopping etcd watcher'
            @watch_thread.kill
            @watch_reader.close
          end
        end

        def changes
          begin
            while IO.select([@watch_reader],[],[],0) # @watch_reader has readable changes
              etcd_change = @watch_reader.readline.chomp
              yield etcd_change
            end
          rescue EOFError => e # etcd watch is broken
            puts '++++++ Fatal: ETCD watch is broken'
            close
            puts '++++++ Exiting...'
            exit 1
          end
        end
      end

      module Utilities
        def set_value(key, value)
          Mech::Plugins::ETCD.set(key, value)
        end

        def set_constant(key, value)
          return !!(Mech::Plugins::ETCD.make(key, value) || value == Mech::Plugins::ETCD.get(key))
        end

        def get_value(key)
          Mech::Plugins::ETCD.get(key)
        end

        def delete_value(key)
          Mech::Plugins::ETCD.delete(key, {recursive: true})
        end

        def list_keys(key)
          Mech::Plugins::ETCD.ls(key)
        end

        def acquire_lock(key, value)
          puts "++++++ Attempting to acquire lock: #{key} -> #{value}"
          lock = Mech::Plugins::ETCD.make(key, value)
          if lock || value == Mech::Plugins::ETCD.get(key)
            puts "++++++ Successfully acquired lock: #{key} -> #{value}"
            return true
          else
            puts "++++++ Error: Could not acquire lock: #{key} -> #{value}"
            return false
          end
        end

        def release_lock(key)
          puts "++++++ Releasing lock: #{key}"
          Mech::Plugins::ETCD.delete(key)
          puts "++++++ Successfully released lock: #{key}"
        end

        def signal(key)
          puts "++++++ Signaling #{key}"
          Mech::Plugins::ETCD.set(key, true)
        end
      end
    end
  end
end