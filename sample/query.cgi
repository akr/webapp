#!/usr/bin/env ruby

require 'webapp'
require 'pathname'

Template = <<'End'
<html>
  <head>
    <title>query sample</title>
  </head>
  <body>
    <form action="q.cgi">
      Menu:
      <select name=menu multiple>
        <option selected>fish</option>
        <option>meet</option>
      </select>
      <input type=hidden name=form_submitted value=yes>
      <input type=submit>
    </form>
    <hr>
    <p>
      Since WebApp#validate_html_query validates a query
      according to a given form,
      impossible query such as <a href="q.cgi?menu=kusaya">kusaya</a> is
      ignored because WebApp#validate_html_query raises
      WebApp::QueryValidationFailure exception.
    </p>
    <div _if="q">
      <hr>
      <table border=1>
        <tr><th>name<th>value</tr>
        <tr _iter="q.each//key,val">
          <td _text=key>key<td _text=val>val</tr>
      </table>
    </div>
  </body>
</html>
End

WebApp {|webapp|
  begin
    q = webapp.validate_html_query(Template)
  rescue WebApp::QueryValidationFailure
    q = nil
  end

  webapp.content_type = 'text/html'
  HTree.expand_template(webapp) {Template}
}
