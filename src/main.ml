open Js_of_ocaml

type language_file = { name : string; file : string }
type game = {
  languages : string list;
  index : Game.index;
  mutable remaining : string list;
  mutable current : string option;
  mutable answered : bool;
  mutable correct_count : int;
  mutable question_count : int;
}

let document = Dom_html.document
let element id = Dom_html.getElementById id
let set_text node value = node##.textContent := Js.some (Js.string value)
let set_html node value = node##.innerHTML := Js.string value
let show node = node##.style##.display := Js.string ""
let hide node = node##.style##.display := Js.string "none"
let set_hidden node hidden =
  if hidden then node##setAttribute (Js.string "hidden") (Js.string "hidden")
  else node##removeAttribute (Js.string "hidden")
let status = element "status"
let loading = element "loading"
let loading_label = element "loading-label"
let loading_count = element "loading-count"
let loading_progress = element "loading-progress"
let feedback = element "feedback"
let answer_box = element "answers"
let round = element "round"
let next_button = element "next"
let hard_box = element "hard-answer"
let score = element "score"
let word = element "word"
let difficulty : Dom_html.selectElement Js.t = Js.Unsafe.coerce (element "difficulty")
let minimum : Dom_html.inputElement Js.t = Js.Unsafe.coerce (element "minimum-length")
let guess : Dom_html.inputElement Js.t = Js.Unsafe.coerce (element "guess-input")
let full_dataset : Dom_html.inputElement Js.t = Js.Unsafe.coerce (element "full-dataset")

let continents = [ "africa", "Africa"; "asia", "Asia"; "europe", "Europe"; "south-america", "South America" ]

let continent_of_language name =
  let base =
    match String.index_opt name '(' with
    | Some index -> String.trim (String.sub name 0 index)
    | None -> name
  in
  if List.mem base [ "Afrikaans"; "Swahili" ] then "Africa"
  else if List.mem base
    [ "Arabic"; "Bengali"; "Central Kurdish"; "Dzongkha"; "Gujarati"; "Hebrew";
      "Hindi"; "Indonesian"; "Kazakh"; "Korean"; "Kurdish"; "Kurmanji"; "Lao";
      "Malayalam"; "Mongolian"; "Nepali"; "Sinhala"; "Telugu"; "Thai"; "Tibetan";
      "Turkish"; "Uzbek"; "Vietnamese" ] then "Asia"
  else if base = "Guarani" then "South America"
  else "Europe"

