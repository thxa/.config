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
    mapfile -t RUNNING_VMS < <(list_running_vms)
    
    if [ ${#RUNNING_VMS[@]} -gt 0 ]; then
        # Menu for managing existing QEMU VMs
        MENU_OPTIONS="Start New VM\nShutdown All VMs"
        for vm_id in "${RUNNING_VMS[@]}"; do
            MENU_OPTIONS="$MENU_OPTIONS\nInteract with VM $vm_id\nShutdown VM $vm_id"
        done

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
                VM_ID=$(echo "$ACTION" | sed -n 's/Interact with VM \(.*\)/\1/p')
                show "${SPICE_BASE}_${VM_ID}.sock"
                exit 0
                ;;
            "Shutdown VM"*)
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

# Detect if this is a macOS VM
IS_MACOS=false
if [[ "$VM" == *"macOS"* ]] || [[ "$VM" == *"mac_"* ]] || [[ "$VM_NAME" == *"macOS"* ]]; then
    CONFIRM_MACOS=$(echo -e "Yes - macOS VM\nNo - Regular VM" | rofi -dmenu -p "Is this a macOS VM?")
    if [[ "$CONFIRM_MACOS" == *"Yes"* ]]; then
        IS_MACOS=true
    fi
fi

# Ask user for RAM amount
RAM=$(echo -e "2G\n4G\n6G\n8G\n12G\n16G\nCustom" | rofi -dmenu -p "RAM Amount")
if [[ "$RAM" == "Custom" ]]; then
    RAM=$(rofi -dmenu -p "Enter RAM (e.g., 3G, 5120M)" <<< "")
    [ -z "$RAM" ] && RAM="4G"
fi

# Convert RAM to MiB for macOS (if needed)
RAM_MIB=$(echo "$RAM" | sed 's/G/*1024/;s/M//' | bc 2>/dev/null || echo "4096")

# Generate unique ID for this VM
VM_ID="$VM_NAME"
SPICE_SOCKET="${SPICE_BASE}_${VM_ID}.sock"
VHOST_SOCKET="${VHOST_BASE}_${VM_ID}.sock"

if [ "$IS_MACOS" = true ]; then
    echo "Starting macOS VM: $VM_NAME"
    
    # macOS-specific configuration
    MACOS_DIR="$(dirname "$VM")"
    
    # Check for required files
    if [ ! -f "$MACOS_DIR/OpenCore.qcow2" ]; then
        echo "Error: OpenCore.qcow2 not found in $MACOS_DIR"
        rofi -e "Error: OpenCore.qcow2 not found in $MACOS_DIR"
        exit 1
    fi
    
    if [ ! -f "$MACOS_DIR/OVMF_CODE.fd" ] || [ ! -f "$MACOS_DIR/OVMF_VARS.fd" ]; then
        echo "Error: OVMF files not found in $MACOS_DIR"
        rofi -e "Error: OVMF_CODE.fd and OVMF_VARS.fd required in $MACOS_DIR"
        exit 1
    fi
    
    # Ask for CPU configuration
    CPU_CONFIG=$(echo -e "2 cores\n4 cores\n6 cores\n8 cores\nCustom" | rofi -dmenu -p "CPU Cores")
    case "$CPU_CONFIG" in
        "2 cores") CPU_THREADS=2; CPU_CORES=2 ;;
        "4 cores") CPU_THREADS=4; CPU_CORES=4 ;;
        "6 cores") CPU_THREADS=6; CPU_CORES=6 ;;
        "8 cores") CPU_THREADS=8; CPU_CORES=8 ;;
        "Custom") 
            CPU_THREADS=$(rofi -dmenu -p "Enter thread count" <<< "")
            CPU_CORES=$(rofi -dmenu -p "Enter core count" <<< "")
            ;;
        *) CPU_THREADS=4; CPU_CORES=4 ;;
    esac
    
    CPU_SOCKETS="1"
    MY_OPTIONS="+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check"
    
    # macOS QEMU command
    QEMU_CMD=(
        qemu-system-x86_64
        -enable-kvm -m "$RAM_MIB"
        -cpu Haswell-noTSX,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,$MY_OPTIONS
        -machine q35
        -device qemu-xhci,id=xhci
        -device usb-kbd,bus=xhci.0 -device usb-tablet,bus=xhci.0
        -smp "$CPU_THREADS",cores="$CPU_CORES",sockets="$CPU_SOCKETS"
        -device usb-ehci,id=ehci
        -device isa-applesmc,osk="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc"
        -drive if=pflash,format=raw,readonly=on,file="$MACOS_DIR/OVMF_CODE.fd"
        -drive if=pflash,format=raw,file="$MACOS_DIR/OVMF_VARS.fd"
        -smbios type=2
        -device ich9-intel-hda -device hda-duplex
        -device ich9-ahci,id=sata
        -drive id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file="$MACOS_DIR/OpenCore.qcow2"
        -device ide-hd,bus=sata.2,drive=OpenCoreBoot
        -drive id=MacHDD,if=none,file="$VM",format=qcow2
        -device ide-hd,bus=sata.4,drive=MacHDD
        -netdev user,id=net0,hostfwd=tcp::2222-:22
        -device virtio-net-pci,netdev=net0,id=net0,mac=52:54:00:c9:18:27
        -device vmware-svga
        -spice unix=on,addr=$SPICE_SOCKET,disable-ticketing=on
        -name "VM_${VM_ID}"
    )
    
    "${QEMU_CMD[@]}" &
    
    echo "Starting macOS VM $VM_ID..."
    echo "macOS Network MAC: 52:54:00:c9:18:27"
    echo "SSH available on: localhost:2222"
    
