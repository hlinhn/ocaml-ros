open Slave
open Node.Node
open Cohttp
open Lwt
open Xmlrpc
open Tcp
       
let (channel, push_fun) = Lwt_stream.create ()
let mynode = { startUpNode with 
               nodeName = "Mynode";
               master = "http://localhost:11311";
               subscribe = [("/chatter",
                             { startUpSub with subType = "std_msgs/String";
                                               add = subStream "Mynode" "/chatter" channel push_fun})];
               publish = [("/odom",
                           { startUpPub with pubType = "nav_msgs/Odometry" })]
             }
               
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
  (name, p)
    
let registerSub n (host, pnum) =
  let open Cohttp_lwt_unix in
  let open Rpc in
  let open Xmlrpc in
  let open Unix in
  let (name, sub) = List.hd n.subscribe in
  let intf = String.concat "" ["http://"; host; ":"; Pervasives.string_of_int pnum] in
  let c = Rpc.call "registerSubscriber" [String n.nodeName;
                                         String name;
                                         String sub.subType;
                                         String intf] in
  let body = Cohttp_lwt_body.of_string (Xmlrpc.string_of_call c) in
  Client.post ~chunked:false ~body:body ~headers:(Header.init()) (Uri.of_string n.master) 

let registerPub n (host, pnum) =
  let open Cohttp_lwt_unix in
  let open Rpc in
  let open Xmlrpc in
  let open Unix in
  let (name, pub) = List.hd n.publish in
  let intf = String.concat "" ["http://"; host; ":"; Pervasives.string_of_int pnum] in
  let c = Rpc.call "registerPublisher" [String n.nodeName;
                                        String name;
                                        String pub.pubType;
                                        String intf] in
  let body = Cohttp_lwt_body.of_string (Xmlrpc.string_of_call c) in
  Client.post ~chunked:false ~body:body ~headers:(Header.init()) (Uri.of_string n.master) 
  
let create_response req tnode =
  let open Rpc in
  match req.name with
  | "publisherUpdate" -> pubUpdate tnode req.params
  | _ -> Enum [rInt 1; String "Unknown"; rInt 1]
    
let handle_request req =
  let open Rpc in
  let rep = create_response (Xmlrpc.call_of_string req) mynode in
  String.concat "" ["<?xml version=\"1.0\"?><methodResponse><params><param>"; Xmlrpc.to_string rep; "</param></params></methodResponse>"]

let () = 
  let open Cohttp_lwt_unix in
  let open Rpc in
  let () = Printf.printf "Id: %d\n%!" (Unix.getpid ()) in
  let (host, pnum) = findPort() in
  let reg =
    (registerSub mynode (host, pnum))
    >>=
      (fun (r, b) ->
        let code = r |> Response.status |> Code.code_of_status in
        let () = Printf.printf "%d\n" code in       
        (b |> Cohttp_lwt_body.to_string >|=
           fun body ->
           let r = Xmlrpc.response_of_string body in
           if r.success then Printf.printf "%s\n%!" (Rpc.to_string r.contents)
           else Printf.printf "Failed"
      )) in
  
  let server =
    let callback _conn req body =
      body |> Cohttp_lwt_body.to_string >|=
        (fun body ->
          (Printf.sprintf "%s" (handle_request body)))
      >>= (fun body ->
        (Printf.printf "%s\n%!" body);
        Server.respond_string ~status:`OK ~body ())
    in
    Server.create ~mode:(`TCP (`Port pnum)) (Server.make ~callback ()) in
  ignore (Lwt_main.run (reg >>= (fun _ -> server)))

         
         


               
               
