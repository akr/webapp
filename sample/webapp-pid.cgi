#!/usr/bin/env ruby

require 'webapp'

count = 0
WebApp {|webapp|
  webapp.content_type = 'text/plain'
  webapp.puts <<"End"
pid: #$$
count: #{count}
End
  count += 1
}
