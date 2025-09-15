#!/usr/bin/env bash

WS=$1

# اسم نافذة remote-viewer بالضبط (شوفه بـ hyprctl clients)
SPICE_WINDOW_NAME="Remote Viewer"

# تحقق إذا النافذة فوكس
FOCUSED=$(xdotool getwindowfocus getwindowname)
if [[ "$FOCUSED" == *"$SPICE_WINDOW_NAME"* ]]; then
    # فك الـ grab
    xdotool key Ctrl+Alt
fi

# نقل workspace
hyprctl dispatch workspace $WS

