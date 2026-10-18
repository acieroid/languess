(* Usage: preprocess OUTPUT_DIR "Language:path/to/words" ...
   Input is one word per line.  Output is UTF-8 JSON plus a manifest. *)
let json_string s =
  let buffer = Buffer.create (String.length s + 8) in
  Buffer.add_char buffer '"';
  String.iter
    (function
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\r' -> Buffer.add_string buffer "\\r"
      | '\t' -> Buffer.add_string buffer "\\t"
      | c -> Buffer.add_char buffer c)
    s;
  Buffer.add_char buffer '"';
  Buffer.contents buffer

let normalize word = String.lowercase_ascii (String.trim word)

let strip_dictionary_metadata line =
  let line = String.trim line in
  let stop = ref (String.length line) in
  String.iteri (fun index character ->
    if (character = '/' || character = '\t' || character = ' ') && index < !stop then stop := index) line;
  String.sub line 0 !stop

let is_count_line line =
  match int_of_string_opt (String.trim line) with Some _ -> true | None -> false

let evenly_sample limit words =
  let values = Array.of_list words in
  let length = Array.length values in
  if length <= limit then words
  else if limit = 1 then [ values.(0) ]
  else List.init limit (fun index -> values.(index * (length - 1) / (limit - 1)))

let shell_quote value =
  "'" ^ String.concat "'\\''" (String.split_on_char '\'' value) ^ "'"

let dictionary_encoding path =
  if not (Filename.check_suffix path ".dic") then None
  else
    let affix = Filename.remove_extension path ^ ".aff" in
    if not (Sys.file_exists affix) then None
    else
      let input = open_in affix in
      let rec find () =
        match input_line input with
        | line when String.starts_with ~prefix:"SET " line ->
            close_in input;
            Some (String.trim (String.sub line 4 (String.length line - 4)))
        | _ -> find ()
        | exception End_of_file -> close_in input; None
      in
      find ()

let read_words ?limit path =
  let input, close =
    match dictionary_encoding path with
    | Some encoding when String.uppercase_ascii encoding <> "UTF-8" ->
        let channel = Unix.open_process_in ("iconv -f " ^ shell_quote encoding ^ " -t UTF-8 " ^ shell_quote path) in
        channel, (fun () -> ignore (Unix.close_process_in channel))
    | _ ->
        let channel = open_in path in
        channel, (fun () -> close_in channel)
  in
  let seen = Hashtbl.create 2048 in
  (try
     while true do
       let raw = input_line input in
       let word = normalize (strip_dictionary_metadata raw) in
       if word <> "" && word.[0] <> '#' && not (is_count_line raw) then Hashtbl.replace seen word ()
     done
   with End_of_file -> close ());
  let words = Hashtbl.to_seq_keys seen |> List.of_seq |> List.sort String.compare in
  match limit with Some value -> evenly_sample value words | None -> words

let language_names =
  [ "af", "Afrikaans"; "an", "Aragonese"; "ar", "Arabic"; "be", "Belarusian";
    "bg", "Bulgarian"; "bn", "Bengali"; "bo", "Tibetan"; "br", "Breton";
    "bs", "Bosnian"; "ca", "Catalan"; "ckb", "Central Kurdish"; "cs", "Czech";
    "da", "Danish"; "de", "German"; "dz", "Dzongkha"; "el", "Greek";
    "en", "English"; "eo", "Esperanto"; "es", "Spanish"; "eu", "Basque";
    "fr", "French"; "gd", "Scottish Gaelic"; "gl", "Galician"; "gu", "Gujarati";
    "gug", "Guarani"; "he", "Hebrew"; "hi", "Hindi"; "hr", "Croatian";
    "hu", "Hungarian"; "id", "Indonesian"; "is", "Icelandic"; "it", "Italian";
    "kk", "Kazakh"; "kmr", "Kurmanji"; "ko", "Korean"; "ku", "Kurdish";
    "lo", "Lao"; "lt", "Lithuanian"; "lv", "Latvian"; "ml", "Malayalam";
    "mn", "Mongolian"; "nb", "Norwegian Bokmål"; "ne", "Nepali"; "nl", "Dutch";
    "nn", "Norwegian Nynorsk"; "oc", "Occitan"; "pl", "Polish"; "pt", "Portuguese";
    "ro", "Romanian"; "ru", "Russian"; "si", "Sinhala"; "sk", "Slovak";
    "sl", "Slovene"; "sr", "Serbian"; "sv", "Swedish"; "sw", "Swahili";
    "te", "Telugu"; "th", "Thai"; "tr", "Turkish"; "uk", "Ukrainian";
    "uz", "Uzbek"; "vi", "Vietnamese" ]

let hunspell_code filename =
  Filename.remove_extension filename |> String.split_on_char '_' |> List.hd

let hunspell_label filename =
  let stem = Filename.remove_extension filename in
  match String.split_on_char '_' stem with
  | code :: suffix ->
      let language = match List.assoc_opt code language_names with Some name -> name | None -> code in
      if suffix = [] then language else language ^ " (" ^ String.concat " " suffix ^ ")"
  | [] -> stem

