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

let runNode name sl =
  let open Slave in
  let open Node.Node in

  let doneCleanUp = Lwt_condition.create () in
  let quit = Lwt_switch.create () in
  let () = setShutdownAct sl quit in

  let (t, w) = Lwt.wait () in
  let () = Lwt.async (fun () -> t >>= (fun _ -> cleanupNode sl)) in
  let shutdown = fun () -> (Lwt.wakeup w ()) in
  (*                            Lwt_condition.signal doneCleanUp ()) in*)
  let () = Lwt_switch.add_hook (Some quit) (fun () -> Lwt.return (shutdown ())) in

  let handler = function
    | n when n = Sys.sigint -> Lwt.async (fun () -> Lwt_switch.turn_off quit)
    | _ -> Printf.printf "Unhandled\n%!" in
  let () = Sys.catch_break true in
  let () = Sys.set_signal Sys.sigint (Sys.Signal_handle handler) in
  ignore (Lwt_main.run (
              let waitSig = runSlave sl in
              registerNode name sl
              >>= (fun _ -> waitSig ())))
                    (*              >>= (fun _ -> Lwt_condition.wait doneCleanUp)))*)
        
