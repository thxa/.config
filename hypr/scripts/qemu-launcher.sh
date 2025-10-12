#!/usr/bin/env bash

show() {
    # Open SPICE viewer to interact with the VM
    local SPICE_SOCKET=$1 
    remote-viewer spice+unix://$SPICE_SOCKET --hotkeys=release-cursor=ctrl+alt
}

# Path to virtiofsd (for shared folders)
VIRTIOFSD="/opt/virtiofsd/target/release/virtiofsd"

# Directories
SHARE_DIR="$HOME/qemu_share"
VM_DIR="$HOME/Desktop/VMs"
SPICE_SOCKET="/tmp/spice.sock"

# Check if any QEMU process is already running
RUNNING_QEMU=$(pgrep -f qemu-system-x86_64)

if [ -n "$RUNNING_QEMU" ]; then
    # Menu for managing existing QEMU VM
    ACTION=$(echo -e "Interact with VM\nShutdown VM\nStart New VM" | rofi -dmenu -p "QEMU already running")
    case "$ACTION" in
        "Interact with VM")
            # Open SPICE viewer to interact with running VM
            # remote-viewer spice+unix://$SPICE_SOCKET --hotkeys=release-cursor=ctrl+alt
            show $SPICE_SOCKET
            exit 0
            ;;
        "Shutdown VM")
            # Kill the running QEMU and virtiofsd processes
            kill $RUNNING_QEMU
            pkill -f "$VIRTIOFSD"
            rm -f "$SPICE_SOCKET" "$VHOST_SOCKET"
            exit 0
            ;;
        "Start New VM")
            # Stop old VM before starting a new one
            kill $RUNNING_QEMU
            pkill -f "$VIRTIOFSD"
            rm -f "$SPICE_SOCKET" "$VHOST_SOCKET"
            ;;
        *)
            exit 0
            ;;
    esac
fi

# Ask user to select VM disk image
VM=$(find "$VM_DIR" -type f \( -name "*.raw" -o -name "*.qcow2" \) | rofi -dmenu -p "Select VM")
[ -z "$VM" ] && exit 0

# Ask user to optionally select an ISO file
ISO=$(find "$VM_DIR" -type f -name "*.iso" | rofi -dmenu -p "Select ISO (optional, press ESC to skip)")

sleep 1

# Build QEMU command
# QEMU_CMD="qemu-system-x86_64 \
#   -enable-kvm \
#   -m 8G \
#   -cpu host \
#   -smp 4 \
#   -machine type=q35,accel=kvm \
#   -drive file=\"$VM\",format=raw \
#   -net nic -net user \
#   -device virtio-net,netdev=net0 \
#   -netdev user,id=net0 \
#   -usb -device usb-tablet \
#   -chardev socket,id=char0,path=\"$VHOST_SOCKET\" \
#   -device vhost-user-fs-pci,chardev=char0,tag=myshare \
#   -object memory-backend-memfd,id=mem,size=8G,share=on \
#   -numa node,memdev=mem \
#   -display none \
#   -device qxl-vga \
#   -device virtio-serial-pci \
#   -chardev spicevmc,id=vdagent,name=vdagent \
#   -device virtserialport,chardev=vdagent,name=com.redhat.spice.0 \
#   -spice unix=on,addr=\"$SPICE_SOCKET\",disable-ticketing"

QEMU_CMD="qemu-system-x86_64 \
  -enable-kvm \
  -m 8G \
  -cpu host \
  -smp 4 \
  -machine type=q35,accel=kvm \
  -drive file=\"$VM\",format=raw \
  -device qxl-vga \
  -spice unix=on,addr=$SPICE_SOCKET,disable-ticketing \
  -device virtio-serial-pci \
  -chardev spicevmc,id=vdagent,name=vdagent \
  -device virtserialport,chardev=vdagent,name=com.redhat.spice.0"



# Add ISO if user selected one
if [ -n "$ISO" ]; then
    QEMU_CMD="$QEMU_CMD -drive file=\"$ISO\",media=cdrom"
fi

# Run QEMU
eval "$QEMU_CMD &"

# Wait until SPICE socket is ready
while [ ! -S "$SPICE_SOCKET" ]; do
  sleep 0.2
done

show $SPICE_SOCKET
