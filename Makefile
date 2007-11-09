RUBY=ruby

all: rdoc/index.html

check test:
	$(RUBY) -I. test-all.rb

install:
	$(RUBY) install.rb

.PHONY: check test all install

RB = webapp.rb $(wildcard webapp/*.rb) 
rdoc/index.html: $(RB)
	rm -rf rdoc
	rdoc --op rdoc $(RB)

