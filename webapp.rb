# Copyright (c) 2004, 2005, 2006 Tanaka Akira. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
#  1. Redistributions of source code must retain the above copyright notice, this
#     list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#  3. The name of the author may not be used to endorse or promote products
#     derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
# EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
# OF SUCH DAMAGE.

# = webapp.rb - unified web application interface for CGI, FastCGI mod_ruby and WEBrick.
#
# == Features
#
# * very easy-to-use API.
# * works under CGI, FastCGI and mod_ruby without modification.
# * works under WEBrick.
#   WEBrick based server must require "webapp/webrick-servlet", though.
#   link:files/webapp/webrick-servlet_rb.html
# * works as a standalone http server without modification
# * works as usual command (CLI) for debugging and static content generation.
#   link:files/webapp/cli_rb.html
#     script.cgi [options] [/path_info] [?query_string]
# * path_info aware relative URI generation.
# * HTML form parameter validation by HTML form. (sample/query.cgi)
# * automatic Content-Type generation.
# * a web application can be used as a web site with WEBrick.
#   (URL will be http://host/path_info?query.
#   No path component to specify a web application.)
#   link:files/webapp/webrick-servlet_rb.html
# * a response is gzipped automatically if the browser accepts.
# * Last-Modified: and If-Modified-Since: support for usual files.
#
# == Example
#
# Following script works as CGI(*.cgi), FastCGI(*.fcgi) and mod_ruby(*.rbx)
# without any modification.
# It also works as WEBrick servlet (*.webrick) if the WEBrick based server
# requires "webapp/webapp/webrick-servlet".
# It also works as usual command.
#
#   #!/path/to/ruby
#
#   require 'webapp'
#  
#   WebApp {|webapp|
#     webapp.puts <<"End"
#   current time: #{Time.now}
#   pid: #{$$}
#   self: #{self.inspect}
#   
#   request_method: #{webapp.request_method}
#   server_name: #{webapp.server_name}
#   server_port: #{webapp.server_port}
#   script_name: #{webapp.script_name}
#   path_info: #{webapp.path_info}
#   query_string: #{webapp.query_string}
#   server_protocol: #{webapp.server_protocol}
#   remote_addr: #{webapp.remote_addr}
#   content_type: #{webapp.content_type}
#   
#   --- request headers ---
#   End
#     webapp.each_request_header {|k, v|
#       webapp.puts "#{k}: #{v}"
#     }
#   }
#
# == recommended directory layout for web application
#
# I recommend following directory layout to develop a web application.
#
# * PROJECT/PROJECT.cgi         primary CGI
# * PROJECT/.htaccess           deny access except to *.cgi
# * PROJECT/config.yml.dist     sample configuration file
# * PROJECT/TEMPLATE.html       HTree template
# * PROJECT/PROJECT.rb          library entry file
# * PROJECT/PROJECT/SUBLIB.rb   library component
# * PROJECT/bin/COMMAND         runnable command
# * PROJECT/cgistub.erb         stub template
# * PROJECT/Makefile            stub generator
# * PROJECT/test-all.rb         test runner
# * PROJECT/test/test-XXXX.rb   unit test
#
# * PROJECT/config.yml          configuration file
# * PROJECT/cgi-bin/PROJECT.cgi stub file generated by cgistub.erb
#
# This layout is not so hierarchical.
# It is intended for ease-of-development. 
#
# Since the current directory of CGI process is initialized to
# the directory which contains the CGI script,
# PROJECT.cgi can require PROJECT.rb.
# It is because '.' is contained in a load path if ruby starts with $SAFE == 0,
# it is usual.
#

require 'pathname'
require 'htree'
require 'time'
require 'webapp/manager'
require 'webapp/urigen'
require 'webapp/htmlform'
require 'webapp/querystring'

