open Lwt
open Cohttp_lwt_unix
open Rpc
open Xmlrpc
open Cohttp

module type RPC_TYPE =
  sig
    type t
    val rpc_of_t : t -> Rpc.t
    val t_of_rpc : Rpc.t -> t
  end
    
module type PARAM =
  functor (R: RPC_TYPE) ->
  sig
    type a = R.t
    val convert_to_rpc: a -> Rpc.t
    val convert_to_t: Rpc.t -> a
    val unroll : Rpc.t list -> a
  end

module MakeParam : PARAM =
  functor (R: RPC_TYPE) ->
  struct
    type a = R.t
    let convert_to_rpc x = R.rpc_of_t x
    let convert_to_t x = R.t_of_rpc x
    let unroll x =
      let open Rpc in
      let open Xmlrpc in
      let str = Xmlrpc.to_string (Enum x) in  
      let middle = Xmlrpc.of_string str in
      R.t_of_rpc middle    
  end
       
(* print code for debugging, remove afterwards *)
let checkRep r body =
  let code = r |> Response.status |> Code.code_of_status in
  let () = Printf.printf "%d\n" code in       
  (body |> Cohttp_lwt_body.to_string >|=
     fun b ->
     let res = Xmlrpc.response_of_string b in
     if res.success then res.contents
     else String "Failed")
   
let postReq call dest =
  let body = Cohttp_lwt_body.of_string (Xmlrpc.string_of_call call) in
  let req = Client.post ~chunked:false ~body:body
                        ~headers:(Header.init_with "content-type" "text/xml")
                        (Uri.of_string dest) in
  req >>= (fun (r, b) -> checkRep r b)

let unregisterPublisher master nname tname nuri =
  let module UnregP = struct
      type t = (int * string * int) with rpc
    end in
  let call = Rpc.call "unregisterPublisher"
                      [String nname; String tname; String nuri] in
  postReq call master >|= (fun rep -> UnregP.t_of_rpc rep)

let unregisterSubscriber master nname tname nuri =
  let module UnregS = struct
      type t = (int * string * int) with rpc
    end in
  let call = Rpc.call "unregisterSubscriber"
                      [String nname; String tname; String nuri] in
  postReq call master >|= (fun rep -> UnregS.t_of_rpc rep)

let registerPublisher master nname tname ttype nuri =
  let module RegP = struct
      type t = (int * string * string list) with rpc
    end in
  let call = Rpc.call "registerPublisher"
                      [String nname; String tname; String ttype; String nuri] in
  postReq call master >|= (fun rep -> RegP.t_of_rpc rep)

let registerSubscriber master nname tname ttype nuri =
  let module RegS = struct
      type t = (int * string * string list) with rpc
    end in
  let call = Rpc.call "registerSubscriber"
                      [String nname; String tname; String ttype; String nuri] in
  postReq call master >|= (fun rep -> RegS.t_of_rpc rep)
