#!/usr/bin/env ruby

require 'webapp'
require 'pathname'

WebApp {|webapp|
  q = webapp.validate_html_query(Pathname.new("query.html"))

  webapp.content_type = 'text/html'
  HTree.expand_template(webapp) {<<'End'}
<html>
  <head>
    <title>query sample</title>
  </head>
  <body>
    <table border=1>
      <tr><th>name<th>value
      <div _iter="q.each//key,val">
        <tr><td _text=key>key<td _text=val>val
      </div>
    </table>
  </body>
</html>
End
}
