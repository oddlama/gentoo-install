#!/bin/bash

source "$GENTOO_BOOTSTRAP_DIR/scripts/protection.sh" || exit 1

elog() {
	echo "[1m *[m $*"
}

einfo() {
	echo "[1;32m *[m $*"
}

ewarn() {
	echo "[1;33m *[m $*" >&2
}

eerror() {
	echo "[1;31m * ERROR:[m $*" >&2
}

die() {
	eerror "$*"
	kill "$GENTOO_BOOTSTRAP_SCRIPT_PID"
	exit 1
}

ask() {
	while true; do
		read -r -p "$* (Y/n) " response
		case "${response,,}" in
			'') return 0 ;;
			y|yes) return 0 ;;
			n|no) return 1 ;;
			*) continue ;;
		esac
	done
}

countdown() {
	echo -n "$1"

	local i="$2"
	while [[ $i -gt 0 ]]; do
		echo -n "[1;31m$i[m "
		i=$((i - 1))
		sleep 1
	done
	echo
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
