type index = (string, string list) Hashtbl.t

let utf8_length s =
  let count = ref 0 in
  String.iter (fun c -> if Char.code c land 0xc0 <> 0x80 then incr count) s;
  !count

(* Dictionary files are case-folded at preprocessing time.  This additional
   ASCII fold also makes callers robust when given hand-written sample data. *)
let normalize s = String.lowercase_ascii (String.trim s)

let build_index ~minimum_length dictionaries =
  let result = Hashtbl.create 1024 in
  List.iter
    (fun (language, words) ->
      List.iter
        (fun raw_word ->
          let word = normalize raw_word in
          if word <> "" && utf8_length word >= minimum_length then
            let old = match Hashtbl.find_opt result word with Some x -> x | None -> [] in
            if not (List.mem language old) then Hashtbl.replace result word (language :: old))
        words)
    dictionaries;
  result

let words index = Hashtbl.to_seq_keys index |> List.of_seq
let languages_for index word =
  match Hashtbl.find_opt index (normalize word) with Some xs -> List.rev xs | None -> []

let shuffle values =
  let a = Array.of_list values in
  for i = Array.length a - 1 downto 1 do
    let j = Random.int (i + 1) in
    let t = a.(i) in a.(i) <- a.(j); a.(j) <- t
  done;
  Array.to_list a

let choices ~available_languages ~correct ~count =
  match correct with
  | [] -> []
  | _ ->
      let correct_choice = List.nth correct (Random.int (List.length correct)) in
      let incorrect =
        available_languages
        |> List.filter (fun language -> not (List.mem language correct))
        |> shuffle
      in
      let needed = max 0 (count - 1) in
      let rec take n xs =
        if n = 0 then [] else match xs with [] -> [] | x :: rest -> x :: take (n - 1) rest
      in
      shuffle (correct_choice :: take needed incorrect)

let answer_is_correct ~correct answer =
  let normalized = normalize answer in
  List.exists (fun language -> normalize language = normalized) correct