let selected_continents () =
  List.filter_map (fun (id, name) ->
    let checkbox : Dom_html.inputElement Js.t = Js.Unsafe.coerce (element ("continent-" ^ id)) in
    if Js.to_bool checkbox##.checked then Some name else None) continents

let current_game : game option ref = ref None
let dictionary_cache : (string, string list) Hashtbl.t = Hashtbl.create 11

let js_string value = Js.to_string (Js.Unsafe.coerce value)
let property object_ key = Js.Unsafe.get object_ key
let json_parse text =
  Js.Unsafe.fun_call (Js.Unsafe.pure_js_expr "JSON.parse") [| Js.Unsafe.inject (Js.string text) |]

let read_response_text response url =
  if String.ends_with ~suffix:".gz" url then begin
    let supported = Js.to_bool (Js.Unsafe.coerce
      (Js.Unsafe.pure_js_expr "typeof DecompressionStream !== 'undefined'")) in
    if not supported then raise (Failure "gzip decompression is not supported by this browser");
    let decompressor = Js.Unsafe.new_obj (Js.Unsafe.pure_js_expr "DecompressionStream")
      [| Js.Unsafe.inject (Js.string "gzip") |] in
    let stream = Js.Unsafe.meth_call (property response "body") "pipeThrough"
      [| Js.Unsafe.inject decompressor |] in
    let decoded = Js.Unsafe.new_obj (Js.Unsafe.pure_js_expr "Response")
      [| Js.Unsafe.inject stream |] in
    Js.Unsafe.meth_call decoded "text" [||]
  end else
    Js.Unsafe.meth_call response "text" [||]

let fetch_text url success failure =
  let fetch = Js.Unsafe.pure_js_expr "fetch" in
  let promise = Js.Unsafe.fun_call fetch [| Js.Unsafe.inject (Js.string url) |] in
  let received response =
    let ok = Js.to_bool (Js.Unsafe.coerce (property response "ok")) in
    if not ok then failure ("request failed for " ^ url)
    else
      let text_promise = read_response_text response url in
      let after_text text = success (js_string text) in
      let chained = Js.Unsafe.meth_call text_promise "then" [| Js.Unsafe.inject (Js.wrap_callback after_text) |] in
      ignore (Js.Unsafe.meth_call chained "catch" [| Js.Unsafe.inject (Js.wrap_callback (fun _ -> failure ("could not read " ^ url))) |])
  in
  let chained = Js.Unsafe.meth_call promise "then" [| Js.Unsafe.inject (Js.wrap_callback received) |] in
  ignore (Js.Unsafe.meth_call chained "catch" [| Js.Unsafe.inject (Js.wrap_callback (fun _ -> failure ("network error while loading " ^ url))) |])

let parse_manifest text =
  let root = json_parse text in
  let entries = Js.to_array (Js.Unsafe.coerce (property root "languages")) in
  Array.to_list entries
  |> List.map (fun entry -> { name = js_string (property entry "name"); file = js_string (property entry "file") })

let parse_words text =
  let root = json_parse text in
  let items = Js.to_array (Js.Unsafe.coerce (property root "words")) in
  Array.to_list items |> List.map js_string

let update_score game = set_text score (Printf.sprintf "Score: %d / %d" game.correct_count game.question_count)

let update_loading completed total =
  set_text loading_count (Printf.sprintf "%d / %d dictionaries" completed total);
  loading_progress##setAttribute (Js.string "max") (Js.string (string_of_int (max 1 total)));
  loading_progress##setAttribute (Js.string "value") (Js.string (string_of_int completed))

let defer callback =
  ignore (Js.Unsafe.fun_call (Js.Unsafe.pure_js_expr "setTimeout")
    [| Js.Unsafe.inject (Js.wrap_callback (fun _ -> callback ()));
       Js.Unsafe.inject (Js.number_of_float 0.) |])

(* Browser normalization makes e.g. "Francais" match "Français" when custom
   manifests use accented language names. *)
let fold_language_name value =
  let decomposed =
    Js.Unsafe.meth_call (Js.string (String.trim value)) "normalize"
      [| Js.Unsafe.inject (Js.string "NFD") |]
  in
  let marks = Js.Unsafe.new_obj (Js.Unsafe.pure_js_expr "RegExp")
    [| Js.Unsafe.inject (Js.string "[\\u0300-\\u036f]"); Js.Unsafe.inject (Js.string "g") |]
  in
  let unaccented = Js.Unsafe.meth_call decomposed "replace"
    [| Js.Unsafe.inject marks; Js.Unsafe.inject (Js.string "") |]
  in
  js_string (Js.Unsafe.meth_call unaccented "toLowerCase" [||])

let language_name_matches a b = fold_language_name a = fold_language_name b

let submit game answer =
  if not game.answered then begin
    game.answered <- true;
    game.question_count <- game.question_count + 1;
    let current = match game.current with Some item -> item | None -> "" in
    let valid = Game.languages_for game.index current in
    let correct = List.exists (language_name_matches answer) valid in
    if correct then begin
      game.correct_count <- game.correct_count + 1;
      feedback##.className := Js.string "feedback correct";
      set_text feedback ("Correct. This word occurs in: " ^ String.concat ", " valid)
    end else begin
      feedback##.className := Js.string "feedback incorrect";
      set_text feedback ("Not quite. This word occurs in: " ^ String.concat ", " valid)
    end;
    update_score game;
    set_hidden next_button false;
    show next_button
  end

let add_button label action =
  let button = document##createElement (Js.string "button") in
  button##setAttribute (Js.string "type") (Js.string "button");
  set_text button label;
  Dom_html.addEventListener button Dom_html.Event.click
    (Dom_html.handler (fun _ -> action (); Js._false)) Js._false |> ignore;
  Dom.appendChild answer_box button

let render_suggestions languages =
  let list = element "language-suggestions" in
  set_html list "";
  List.iter (fun name ->
    let option = document##createElement (Js.string "option") in
    option##setAttribute (Js.string "value") (Js.string name);
    Dom.appendChild list option) languages

let show_word game =
  match game.remaining with
  | [] ->
      game.current <- None;
      set_text word "Game complete";
      set_text feedback "You have used every available word. Restart to play again.";
      set_html answer_box "";
      hide hard_box;
      hide next_button
  | _ ->
      let selected = List.nth game.remaining (Random.int (List.length game.remaining)) in
      game.remaining <- List.filter (fun item -> item <> selected) game.remaining;
      game.current <- Some selected;
      game.answered <- false;
      set_text word selected;
      set_text feedback "";
      feedback##.className := Js.string "feedback";
      set_hidden next_button true;
      hide next_button;
      set_html answer_box "";
      let mode = Js.to_string difficulty##.value in
      if mode = "hard" then begin
        show hard_box;
        guess##.value := Js.string "";
        guess##focus
      end else begin
        hide hard_box;
        let count = if mode = "easy" then 3 else 6 in
        let valid = Game.languages_for game.index selected in
        Game.choices ~available_languages:game.languages ~correct:valid ~count
        |> List.iter (fun language -> add_button language (fun () -> submit game language))
      end

let start_game dictionaries =
  let min_length = try max 1 (int_of_string (Js.to_string minimum##.value)) with Failure _ -> 5 in
  let index = Game.build_index ~minimum_length:min_length dictionaries in
  let available = Game.words index in
  if available = [] then begin
    set_hidden loading true;
    status##.className := Js.string "status error";
    set_text status "No words meet that minimum length. Choose a smaller value."
  end else begin
    let languages = List.map fst dictionaries in
    let game = { languages; index; remaining = available; current = None; answered = false; correct_count = 0; question_count = 0 } in
    current_game := Some game;
    set_hidden loading true;
    status##.className := Js.string "status";
    set_text status (Printf.sprintf "%d languages · %d words ready." (List.length languages) (List.length available));
    render_suggestions languages;
    set_hidden round false;
    show round;
    update_score game;
    show_word game
  end

let load_game () =
  let data_root = if Js.to_bool full_dataset##.checked then "data-full" else "data" in
  let loading_name = if data_root = "data-full" then "Loading full dictionaries" else "Loading dictionaries" in
  set_text status (loading_name ^ "…");
  status##.className := Js.string "status";
  set_text loading_label loading_name;
  update_loading 0 0;
  set_hidden loading false;
  set_hidden round true;
  let fail message =
    set_hidden loading true;
    status##.className := Js.string "status error";
    set_text status ("Could not start game: " ^ message)
  in
  fetch_text (data_root ^ "/manifest.json")
    (fun manifest_text ->
      try
        let files = parse_manifest manifest_text in
        let selected = selected_continents () in
        let files = List.filter (fun info -> List.mem (continent_of_language info.name) selected) files in
        if files = [] then fail "the manifest has no languages"
        else begin
          let total = List.length files in
          let completed = ref 0 in
          let loaded = ref [] in
          let failed = ref false in
          update_loading 0 total;
          let loaded_dictionary info words =
            if not !failed then begin
              loaded := (info.name, words) :: !loaded;
              incr completed;
              update_loading !completed total;
              if !completed = total then begin
                set_text loading_label "Indexing words";
                set_text status "Preparing the game…";
                defer (fun () -> start_game (List.rev !loaded))
              end
            end
          in
          List.iter (fun info ->
            let cache_key = data_root ^ "/" ^ info.file in
            match Hashtbl.find_opt dictionary_cache cache_key with
            | Some words ->
                loaded_dictionary info words
            | None -> fetch_text cache_key
                (fun text -> try
                  let words = parse_words text in
                  Hashtbl.replace dictionary_cache cache_key words;
                  loaded_dictionary info words
                with _ -> if not !failed then (failed := true; fail ("invalid data in " ^ info.file)))
                (fun message -> if not !failed then (failed := true; fail message))) files
        end
      with _ -> fail "invalid manifest") fail

let () =
  Random.self_init ();
  Dom_html.addEventListener (element "start") Dom_html.Event.click
    (Dom_html.handler (fun _ -> load_game (); Js._false)) Js._false |> ignore;
  Dom_html.addEventListener (element "next") Dom_html.Event.click
    (Dom_html.handler (fun _ -> (match !current_game with Some game -> show_word game | None -> ()); Js._false)) Js._false |> ignore;
  Dom_html.addEventListener (element "submit-guess") Dom_html.Event.click
    (Dom_html.handler (fun _ -> (match !current_game with Some game -> submit game (Js.to_string guess##.value) | None -> ()); Js._false)) Js._false |> ignore;
  Dom_html.addEventListener guess Dom_html.Event.keydown
    (Dom_html.handler (fun event ->
      if event##.keyCode = 13 then
        (match !current_game with Some game -> submit game (Js.to_string guess##.value) | None -> ());
      Js._true)) Js._false |> ignore
