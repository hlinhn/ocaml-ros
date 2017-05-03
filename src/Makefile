PACKS = core_kernel,batteries,rpclib,lwt,lwt.unix,cohttp.lwt
all: Node.cmx RosHeader.cmx TypeInfo.cmx MasterAPI.cmx slave.cmx Tcp.cmx runNode.cmx
clean: 
	-rm *.cmx

%.opt: %.cmx
	ocamlfind ocamlopt -linkpkg -package $(PACKS) -o $@ Node.cmx RosHeader.cmx TypeInfo.cmx MasterAPI.cmx slave.cmx Tcp.cmx runNode.cmx $<

%.cmx: %.ml
	ocamlfind ocamlopt -annot -g -package $(PACKS),rpclib.syntax -syntax camlp4o -c -o $@ $<
