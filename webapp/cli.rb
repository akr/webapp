require 'optparse'
require 'optparse'

class WebApp
  class Manager
    # CLI (command line interface)
    def run_cli
      opt_output = '-'
      opt_cern_meta = false
      opt_server_name = 'localhost'
      opt_server_port = 80
      opt_script_name = "/#{File.basename($0)}"
      opt_remote_addr = '127.0.0.1'
      ARGV.options {|q|
        q.banner = "#{File.basename $0} [options] [/path_info] [?query_string]"
        q.def_option('-h', '--help', 'show this message') { puts q; exit(0) }
        q.def_option('-o FILE', '--output=FILE', 'set output file') {|arg| opt_output = arg.untaint }
        q.def_option('--cern-meta', 'output header as CERN httpd metafile') { opt_cern_meta = true }
        q.def_option('--server-name=STRING', 'set server name') {|arg| opt_server_name = arg }
        q.def_option('--server-port=INTEGER', 'set server port number') {|arg| opt_server_port = arg.to_i }
        q.def_option('--script-name=STRING', 'set script name') {|arg| opt_script_name = arg }
        q.def_option('--remote-addr=STRING', 'set remote IP address') {|arg| opt_remote_addr = arg }
        q.parse!
      }
      if path_info = ARGV.shift
        if %r{\A/} !~ path_info
          ARGV.unshift path_info
          path_info = nil
        end
      end
      if query_string = ARGV.shift
        if %r{\A\?} !~ query_string
          ARGV.unshift query_string
          query_string = nil
        end
      end
      if !ARGV.empty?
        raise "extra arguments: #{ARGV.inspect[1..-2]}"
      end
      path_info ||= ''
      query_string ||= ''
      setup_request = lambda {|req|
        req.make_request_header_from_cgi_env({
          'REQUEST_METHOD' => 'GET',
          'SERVER_NAME' => opt_server_name,
          'SERVER_PORT' => opt_server_port,
          'SCRIPT_NAME' => opt_script_name,
          'PATH_INFO' => path_info,
          'QUERY_STRING' => query_string,
          'SERVER_PROTOCOL' => 'HTTP/1.0',
          'REMOTE_ADDR' => opt_remote_addr,
          'CONTENT_TYPE' => ''
        })
      }
      output_response = lambda {|res|
        if opt_output == '-'
          res.output_cgi_status_field($stdout)
          res.output_message($stdout)
        else
          if opt_cern_meta
            dir = "#{File.dirname(opt_output)}/.web"
            begin
              Dir.mkdir dir
            rescue Errno::EEXIST
            end
            open("#{dir}/#{File.basename(opt_output)}.meta", 'w') {|f|
              #res.output_cgi_status_field(f)
              res.output_header(f)
            }
            open(opt_output, 'w') {|f|
              res.output_body(f)
            }
          else
            open(opt_output, 'w') {|f|
              res.output_cgi_status_field(f)
              res.output_message(f)
            }
          end
        end
      }
      primitive_run(setup_request, output_response)
    end
  end
end
