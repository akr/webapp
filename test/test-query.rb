require 'test/unit'
require 'webapp'

class HTMLFormQueryTest < Test::Unit::TestCase
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
end
