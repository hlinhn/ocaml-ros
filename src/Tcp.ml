open Lwt
open RosHeader

let sendHeader sock nname tname ttype md5 =
  let header = genHeader [("callerid", nname);
                          ("md5sum", md5);
                          ("tcp_nodelay", "0");
                          ("topic", tname);
                          ("type", ttype)] in
  Lwt_unix.send sock header 0 (String.length header) []
           
let getInfo sock =
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
      
let checkType msg ttype md5 =
  let conn = parseHeader msg in
  let typeMatch =
    match (List.assoc "type" conn) with
    | t when t = ttype -> Lwt.return ()
    | _ -> Lwt.fail_with "Different type" in
  let md5Match =
    match (List.assoc "md5sum" conn) with
    | m when m = md5 -> Lwt.return ()
    | _ -> Lwt.fail_with "Not matching md5" in
  typeMatch >>= (fun _ -> md5Match)

let negotiatePub nname ttype md5 sock =
  getInfo sock
  >>= (fun msg ->
    match msg with
    | None -> Lwt.fail_with "No header"
    | Some m ->
       let conn = parseHeader m in
       let nodelay =
         match (List.assoc "tcp_nodelay" conn) with
         | "1" ->
            Lwt.return (Lwt_unix.setsockopt sock Lwt_unix.TCP_NODELAY true)
         | _ -> Lwt.return () in
       
       let header = genHeader [("callerid", nname); ("md5sum", md5); ("type", ttype)] in
       (checkType m ttype md5) >>= (fun _ -> nodelay) >>=
         (fun _ -> Lwt_unix.send sock header 0 (String.length header) []))
                
let negotiateSub sock nname tname ttype md5 =
  let _ = sendHeader sock nname tname ttype md5 in
  getInfo sock
  >>= (fun msg ->
    match msg with
    | None -> Lwt.fail_with "Got no header"
    | Some m -> checkType m ttype md5) 
  >>= (fun _ -> Lwt.return (Lwt_unix.setsockopt sock Lwt_unix.SO_KEEPALIVE true))

let getMsg m =
  let msglen = BatInt32.to_int (BatInt32.unpack (Bytes.sub m 0 4) 0) in
  let msg = Bytes.sub m 4 ((Bytes.length m) - 4) in
  (msglen, msg)
    
let rec pushInfo sock push unpack =
  getInfo sock >>=
    (fun msg ->
      match msg with
      | None -> Lwt.return (Printf.printf "Publisher stopped\n%!")
      | Some m -> let orig = unpack m in
                  Lwt.return (push (Some orig)) >>=
                    (fun _ -> Lwt_unix.yield ()) >>=
                    (fun _ -> pushInfo sock push unpack))
        
let subStream nname tname msgLocation push publisher =
  let open Slave in
  let open Rpc in
  let open Node.Node in
  let open Lwt_unix in
  let open TypeInfo in
  
  Printf.printf "Connecting to %s for %s\n" publisher tname;
  callRequestTopic publisher nname tname [Enum [String "TCPROS"]] >>=
    (fun contents ->
      match contents with
      | Enum [success; _; Enum [String "TCPROS"; host; port]]
        -> if (int_of_rpc success) == 1 then
             let s_descr = socket PF_INET SOCK_STREAM 0 in
             let ip = (Unix.gethostbyname (string_of_rpc host)).h_addr_list.(0) in
             let addr = Unix.ADDR_INET (ip, int_of_rpc port) in
             let conn () = connect s_descr addr in
             let (ttype, md5) = createTypeInfo msgLocation in
             let unpackFun = unpackType msgLocation in
             let (launch, cancel) = runLoop
                                      ~message:"Abort pushing info to stream\n%!" 
                                      (fun () -> pushInfo s_descr push unpackFun) in
             conn ()
             >>= (fun _ -> negotiateSub s_descr nname tname ttype md5)
             >|= (fun _ -> launch ())
           else
             Lwt.return (Printf.printf "Failed to request topic\n%!")
      | _ -> Lwt.return (Printf.printf "Not supported\n%!"))

let rec writeClient sock st =
  Lwt_stream.get st
  >>= (fun msg ->
    match msg with
    | Some m -> Lwt_unix.send sock m 0 (String.length m) []
                >>= (fun _ -> Lwt_unix.yield ())
                >>= (fun _ -> writeClient sock st)
    | None -> Lwt.return ())
      
let rec acceptClient sock pub negotiate cleanup =
  let open Node.Node in
  let open Slave in
  Lwt_unix.accept sock
  >>= (fun (clientSock, _) ->
    negotiate clientSock
    >>= (fun _ ->
         let clients = pub.subAddr in
         let (st, pf) = Lwt_stream.create () in
         let () = pub.subAddr <- ((clientSock, (pf, st)) :: clients) in
         let (launch, cancel) = runLoop
                                  ~cleanup:(fun () ->
                                    pub.subAddr <- List.remove_assoc clientSock pub.subAddr)
                                  (fun () -> writeClient clientSock st) in
         let () = launch () in
         Printf.printf "Accepted..\n%!";
         acceptClient sock pub negotiate
                      (cleanup
                       >>= (fun _ -> if Lwt_unix.state clientSock == Lwt_unix.Opened then Lwt_unix.close clientSock else Lwt.return (Printf.printf "Already closed\n%!"))
  )))
        
let rec pubAction tp formatMsg publisher =
  let open Node.Node in
  Lwt_stream.get tp >>=
    (fun elem ->
      let tosend = 
        match elem with
        | Some e -> Some (formatMsg e)
        | None -> None in
      let clients = publisher.subAddr in
      let _ = List.map (fun (_, (pf, _)) -> pf tosend) clients in
      match elem with
      | Some e -> Lwt_unix.yield ()
                  >>= fun _ -> pubAction tp formatMsg publisher
      | None -> Lwt.return ())

let runServerHelper pnum negotiate publishStream publisher =
  let open Slave in
  let sock = Lwt_unix.socket Lwt_unix.PF_INET Lwt_unix.SOCK_STREAM 0 in
  let addr = (Unix.gethostbyname (Unix.gethostname ())).Unix.h_addr_list.(0) in 
  let () = Lwt_unix.bind sock (Lwt_unix.ADDR_INET(addr, pnum)) in
  let () = Lwt_unix.listen sock 5 in
  let (t, w) = Lwt.wait () in
  let accept () = acceptClient sock publisher negotiate t in
  let (serve, stop) = runLoop (fun () -> publishStream publisher)
                              ~message:"Stop server helper here\n%!"
  in
  let () = Lwt.async (fun () -> accept ()) in
  let () = serve () in
  let cleanup () = Lwt.wakeup w (); Lwt.return (stop ())
                   (*Lwt_unix.close sock
                   >>= fun _ -> Lwt.return (Printf.printf "Closed socket\n%!"*) in
  cleanup

let runServers nname ls =
  let (t, w) = Lwt.wait () in
  let _ = List.fold_left
            (fun x y -> Lwt.bind x (fun _ -> y ())) t
            (List.map (fun (pnum, msgLocation, tp, publisher) ->
                 let formatMsg = TypeInfo.formatType msgLocation in
                 let publishStream = pubAction tp formatMsg in
                 let (ttype, md5) = TypeInfo.createTypeInfo msgLocation in
                 let negotiate = negotiatePub nname ttype md5 in
                 runServerHelper pnum negotiate publishStream publisher) ls) in
  w
