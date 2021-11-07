qemu-img create -f qcow2 linux.img 30G
qemu-system-x86_64 -cdrom <iso> -boot order=d -drive file=linux.img,format=qcow2 -m 3G
qemu-system-x86_64 -m 3G -device virtio-vga,virgl=on -drive file=linux.img,format=qcow2,if=virtio -cpu host -smp 4 "$@"
