export PACKER_LOG ?= 0

run: packer-out/fedora.qcow2
	./run-qemu.sh packer-out/fedora.qcow2

packer-out/fedora.qcow2:
	packer build fedora.pkr.hcl

init:
	packer init fedora.pkr.hcl

clean:
	rm -rfv packer-out

.PHONY: run init clean
