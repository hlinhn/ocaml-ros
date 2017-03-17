
let registerSubscription name sl master uri (tname, ttype, _) =
  let (stt, _, ls) = registerSubscriber master name tname ttype uri in
  if stt == 1 then publisherUpdate sl tname ls
  else Lwt.return (Printf.printf "Failed to register subscriber")

let registerPublication name sl master uri (tname, ttype, _) =
  let (stt, _, ls) = registerPublisher master name tname ttype uri in
  ()
    
let registerNode name sl =
  let uri = sl.nodeUri in
  let master = sl.master in
  let p = fun () -> Lwt.join (List.map (registerPublication name sl master uri) (getPublications sl)) in
  let s = fun () -> Lwt.join (List.map (registerSubscription name sl master uri) (getSubscriptions sl)) in
  p ();
  s ();

let runNode name sl =
  let doneCleanUp = Lwt_condition.create () in
  let shutdown = fun () -> cleanUp sl;
                           Lwt_condition.signal doneCleanUp in
  let () = setShutdownAct sl shutdown in

  runSlave sl >>=
    (fun (waitSig, pnum) ->
      let () = registerNode name sl in      
      waitSig >>= (fun _ -> Lwt_condition.wait doneCleanUp))
        
