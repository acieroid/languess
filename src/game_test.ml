let fail message = prerr_endline message; exit 1
let expect condition message = if not condition then fail message

let () =
  expect (Game.utf8_length "café" = 4) "word length must count Unicode characters";
  let index =
    Game.build_index ~minimum_length:5
      [ ("English", [ "House"; "shared"; "tiny" ]);
        ("German", [ "Haus"; "shared"; "klein" ]) ]
  in
  expect (Game.languages_for index "shared" = [ "English"; "German" ])
    "shared words must retain every language";
  expect (Game.languages_for index "tiny" = []) "minimum word length must filter";
  expect (Game.answer_is_correct ~correct:[ "English"; "German" ] "german")
    "answers should be case insensitive";
  Random.init 7;
  let options =
    Game.choices ~available_languages:[ "English"; "German"; "French"; "Spanish" ]
      ~correct:[ "English"; "German" ] ~count:3
  in
  expect (List.length options = 3) "choice count";
  expect (List.length (List.sort_uniq String.compare options) = List.length options)
    "choices must be distinct";
  expect (List.exists (fun x -> x = "English" || x = "German") options)
    "choices must include a correct language"
