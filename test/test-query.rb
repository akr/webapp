require 'test/unit'
require 'webapp'

class HTMLFormQueryTest < Test::Unit::TestCase
  def webapp_test(env, content='', &block)
    manager = WebApp::Manager.new(Object, block)
    setup_request = lambda {|req|
      req.make_request_header_from_cgi_env(env)
      req.body_object << content
    }
    response = nil
    output_response = lambda {|res|
      response = res
    }
    manager.primitive_run(setup_request, output_response)
    response
  end

  def d(str)
    q = WebApp::QueryString.primitive_new_for_raw_query_string(str)
    q.decode_as_application_x_www_form_urlencoded
  end

  def test_decode_x_www_form_urlencoded
    assert_equal("b", d("a=b")["a"])
  end

  def test_query_string_new
    assert_raise(NoMethodError) {
      WebApp::QueryString.new("")
    }
  end

  def test_extract_html_form
    extract1 = lambda {|form_string|
      WebApp::HTMLFormValidator.allocate.extract_html_form_tree(form_string)
    }
    extract2 = lambda {|form_string, id|
      WebApp::HTMLFormValidator.allocate.extract_html_form_tree(form_string, id)
    }

    form_string = <<'End'
<form id=form1 tst=1>
</form>
<form id=form2 tst=2>
</form>
End
    form = extract1.call(form_string)
    assert_equal('form', form.name)
    assert_equal('1', form.get_attr('tst'))
    assert_equal('1', extract2.call(form_string, 'form1').get_attr('tst'))
    assert_equal('2', extract2.call(form_string, 'form2').get_attr('tst'))

    form_string = <<'End'
<form name=form1 tst=1>
</form>
<form name=form2 tst=2>
</form>
End
    form = extract1.call(form_string)
    assert_equal('form', form.name)
    assert_equal('1', form.get_attr('tst'))
    assert_equal('1', extract2.call(form_string, 'form1').get_attr('tst'))
    assert_equal('2', extract2.call(form_string, 'form2').get_attr('tst'))

    form_string = <<'End'
<html>
  <form name=f>
  </form>
