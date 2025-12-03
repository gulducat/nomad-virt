#!/usr/bin/env bash

image="${1:-./packer-out/fedora.qcow2}"
test -f "$image" || {
  echo "image not found $image"
  exit 1
}

is_mac() {
  [ ! -f /etc/os-release ] # lazy, but ok
}

is_mac && arch='aarch64' || arch='x86_64'
qemu="qemu-system-$arch"
command -v $qemu || {
  echo "$qemu binary not found"
  exit 1
}

is_mac \
&& machine='-machine virt,accel=hvf' \
|| machine='-machine q35,accel=kvm -enable-kvm'

# bare minimum qemu command
set -x
$qemu \
  -m 'size=512' \
  $machine \
  -netdev 'user,id=user.0,hostfwd=tcp::12222-:22,hostfwd=tcp::14646-:4646' \
  -device 'virtio-net,netdev=user.0' \
  -drive  "file=$image" \
  -D qemu.log &
  #-nographic
{ set +x; } 2>/dev/null

# TODO: gracefully shutdown the vm on ctrl+c

cat <<EOF
put this in your ~/.ssh/config:

---
Host localhost
        StrictHostKeyChecking off
        UserKnownHostsFile /dev/null

Host fedora1
        Hostname localhost
        Port 12222
        User fedora
---

and run: ssh fedora1

or,

ssh -o StrictHostKeyChecking=off \\
    -o UserKnownHostsFile=/dev/null \\
    -p 12222 \\
    fedora@localhost

with password "asdf"

EOF

tail -f qemu.log


# TODO: numa stuff
exit
qemu-system-x86_64 \
  -enable-kvm \
  -machine "q35,accel=kvm" \
  -cpu "host" \
  -smp "4,sockets=1,clusters=1,cores=2" \
  -device "pxb-pcie,id=pcie.1,bus=pcie.0,numa_node=0,bus_nr=3" \
  -device "pxb-pcie,id=pcie.2,bus=pcie.0,numa_node=1,bus_nr=8" \
  -device "pcie-root-port,id=pcie_rp1,bus=pcie.1,chassis=1,slot=1" \
  -device "pcie-root-port,id=pcie_rp2,bus=pcie.2,chassis=1,slot=2" \
  -object "memory-backend-ram,id=mem0,size=2000M" \
  -object "memory-backend-ram,id=mem1,size=2000M" \
  -numa "node,nodeid=0,cpus=0-1,memdev=mem0" \
  -numa "node,nodeid=1,cpus=2-3,memdev=mem1" \
  -device "pcie-root-port,id=pcie_rp3,bus=pcie.1,chassis=1,slot=3" \
  -device "virtio-scsi-pci,id=scsi0,bus=pcie_rp3" \
  -drive  "file=$image,if=none,id=image0" \
  -device "scsi-hd,drive=image0,bus=scsi0.0" \
  -netdev "user,net=10.0.2.1/24,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::4646-:4646" \
  -device "e1000e,netdev=net0,bus=pcie_rp1" \
  -netdev "user,net=10.0.3.1/24,id=net1" \
  -device "e1000e,netdev=net1,bus=pcie_rp2" \
  -m 4000 \
  -snapshot
  #$image

# qemu-img create -f qcow2 -b original-image.qcow2 -F qcow2 overlay-image.qcow2
#
# https://wiki.debian.org/DebianInstaller/Qemu
# https://eudaimonia.io/posts/fedora-with-qemu
