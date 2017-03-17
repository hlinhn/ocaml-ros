open Lwt
open RosHeader

       
let recvExact sock len =
  let buffer = Bytes.create len in
  let rec aux len acc =
    (Lwt_unix.recv sock buffer 0 len [])
    >>=
      (fun c ->
        if c < len then aux (len - c) ((String.sub buffer 0 c) :: acc)
        else Lwt.return (String.concat "" (List.rev ((String.sub buffer 0 c) :: acc)))) in
  aux len []

let sendHeader sock tname ttype md5 =
  let header = genHeader [("callerid", "mynode");
                          ("md5sum", md5);
                          ("tcp_nodelay", "0");
                          ("topic", tname);
                          ("type", ttype)
                         ] in
  Lwt_unix.send sock header 0 (String.length header) []
           
let getInfo sock =
  let () = Printf.printf "Getting info..\n%!" in
  let buff = Bytes.create 4 in
  Lwt_unix.recv sock buff 0 4 [] >>=
    (fun len -> if len == 0 then Lwt.return(None)
                else Lwt.return(Some (BatInt32.to_int (BatInt32.unpack buff 0)))) >>=
    (fun msglen ->
      match msglen with
      | None -> Lwt.return(None)
      | Some l -> let info = Bytes.create l in
                  (Lwt_unix.recv sock info 0 l []) >>=
                    (fun _ -> Lwt.return (Some info)))
      
let negotiatePub ttype md5 sock =
  getInfo sock
  >>= (fun msg ->
    match msg with
    | None -> Lwt.fail_with "No header"
    | Some m ->
       let conn = parseHeader m in
       let typeMatch =
         match (List.assoc "type" conn) with
         | t when t = ttype -> Lwt.return ()
         | _ -> Lwt.fail_with "Different type" in
       let md5Match =
         match (List.assoc "md5sum" conn) with
         | m when m = md5 -> Lwt.return ()
         | _ -> Lwt.fail_with "Not matching md5" in
       let nodelay =
         match (List.assoc "tcp_nodelay" conn) with
         | "1" ->
            Lwt.return (Lwt_unix.setsockopt sock Lwt_unix.TCP_NODELAY true)
         | _ -> Lwt.return () in
       
       let header = genHeader [("md5sum", md5);
                               ("type", ttype)
                              ] in
       typeMatch >>= (fun _ -> md5Match) >>= (fun _ -> nodelay) >>=
         (fun _ -> Lwt_unix.send sock header 0 (String.length header) []))
                
let negotiateSub sock tname ttype md5 =
  let _ = sendHeader sock tname ttype md5 in
  getInfo sock
  >>= (fun msg ->
    match msg with
    | None -> Lwt.fail_with "Got no header"
    | Some m ->
       let conn = parseHeader m in
       let typeMatch =
         match (List.assoc "type" conn) with
         | t when t = ttype -> Lwt.return ()
         | _ -> Lwt.fail_with "Different type" in
       let md5Match =
         match (List.assoc "md5sum" conn) with
         | m when m = md5 -> Lwt.return ()
         | _ -> Lwt.fail_with "Not matching md5" in
       typeMatch >>= (fun _ -> md5Match))    
  >>= (fun _ -> Lwt.return (Lwt_unix.setsockopt sock Lwt_unix.SO_KEEPALIVE true))

let getMsg m =
  let msglen = BatInt32.to_int (BatInt32.unpack (Bytes.sub m 0 4) 0) in
  let msg = Bytes.sub m 4 ((Bytes.length m) - 4) in
  (msglen, msg)
    
let rec print_info sock push =
  getInfo sock >>=
    (fun msg ->
      match msg with
      | None -> Lwt.return(Printf.printf "Publisher stopped\n")
      | Some m -> let (len, msg) = getMsg m in                  
                  Lwt.return(push (Some msg)) >>=
                    (fun _ -> print_info sock push))
(*      
let rec consume chan =
  Lwt_stream.get chan >>=
    (fun msg ->
      match msg with
      | None -> Lwt.return (Printf.printf "Empty\n")
      | Some m -> Lwt.return (Printf.printf "Consuming: %s\n%!" m))
  >>= (fun _ -> consume chan)
 *)                  
        
let subStream n tname chan push_func pub =
  let open Slave in
  let module S = Slave in
  let open Rpc in
  let open Cohttp in
  let open Node.Node in
  let open Cohttp_lwt_unix in
  let open Lwt_unix in
  Printf.printf "Connecting to %s for %s\n" pub tname;
  let c = Rpc.call "requestTopic" [String n;
                                   String tname;
                                   Enum [Enum [String "TCPROS"]];] in
  let body = Cohttp_lwt_body.of_string (Xmlrpc.string_of_call c) in
  let res = Client.post ~chunked:false ~body:body ~headers:(Header.init()) (Uri.of_string pub) in
  res >>= 
    (fun (r, b) ->
      let code = r |> Response.status |> Code.code_of_status in
      let () = Printf.printf "%d\n" code in       
      (b |> Cohttp_lwt_body.to_string >|=
         fun body ->
         let r = Xmlrpc.response_of_string body in
         if r.success then
           let _ = 
             match r.contents with
             | Enum [success; _; Enum [String "TCPROS"; host; port]]
               -> if (int_of_rpc success) == 1 then
                    let s_descr = socket PF_INET SOCK_STREAM 0 in
                    let ip = (Unix.gethostbyname (string_of_rpc host)).h_addr_list.(0) in
                    let addr = Unix.ADDR_INET (ip, int_of_rpc port) in
                    let conn = connect s_descr addr in
                    conn >>=
                      (fun _ -> (negotiateSub s_descr "/chatter" "std_msgs/String" "992ce8a1687cec8c8bd883ec73ca41d1")) >>=
                      (fun _ -> print_info s_descr push_func)
                  else
                    Lwt.return (Printf.printf "Match but not succeed\n%!")
             | _ -> Lwt.return (Printf.printf "Not match\n%!") in
           Printf.printf "%s\n%!" (Rpc.to_string r.contents)
         else Printf.printf "Failed"
    ))
      
                   
