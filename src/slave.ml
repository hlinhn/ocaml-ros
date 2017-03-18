(*
receive callbacks from master
negotiating connections with other nodes
 *)

open Node.Node
open Rpc
open MasterAPI
       
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

let callRequestTopic addr nname tname prot_ls =
  let call = Rpc.call "requestTopic"
                      [String nname; String tname; Enum prot_ls] in
  postReq call addr
            
let shutdown n cond id =
  (*  let _ = stopNode n in*)
  let () = Lwt.async (fun () -> Lwt_switch.turn_off n.signalShutdown) in
  Enum [rInt 1; String "Shutting down"; Bool true]
       
let cleanupNode n =
  let open Lwt in
  let open MasterAPI in
  let pubs = n.publish in
  let subs = n.subscribe in
  let nuri = n.nodeUri in
  let nname = n.nodeName in
  let master = n.master in
  let () = Printf.printf "In cleanupNode\n%!" in
  let sp = fun () -> Lwt.join (List.map (fun p -> unregisterPublisher master nname (fst p) nuri >|= (fun _ ->())) pubs) in
  let ss = fun () -> Lwt.join (List.map (fun s -> unregisterSubscriber master nname (fst s) nuri >|= (fun _ ->())) subs) in
  sp () >>= (fun _ -> ss ()) >|= (fun _ -> stopNode n)
  
let slaveRPC tnode cond req =
  match req.name with
  | "publisherUpdate" -> pubUpdate tnode req.params
  | "requestTopic" -> requestTopic tnode req.params
  | "getBusStats" -> getBusStats tnode req.params
  | "getBusInfo" -> getBusInfo tnode req.params
  | "getMasterUri" -> getMasterUri tnode req.params
  | "shutdown" -> shutdown tnode cond req.params
  | "getPid" -> getPid tnode
  | "getSubscriptions" -> getSubs tnode req.params
  | "getPublications" -> getPubs tnode req.params
  | _ -> Enum [rInt 0; String "Unknown"; rInt 1]
    
let handle_request tnode cond req =
  let rep = slaveRPC tnode cond (Xmlrpc.call_of_string req) in
  String.concat "" ["<?xml version=\"1.0\"?><methodResponse><params><param>"; Xmlrpc.to_string rep; "</param></params></methodResponse>"]

let findPort () =
  let s_descr = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  let name = Unix.gethostname () in
  let addr = (Unix.gethostbyname name).Unix.h_addr_list.(0) in  
  let () = Unix.bind s_descr (Unix.ADDR_INET(addr, 0)) in
  let (_, p) =
    match Unix.getsockname s_descr with
      Unix.ADDR_INET (a, n) -> (a, n)
    | _ -> failwith "Not INET" in
  let () = Unix.close s_descr in
  (addr, p)

let server pnum handler =
  let open Lwt in
  let open Cohttp in
  let open Cohttp_lwt_unix in
  let callback _conn req body =
    body |> Cohttp_lwt_body.to_string >|=
      (fun body ->
        (Printf.sprintf "%s" (handler body)))
    >>= (fun body ->
      Server.respond_string ~headers:(Header.init_with "content-type" "text/xml") ~status:`OK ~body ()) in
  Server.create ~mode:(`TCP (`Port pnum)) (Server.make ~callback ()) 

let runLoop ?cleanup:(fc = fun () -> ()) ?message:(msg = "") f =
  let open Lwt in
  let (t, w) = Lwt.wait () in
  let exec = (t >>= fun _ -> f()) in
  let thread_t = ref exec in
  let launch () = 
    let () = Lwt.wakeup w () in
    Lwt.async (fun () ->
        Lwt.catch (fun () -> !thread_t)
                  (fun exn -> fc ();
                              Lwt.return (Printf.printf "%s\n%!" msg))) in
  let cancel = fun () -> Lwt.cancel !thread_t in
  (launch, cancel)

    
let runSlave sl =
  let open Lwt in
  let quitsig = Lwt_condition.create () in
  let (_, p) = findPort () in
  let nuri = String.concat "" ["http://"; Unix.gethostname (); ":"; Pervasives.string_of_int p] in
  let () = sl.nodeUri <- nuri in
  let serv = fun () -> server p (handle_request sl quitsig) in

  let (run_server, stop_server) = runLoop ~message:"Terminating server"
                                          ~cleanup:(fun () -> Lwt_condition.signal quitsig ())
                                          serv in
  let () = Lwt_switch.add_hook (Some sl.signalShutdown) (fun () -> Lwt.return (Lwt_condition.signal quitsig ())) in
  let () = run_server () in
  let wait_t = fun () ->
    (Lwt_condition.wait quitsig) >>=
      (fun _ -> Lwt_unix.sleep 1.0) >>=
      (fun _ -> (*let _ = stopNode sl in*)
                Lwt.return (stop_server ())) in
  wait_t 
       
