open Node.Node
open Tcp
open Lwt
open Slave
open RunNode
       
let makeSub tname msgLocation nname =
  let (channel, push) = Lwt_stream.create () in
  let (ttype, _) = TypeInfo.createTypeInfo msgLocation in
  let newsubs = { publishers = [];
                  subType = ttype;
                  add = subStream nname tname msgLocation push;
                  subStats = []; } in
  (newsubs, channel)
    
let makePub _topic msgLocation push =
  let open Slave in
  let (_, pnum) = findPort () in
  let (ttype, _) = TypeInfo.createTypeInfo msgLocation in
  let newpubs = { subscribers = [];
                  subAddr = [];
                  pubType = ttype;
                  pubPort = pnum;
                  pubTopic = Topic _topic;
                  pubCleanUp = (fun () -> push None);
                  pubStats = [] } in
  newpubs
    
let subscribe tname msgLocation node =
  let subs_list = node.subscribe in
  if List.mem_assoc tname subs_list then (node, None)
  else
    if List.mem_assoc tname node.publish then (node, None)
    else
      let (newsubs, chan) = makeSub tname msgLocation node.nodeName in
      ({ node with subscribe = (tname, newsubs) :: node.subscribe },
       Some chan)
        
let advertise chan push tname msgLocation node =
  let pub_list = node.publish in
  if List.mem_assoc tname pub_list then (node, None)
  else
    if List.mem_assoc tname node.subscribe then (node, None)
    else
      let newpubs = makePub chan msgLocation push in
      let nodenew = { node with publish = (tname, newpubs) :: node.publish } in
      let info = (newpubs.pubPort, msgLocation, chan, newpubs) in
      let cleanup = runServers nodenew.nodeName [info] in
      (nodenew, Some cleanup)
                                           
let mynode = { nodeName = "Mynode";
               master = "http://localhost:11311";
               nodeUri = "";
               signalShutdown = Lwt_switch.create();
               subscribe = [];
               publish = [];
             }
               
let rec consume chan =
  Lwt_stream.get chan
  >>= (fun msg ->
    match msg with
    | None -> Lwt.return (Printf.printf "End\n%!")
    | Some m -> Printf.printf "%s\n%!" m;
                consume chan)

let rec feed push n =
  let msg = String.concat " " ["Hello World"; Pervasives.string_of_int n] in
  let () = Printf.printf "%s\n%!" msg in
  Lwt.return (push (Some msg)) >>=
    (fun _ -> Lwt_unix.sleep 1.0) >>=
    (fun _ -> feed push (n + 1))
        
(*let () =
  let (nnode, chan) = subscribe "/chatter" "" mynode in
  let () =
    match chan with
    | None -> ()
    | Some c ->
       let (run, cancel) = runLoop (fun () -> consume c) in
       run () in
  ignore (runNode "Mynode" nnode)
 *)

let () =
  let (chan, push) = Lwt_stream.create () in
  let (nnode, waitsig) = advertise chan push "/chatter" "" mynode in
  let () =
    match waitsig with
    | None -> ()
    | Some signal ->
       let (run, cancel) = runLoop (fun () -> feed push 0)
                                   ~cleanup:(fun () -> Lwt.wakeup signal ()) in
       run () in
  ignore (runNode "Mynode" nnode)
