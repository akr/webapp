#!/usr/bin/env ruby

require 'webapp'

count = 0 # This line runs once per process.

WebApp {|webapp|
  # This block runs once per request.
  webapp.puts <<"End"
pid: #$$
count: #{count}
End
  count += 1
}
