# Language Guess

A small static language-guessing game. The browser application is written in OCaml and compiled to JavaScript with `js_of_ocaml`; it uses no JavaScript framework, server, API, or Node.js dependency.

## Run it

Install OCaml, Dune, and `js_of_ocaml`. With opam:

```sh
opam install dune js_of_ocaml
```

On Debian/Ubuntu, the system packages are also sufficient:

```sh
sudo apt-get install ocaml-nox ocaml-dune js-of-ocaml libjs-of-ocaml-dev
```

Build and serve the static site:

```sh
make build
python3 -m http.server 8000 --directory public
```

Open <http://localhost:8000>. `make serve` is the shortcut, and `make test` runs the pure game-logic tests. Deploy the contents of `public/` to any static host. It must be served over HTTP because dictionaries are fetched separately.

## Sentence Guess

Open `/sentence.html` (or use the link from Word Guess) to play the sentence variant. It uses the same Easy, Medium, and Hard answer modes, continent filters, scorekeeping, gzip loading, and progress display. The repository ships a deterministic random sample of up to 1,000 filtered sentences per language from Tatoeba, rather than its very large complete corpus. Sentence Guess uses the 150 languages that currently have at least 1,000 source sentences; the smaller 61-language sample remains in `public/sentences/` for development.

The source files are Tatoeba's weekly per-language TSV exports. Each row contains a sentence id, ISO 639-3 code, and text. `scripts/preprocess_sentences.ml` downloads those exports, removes very short/long and duplicate entries, reservoir-samples the remaining sentences with a fixed seed, and writes `public/sentences/*.json.gz` with a manifest. Rebuild it with:

```sh
make sentence-data
```

To regenerate the expanded dataset used by Sentence Guess, run:

```sh
make sentence-1k-data
```

This needs `curl` and `bzip2`, in addition to the OCaml prerequisites. The Tatoeba sentence data used here is **CC BY 2.0 FR**; the sentence page and this README attribute Tatoeba. Sentences are community-contributed and may contain unexpected content. See [Tatoeba's download and licensing information](https://tatoeba.org/en/downloads).

## Dictionaries

When Hunspell dictionaries and the three supplemental Unix lists are installed, `make build` generates the base-first unique dataset: one canonical dictionary per language, then only words that occur in exactly one selected dictionary. This retains the most useful guessing words while avoiding regional-edition duplication. Each source is deterministically sampled to at most 5,000 normalized real words. The repository also includes a deliberately small fallback dataset in `data/sample/`, so builds remain immediately playable on machines without dictionaries. Its `shared` entry is intentionally present in every language to demonstrate multiple valid answers.

On Debian/Ubuntu, install the six source lists with:

```sh
sudo apt-get install $(apt-cache search hunspell- | awk '$1 ~ /^hunspell-[a-z]/ && $1 != "hunspell-tools" && $1 !~ /-frami$/ && $1 != "hunspell-fr-classical" && $1 != "hunspell-fr-revised" {print $1}') wfaroese wirish wmanx
```

Replace it with plain Unix dictionary files (one word per line) using:

```sh
dune exec scripts/preprocess.exe -- --gzip public/data \
  English:/usr/share/dict/words German:/path/to/german-words \
  French:/path/to/french-words Spanish:/path/to/spanish-words \
  Italian:/path/to/italian-words
```

On Linux these lists are commonly distributed as `wamerican`, `wspanish`, `wfrench`, or Hunspell packages. The preprocessor strips Hunspell affix flags, trims and deduplicates words per language, preserves UTF-8 accents, and emits a gzip-compressed JSON file for each language plus `manifest.json`. The browser uses its built-in `DecompressionStream` to read these files, so deployment does not depend on host-side HTTP compression. `make data` chooses the complete installed set when present and otherwise uses the fallback; `make all-data`, `make real-data`, and `make sample-data` select a mode explicitly.

### Unique-word variant

Run `make unique-build` to create a discriminative variant: a word is retained only when it occurs in exactly one normalized source dictionary, then each remaining dictionary is capped at 5,000 representative entries. Dictionaries without any unique words are omitted from that manifest. This build is slower and uses substantial RAM because it compares the complete source corpus. Run `make build` to restore the normal shared-word dataset.

`make build` uses the recommended base-first unique variant. It first keeps one canonical dictionary per base language and discards regional/edition variants, then applies the same global unique-word rule. This avoids a language such as French being removed merely because its French regional variants overlap. `make base-unique-build` explicitly selects the same mode.

### Full dataset

The unchecked **Full dataset** control switches the game to `public/data-full/`: the same base-first unique corpus without the 5,000-word-per-language cap. Generate a deployable site with both datasets using `make full-site`. The current full corpus contains about 7.9 million playable words (minimum length 5), stored as roughly 26.5 MB of gzip-compressed JSON (about 146 MB after decompression), so it is intended for fast connections and has a noticeably longer loading/indexing phase.

## Architecture

- `src/game.ml` provides pure UTF-8 length filtering, word-to-language indexing, answer checks, and shuffled choices; `src/game_test.ml` tests these rules.
- `src/main.ml` fetches the manifest and JSON dictionaries asynchronously, caches them in memory, manages game state, and renders the DOM.
- `public/sentence.html` reuses that browser application with a sentence-data manifest; Tatoeba data is fetched only from the static host, never from Tatoeba at play time.
- Dictionaries are never bundled into the generated JavaScript. Every selected word is removed from the current pool, and every language containing it is accepted.

Easy and medium generate 3 and 6 distinct shuffled choices (or fewer if a custom manifest has too few languages). Hard mode uses a keyboard-accessible native `datalist` autocomplete. The prototype loads all manifest languages at game start asynchronously: simple and responsive for the initial set, while leaving the data format open to future lazy loading.
