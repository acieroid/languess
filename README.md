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
- Dictionaries are never bundled into the generated JavaScript. Every selected word is removed from the current pool, and every language containing it is accepted.

Easy and medium generate 3 and 6 distinct shuffled choices (or fewer if a custom manifest has too few languages). Hard mode uses a keyboard-accessible native `datalist` autocomplete. The prototype loads all manifest languages at game start asynchronously: simple and responsive for the initial set, while leaving the data format open to future lazy loading.