</html>
End
    form = extract1.call(form_string)
    assert_equal('f', form.get_attr('name'))
    assert_equal('{http://www.w3.org/1999/xhtml}form', form.name)
  end

  def test_extract_html_form_validation_info
    e = lambda {|form|
      v = WebApp::HTMLFormValidator.allocate
      v.extract_html_form_controls(v.extract_html_form_tree(form)).first
    }
    assert_equal([], e.call('<form></form>'))
    assert_equal([], e.call('<form><input type=text></form>'))
    assert_equal([{:elem=>:input, :type=>'text', :name=>'n', :value=>'', :disabled=>nil, :readonly=>nil, :maxlength=>nil}],
      e.call('<form><input name=n></form>'))
    assert_equal([{:elem=>:input, :type=>'text', :name=>'n', :value=>'', :disabled=>nil, :readonly=>nil, :maxlength=>3}],
      e.call('<form><input type=text name=n maxlength=3></form>'))
    assert_equal([{:elem=>:input, :type=>'password', :name=>'n', :value=>'', :maxlength=>nil, :disabled=>nil, :readonly=>nil}],
      e.call('<form><input type=password name=n></form>'))
    assert_equal([{:elem=>:input, :type=>'checkbox', :name=>'n', :value=>'v', :disabled=>nil, :checked=>nil}],
      e.call('<form><input type=checkbox name=n value=v></form>'))
    assert_equal([{:elem=>:input, :type=>'radio', :name=>'n', :value=>'v', :disabled=>nil, :checked=>nil}],
      e.call('<form><input type=radio name=n value=v></form>'))
    assert_equal([{:elem=>:input, :type=>'submit', :name=>'n', :value=>'v', :disabled=>nil}],
      e.call('<form><input type=submit name=n value=v></form>'))
    assert_equal([],
      e.call('<form><input type=reset name=n></form>'))
    #assert_equal([{:elem=>:input, :type=>'file', :name=>'n', :value=>nil, :disabled=>nil, :accept=>nil}],
    #  e.call('<form><input type=file name=n></form>'))
    assert_equal([{:elem=>:input, :type=>'hidden', :name=>'n', :value=>'v', :disabled=>nil}],
      e.call('<form><input type=hidden name=n value=v></form>'))
    assert_equal(
      [{:elem=>:input, :type=>'image-x', :name=>'n.x', :value=>nil, :disabled=>nil},
       {:elem=>:input, :type=>'image-y', :name=>'n.y', :value=>nil, :disabled=>nil},
       {:elem=>:input, :type=>'image', :name=>'n', :value=>nil, :disabled=>nil}],
      e.call('<form><input type=image name=n></form>'))
    assert_equal([{:elem=>:input, :type=>'button', :name=>'n', :value=>'v', :disabled=>nil}],
      e.call('<form><input type=button name=n value=v></form>'))
    select = {:elem=>:select, :name=>'n', :multiple=>nil, :disabled=>nil}
    assert_equal([
      {:elem=>:option, :name=>'n', :select=>select, :disabled=>nil, :value=>"v1"},
      {:elem=>:option, :name=>'n', :select=>select, :disabled=>nil, :value=>"v2"}],
      e.call('<form><select name=n><option value=v1><option>v2</select></form>'))
    assert_equal([{:elem=>:textarea, :name=>'n', :disabled=>nil, :readonly=>nil}],
      e.call('<form><textarea name=n>aaa</textarea></form>'))
    assert_equal([{:elem=>:textarea, :name=>'n', :disabled=>nil,
      :readonly=>"readonly", :value=>HTree::Text.new("aaa")}],
      e.call('<form><textarea name=n readonly>aaa</textarea></form>'))
    assert_equal([{:elem=>:button, :name=>'n', :value=>nil, :type=>"submit", :disabled=>nil}],
      e.call('<form><button name=n></form>'))
  end

  def query_string_test(query_string, &block)
    env = {}
    env['REQUEST_METHOD'] = 'GET'
    env['SERVER_NAME'] = 'test-servername'
    env['SERVER_PORT'] = '80'
    env['SCRIPT_NAME'] = '/test-scriptname'
    env['PATH_INFO'] = '/test-pathinfo'
    env['QUERY_STRING'] = query_string
    env['SERVER_PROTOCOL'] = 'HTTP/1.0'
    env['REMOTE_ADDR'] = '127.0.0.1'
    env['CONTENT_TYPE'] = ''
    webapp_test(env, &block)
  end

  def validate(query_string, form)
    exc = nil
    query_string_test(query_string) {|webapp|
      begin
        return webapp.validate_html_query(form)
      rescue Exception
        exc = $!
      end
    }
    raise exc
  end

  ValFail = WebApp::QueryValidationFailure

  def test_html_form_validation_text
    form = '<form><input type=text name="n"></form>'
    q = validate('n=xxx', form)
    assert_equal(["n"], q.keys)
    assert_equal("xxx", q['n'])
    assert_raises(ValFail) { validate('', form) }
    assert_raises(ValFail) { validate('q=v', form) }
    form = '<form><input type=text name="n" maxlength=3></form>'
    q = validate('n=abc', form)
    assert_equal("abc", q['n'])
    assert_raises(ValFail) { validate('n=abcd', form) }
    form = '<form><input type=text name="n" readonly></form>'
    q = validate('n=', form)
    assert_equal("", q['n'])
    assert_raises(ValFail) { validate('n=a', form) }
    form = '<form><input type=text name="n" disabled></form>'
    assert_equal([], validate('', form).keys)
    assert_raises(ValFail) { validate('n=a', form) }
  end

  def test_html_form_validation_checkbox
    form = <<'End'
<form>
<input type=checkbox name="n" value="a">
<input type=checkbox name="n" value="b">
</form>
End
    q = validate('', form)
    assert_equal([], q.keys)
    q = validate('n=a', form)
    assert_equal(['n'], q.keys)
    assert_equal(["a"], q.lookup_all('n'))
    q = validate('n=b', form)
    assert_equal(['n'], q.keys)
    assert_equal(["b"], q.lookup_all('n'))
    q = validate('n=a&n=b', form)
    assert_equal(['n'], q.keys)
    assert_equal(["a", "b"], q.lookup_all('n'))
    q = validate('n=b&n=a', form)
    assert_equal(['n'], q.keys)
    assert_equal(["b", "a"], q.lookup_all('n'))
    assert_raises(ValFail) { validate('n=c', form) }
    assert_raises(ValFail) { validate('n=a&n=c', form) }
  end

  def test_html_form_validation_radio
    form = <<'End'
