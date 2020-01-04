#!/bin/bash

source "$GENTOO_BOOTSTRAP_DIR/scripts/protection.sh" || exit 1

echo_console() {
	if { true >&3; } 2<> /dev/null; then
		echo "$@" >&3
	else
		echo "$@"
	fi
}

log_stdout() {
	echo "$*"
	if { true >&3; } 2<> /dev/null; then
		echo "$*" >&3
	fi
}

log_stderr() {
	echo "$*" >&2
	echo "$*"
}

elog() {
	log_stdout "[1m *[m $*"
}

einfo() {
	log_stdout "[1;32m *[m $*"
}

ewarn() {
	log_stderr "[1;33m *[m $*"
}

eerror() {
	log_stderr "[1;31m * ERROR:[m $*"
}

die() {
	eerror "$*"
	kill "$GENTOO_BOOTSTRAP_SCRIPT_PID"
	exit 1
}

for_line_in() {
	while IFS="" read -r line || [[ -n "$line" ]]; do
		"$2" "$line"
	done <"$1"
}

flush_stdin() {
	local empty_stdin
	while read -r -t 0.01 empty_stdin; do true; done
}

ask() {
	local response
	while true; do
		flush_stdin
		read -r -p "$* (Y/n) " response \
			|| die "Error in read"
		case "${response,,}" in
			'') return 0 ;;
			y|yes) return 0 ;;
			n|no) return 1 ;;
			*) continue ;;
		esac
	done
}

try() {
	local response
	local cmd_status
	local prompt_parens="([1mS[mhell/[1mr[metry/[1ma[mbort/[1mc[montinue/[1mp[mrint)"

	# Outer loop, allows us to retry the command
	while true; do
		# Try command
		"$@"
		cmd_status="$?"

		if [[ "$cmd_status" != 0 ]]; then
			echo_console "[1;31m * Command failed: [1;33m\$[m $*"
			echo_console -n "Last command failed (code $cmd_status), specify next action $prompt_parens "

			# Prompt until input is valid
			while true; do
				flush_stdin
				read -r response \
					|| die "Error in read"
				case "${response,,}" in
					''|s|shell)
						echo_console "Hint: The script log is at '$GENTOO_BOOTSTRAP_DIR/log.out'"
						echo_console "You will be prompted for action again after exiting this shell."
						/bin/bash --init-file <(echo "disable_logging; source $TMP_DIR/.bashrc")
						;;
					r|retry) continue 2 ;;
					a|abort) die "Installation aborted" ;;
					c|continue) return 0 ;;
					p|print) echo_console "[1;33m\$[m $*" ;;
					*) echo_console -n "Response not understood $prompt_parens " ;;
				esac
			done
		fi

		return
	done
}

countdown() {
	echo -n "$1" >&3

	local i="$2"
	while [[ $i -gt 0 ]]; do
		echo -n "[1;31m$i[m " >&3
		i=$((i - 1))
		sleep 1
	done
	echo >&3
}

download_stdout() {
	wget --quiet --https-only --secure-protocol=PFS -O - -- "$1"
}

download() {
	wget --quiet --https-only --secure-protocol=PFS --show-progress -O "$2" -- "$1"
}

get_device_by_partuuid() {
	blkid -g \
		|| die "Error while executing blkid"
	local dev
	dev="$(blkid -o export -t PARTUUID="$1")" \
		|| die "Error while executing blkid to find PARTUUID=$1"
	dev="$(grep DEVNAME <<< "$dev")" \
		|| die "Could not find DEVNAME=... in blkid output"
	dev="${dev:8}"
	echo -n "$dev"
}

load_or_generate_uuid() {
	local uuid
	local uuid_file="$UUID_STORAGE_DIR/$1"

	if [[ -e "$uuid_file" ]]; then
		uuid="$(cat "$uuid_file")"
	else
		uuid="$(uuidgen -r)"
		mkdir -p "$UUID_STORAGE_DIR"
		echo -n "$uuid" > "$uuid_file"
	fi

	echo -n "$uuid"
}
