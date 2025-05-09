#!/bin/sh
# Copyright (C) Maina Derrick (d1dee) 2025
# This software is released under the GNU GPL license.

# Load config args from file
load_args() {
	. /var/ndscids/authmonargs
}

# Function to send JSON status using same method as authmon
send_json_status() {
	json_out=$(ndsctl json 2>/dev/null)

	if [ -z "$json_out" ]; then
		echo "jsonreport - ERROR: empty ndsctl json output" | logger -p "daemon.err" -t "jsonreport[$$]"
		return
	fi

	# Check free memory
	free_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
	if [ "$free_kb" -lt 1024 ]; then
		echo "jsonreport - ERROR: low memory ($free_kb KB), skipping send" | logger -p "daemon.err" -t "jsonreport[$$]"
		return
	fi

	# Split JSON into chunks if large
	max_clients=1000
	client_count=$(echo "$json_out" | jq -r '.client_list_length')
	echo "$json_out" >"/tmp/ndsctl_json_$$.json"

	reporturl="$url/jsonreport/$gatewayhash"

	ret=$(uclient-fetch -q -O - --user-agent "$user_agent" --post-file="/tmp/ndsctl_json_$$.json" "$reporturl")

	[ "$debuglevel" -ge 2 ] && echo "jsonreport - POST response: [$ret]" | logger -p "daemon.debug" -t "jsonreport[$$]"
	rm -f "$tmpfile"

}

# Get configured option
get_option_from_config() {
	option_value=$(/usr/lib/opennds/libopennds.sh get_option_from_config $option)
}

# Check if authmon is running
check_authmon_running() {
	authmon_pid=$(pgrep -f '/usr/lib/opennds/authmon.sh')
	if [ -z "$authmon_pid" ]; then
		echo "jsonreport - ERROR: authmon is not running" | logger -p "daemon.err" -t "jsonreport[$$]"
		exit 1
	fi
}

# === MAIN START ===
# Check if jq is installed
if ! command -v jq >/dev/null 2>&1; then
	echo "jsonreport - ERROR: jq is required but not installed" | logger -p "daemon.err" -t "jsonreport[$$]"
	exit 1
fi
# Check if usclient-fetch exists
if ! command -v uclient-fetch >/dev/null 2>&1; then
	echo "jsonreport - ERROR: uclient-fetch is required but not installed" | logger -p "daemon.err" -t "jsonreport[$$]"
	exit 1
fi

# Wait for openNDS to start
sleep 60

# Check authmon
check_authmon_running

# Get tmpfs mountpoint
mountpoint=$(/usr/lib/opennds/libopennds.sh tmpfs)

# Load config args
load_args

# Extract openNDS version and debuglevel
ndsctlout=$(ndsctl status 2>/dev/null)
debuglevel=$(echo "$ndsctlout" | grep "Debug Level" | awk '{print $4}')
version=$(echo "$ndsctlout" | grep "Version" | awk '{print $2}')

# Determine polling interval
option="nat_traversal_poll_interval"
get_option_from_config
loop_interval=$option_value

[ -z "$loop_interval" ] || [ "$loop_interval" -le 0 ] || [ "$loop_interval" -ge 60 ] && loop_interval=5

[ -z "$user_agent" ] && user_agent="openNDS(jsonreport;NDS:$version;)"

# Report startup
if [ "$debuglevel" -ge 1 ]; then
	echo "jsonreport - started, polling every $loop_interval second(s)" | logger -p "daemon.notice" -t "jsonreport[$$]"
fi

# === MAIN LOOP ===
while true; do
	[ -e "$mountpoint/ndsdebuglevel" ] && debuglevel=$(cat "$mountpoint/ndsdebuglevel")

	send_json_status

	sleep $loop_interval
done
