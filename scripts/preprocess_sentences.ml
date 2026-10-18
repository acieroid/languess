(* Build a compact, deterministic sample of Tatoeba's per-language exports.
   Each source row is: sentence id <TAB> ISO 639-3 code <TAB> sentence text. *)

type source = { name : string; code : string }

let default_sources =
  [ "Afrikaans", "afr"; "Aragonese", "arg"; "Arabic", "ara";
    "Basque", "eus"; "Belarusian", "bel"; "Bengali", "ben"; "Bosnian", "bos";
    "Breton", "bre"; "Bulgarian", "bul"; "Catalan", "cat";
    "Croatian", "hrv"; "Czech", "ces"; "Danish", "dan"; "Dutch", "nld"; "English", "eng";
    "Esperanto", "epo"; "Faroese", "fao"; "French", "fra";
    "Galician", "glg"; "German", "deu"; "Greek", "ell"; "Guarani", "grn";
    "Gujarati", "guj"; "Hebrew", "heb"; "Hindi", "hin"; "Hungarian", "hun";
    "Icelandic", "isl"; "Indonesian", "ind"; "Irish", "gle"; "Italian", "ita";
    "Kazakh", "kaz"; "Korean", "kor"; "Kurmanji", "kmr"; "Lao", "lao";
    "Latvian", "lvs"; "Lithuanian", "lit"; "Malayalam", "mal"; "Manx", "glv";
    "Mongolian", "mon"; "Nepali", "npi"; "Norwegian Bokmål", "nob";
    "Norwegian Nynorsk", "nno"; "Occitan", "oci"; "Polish", "pol";
    "Portuguese", "por"; "Romanian", "ron"; "Russian", "rus";
    "Scottish Gaelic", "gla"; "Serbian", "srp"; "Sinhala", "sin";
    "Slovak", "slk"; "Slovene", "slv"; "Spanish", "spa"; "Swahili", "swh";
    "Swedish", "swe"; "Telugu", "tel"; "Thai", "tha"; "Tibetan", "bod";
    "Turkish", "tur"; "Ukrainian", "ukr"; "Uzbek", "uzb"; "Vietnamese", "vie" ]
  |> List.map (fun (name, code) -> { name; code })

let quoted_value line =
  match String.split_on_char '"' line with
  | _ :: _field :: _ :: value :: _ -> Some value
  | _ -> None

let read_iso_names path =
  let input = open_in path and current = ref None and names = Hashtbl.create 500 in
  (try while true do
    let line = input_line input |> String.trim in
    if String.starts_with ~prefix:"\"alpha_3\"" line then current := quoted_value line
    else if String.starts_with ~prefix:"\"name\"" line then
      match !current, quoted_value line with
      | Some code, Some name -> Hashtbl.replace names code name
      | _ -> ()
  done with End_of_file -> close_in input);
  names

let read_codes path =
  let input = open_in path in
  let rec loop values =
    match input_line input with
    | line -> let code = String.trim line in loop (if code = "" then values else code :: values)
    | exception End_of_file -> close_in input; List.rev values
  in loop []

let tatoeba_name code =
  match code with
  | "ber" -> Some "Berber"
  | "kzj" -> Some "Coastal Kadazan"
  | "isv" -> Some "Interslavic"
  | _ -> None

let slugify name =
  String.map (function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' as c -> Char.lowercase_ascii c
    | _ -> '-') name

let json_string s =
  let b = Buffer.create (String.length s + 8) in
  Buffer.add_char b '"';
  String.iter (function
    | '"' -> Buffer.add_string b "\\\"" | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n" | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t" | c -> Buffer.add_char b c) s;
  Buffer.add_char b '"'; Buffer.contents b

let shell_quote value =
  "'" ^ String.concat "'\\''" (String.split_on_char '\'' value) ^ "'"

let word_count text =
  text |> String.split_on_char ' ' |> List.filter (fun x -> x <> "") |> List.length