class WebApp
  def initialize(manager, request, response) # :nodoc:
    @manager = manager
    @request = request
    @request_header = request.header_object
    @request_body = request.body_object
    @response = response
    @response_header = response.header_object
    @response_body = response.body_object
    @response_charset = nil
    @urigen = URIGen.new(@request.scheme,
      @request.server_name, @request.server_port,
      @request.script_name, @request.path_info)
  end

  def <<(str) @response_body << str end
  def print(*strs) @response_body.print(*strs) end
  def printf(fmt, *args) @response_body.printf(fmt, *args) end
  def putc(ch) @response_body.putc ch end
  def puts(*strs) @response_body.puts(*strs) end
  def write(str) @response_body.write str end
  def charset=(cs) @response_charset = cs end
  def charset() @response_charset end

  def each_request_header(&block) # :yields: field_name, field_body
    @request_header.each(&block)
  end
  def get_request_header(field_name) @request_header[field_name] end

  def request_method() @request.request_method end
  def server_name() @request.server_name end
  def server_port() @request.server_port end
  def script_name() @request.script_name end
  def path_info() @request.path_info end
  def query_string() @request.query_string end
  def server_protocol() @request.server_protocol end
  def remote_addr() @request.remote_addr end
  def request_content_type() @request.content_type end

  def set_header(field_name, field_body) @response_header.set(field_name, field_body) end
  def add_header(field_name, field_body) @response_header.add(field_name, field_body) end
  def remove_header(field_name) @response_header.remove(field_name) end
  def clear_header() @response_header.clear end
  def has_header?(field_name) @response_header.has?(field_name) end
  def get_header(field_name) @response_header[field_name] end
  def each_header(&block) # :yields: field_name, field_body
    @response_header.each(&block)
  end

  def content_type=(media_type)
    @response_header.set 'Content-Type', media_type
  end
  def content_type
    @response_header['Content-Type']
  end

  # returns a Pathname object.
  # _path_ is interpreted as a relative path from the directory
  # which a web application exists.
  #
  # If /home/user/public_html/foo/bar.cgi is a web application which
  # WebApp {} calls, webapp.resource_path("baz") returns a pathname points to
  # /home/user/public_html/foo/baz.
  #
  # _path_ must not have ".." component and must not be absolute.
  # Otherwise ArgumentError is raised.
  def resource_path(arg)
    path = Pathname.new(arg)
    raise ArgumentError, "absolute path: #{arg.inspect}" if !path.relative?
    path.each_filename {|f|
      raise ArgumentError, "path contains .. : #{arg.inspect}" if f == '..'
    }
    @manager.resource_basedir + path
  end

  # call-seq:
  #   open_resource(path)
  #   open_resource(path) {|io| ... }
  #
  # opens _path_ as relative from a web application directory.
  def open_resource(path, &block) 
    resource_path(path).open(&block)
  end

  # call-seq:
  #   send_resource(path)
  #
  # send the resource indicated by _path_.
  # Last-Modified: and If-Modified-Since: header is supported.
  def send_resource(path)
    path = resource_path(path)
    begin
      mtime = path.mtime
    rescue Errno::ENOENT
      @response.status_line = '404 Not Found'
      HTree.expand_template(@response_body) {<<'End'}
<html>
  <head><title>404 Not Found</title></head>
  <body>
    <h1>404 Not Found</h1>
    <p>Resource not found: <span _text="path"/></p>
  </body>
