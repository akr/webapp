RUBY=ruby

SRC_CGI = $(wildcard *.cgi)
DST_CGI = $(patsubst %.cgi,cgi-bin/%.cgi,$(SRC_CGI))

all: $(DST_CGI)

$(DST_CGI): gen-cgi
	$(RUBY) gen-cgi $(patsubst cgi-bin/%.cgi,%.cgi,$@)
