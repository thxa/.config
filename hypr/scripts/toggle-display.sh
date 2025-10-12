#!/bin/bash

# Hyprland Display Manager with Rofi
# Handles mirror, extend, and internal-only modes with proper scaling

get_all_monitors() {
    # Get ALL connected monitors, including disabled ones
    hyprctl monitors all -j | jq -r '.[] | .name'
}

get_monitors() {
    hyprctl monitors -j | jq -r '.[] | "\(.name):\(.width)x\(.height)"'
}

get_monitor_info() {
    local monitor=$1
    hyprctl monitors all -j | jq -r ".[] | select(.name==\"$monitor\")"
}

get_monitor_name() {
    local index=$1
    hyprctl monitors all -j | jq -r ".[$index].name"
}

get_monitor_resolution() {
    local monitor=$1
    local info=$(get_monitor_info "$monitor")
    echo "$info" | jq -r '"\(.width)x\(.height)"'
}

calculate_scale() {
    local source_res=$1
    local target_res=$2
    
    local src_width=$(echo $source_res | cut -d'x' -f1)
    local src_height=$(echo $source_res | cut -d'x' -f2)
    local tgt_width=$(echo $target_res | cut -d'x' -f1)
    local tgt_height=$(echo $target_res | cut -d'x' -f2)
    
    # Calculate scale factor (source/target)
    local scale_w=$(echo "scale=4; $src_width / $tgt_width" | bc)
    local scale_h=$(echo "scale=4; $src_height / $tgt_height" | bc)
    
    # Use the smaller scale to fit entirely
    if (( $(echo "$scale_w < $scale_h" | bc -l) )); then
        echo $scale_w
    else
        echo $scale_h
    fi
}

