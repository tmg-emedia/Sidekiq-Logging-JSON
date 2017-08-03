require "sidekiq/logging/json/version"
require "sidekiq/logging/json"
require "sidekiq/logging"
require "json"

module Sidekiq
  module Logging
    module Json
      class Logger < Sidekiq::Logging::Pretty
        # Provide a call() method that returns the formatted message.
        def call(severity, time, program_name, message)
          matches = /^ *(\S+) JID-(.*)$/.match(context)
          if matches
            jid = matches[2]
            worker = matches[1]
          else
            jid = nil
            worker = nil
          end
          result = {
            '@timestamp' => time.utc.iso8601,
            '@fields' => {
              :pid => ::Process.pid,
              :tid => "#{Thread.current.object_id.to_s(36)}",
              :program_name => program_name,
              :worker => worker,
              :jid => jid
            },
            '@type' => 'sidekiq',
            '@status' => nil,
            '@severity' => severity,
            '@run_time' => nil,
          }
              
          pm = process_message message
          parsed_msg = pm['@message']
          pm.delete '@message'
          result = result.merge pm
          result['@fields'][:msg] = parsed_msg

          result.to_json + "\n"
        end

        def process_message(message)
          case message
          when Exception
            { '@status' => 'exception', '@message' => message.message }
          when Hash
            if message["retry"]
              {
                '@status' => 'retry',
                '@message' => "#{message['class']} failed, retrying with args #{message['args']}."
              }
            elsif message['class'] && message['args']
              {
                '@status' => 'dead',
                '@message' => "#{message['class']} failed with args #{message['args']}, not retrying."
              }
            else
              { '@message' => message }
            end
          else
            result = message.split(" ")
            status = result[0].match(/^(start|done|fail):?$/) || []

            {
              '@status' => status[1],                                   # start or done
              '@run_time' => status[1] && result[1] && result[1].to_f,  # run time in seconds
              '@message' => message
            }
          end
        end
      end
    end
  end
end
