require 'webrick'

class WebApp
  class WEBrickServletHandler < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, name)
      super
      @name = name
    end

    LoadedServlets = {}
    def load_servlet(name)
      unless LoadedServlets[name]
        begin
          Thread.current[:webrick_load_servlet] = true
          load @name, true
          if Thread.current[:webrick_load_servlet].respond_to? :call
            LoadedServlets[name] = Thread.current[:webrick_load_servlet]
          end
        ensure
          Thread.current[:webrick_load_servlet] = nil
        end
        unless LoadedServlets[name]
          raise "WEBrick servlet is not registered: #{path}"
        end
      end
      LoadedServlets[name]
    end

    def do_GET(req, res)
      load_servlet(@name).call(req, res)
    end
    alias do_POST do_GET
  end

end
WEBrick::HTTPServlet::FileHandler.add_handler('webrick',
  WebApp::WEBrickServletHandler)

if $0 == __FILE__
  httpd = WEBrick::HTTPServer.new(:DocumentRoot => ".", :Port => 10080)
  trap(:INT){ httpd.shutdown }
  httpd.start
end
