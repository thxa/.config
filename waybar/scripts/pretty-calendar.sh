#!/bin/bash

# Get today's date without leading zero (e.g., 5 instead of 05)
today=$(date +%-d)

# Generate calendar and highlight today by surrounding it with brackets
calendar=$(cal | tail -n +2 | sed "s/\b$today\b/[$today]/g")

# Escape double quotes and backslashes for JSON
calendar_escaped=$(echo "$calendar" | sed 's/\\/\\\\/g' | sed 's/\"/\\\"/g')

# Print valid JSON
printf '{"text": " %s   %s","tooltip": "<tt>%s</tt>"}' "$(date +'%I:%M %p')" "$(date +'%d/%m/%Y')" "$calendar_escaped"