</html>
End
      return
    end
    check_last_modified(path.mtime) {
      path.open {|f|
        @response_body << f.read
      }
    }
  end

  def check_last_modified(last_modified)
    if ims = @request_header['If-Modified-Since'] and
       ((ims = Time.httpdate(ims)) rescue nil) and
       last_modified <= ims
      @response.status_line = '304 Not Modified'
      return
    end
    @response_header.set 'Last-Modified', last_modified.httpdate
    yield
  end

  # call-seq:
  #   reluri(:script=>string, :path_info=>string, :query=>query, :fragment=>string) -> URI
  #   make_relative_uri(:script=>string, :path_info=>string, :query=>query, :fragment=>string) -> URI
  # 
  # make_relative_uri returns a relative URI which base URI is the URI the
  # web application is invoked.
  #
  # The argument should be a hash which may have following components.
  # - :script specifies script_name relative from the directory containing
  #   the web application script.
  #   If it is not specified, the web application itself is assumed.
  # - :path_info specifies path_info component for calling web application.
  #   It should begin with a slash.
  #   If it is not specified, "" is assumed.
  # - :query specifies query a component.
  #   It should be a Hash or a WebApp::QueryString.
  # - :fragment specifies a fragment identifier.
  #   If it is not specified, a fragment identifier is not appended to
  #   the result URL.
  #
  # Since the method escapes the components properly,
  # you should specify them in unescaped form.
  #
  # In the example follow, assume that the web application bar.cgi is invoked
  # as http://host/foo/bar.cgi/baz/qux.
  #
  #   webapp.reluri(:path_info=>"/hoge") => URI("../hoge")
  #   webapp.reluri(:path_info=>"/baz/fuga") => URI("fuga")
  #   webapp.reluri(:path_info=>"/baz/") => URI("./")
  #   webapp.reluri(:path_info=>"/") => URI("../")
  #   webapp.reluri() => URI("../../bar.cgi")
  #   webapp.reluri(:script=>"funyo.cgi") => URI("../../funyo.cgi")
  #   webapp.reluri(:script=>"punyo/gunyo.cgi") => URI("../../punyo/gunyo.cgi")
  #   webapp.reluri(:script=>"../genyo.cgi") => URI("../../../genyo.cgi")
  #   webapp.reluri(:fragment=>"sec1") => URI("../../bar.cgi#sec1")
  #)
  #   webapp.reluri(:path_info=>"/h?#o/x y") => URI("../h%3F%23o/x%20y")
  #   webapp.reluri(:script=>"ho%o.cgi") => URI("../../ho%25o.cgi")
  #   webapp.reluri(:fragment=>"sp ce") => URI("../../bar.cgi#sp%20ce")
  #
  def make_relative_uri(hash={})
    @urigen.make_relative_uri(hash)
  end
  alias reluri make_relative_uri

  # calls WebApp#reluri using the webapp object currently processing. 
  def WebApp.reluri(hash={})
    WebApp.get_thread_webapp_object.reluri(hash)
  end

  # call-seq:
  #   make_absolute_uri(:script=>string, :path_info=>string, :query=>query, :fragment=>string) -> URI
  # 
  # make_absolute_uri returns a absolute URI which base URI is the URI of the
  # web application is invoked.
  #
  # The argument is same as make_relative_uri.
  def make_absolute_uri(hash={})
    @urigen.make_absolute_uri(hash)
  end

  # :stopdoc:
  StatusMessage = { # RFC 2616
    100 => 'Continue',
    101 => 'Switching Protocols',
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    203 => 'Non-Authoritative Information',
    204 => 'No Content',
    205 => 'Reset Content',
    206 => 'Partial Content',
    300 => 'Multiple Choices',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    305 => 'Use Proxy',
    307 => 'Temporary Redirect',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    402 => 'Payment Required',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    406 => 'Not Acceptable',
    407 => 'Proxy Authentication Required',
    408 => 'Request Timeout',
    409 => 'Conflict',
    410 => 'Gone',
    411 => 'Length Required',
    412 => 'Precondition Failed',
    413 => 'Request Entity Too Large',
    414 => 'Request-URI Too Long',
    415 => 'Unsupported Media Type',
    416 => 'Requested Range Not Satisfiable',
    417 => 'Expectation Failed',
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    505 => 'HTTP Version Not Supported',
  }
  # :startdoc:

  # setup_redirect makes a status line and a Location header appropriate as
  # redirection.
  #
  # _status_ specifies the status line.
  # It should be a Fixnum 3xx or String '3xx ...'.
  #
  # _uri_ specifies the Location header body.
  # It should be a URI, String or Hash.
  # If a Hash is given, make_absolute_uri is called to convert to URI.
  # If given URI is relative, it is converted as absolute URI.
  def setup_redirection(status, uri)
    case status
    when Fixnum
      if status < 300 || 400 <= status
        raise ArgumentError, "unexpected status: #{status.inspect}"
      end
      status = "#{status} #{StatusMessage[status]}"
    when String
      unless /\A3\d\d(\z| )/ =~ status
        raise ArgumentError, "unexpected status: #{status.inspect}"
      end
      if status.length == 3
        status = "#{status} #{StatusMessage[status.to_i]}"
      end
    else
      raise ArgumentError, "unexpected status: #{status.inspect}"
    end
    case uri
    when URI
      uri = @urigen.base_uri + uri if uri.relative?
    when String
      uri = URI.parse(uri)
      uri = @urigen.base_uri + uri if uri.relative?
    when Hash
      uri = make_absolute_uri(uri)
    else
      raise ArgumentError, "unexpected uri: #{uri.inspect}"
    end
    @response.status_line = status
    @response_header.set 'Location', uri.to_s
  end

  def query_html_get_application_x_www_form_urlencoded
    @request.query_string.decode_as_application_x_www_form_urlencoded
  end

  def query_html_post_application_x_www_form_urlencoded
    if /\Apost\z/i =~ @request.request_method # xxx: should not check?
      q = QueryString.primitive_new_for_raw_query_string(@request.body_object.read)
      q.decode_as_application_x_www_form_urlencoded
    else
      # xxx: warning?
      HTMLFormQuery.new
    end
  end

  class QueryValidationFailure < StandardError
  end
  def validate_html_query(form, form_id=nil)
    HTMLFormValidator.new(form, form_id).validate(self)
  end

  # :stopdoc:
  def WebApp.make_frozen_string(str)
    raise ArgumentError, "not a string: #{str.inspect}" unless str.respond_to? :to_str
    str = str.to_str
    str = str.dup.freeze unless str.frozen?
    str
  end

  LoadedWebAppProcedures = {}
  def WebApp.load_webapp_procedure(path)
    unless LoadedWebAppProcedures[path]
      begin
        Thread.current[:webapp_delay] = true
        load path, true
        LoadedWebAppProcedures[path] = Thread.current[:webapp_proc]
      ensure
        Thread.current[:webapp_delay] = nil
        Thread.current[:webapp_proc] = nil
      end
    end
    unless LoadedWebAppProcedures[path]
      raise RuntimeError, "not a web application: #{path}"
    end
    LoadedWebAppProcedures[path]
  end

  def WebApp.run_webapp_via_stub(path)
    if Thread.current[:webrick_load_servlet]
      load path, true
      return
    end
    WebApp.load_webapp_procedure(path).call
  end
  # :startdoc:
