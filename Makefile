.PHONY: build full-site sentence-build sentence-data sentence-1k-data tag-word-data unique-build base-unique-build data all-data full-data unique-data base-unique-data real-data sample-data test serve clean

build: data
	dune build src/main.bc.js
	mkdir -p public/assets
	cp static/style.css public/assets/style.css
	cp -f _build/default/src/main.bc.js public/assets/app.js

full-site: build full-data

# Downloads a deterministic, compact sample of Tatoeba's weekly sentence exports.
# It is separate from `build` so ordinary word-game builds never need the network.
sentence-data:
	mkdir -p public/sentences
	dune exec scripts/preprocess_sentences.exe -- --output public/sentences --limit=1000

sentence-build: build sentence-data

# Tatoeba languages with at least 1,000 source sentences. Requires iso-codes
# for human-readable ISO 639-3 names (sudo apt-get install iso-codes).
sentence-1k-data:
	mkdir -p public/sentences-1k
	dune exec scripts/preprocess_sentences.exe -- --output public/sentences-1k --limit=1000 --codes data/tatoeba-1k-codes.txt

# Refresh only word-manifest metadata; existing compressed dictionaries are untouched.
tag-word-data:
	dune exec scripts/preprocess.exe -- --gzip --limit=5000 --base-only --unique --manifest-only public/data --hunspell=/usr/share/hunspell \
		Faroese:/usr/share/dict/faroese Irish:/usr/share/dict/irish Manx:/usr/share/dict/manx
	dune exec scripts/preprocess.exe -- --gzip --base-only --unique --manifest-only public/data-full --hunspell=/usr/share/hunspell \
		Faroese:/usr/share/dict/faroese Irish:/usr/share/dict/irish Manx:/usr/share/dict/manx

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
	dune exec scripts/preprocess.exe -- --gzip --limit=5000 public/data --hunspell=/usr/share/hunspell \
		Faroese:/usr/share/dict/faroese Irish:/usr/share/dict/irish Manx:/usr/share/dict/manx

full-data:
	mkdir -p public/data-full
	dune exec scripts/preprocess.exe -- --gzip --base-only --unique public/data-full --hunspell=/usr/share/hunspell \
		Faroese:/usr/share/dict/faroese Irish:/usr/share/dict/irish Manx:/usr/share/dict/manx

unique-data:
	mkdir -p public/data
	dune exec scripts/preprocess.exe -- --gzip --limit=5000 --unique public/data --hunspell=/usr/share/hunspell \
		Faroese:/usr/share/dict/faroese Irish:/usr/share/dict/irish Manx:/usr/share/dict/manx

base-unique-data:
	mkdir -p public/data
	dune exec scripts/preprocess.exe -- --gzip --limit=5000 --base-only --unique public/data --hunspell=/usr/share/hunspell \
		Faroese:/usr/share/dict/faroese Irish:/usr/share/dict/irish Manx:/usr/share/dict/manx

real-data:
	mkdir -p public/data
	dune exec scripts/preprocess.exe -- --gzip public/data \
		English:/usr/share/dict/american-english German:/usr/share/dict/ngerman \
		French:/usr/share/dict/french Spanish:/usr/share/dict/spanish \
		Italian:/usr/share/dict/italian Portuguese:/usr/share/dict/portuguese

sample-data:
	mkdir -p public/data
	dune exec scripts/preprocess.exe -- --gzip public/data \
		English:data/sample/english.txt German:data/sample/german.txt \
		French:data/sample/french.txt Spanish:data/sample/spanish.txt Italian:data/sample/italian.txt Portuguese:data/sample/portuguese.txt

test:
	dune runtest

serve: build
	python3 -m http.server 8000 --directory public

clean:
	dune clean
	rm -rf public/assets public/data