mirror_displays() {
    local monitors=($(get_all_monitors))
    
    if [ ${#monitors[@]} -lt 2 ]; then
        notify-send "Display Manager" "Need at least 2 monitors to mirror"
        return 1
    fi
    
    # Get internal and external monitors
    local internal=""
    local external=""
    
    for mon in "${monitors[@]}"; do
        if [[ $mon == "eDP-1" ]] || [[ $mon == "LVDS-1" ]]; then
            internal=$mon
        else
            external=$mon
        fi
    done
    
    # If no internal found, use first two monitors
    if [ -z "$internal" ]; then
        internal=${monitors[0]}
        external=${monitors[1]}
    fi
    
    if [ -z "$external" ]; then
        external=${monitors[1]}
    fi
    
    # First enable both monitors to get their info
    hyprctl keyword monitor "$internal,preferred,auto,1"
    hyprctl keyword monitor "$external,preferred,auto,1"
    
    sleep 0.5
    
    # Get resolutions
    local internal_res=$(get_monitor_resolution "$internal")
    local external_res=$(get_monitor_resolution "$external")
    
    local int_width=$(echo $internal_res | cut -d'x' -f1)
    local int_height=$(echo $internal_res | cut -d'x' -f2)
    local ext_width=$(echo $external_res | cut -d'x' -f1)
    local ext_height=$(echo $external_res | cut -d'x' -f2)
    
    # Determine which is bigger
    local int_pixels=$((int_width * int_height))
    local ext_pixels=$((ext_width * ext_height))
    
    if [ $ext_pixels -gt $int_pixels ]; then
        # External is bigger - mirror internal to external
        local scale=$(calculate_scale "$external_res" "$internal_res")
        
        # Disable internal, configure external with mirroring
        hyprctl keyword monitor "$internal,disabled"
        hyprctl keyword monitor "$external,${external_res}@60,0x0,1"
        hyprctl keyword monitor "$internal,${internal_res}@60,0x0,$scale,mirror,$external"
        
        notify-send "Display Manager" "Mirroring: Internal → External (larger)\nScale: $scale"
    else
        # Internal is bigger or equal - mirror external to internal
        local scale=$(calculate_scale "$internal_res" "$external_res")
        
        # Configure both monitors with mirroring
        hyprctl keyword monitor "$external,disabled"
        hyprctl keyword monitor "$internal,${internal_res}@60,0x0,1"
        hyprctl keyword monitor "$external,${external_res}@60,0x0,$scale,mirror,$internal"
        
        notify-send "Display Manager" "Mirroring: External → Internal (larger)\nScale: $scale"
    fi
}

extend_displays() {
    local monitors=($(get_all_monitors))
    
    if [ ${#monitors[@]} -lt 2 ]; then
        notify-send "Display Manager" "Need at least 2 monitors to extend"
        return 1
    fi
    
    # Get internal and external monitors
    local internal=""
    local external=""
    
    for mon in "${monitors[@]}"; do
        if [[ $mon == "eDP-1" ]] || [[ $mon == "LVDS-1" ]]; then
            internal=$mon
        else
            external=$mon
        fi
    done
    
    if [ -z "$internal" ]; then
        internal=${monitors[0]}
        external=${monitors[1]}
    fi
    
    if [ -z "$external" ]; then
        external=${monitors[1]}
    fi
    
    # First enable both to get resolutions
    hyprctl keyword monitor "$internal,preferred,auto,1"
    hyprctl keyword monitor "$external,preferred,auto,1"
    
    sleep 0.5
    
    # Get resolutions
    local internal_res=$(get_monitor_resolution "$internal")
    local external_res=$(get_monitor_resolution "$external")
    
    local int_width=$(echo $internal_res | cut -d'x' -f1)
    
    # Configure extended display (external to the right of internal)
    hyprctl keyword monitor "$internal,${internal_res}@60,0x0,1"
    hyprctl keyword monitor "$external,${external_res}@60,${int_width}x0,1"
    
    notify-send "Display Manager" "Extended: Internal + External side-by-side"
}

internal_only() {
    local monitors=($(get_all_monitors))
    local internal=""
    
    # Find internal monitor
    for mon in "${monitors[@]}"; do
        if [[ $mon == "eDP-1" ]] || [[ $mon == "LVDS-1" ]]; then
            internal=$mon
            break
        fi
    done
    
    # If no internal found, use first monitor
    if [ -z "$internal" ]; then
        internal=${monitors[0]}
    fi
    
    # Enable internal first
    hyprctl keyword monitor "$internal,preferred,auto,1"
    
    sleep 0.3
    
    # Disable all other monitors
    for mon in "${monitors[@]}"; do
        if [ "$mon" != "$internal" ]; then
            hyprctl keyword monitor "$mon,disable"
        fi
    done
    
    # Get resolution and reconfigure
    local internal_res=$(get_monitor_resolution "$internal")
    hyprctl keyword monitor "$internal,${internal_res}@60,0x0,1"
    
    notify-send "Display Manager" "Internal display only"
}

external_only() {
    local monitors=($(get_all_monitors))
    local internal=""
    local external=""
    
    # Find internal and external monitors
    for mon in "${monitors[@]}"; do
        if [[ $mon == "eDP-1" ]] || [[ $mon == "LVDS-1" ]]; then
            internal=$mon
        else
            external=$mon
        fi
    done
    
    # If no external found, notify and exit
    if [ -z "$external" ]; then
        notify-send "Display Manager" "No external display detected"
        return 1
    fi
    
    # Enable external first
    hyprctl keyword monitor "$external,preferred,auto,1"
    
    sleep 0.3
    
    # Disable internal monitor
    if [ -n "$internal" ]; then
        hyprctl keyword monitor "$internal,disable"
    fi
    
    # Get resolution and reconfigure
    local external_res=$(get_monitor_resolution "$external")
    hyprctl keyword monitor "$external,${external_res}@60,0x0,1"
    
    notify-send "Display Manager" "External display only"
}

# Rofi menu
CHOICE=$(echo -e "🔄 Mirror Displays\n↔️  Extend Displays\n💻 Internal Only\n🖥️  External Only\n❌ Cancel" | rofi -dmenu -i -p "Display Mode" -theme-str 'window {width: 400px;}')

case "$CHOICE" in
    "🔄 Mirror Displays")
        mirror_displays
        ;;
    "↔️  Extend Displays")
        extend_displays
        ;;
    "💻 Internal Only")
        internal_only
        ;;
    "🖥️  External Only")
        external_only
        ;;
    *)
        exit 0
        ;;
esac
