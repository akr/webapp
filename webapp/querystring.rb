# Copyright (c) 2006 Tanaka Akira. All rights reserved.
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
