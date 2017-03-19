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
        