let useful_sentence text =
  let text = String.trim text in
  let letters = ref 0 in
  String.iter (fun c -> if Char.code c >= 128 || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') then incr letters) text;
  String.length text >= 15 && String.length text <= 220 && word_count text >= 3 && word_count text <= 24 && !letters >= 6

let reservoir_sample limit channel =
  let chosen = Array.make limit "" in
  let count = ref 0 and seen = Hashtbl.create (limit * 2) in
  let eligible = ref 0 in
  (try while true do
    match String.split_on_char '\t' (input_line channel) with
    | _id :: _language :: text_parts ->
        let text = String.concat "\t" text_parts |> String.trim in
        if useful_sentence text && not (Hashtbl.mem seen text) then begin
          Hashtbl.add seen text ();
          incr eligible;
          if !count < limit then (chosen.(!count) <- text; incr count)
          else begin
            let slot = Random.int !eligible in
            if slot < limit then chosen.(slot) <- text
          end
        end
    | _ -> ()
  done with End_of_file -> ());
  Array.to_list (Array.sub chosen 0 !count) |> List.sort String.compare

let download_and_sample ~limit source =
  let url = Printf.sprintf "https://downloads.tatoeba.org/exports/per_language/%s/%s_sentences.tsv.bz2" source.code source.code in
  let command = "curl -fsSL --retry 3 " ^ shell_quote url ^ " | bzip2 -dc" in
  prerr_endline ("Downloading " ^ source.name ^ "…");
  let channel = Unix.open_process_in command in
  let sentences = reservoir_sample limit channel in
  match Unix.close_process_in channel with
  | Unix.WEXITED 0 -> sentences
  | _ -> failwith ("could not download " ^ source.name)

let write_file path sentences =
  let output = open_out path in
  output_string output "{\"sentences\":[";
  List.iteri (fun i sentence ->
    if i > 0 then output_char output ',';
    output_string output (json_string sentence)) sentences;
  output_string output "]}\n";
  close_out output

let () =
  let output = ref "public/sentences" and limit = ref 1000 in
  let codes_file = ref None and iso_names = ref "/usr/share/iso-codes/json/iso_639-3.json" in
  let args = Array.to_list Sys.argv |> List.tl in
  let rec parse = function
    | [] -> ()
    | "--output" :: value :: rest -> output := value; parse rest
    | "--codes" :: value :: rest -> codes_file := Some value; parse rest
    | "--iso-names" :: value :: rest -> iso_names := value; parse rest
    | value :: rest when String.starts_with ~prefix:"--limit=" value ->
        limit := int_of_string (String.sub value 8 (String.length value - 8)); parse rest
    | _ -> failwith "Usage: preprocess_sentences [--output DIR] [--limit=N]"
  in
  parse args;
  if !limit < 1 then failwith "limit must be positive";
  let sources =
    match !codes_file with
    | None -> default_sources
    | Some path ->
        let names = read_iso_names !iso_names in
        read_codes path |> List.map (fun code ->
          { code; name =
              match tatoeba_name code, Hashtbl.find_opt names code with
              | Some name, _ -> name | None, Some name -> name | None, None -> code })
  in
  Random.init 20261018;
  if not (Sys.file_exists !output) then Unix.mkdir !output 0o755;
  let written = ref [] in
  List.iter (fun source ->
    let file = slugify source.name ^ ".json" in
    let compressed = Filename.concat !output (file ^ ".gz") in
    if Sys.file_exists compressed then
      written := (source.name, file ^ ".gz") :: !written
    else begin
      let sentences = download_and_sample ~limit:!limit source in
      if sentences <> [] then begin
      write_file (Filename.concat !output file) sentences;
      ignore (Sys.command ("gzip -9 -f " ^ shell_quote (Filename.concat !output file)));
      written := (source.name, file ^ ".gz") :: !written
      end
    end) sources;
  let manifest = open_out (Filename.concat !output "manifest.json") in
  output_string manifest "{\n  \"source\": \"Tatoeba sentence exports\",\n  \"license\": \"CC BY 2.0 FR\",\n  \"languages\": [\n";
  List.rev !written |> List.iteri (fun i (name, file) ->
    if i > 0 then output_string manifest ",\n";
    Printf.fprintf manifest "    {\"name\":%s,\"file\":%s}" (json_string name) (json_string file));
  output_string manifest "\n  ]\n}\n";
  close_out manifest
