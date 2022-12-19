#!/bin/sh
image="$1"
iso="$2"
memory="3G"
disk="30G"

qemu-img create -f qcow2 $image $disk
qemu-system-x86_64 -cdrom $iso -boot order=d -drive file=$image,format=qcow2 -m $memory
qemu-system-x86_64 -m $memory -device virtio-vga,virgl=on -drive file=$image,format=qcow2,if=virtio -cpu host -smp 4 "$image"
