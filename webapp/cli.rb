# = webapp command line interface
#
# A web application using webapp has CLI (command line interface).
# You can invoke a webapp script from command line.
# There are two modes: client and server.
# In the client mode, the script processes a request which is specified as
# a command line arguments.
# In the server mode, the script works as a HTTP server which provides the web
# application.
#
#   xxx.cgi [options] [/path_info] [?query_string]
#       -h, --help                       show this message
#       -o, --output=FILE                set output file
#           --cern-meta                  output header as CERN httpd metafile
#           --server-name=STRING         set server name
#           --server-port=INTEGER        set server port number
#           --script-name=STRING         set script name
#           --remote-addr=STRING         set remote IP address
#           --header=NAME:BODY           set additional request header
#
#   xxx.cgi server [[hostname:]port]
#
# == client mode
#
# A webapp script should be invoked as follows in the client mode.
# 
#   xxx.cgi [options] [/path_info] [?query_string]
#
# For example, hello.cgi, as follows, can be invoked from command line.
#
#   % cat hello.cgi 
#   #!/usr/bin/env ruby
#   require 'webapp'
#   WebApp {|w| w.puts "Hello" }
#   % ./hello.cgi 
#   Status: 200 OK
#   Content-Type: text/plain
#   Content-Length: 6
#  
#   Hello
#
# webapp.rb can be used in command line directly as follows.
# This document use the form to make examples short. 
#
#   % ruby -rwebapp -e 'WebApp {|w| w.puts "Hello" }'
#   Status: 200 OK
#   Content-Type: text/plain
#   Content-Length: 6
#  
#   Hello
#
# The web application takes two optional argument: path info and query string.
# The optional first argument which begins with '/' is path info.
# The optional second argument which begins with '?' is query string.
# Since '?' is a shell meta character, it should be quoted.
#
#   % ruby -rwebapp -e '
#     WebApp {|w|
#       w.puts w.path_info
#       w.puts w.query_string
#     }' /a '?q'
#   Status: 200 OK
#   Content-Type: text/plain
#   Content-Length: 30
#  
#   /a
#   #<WebApp::QueryString: ?q>
#
# If the option -o is specified, a response is generated on the specified file.
# Note that the format is suitable for Apache mod_asis.
#
#   % ruby -rwebapp -e 'WebApp {|w| w.puts "Hello" }' -- -o ~/public_html/hello.asis
#   % cat ~/public_html/hello.asis 
#   Status: 200 OK
#   Content-Type: text/plain
#   Content-Length: 6
#
#   Hello
# 
# If the option --cern-meta is specified addition to -o,
# The header in the response is stored in separated file.
# Note that the format is suitable for Apache mod_cern_meta.
#
#   % ruby -rwebapp -e 'WebApp {|w| w.puts "Hello" }' -- --cern-meta -o ~/public_html/hello2.txt
#   % cat ~/public_html/.web/hello2.txt.meta 
#   Content-Type: text/plain
#   Content-Length: 6
#   % cat ~/public_html/hello2.txt 
#   Hello
#
# The options --server-name, --server-port, --script-name and --remote-addr specifies  
# information visible from web application.
# For example, WebApp#server_name returns a server name specified by --server-name.
#
#   % ruby -rwebapp -e 'WebApp {|w| w.puts w.server_name }'
#   Status: 200 OK
#   Content-Type: text/plain
#   Content-Length: 10
#  
#   localhost
#   % ruby -rwebapp -e 'WebApp {|w| w.puts w.server_name }' -- --server-name=www.example.org
#   Status: 200 OK
#   Content-Type: text/plain
#   Content-Length: 16
#
#   www.example.org
#
# The option --header specifies an additional request header.
# For example, specifying "Accept-Encoding: gzip" makes output gzipped.
#
#   % ruby -rwebapp -e 'WebApp {|w| w.puts "Hello"*100 }' -- --header='Accept-Encoding: gzip'|cat -v 
#   Status: 200 OK
#   Content-Type: text/plain
#   Content-Encoding: gzip
#   Content-Length: 31
#
#   ^_M-^K^H^@^O^VM-TA^@^CM-sHM-MM-IM-IM-w^X%F^RM-A^E^@ZTsDM-u^A^@^@
#
# == server mode
#
# A webapp script should be invoked as follows in the server mode.
#
#   xxx.cgi server [[hostname:]port]
#
# If _port_ is specified, the server listens the specified port.
# Otherwise, some non-used port is selected.
#
# If _hostname_ is specified, listening socket is bound to the specified hostname.
#
#   % ./hello.cgi server
#   http://hostname:38846/
#   [2005-02-19 10:29:26] INFO  WEBrick 1.3.1
#   [2005-02-19 10:29:26] INFO  ruby 1.9.0 (2005-02-17) [i686-linux]
#   [2005-02-19 10:29:26] INFO  WEBrick::HTTPServer#start: pid=9280 port=38846
#   ...
#
# In the server mode, the web application is located to the root ("/").
# I.e. WebApp#script_name returns "".
#

