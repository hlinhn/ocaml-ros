open Slave
open Node.Node
open Cohttp
open Lwt
open Xmlrpc
open Tcp

let msg_format m =
  let open RosHeader in
  let mainstr = taglen m in
  taglen mainstr

let rec pubAction top pub =
  Lwt_stream.get top >>=
    (fun elem ->
      match elem with
      | Some e ->
         let clients = pub.subAddr in
         let () = Printf.printf "Got elem for %d\n%!" (List.length clients) in
         let msg = msg_format e in
         Lwt.join (List.map (fun s -> Lwt_unix.send s msg 0 (String.length msg)[] >>= (fun _ -> Lwt.return (Printf.printf "Sending..\n%!"))) clients)
      | None -> Lwt.return ())
  >>= (fun _ -> pubAction top pub)
        
let rec acceptClient sock pub negotiate =
  Lwt_unix.accept sock >>=
    (fun (clientSock, _) ->
      let () = Printf.printf "Accepted\n%!" in
      negotiate clientSock >>=
        (fun _ -> let clients = pub.subAddr in
                  let () = pub.subAddr <- (clientSock :: clients) in
                  Lwt.return (Printf.printf "Accepted..\n%!")))
  >>=
    (fun _ -> acceptClient sock pub negotiate)
          
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
    
let runServer (addr, pnum) top pub ttype md5 =
  let sock = Lwt_unix.socket Lwt_unix.PF_INET Lwt_unix.SOCK_STREAM 0 in
  let () = Lwt_unix.bind sock (Lwt_unix.ADDR_INET(addr, pnum)) in
  let () = Lwt_unix.listen sock 5 in
  let () = Printf.printf "Started: %d\n%!" pnum in
  let accept_t () = acceptClient sock pub (negotiatePub ttype md5) in
  let serve_t () = pubAction top pub in
  let () = Lwt.async (fun () -> accept_t ()) in
  Lwt.async (fun () -> serve_t ()) 
            
let makePub top ttype md5 =
  let (addr, pnum) = findPort () in
  
  let pub = { subscribers = [];
              subAddr = [];
              pubType = ttype;
              pubPort = pnum;
              pubTopic = (Topic top);
              pubStats = []; } in
 
  let () = runServer (addr, pnum) top pub ttype md5 in
  pub

let (c, p) = Lwt_stream.create ()

let createNode pnum =
  let mypub = makePub c "std_msgs/String" "992ce8a1687cec8c8bd883ec73ca41d1" in
  let host = Unix.gethostname () in
  let uri = String.concat "" ["http://"; host; ":"; Pervasives.string_of_int pnum] in
  let mynode = { startUpNode with 
                 nodeName = "MynodePub";
                 master = "http://localhost:11311";
                 nodeUri = uri;
                 publish = [("/chatter", mypub)]
               } in
  mynode
               
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
  | "requestTopic" -> requestTopic tnode req.params
  | _ -> Enum [rInt 1; String "Unknown"; rInt 1]
    
let handle_request req tnode =
  let open Rpc in
  let rep = create_response (Xmlrpc.call_of_string req) tnode in
  String.concat "" ["<?xml version=\"1.0\"?><methodResponse><params><param>"; Xmlrpc.to_string rep; "</param></params></methodResponse>"]

let rec produce n =
  let msg = String.concat " " ["Hello World"; Pervasives.string_of_int n] in
  let () = Printf.printf "%s\n%!" msg in
  Lwt.return (p (Some msg)) >>=
    (fun _ -> Lwt_unix.sleep 5.0) >>=
    (fun _ -> produce (n + 1))
                
let () = 
  let open Cohttp_lwt_unix in
  let open Rpc in
  let () = Printf.printf "Id: %d\n%!" (Unix.getpid ()) in
  let (_, pnum) = findPort () in
  let addr = Unix.gethostname () in
  let mynode = createNode pnum in
  let reg =
    (registerPub mynode (addr, pnum))
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
  let () = Lwt.async (fun () -> produce 0) in
  let server =
    let callback _conn req body =
      body |> Cohttp_lwt_body.to_string >|=
        (fun body ->
          (Printf.sprintf "%s" (handle_request body mynode)))
      >>= (fun body ->
        Server.respond_string ~headers:(Header.init_with "content-type" "text/xml") ~status:`OK ~body ())
    in
    Server.create ~mode:(`TCP (`Port pnum)) (Server.make ~callback ()) in
  ignore (Lwt_main.run (reg >>= (fun _ -> server)))

