require 'webrick'

class WebApp
  class WEBrickServletHandler
    LoadedServlets = {}
    def WEBrickServletHandler.get_instance(config, name)
      unless LoadedServlets[name]
        LoadedServlets[name] = load_servlet(name)
      end
      LoadedServlets[name]
    end

    def WEBrickServletHandler.load_servlet(path)
      begin
        Thread.current[:webrick_load_servlet] = true
        load path, true
        unless Thread.current[:webrick_load_servlet].respond_to? :call
          raise "WEBrick servlet is not registered: #{path}"
        end
        return WEBrick::HTTPServlet::ProcHandler.new(Thread.current[:webrick_load_servlet])
      ensure
        Thread.current[:webrick_load_servlet] = nil
      end
    end
  end
end
WEBrick::HTTPServlet::FileHandler.add_handler('webrick',
  WebApp::WEBrickServletHandler)

if $0 == __FILE__
  # usage: [-p port] [docroot|servlet]
  require 'optparse'
  port = 10080
  ARGV.options {|q|
    q.def_option('--help', 'show this message') {puts q; exit(0)}
    q.def_option('--port=portnum', 'specify server port') {|num| port = num.to_i }
    q.parse!
  }
  docroot = ARGV.shift || Dir.getwd
  if File.directory? docroot
    httpd = WEBrick::HTTPServer.new(:DocumentRoot => docroot, :Port => port)
    trap(:INT){ httpd.shutdown }
    httpd.start
  else
    servlet = WebApp::WEBrickServletHandler.load_servlet(docroot)
    httpd = WEBrick::HTTPServer.new(:Port => port)
    trap(:INT){ httpd.shutdown }
    httpd.mount("/", servlet)
    httpd.start
  end
end
