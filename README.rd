= webapp - easy-to-use CGI/FastCGI/mod_ruby interface

== Features

* very easy-to-use API
* works under CGI, FastCGI and mod_ruby without modification
* path_info aware relative URI generation
* HTML form parameter varidation by HTML form

== How to Install

Just a single command as follows.

% ruby install.rb

To see the list of files to install: ruby install.rb -n

== Example

=== Hello World

The script follows works under CGI, FastCGI and mod_ruby without modification.

  require 'webapp'
  WebApp {|webapp|
    webapp.content_type = 'text/plain'
    webapp.puts "Hello World."
  }

== TODO

* session support
* file upload (multipart/form-data) support
* customizable cookie support

== Requirements

* Ruby 1.8
* htree 0.2
