#!/bin/bash

EXTERNAL="HDMI-A-1"  # change to your output name
INTERNAL="eDP-1"

if hyprctl monitors | grep "$EXTERNAL"; then
  hyprctl dispatch dpms off "$EXTERNAL"
else
  hyprctl dispatch dpms on "$EXTERNAL"
fi