require 'optparse'

class WebApp
  class Manager
    # CLI (command line interface)
    def run_cli
      if ARGV[0] == 'server'
        ARGV.shift
        run_cli_server
      else
        run_cli_client
      end
    end

    def run_cli_server
      require 'webrick'
      config = {}
      case ARGV[0]
      when nil
        config = {
          :Port => TCPServer.open(0) {|s| s.addr[1] }
        }
      when /:(\d+)\z/
        config = {
          :ServerName => $`,
          :BindAddress => $`,
          :Port => $1.to_i
        }
      when /\A\d+\z/
        config = {
          :Port => ARGV[0].to_i
        }
      else
        raise ArgumentError, "unexpected port: #{ARGV[0].inspect}"
      end

      servlet = WEBrick::HTTPServlet::ProcHandler.new(run_webrick)
      Thread.current[:webrick_load_servlet] = nil

      top_uri = "http://"
      top_uri << (config[:BindAddress] || config[:ServerName] || WEBrick::Utils.getservername)
      top_uri << ":#{config[:Port]}" if config[:Port] != 80
      top_uri << '/'
      puts top_uri

      httpd = WEBrick::HTTPServer.new(config)
      trap(:INT){ httpd.shutdown }
      httpd.mount("/", servlet)
      httpd.start
      exit 0
    end

    def run_cli_client
      opt_output = '-'
      opt_cern_meta = false
      opt_server_name = 'localhost'
      opt_server_port = 80
      opt_script_name = "/#{File.basename($0)}"
      opt_remote_addr = '127.0.0.1'
      opt_headers = []
      ARGV.options {|q|
        q.banner = "#{File.basename $0} [options] [/path_info] [?query_string]"
        q.def_option('-h', '--help', 'show this message') { puts q; exit(0) }
        q.def_option('-o FILE', '--output=FILE', 'set output file') {|arg| opt_output = arg.untaint }
        q.def_option('--cern-meta', 'output header as CERN httpd metafile') { opt_cern_meta = true }
        q.def_option('--server-name=STRING', 'set server name') {|arg| opt_server_name = arg }
        q.def_option('--server-port=INTEGER', 'set server port number') {|arg| opt_server_port = arg.to_i }
        q.def_option('--script-name=STRING', 'set script name') {|arg| opt_script_name = arg }
        q.def_option('--remote-addr=STRING', 'set remote IP address') {|arg| opt_remote_addr = arg }
        q.def_option('--header=NAME:BODY', 'set additional request header') {|arg| opt_headers << arg.split(/:/, 2) }
        q.parse!
      } or exit(1)
      if ARGV[0] && %r{\A/} =~ ARGV[0]
        path_info = ARGV.shift
      end
      if ARGV[0] && %r{\A\?} =~ ARGV[0]
        ARGV.shift
        query_string = $'
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
        opt_headers.each {|name, body|
          req.header_object.add name, body
        }
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