let preferred_dictionary code =
  match code with
  | "en" -> "en_US.dic" | "es" -> "es_ES.dic" | "fr" -> "fr_FR.dic"
  | "de" -> "de_DE.dic" | "it" -> "it_IT.dic" | "pt" -> "pt_PT.dic"
  | "ku" -> "ku_TR.dic" | "sr" -> "sr_RS.dic"
  | _ -> code ^ ".dic"

let base_label code =
  match List.assoc_opt code language_names with Some name -> name | None -> code

(* Debian aliases ckb_IQ and ku_TR to kmr_Latn.  Dzongkha has the same
   normalized roots as Tibetan; for the base-only game, retain Tibetan. *)
let omitted_base_codes = [ "ckb"; "ku"; "dz" ]

let hunspell_sources ?(base_only = false) directory =
  let files =
    Sys.readdir directory |> Array.to_list
    |> List.filter (fun file -> Filename.check_suffix file ".dic")
    |> List.sort String.compare
  in
  if not base_only then
    List.map (fun file -> hunspell_label file, Filename.concat directory file) files
  else begin
    let by_code = Hashtbl.create 67 in
    List.iter (fun file ->
      let code = hunspell_code file in
      let old = match Hashtbl.find_opt by_code code with Some value -> value | None -> [] in
      Hashtbl.replace by_code code (file :: old)) files;
    Hashtbl.to_seq by_code |> List.of_seq
    |> List.filter (fun (code, _) -> not (List.mem code omitted_base_codes))
    |> List.sort (fun (a, _) (b, _) -> String.compare a b)
    |> List.map (fun (code, candidates) ->
      let selected =
        match List.find_opt (fun file -> file = preferred_dictionary code) candidates with
        | Some file -> file
        | None -> List.hd (List.sort String.compare candidates)
      in
      base_label code, Filename.concat directory selected)
  end

let slugify name =
  String.map
    (function
      | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' as character -> Char.lowercase_ascii character
      | _ -> '-') name

let parse_source argument =
  match String.split_on_char ':' argument with
  | language :: path_parts when path_parts <> [] -> language, String.concat ":" path_parts
  | _ -> failwith "Each dictionary must be Language:path"

let () =
  if Array.length Sys.argv < 3 then (
    prerr_endline "Usage: preprocess [--limit=N] [--base-only] [--unique] OUTPUT_DIR [--hunspell=DIR] Language:path ...";
    exit 2);
  let argument = ref 1 in
  let limit = ref None in
  let unique = ref false in
  let base_only = ref false in
  while !argument < Array.length Sys.argv && String.starts_with ~prefix:"--" Sys.argv.(!argument) do
    let option = Sys.argv.(!argument) in
    if String.starts_with ~prefix:"--limit=" option then
      limit := Some (int_of_string (String.sub option 8 (String.length option - 8)))
    else if option = "--unique" then unique := true
    else if option = "--base-only" then base_only := true
    else failwith ("Unknown option " ^ option);
    incr argument
  done;
  if !argument >= Array.length Sys.argv then failwith "Missing output directory";
  let output = Sys.argv.(!argument) in
  incr argument;
  if not (Sys.file_exists output) then Unix.mkdir output 0o755;
  let sources = ref [] in
  while !argument < Array.length Sys.argv do
    let value = Sys.argv.(!argument) in
    if String.starts_with ~prefix:"--hunspell=" value then
      sources := !sources @ hunspell_sources ~base_only:!base_only (String.sub value 11 (String.length value - 11))
    else sources := !sources @ [ parse_source value ];
    incr argument
  done;
  if !sources = [] then failwith "No dictionaries supplied";
  let dictionaries =
    if !unique then begin
      let loaded = List.map (fun (language, path) -> language, read_words path) !sources in
      let occurrences = Hashtbl.create 65536 in
      List.iter (fun (_, words) ->
        List.iter (fun word ->
          let count = match Hashtbl.find_opt occurrences word with Some value -> value | None -> 0 in
          Hashtbl.replace occurrences word (count + 1)) words) loaded;
      loaded
      |> List.map (fun (language, words) ->
        let only_here = List.filter (fun word -> Hashtbl.find occurrences word = 1) words in
        let selected = match !limit with Some value -> evenly_sample value only_here | None -> only_here in
        language, selected)
      |> List.filter (fun (_, words) -> words <> [])
    end else
      List.map (fun (language, path) -> language, read_words ?limit:!limit path) !sources
  in
  let entries = ref [] in
  List.iter
    (fun (language, words) ->
      let file = slugify language ^ ".json" in
      let out = open_out (Filename.concat output file) in
      output_string out ("{\"words\":[" ^ String.concat "," (List.map json_string words) ^ "]}\n");
      close_out out;
      entries := (language, file) :: !entries)
    dictionaries;
  let manifest = open_out (Filename.concat output "manifest.json") in
  let item (name, file) =
    "{\"name\":" ^ json_string name ^ ",\"file\":" ^ json_string file ^ "}"
  in
  output_string manifest ("{\"languages\":[" ^ String.concat "," (List.map item (List.rev !entries)) ^ "]}\n");
  close_out manifest
