open MasterAPI
open Lwt
let registerSubscription name sl master nuri (tname, ttype, _) =
  let open Node.Node in
  registerSubscriber master name tname ttype nuri >|=
    (fun (stt, _, ls) ->
      if stt == 1 then
        let update = publisherUpdate sl tname ls in
        let _ = update () in Printf.printf "Registered\n%!"
      else Printf.printf "Failed to register subscriber\n%!")

let registerPublication name sl master nuri (tname, ttype, _) =
  registerPublisher master name tname ttype nuri >|=
    (fun _ -> ())
    
let registerNode name sl =
  let open Node.Node in
  let nuri = sl.nodeUri in
  let master = sl.master in
  let p = fun () -> Lwt.join (List.map (registerPublication name sl master nuri) (getPublications sl)) in
  let s = fun () -> Lwt.join (List.map (registerSubscription name sl master nuri) (getSubscriptions sl)) in
  s () >>= (fun _ -> p ())

let makeSub tname msgLocation nname =
  let open Node.Node in
  let open Tcp in
  let (channel, push) = Lwt_stream.create () in
  let (ttype, _) = TypeInfo.createTypeInfo msgLocation in
  let newsubs = { publishers = [];
                  subType = ttype;
                  add = subStream nname tname msgLocation push;
                  subStats = []; } in
  (newsubs, channel)
    
let makePub _topic msgLocation push =
  let open Slave in
  let open Node.Node in
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
  let open Node.Node in
  let subs_list = node.subscribe in
  if List.mem_assoc tname subs_list then (node, None)
  else
    if List.mem_assoc tname node.publish then (node, None)
    else
      let (newsubs, chan) = makeSub tname msgLocation node.nodeName in
      ({ node with subscribe = (tname, newsubs) :: node.subscribe },
       Some chan)
        
let advertise chan push tname msgLocation node =
  let open Node.Node in
  let open Tcp in
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

let initNode name =
  let open Node.Node in
  let master_ = try Unix.getenv "ROS_MASTER_URI" with
               | Not_found -> raise (Failure "Master URI is not set")
               | _ -> raise (Failure "Errors while getenv") in
  
  { nodeName = name;
    master = master_;
    nodeUri = "";
    signalShutdown = Lwt_switch.create();
    subscribe = [];
    publish = [];
  }

let runNode name sl =
  let open Slave in
  let open Node.Node in

  let quit = Lwt_switch.create () in
  let () = setShutdownAct sl quit in

  let (waitSig, stop, w, run) = runSlave sl in
  let () = Lwt_switch.add_hook
             (Some quit) (fun () -> cleanupNode sl >|=
                                      (fun _ -> stop ()) >|=
                                      (fun _ -> Lwt.wakeup w ())
                         ) in
  
  let handler = function
    | n when n = Sys.sigint -> Lwt.async (fun () -> Lwt_switch.turn_off quit)
    | _ -> Printf.printf "Unhandled\n%!" in
  let () = Sys.catch_break true in
  let () = Sys.set_signal Sys.sigint (Sys.Signal_handle handler) in
  let () = run () in
  ignore (Lwt_main.run (
              registerNode name sl
              >>= (fun _ -> waitSig ())))
        