end

# WebApp is a main routine of web application.
# It should be called from a toplevel of a CGI/FastCGI/mod_ruby/WEBrick script.
#
# WebApp is used as follows.
#
#   #!/usr/bin/env ruby
#   
#   require 'webapp'
#   
#   ... class/method definitions ... # run once per process.
#   
#   WebApp {|webapp| # This block runs once per request.
#     ... process a request ...
#   }
#
# WebApp yields with an object of the class WebApp.
# The object contains request and response.
#
# WebApp rise $SAFE to 1.
#
# WebApp catches all kind of exception raised in the block.
# If HTTP connection is made from localhost or a developper host,
# the backtrace is sent back to the browser.
# Otherwise, the backtrace is sent to stderr usually which is redirected to
# error.log.
# The developper hosts are specified by the environment variable 
# WEBAPP_DEVELOP_HOST.
# It may be an IP address in dotted-decimal format such as "192.168.1.200" or
# an network address such as "192.168.1.200/24".
# (An environment variable for CGI can be set by SetEnv directive in Apache.)
#
def WebApp(&block) # :yields: webapp
  $SAFE = 1 if $SAFE < 1
  manager = WebApp::Manager.new(block)
  if defined?(Apache::Request) && Apache.request.kind_of?(Apache::Request)
    run = lambda { manager.run_rbx }
  elsif Thread.current[:webrick_load_servlet]
    run = lambda { manager.run_webrick }
  elsif STDIN.respond_to?(:stat) && STDIN.stat.socket? &&
        begin
          # getpeername(FCGI_LISTENSOCK_FILENO) causes ENOTCONN on FastCGI
          # cf. http://www.fastcgi.com/devkit/doc/fcgi-spec.html
          require 'socket'
          sock = Socket.for_fd(0)
          sock.getpeername
          false
        rescue Errno::ENOTCONN
          true
        rescue SystemCallError
          false
        end
    run = lambda { manager.run_fcgi }
  elsif ENV.include?('REQUEST_METHOD')
    run = lambda { manager.run_cgi }
  else
    require 'webapp/cli'
    run = lambda { manager.run_cli }
  end
  if Thread.current[:webapp_delay]
    Thread.current[:webapp_proc] = run
  else
    run.call
  end
end
