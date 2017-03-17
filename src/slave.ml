(*
receive callbacks from master
negotiating connections with other nodes
every node has one of these
 *)
open Node.Node
open Rpc
       
let rInt x = Int32 (BatInt32.of_int x)
let mkPub (n, _, pub) =
  let formatStats (_, p) = Enum [rInt 0; rInt p.byteSent; rInt p.numSent; Bool p.pubConnected] in
  Enum [String n; rInt 0; Enum (List.map formatStats pub)]

let mkSub (n, _, sub) =
  let formatStats (_, s) = Enum [rInt 0; rInt s.byteReceived; rInt (-1); Bool s.subConnected] in
  Enum [String n; rInt 0; Enum (List.map formatStats sub)]

(* all functions below ignore id - most likely used for debugging 
   So any functions that used node and id alone is not going to have
   modules to convert to rpc
 *)
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

    
let getBusStats n id =  
  let pub = Enum (List.map mkPub (getPublications n)) in
  let sub = Enum (List.map mkSub (getSubscriptions n)) in
  let serv = Enum [rInt 0; rInt 0; rInt 0] in
  Enum [rInt 1; String "Bus stats"; Enum [pub; sub; serv]] 

let getBusInfo n id =
  let formatPub (name, _, stats) =
    List.map (fun (u, _) -> Enum [rInt 0; String u; String "o"; String "TCPROS"; String name]) stats in
  let formatSub (name, _, stats) =
    List.map (fun (u, _) -> Enum [rInt 0; String u; String "i"; String "TCPROS"; String name]) stats in
  let pubs = List.flatten (List.map formatPub (getPublications n)) in
  let subs = List.flatten (List.map formatSub (getSubscriptions n)) in
  Enum [rInt 1; String "Bus info"; Enum (pubs @ subs)]

let getMasterUri n id =
  Enum [rInt 1; String "Master uri"; String n.master]

let getPid id = Enum [rInt 1; String "Pid"; rInt (Unix.getpid())]

let getSubs n id =
  let s = Enum (List.map (fun (n, t, _) -> Enum [String n; String t]) (getSubscriptions n)) in
  Enum [rInt 1; String "Subscriptions"; s]

let getPubs n id =
  let p = Enum (List.map (fun (n, t, _) -> Enum [String n; String t]) (getPublications n)) in
  Enum [rInt 1; String "Publications"; p]

let paramUpdate n ls =
  (* ls = [id; key; val] Not implemented at the moment *)
  Enum [rInt 1; String "Params not updated"; Bool true]

let pubUpdate n ls =
  let module PubType = struct
      type t = (string * string * string list) with rpc
    end in
  let module Pub = MakeParam(PubType) in
  let params = Pub.unroll ls in
  match params with
  | (id, top, pubs) ->
     let m = publisherUpdate n top pubs in
     let _ = m () in
     Enum [rInt 1; String "Publisher updated"; rInt 1]

let getNodeName n =
  let extractName u =
    let len = (String.index u '/') + 2 in
    let m = String.sub u len (String.length u - len) in
    let p = String.index m ':' in
    String.sub m 0 p in
  extractName n.nodeUri
              
let requestTopic n ls =
  let module RequestType =
    struct
      type t = (string * string * string list list) with rpc
    end in
  let module ReqParam = MakeParam(RequestType) in
  let params = ReqParam.unroll ls in
  match params with
  | (id, top, prot) ->
     if (List.exists (fun x -> List.mem "TCPROS" x) prot) then
       match (getPort n top) with
       | None -> Enum [rInt 0; String "Unknown topic"; Enum []]
       | Some p -> Enum [rInt 1; String "Using TCP"; Enum [String "TCPROS"; String (getNodeName n); rInt p]]
     else
       Enum [rInt 1; String "No protocols supported"; Enum []]

let shutdown n id =
  (* some cleanup action here *)
  (1, "", true)

let slaveRPC n sem s =
  ()
