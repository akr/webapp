#!/usr/bin/env ruby

require 'webapp'

WebApp {|request, response|
  response.content_type = 'text/plain'
  response.puts "Hello World."
}
