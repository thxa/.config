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
SPICE_BASE="/tmp/spice"
VHOST_BASE="/tmp/vhost"
SERIAL_BASE="/tmp/qemu-serial"

# Network configuration
NETWORK_SOCKET="/tmp/qemu-vlan.sock"
MULTICAST_ADDR="230.0.0.1:1234"
VLAN_ID="0"

# Generate unique VM ID based on running VMs
# generate_vm_id() {
#     local ID=1
#     while [ -S "${SPICE_BASE}_${ID}.sock" ]; do
#         ID=$((ID + 1))
#     done
#     echo $ID
# }

# Generate unique VM ID based on VM name
generate_vm_id() {
    local VM_NAME=$1
    echo "$VM_NAME"
}

# List all running VMs

# list_running_vms() {
#     local VMS=()
#     for sock in ${SPICE_BASE}_*.sock; do
#         if [ -S "$sock" ]; then
#             local vm_id=$(echo "$sock" | sed -n 's/.*spice_\([0-9]*\)\.sock/\1/p')
#             local vm_pid=$(pgrep -f "spice.*addr=${SPICE_BASE}_${vm_id}.sock")
#             if [ -n "$vm_pid" ]; then
#                 VMS+=("VM $vm_id (PID: $vm_pid)")
#             fi
#         fi
#     done
#     echo "${VMS[@]}"
# }


# list_running_vms() {
#     for sock in ${SPICE_BASE}_*.sock; do
#         if [ -S "$sock" ]; then
#             local vm_id=$(echo "$sock" | sed -n 's/.*spice_\([0-9]*\)\.sock/\1/p')
#             local vm_pid=$(pgrep -f "spice.*addr=${SPICE_BASE}_${vm_id}.sock")
#             if [ -n "$vm_pid" ]; then
#                 echo "$vm_id"  # Output just the VM ID, one per line
#             fi
#         fi
#     done
# }

list_running_vms() {
    for sock in ${SPICE_BASE}_*.sock; do
        if [ -S "$sock" ]; then
            local vm_id=$(echo "$sock" | sed -n 's|.*/spice_\(.*\)\.sock|\1|p')
            echo "$vm_id"
        fi
    done
}


# Check if any QEMU process is already running
RUNNING_QEMU=$(pgrep -f qemu-system-x86_64)

if [ -n "$RUNNING_QEMU" ]; then
    # Get list of running VMs
    # RUNNING_VMS=($(list_running_vms))
    mapfile -t RUNNING_VMS < <(list_running_vms)
    
    if [ ${#RUNNING_VMS[@]} -gt 0 ]; then
        # Menu for managing existing QEMU VMs
        MENU_OPTIONS="Start New VM\nShutdown All VMs"
        for vm_id in "${RUNNING_VMS[@]}"; do
            MENU_OPTIONS="$MENU_OPTIONS\nInteract with VM $vm_id\nShutdown VM $vm_id"
        done

        # ACTION=$(echo -e "$MENU_OPTIONS" | rofi -dmenu -p "Manage QEMU VMs (${#RUNNING_VMS[@]} running)")
        # case "$ACTION" in
        #     "Start New VM")
        #         # Continue to start new VM
        #         ;;
        #     "Shutdown All VMs")
        #         # Kill all running QEMU and virtiofsd processes
        #         pkill -f qemu-system-x86_64
        #         pkill -f "$VIRTIOFSD"
        #         rm -f ${SPICE_BASE}_*.sock ${VHOST_BASE}_*.sock
        #         rm -f "$NETWORK_SOCKET"
        #         exit 0
        #         ;;
        #     "Interact with VM"*)
        #         # Extract VM ID and open viewer
        #         VM_ID=$(echo "$ACTION" | grep -oP 'VM \K\d+')
        #         show "${SPICE_BASE}_${VM_ID}.sock"
        #         exit 0
        #         ;;
        #     "Shutdown VM"*)
        #         # Extract VM ID and shutdown specific VM
        #         VM_ID=$(echo "$ACTION" | grep -oP 'VM \K\d+')
        #         VM_PID=$(pgrep -f "spice.*addr=${SPICE_BASE}_${VM_ID}.sock")
        #         if [ -n "$VM_PID" ]; then
        #             kill $VM_PID
        #             rm -f "${SPICE_BASE}_${VM_ID}.sock" "${VHOST_BASE}_${VM_ID}.sock"
        #         fi
        #         exit 0
        #         ;;
        #     *)
        #         exit 0
        #         ;;
        # esac

        ACTION=$(echo -e "$MENU_OPTIONS" | rofi -dmenu -p "Manage QEMU VMs (${#RUNNING_VMS[@]} running)")

        case "$ACTION" in
            "Start New VM")
                # Continue to start new VM
                ;;
            "Shutdown All VMs")
                # Kill all running QEMU and virtiofsd processes
                pkill -f qemu-system-x86_64
                pkill -f "$VIRTIOFSD"
                rm -f ${SPICE_BASE}_*.sock ${VHOST_BASE}_*.sock
                rm -f "$NETWORK_SOCKET"
                if [ -e /tmp/qemu-hub.lock ]; then
                    rm -f /tmp/qemu-hub.lock
                fi
                exit 0
                ;;
            "Interact with VM"*)
                # Extract VM ID (name) from the action
                VM_ID=$(echo "$ACTION" | sed -n 's/Interact with VM \(.*\)/\1/p')
                show "${SPICE_BASE}_${VM_ID}.sock"
                exit 0
                ;;
            "Shutdown VM"*)
                # Extract VM ID (name) and shutdown specific VM
                VM_ID=$(echo "$ACTION" | sed -n 's/Shutdown VM \(.*\)/\1/p')
                VM_PID=$(pgrep -f "spice.*addr=${SPICE_BASE}_${VM_ID}.sock")
                if [ -n "$VM_PID" ]; then
                    kill $VM_PID
                    rm -f "${SPICE_BASE}_${VM_ID}.sock" "${VHOST_BASE}_${VM_ID}.sock"
                fi
                exit 0
                ;;
            *)
                exit 0
                ;;
        esac


    fi