<form>
<input type=radio name="n" value="a">
<input type=radio name="n" value="b">
<input type=radio name="n" value="c">
<input type=radio name="m" value="d">
<input type=radio name="m" value="e">
<input type=radio name="m" value="f">
</form>
End

    q = validate('', form)
    assert_equal([], q.keys)
    q = validate('n=a', form)
    assert_equal(['n'], q.keys)
    assert_equal(["a"], q.lookup_all('n'))
    q = validate('n=b', form)
    assert_equal(['n'], q.keys)
    assert_equal(["b"], q.lookup_all('n'))
    q = validate('n=c', form)
    assert_equal(['n'], q.keys)
    assert_equal(["c"], q.lookup_all('n'))
    assert_raises(ValFail) { validate('n=a&n=b', form) }
    assert_raises(ValFail) { validate('n=a&n=c', form) }
    assert_raises(ValFail) { validate('n=b&n=c', form) }
    assert_raises(ValFail) { validate('n=a&n=b&n=c', form) }
    assert_raises(ValFail) { validate('n=d', form) }
    q = validate('n=a&m=d', form)
    assert_equal(['n', 'm'], q.keys)
    assert_equal(["a"], q.lookup_all('n'))
    assert_equal(["d"], q.lookup_all('m'))
    form = <<'End'
<form>
<input type=radio name="n" value="a" checked>
<input type=radio name="n" value="b">
</form>
End
    assert_raises(ValFail) { validate('', form) }
  end

  def test_html_form_validation_submit
    form = <<'End'
<form>
<input type=submit name="n" value="a">
<input type=image name="m">
<button type=submit name="l" value="b">SUBMIT</button>
</form>
End
    assert_raises(ValFail) { validate('', form) }
    q = validate('n=a', form)
    assert_equal(['n'], q.keys)
    assert_equal(["a"], q.lookup_all('n'))
    q = validate('m.x=0&m.y=1', form)
    assert_equal(['m.x', 'm.y'], q.keys)
    assert_equal(["0"], q.lookup_all('m.x'))
    assert_equal(["1"], q.lookup_all('m.y'))
    assert_raises(ValFail) { validate('m.x=a&m.y=1', form) }
    q = validate('l=b', form)
    assert_equal(['l'], q.keys)
    assert_equal(["b"], q.lookup_all('l'))
    assert_raises(ValFail) { validate('n=a&l=b', form) }
    form = <<'End'
<form>
<input type=submit name="n" value="a">
<input type=image name="m">
<button type=submit name="l" value="b">SUBMIT</button>
<input type=submit>
</form>
End
    assert_equal([], validate('', form).keys)
  end

  def test_html_form_validation_reset
    form = <<'End'
<form>
<input type=reset name="n" value="a">
</form>
End
    assert_equal([], validate('', form).keys)
  end

  def test_html_form_validation_hidden
    form = <<'End'
<form>
<input type=hidden name="n" value="a">
<input type=hidden name="m" value="b">
</form>
End
    assert_raises(ValFail) { validate('', form) }
    q = validate('n=a&m=b', form)
    assert_equal(['n', 'm'], q.keys)
    assert_equal(["a"], q.lookup_all('n'))
    assert_equal(["b"], q.lookup_all('m'))
    assert_raises(ValFail) { validate('n=b&m=b', form) }
    assert_raises(ValFail) { validate('n=a&m=', form) }
    assert_raises(ValFail) { validate('n=a&n=', form) }
  end

  def test_html_form_validation_select
    form = <<'End'
<form>
<select name="n">
<option value="v1" selected>
<option>v2</option>
</select>
</form>
End
    assert_raises(ValFail) { validate('', form) }
    q = validate('n=v1', form)
    assert_equal(['n'], q.keys)
    assert_equal(["v1"], q.lookup_all('n'))
    q = validate('n=v2', form)
    assert_equal(['n'], q.keys)
    assert_equal(["v2"], q.lookup_all('n'))
    assert_raises(ValFail) { validate('n=v1&n=v2', form) }
    form = <<'End'
<form>
<select name="n">
<option value="v1">
<option>v2</option>
</select>
</form>
End
    assert_equal([], validate('', form).keys)
  end

  def test_html_form_validation_textarea
    form = <<'End'
<form>
<textarea name=n readonly>abcdef</textarea>
</form>
End
    assert_raises(ValFail) { validate('', form) }
    q = validate('n=abcdef', form)
    assert_equal(['n'], q.keys)
    assert_equal(["abcdef"], q.lookup_all('n'))
    assert_raises(ValFail) { validate('n=xxxx', form) }
  end

end
