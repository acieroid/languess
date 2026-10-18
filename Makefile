.PHONY: build full-site unique-build base-unique-build data all-data full-data unique-data base-unique-data real-data sample-data test serve clean

build: data
	dune build src/main.bc.js
	mkdir -p public/assets
	cp static/style.css public/assets/style.css
	cp -f _build/default/src/main.bc.js public/assets/app.js

full-site: build full-data

unique-build: unique-data
	dune build src/main.bc.js
	mkdir -p public/assets
	cp static/style.css public/assets/style.css
	cp -f _build/default/src/main.bc.js public/assets/app.js

base-unique-build: base-unique-data
	dune build src/main.bc.js
	mkdir -p public/assets
	cp static/style.css public/assets/style.css
	cp -f _build/default/src/main.bc.js public/assets/app.js

data:
	@if test -d /usr/share/hunspell && test -r /usr/share/dict/faroese && test -r /usr/share/dict/irish && test -r /usr/share/dict/manx; then \
		$(MAKE) base-unique-data; \
	elif test -r /usr/share/dict/american-english && test -r /usr/share/dict/ngerman && test -r /usr/share/dict/french && test -r /usr/share/dict/spanish && test -r /usr/share/dict/italian && test -r /usr/share/dict/portuguese; then \
		$(MAKE) real-data; \
	else \
		$(MAKE) sample-data; \
	fi

all-data:
	mkdir -p public/data
	dune exec scripts/preprocess.exe -- --limit=5000 public/data --hunspell=/usr/share/hunspell \
		Faroese:/usr/share/dict/faroese Irish:/usr/share/dict/irish Manx:/usr/share/dict/manx

full-data:
	mkdir -p public/data-full
	dune exec scripts/preprocess.exe -- --base-only --unique public/data-full --hunspell=/usr/share/hunspell \
		Faroese:/usr/share/dict/faroese Irish:/usr/share/dict/irish Manx:/usr/share/dict/manx

unique-data:
	mkdir -p public/data
	dune exec scripts/preprocess.exe -- --limit=5000 --unique public/data --hunspell=/usr/share/hunspell \
		Faroese:/usr/share/dict/faroese Irish:/usr/share/dict/irish Manx:/usr/share/dict/manx

base-unique-data:
	mkdir -p public/data
	dune exec scripts/preprocess.exe -- --limit=5000 --base-only --unique public/data --hunspell=/usr/share/hunspell \
		Faroese:/usr/share/dict/faroese Irish:/usr/share/dict/irish Manx:/usr/share/dict/manx

real-data:
	mkdir -p public/data
	dune exec scripts/preprocess.exe -- public/data \
		English:/usr/share/dict/american-english German:/usr/share/dict/ngerman \
		French:/usr/share/dict/french Spanish:/usr/share/dict/spanish \
		Italian:/usr/share/dict/italian Portuguese:/usr/share/dict/portuguese

sample-data:
	mkdir -p public/data
	dune exec scripts/preprocess.exe -- public/data \
		English:data/sample/english.txt German:data/sample/german.txt \
		French:data/sample/french.txt Spanish:data/sample/spanish.txt Italian:data/sample/italian.txt Portuguese:data/sample/portuguese.txt

test:
	dune runtest

serve: build
	python3 -m http.server 8000 --directory public

clean:
	dune clean
	rm -rf public/assets public/data