fi

# Ask user to select VM disk image
VM=$(find "$VM_DIR" -type f \( -name "*.raw" -o -name "*.qcow2" \) | rofi -dmenu -p "Select VM")
[ -z "$VM" ] && exit 0

# Extract VM name from filename (without path and extension)
VM_NAME=$(basename "$VM" | sed 's/\.[^.]*$//')

# Ask user to optionally select an ISO file
ISO=$(find "$VM_DIR" -type f -name "*.iso" | rofi -dmenu -p "Select ISO (optional, press ESC to skip)")

# Ask if user wants to use e1000 (for Windows without VirtIO drivers)
USE_E1000=$(echo -e "VirtIO (faster, needs drivers)\ne1000 (slower, built-in Windows support)" | rofi -dmenu -p "Network Adapter Type")
if [[ "$USE_E1000" == *"e1000"* ]]; then
    NET_DEVICE="e1000"
else
    NET_DEVICE="virtio-net-pci"
fi

# Ask user for RAM amount
RAM=$(echo -e "2G\n4G\n6G\n8G\n12G\n16G\nCustom" | rofi -dmenu -p "RAM Amount")
if [[ "$RAM" == "Custom" ]]; then
    RAM=$(rofi -dmenu -p "Enter RAM (e.g., 3G, 5120M)" <<< "")
    [ -z "$RAM" ] && RAM="4G"  # Default to 4G if empty
fi

# Generate unique ID for this VM
VM_ID="$VM_NAME"
# VM_ID=$(generate_vm_id)
SPICE_SOCKET="${SPICE_BASE}_${VM_ID}.sock"
VHOST_SOCKET="${VHOST_BASE}_${VM_ID}.sock"

# Generate unique MAC address for LAN interface
# MAC_SUFFIX=$(printf "%02x" $VM_ID)
MAC_SUFFIX=$(echo -n "$VM_NAME" | md5sum | cut -c1-2)
LAN_MAC="52:54:00:aa:bb:${MAC_SUFFIX}"
NAT_MAC="52:54:00:aa:cc:${MAC_SUFFIX}"

# Ask user network type
NETWORK_TYPE=$(echo -e "Multicast (simple)\nSocket Hub (reliable)\nVLAN (legacy)" | rofi -dmenu -p "Network Type")

sleep 1

# Configure network based on selection
# case "$NETWORK_TYPE" in
#     "Socket Hub"*)
#         # Use socket hub - first VM creates hub, others connect
#         if [ $VM_ID -eq 1 ]; then
#             NETWORK_CONFIG="-netdev socket,id=lan,listen=:5555"
#         else
#             NETWORK_CONFIG="-netdev socket,id=lan,connect=127.0.0.1:5555"
#         fi
#         ;;
#     "VLAN"*)
#         # Use legacy VLAN mode (deprecated but sometimes more reliable)
#         NETWORK_CONFIG="-netdev socket,id=lan,mcast=${MULTICAST_ADDR},localaddr=127.0.0.1"
#         ;;
#     *)
#         # Default: multicast
#         NETWORK_CONFIG="-netdev socket,id=lan,mcast=${MULTICAST_ADDR}"
#         ;;
# esac

case "$NETWORK_TYPE" in
    "Socket Hub"*)
        # Use socket hub - first VM creates hub, others connect
        if [ ! -e /tmp/qemu-hub.lock ]; then
            touch /tmp/qemu-hub.lock
            NETWORK_CONFIG="-netdev socket,id=lan,listen=:5555"
        else
            NETWORK_CONFIG="-netdev socket,id=lan,connect=127.0.0.1:5555"
        fi
        ;;
    "VLAN"*)
        # Use legacy VLAN mode (deprecated but sometimes more reliable)
        NETWORK_CONFIG="-netdev socket,id=lan,mcast=${MULTICAST_ADDR},localaddr=127.0.0.1"
        ;;
    *)
        # Default: multicast
        NETWORK_CONFIG="-netdev socket,id=lan,mcast=${MULTICAST_ADDR}"
        ;;
esac


QEMU_CMD="qemu-system-x86_64 \
  -enable-kvm \
  -m $RAM \
  -cpu host \
  -smp 4 \
  -machine type=q35,accel=kvm \
  -drive file=\"$VM\",format=raw \
  -device qxl-vga \
  -spice unix=on,addr=$SPICE_SOCKET,disable-ticketing \
  -device virtio-serial-pci \
  $NETWORK_CONFIG \
  -device $NET_DEVICE,netdev=lan,mac=$LAN_MAC \
  -netdev user,id=natnet \
  -device $NET_DEVICE,netdev=natnet,mac=$NAT_MAC \
  -chardev spicevmc,id=vdagent,name=vdagent \
  -device virtserialport,chardev=vdagent,name=com.redhat.spice.0 \
  -name \"VM_${VM_ID}\""

# Add ISO if user selected one
if [ -n "$ISO" ]; then
    QEMU_CMD="$QEMU_CMD -drive file=\"$ISO\",media=cdrom"
fi

# Run QEMU
eval "$QEMU_CMD &"

echo "Starting VM $VM_ID..."
echo "LAN MAC: $LAN_MAC"
echo "NAT MAC: $NAT_MAC"

# Wait until SPICE socket is ready
while [ ! -S "$SPICE_SOCKET" ]; do
  sleep 0.2
done

show $SPICE_SOCKET
