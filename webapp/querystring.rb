class WebApp
  # QueryString represents a query component of URI.
  class QueryString
    class << self
      alias primitive_new_for_raw_query_string new
      undef new
    end

    PctEncoded = /%[0-9A-Fa-f][0-9A-Fa-f]/
    def initialize(escaped)
      if /\A(?:[#{QueryChars}]|#{PctEncoded})*\z/o !~ escaped
        raise ArgumentError, "not properly escaped: #{escaped.inspect}"
      end
      @escaped_query_string = escaped
    end

    def inspect
      "#<#{self.class}: #{@escaped_query_string}>"
    end
    alias to_s inspect

    def QueryString.html_form(arg, sep=';')
      case arg
      when Array
        QueryString.html_form_array(arg, sep)
      when Hash
        QueryString.html_form_hash(arg, sep)
      else
        raise ArgumentError, "array or hash expected: #{arg.inspect}"
      end
    end

    # :stopdoc:

    def QueryString.html_form_hash(hash, sep=';')
      pairs = []
      hash.keys.sort.each {|k|
        v = hash[k]
        if Array === v
          v.each {|vv| pairs << [k, vv] }
        else
          pairs << [k, v]
        end
      }
      QueryString.html_form_array(pairs, sep)
    end

    def QueryString.html_form_array(pairs, sep=';')
      raw_query = pairs.map {|k, v|
        "#{escape_html_form_key_value(k)}=#{escape_html_form_key_value(e)}"
      }.join(sep)
      primitive_new_for_raw_query_string(raw_query)
    end

    # RFC 3986
    Alpha = 'a-zA-Z'
    Digit = '0-9'
    UnreservedChars = Alpha + Digit + '\-._~'
    SubDelimChars = '!$&\'()*+,;='
    PChars = UnreservedChars + SubDelimChars + ":@"

    QueryChars = PChars + "/?"

    def QueryString.escape_query_string(s)
      s.gsub(/[^#{QueryChars}]/on) {|c|
        sprintf("%%%02X", c[0])
      }
    end

    # [;&=+] are used as delimiters in application/x-www-form-urlencoded.
    FormKeyValueChars = QueryChars.gsub(/[;&=+]/, '') + ' '
    def QueryString.escape_html_form_key_value(s)
      s.gsub(/[^#{FormKeyValueChars}]/on) {|c|
        sprintf("%%%02X", c[0])
      }.gsub(/ /on, '+')
    end

    # :startdoc:
  end
end
