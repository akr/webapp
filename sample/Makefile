RUBY=ruby

SRC_CGI = $(wildcard *.cgi)
DST_CGI = $(patsubst %.cgi,cgi-bin/%.cgi,$(SRC_CGI))

all: $(DST_CGI)

cgi-bin:
	mkdir cgi-bin

$(DST_CGI): cgistub.erb cgi-bin
	$(RUBY) -rerb -e 'ERB.new(STDIN.read).run' $(patsubst cgi-bin/%.cgi,%.cgi,$@) < cgistub.erb > $@
	chmod 755 $@
