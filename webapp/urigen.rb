require 'uri'

class WebApp
  # :stopdoc:
  class URIGen
    def initialize(scheme, server_name, server_port, script_name, path_info)
      @scheme = scheme
      @server_name = server_name
      @server_port = server_port
      @script_name = script_name
      @path_info = path_info
      uri = "#{scheme}://#{server_name}:#{server_port}"
      uri << script_name.gsub(%r{[^/]+}) {|segment| pchar_escape(segment) }
      # xxx: path_info may begin with a non-slash character.
      uri << path_info.gsub(%r{[^/]+}) {|segment| pchar_escape(segment) }
      @base_uri = URI.parse(uri)
    end
    attr_reader :base_uri

    def make_relative_uri(hash)
      script = nil
      path_info = nil
      query = nil
      fragment = nil
      hash.each_pair {|k,v|
        case k
        when :script then script = v
        when :path_info then path_info = v
        when :query then query = v
        when :fragment then fragment = v
        else
          raise ArgumentError, "unexpected: #{k} => #{v}"
        end
      }

      if !script
        script = @script_name
      elsif %r{\A/} !~ script
        script = @script_name.sub(%r{[^/]*\z}) { script }
        while script.sub!(%r{/[^/]*/\.\.(?=/|\z)}, '')
        end
        script.sub!(%r{\A/\.\.(?=/|\z)}, '')
      end

      path_info = '/' + path_info if %r{\A[^/]} =~ path_info

      dst = "#{script}#{path_info}"
      dst.sub!(%r{\A/}, '')
      dst.sub!(%r{[^/]*\z}, '')
      dst_basename = $&

      src = "#{@script_name}#{@path_info}"
      src.sub!(%r{\A/}, '')
      src.sub!(%r{[^/]*\z}, '')

      while src[%r{\A[^/]*/}] == dst[%r{\A[^/]*/}]
        if $~
          src.sub!(%r{\A[^/]*/}, '')
          dst.sub!(%r{\A[^/]*/}, '')
        else
          break
        end
      end

      rel_path = '../' * src.count('/')
      rel_path << dst << dst_basename
      rel_path = './' if rel_path.empty?

      rel_path.gsub!(%r{[^/]+}) {|segment| pchar_escape(segment) }
      if %r{\A/} =~ rel_path ||
         /:/ =~ rel_path[%r{\A[^/]*}] # It seems absolute URI.
        rel_path = './' + rel_path
      end

      if query
        case query
        when QueryString
          query = query.instance_eval { @escaped_query_string }
        when Hash
          query = query.map {|k, v|
            case v
            when String
              "#{form_key_value_escape(k)}=#{form_key_value_escape(v)}"
            when Array
              v.map {|e|
                unless String === e
                  raise ArgumentError, "unexpected query value: #{e.inspect}"
                end
                "#{form_key_value_escape(k)}=#{form_key_value_escape(e)}"
              }
            else
              raise ArgumentError, "unexpected query value: #{v.inspect}"
            end
          }.join(';')
        else
          raise ArgumentError, "unexpected query: #{query.inspect}"
        end
        unless query.empty?
          query = '?' + query
        end
      else
        query = ''
      end

      if fragment
        fragment = "#" + fragment_escape(fragment)
      else
        fragment = ''
      end

      URI.parse(rel_path + query + fragment)
    end

    def make_absolute_uri(hash)
      @base_uri + make_relative_uri(hash)
    end

    # RFC 3986
    Alpha = 'a-zA-Z'
    Digit = '0-9'
    UnreservedChars = Alpha + Digit + '\-._~'
    SubDelimChars = '!$&\'()*+,;='
    PChars = UnreservedChars + SubDelimChars + ":@"
    FragmentChars = PChars + "/?"
    def fragment_escape(s)
      s.gsub(/[^#{FragmentChars}]/on) {|c| sprintf("%%%02X", c[0]) }
    end

    QueryChars = PChars + "/?"

    # [;&=+] is used for delimiter of application/x-www-form-urlencoded.
    FormKeyValueChars = QueryChars.gsub(/[;&=+]/, '') + ' '
    def form_key_value_escape(s)
      s.gsub(/[^#{FormKeyValueChars}]/on) {|c|
        sprintf("%%%02X", c[0])
      }.gsub(/ /on, '+')
    end
    #

    # RFC 2396
    AlphaNum = Alpha + Digit
    Mark = '\-_.!~*\'()'
    Unreserved = AlphaNum + Mark
    PChar = Unreserved + ':@&=+$,'
    def pchar_escape(s)
      s.gsub(/[^#{PChar}]/on) {|c| sprintf("%%%02X", c[0]) }
    end

  end
  # :startdoc:
end