else
    # Regular VM (Linux/Windows)
    echo "Starting regular VM: $VM_NAME"
    
    # Ask user to optionally select an ISO file
    ISO=$(find "$VM_DIR" -type f -name "*.iso" | rofi -dmenu -p "Select ISO (optional, press ESC to skip)")
    
    # Ask if user wants to use e1000 (for Windows without VirtIO drivers)
    USE_E1000=$(echo -e "VirtIO (faster, needs drivers)\ne1000 (slower, built-in Windows support)" | rofi -dmenu -p "Network Adapter Type")
    if [[ "$USE_E1000" == *"e1000"* ]]; then
        NET_DEVICE="e1000"
    else
        NET_DEVICE="virtio-net-pci"
    fi
    
    # Generate unique MAC address for LAN interface
    MAC_SUFFIX=$(echo -n "$VM_NAME" | md5sum | cut -c1-2)
    LAN_MAC="52:54:00:aa:bb:${MAC_SUFFIX}"
    NAT_MAC="52:54:00:aa:cc:${MAC_SUFFIX}"
    
    # Ask user network type
    NETWORK_TYPE=$(echo -e "Multicast (simple)\nSocket Hub (reliable)\nVLAN (legacy)" | rofi -dmenu -p "Network Type")
    
    sleep 1
    
    case "$NETWORK_TYPE" in
        "Socket Hub"*)
            if [ ! -e /tmp/qemu-hub.lock ]; then
                touch /tmp/qemu-hub.lock
                NETWORK_CONFIG="-netdev socket,id=lan,listen=:5555"
            else
                NETWORK_CONFIG="-netdev socket,id=lan,connect=127.0.0.1:5555"
            fi
            ;;
        "VLAN"*)
            NETWORK_CONFIG="-netdev socket,id=lan,mcast=${MULTICAST_ADDR},localaddr=127.0.0.1"
            ;;
        *)
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
      -spice unix=on,addr=$SPICE_SOCKET,disable-ticketing=on \
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
fi

# Wait until SPICE socket is ready
while [ ! -S "$SPICE_SOCKET" ]; do
  sleep 0.2
done

show $SPICE_SOCKET
