(* Entry in the header: 
1. the length of the whole message, 32 int, little endian
2. the length of the field
   name of the field
   equal sign
   value of the field

   Contrary to the wiki, subscriber doesn't send message definition - 
publisher does. At least the version of roscpp does, so I assume
it's the case here
 *)

type connHeader = ConnHeader of (string * string) list

let taglen str =
  let len = BatInt32.of_int (String.length str) in
  let lenstr = Bytes.create 4 in
  let () = BatInt32.pack lenstr 0 len in
  String.concat "" [lenstr; str]
                
let genHeader infos =
  let mainstr = String.concat "" (List.map (fun (x, y) ->
                                      let str = String.concat "=" [x; y] in
                                      taglen str) infos) in
  taglen mainstr

let parsePair msg =
  let msglen = Bytes.sub msg 0 4 in
  let len = BatInt32.to_int (BatInt32.unpack msglen 0) in
  let content = Bytes.sub msg 4 len in
  let eqInd = Bytes.index content '=' in
  let pair = ((Bytes.sub content 0 eqInd),
              (Bytes.sub content (eqInd + 1) (len - eqInd - 1))) in
  (pair, len + 4)
              
let rec parseHeader msg =
  match (Bytes.length msg) with
  | 0 -> []
  | _ -> let (p, len) = parsePair msg in
         let rst = Bytes.sub msg len (Bytes.length msg - len) in
         p :: (parseHeader rst)
                
