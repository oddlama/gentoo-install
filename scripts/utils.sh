# shellcheck source=./scripts/protection.sh
source "$GENTOO_INSTALL_REPO_DIR/scripts/protection.sh" || exit 1

function elog() {
	echo "[[1m+[m] $*"
}

function einfo() {
	echo "[[1m+[m] [1;33m$*[m"
}

function ewarn() {
	echo "[[1;31m![m] [1;33m$*[m" >&2
}

function eerror() {
	echo "[1;31merror:[m $*" >&2
}

function die() {
	eerror "$*"
	[[ $$ == "$GENTOO_INSTALL_REPO_SCRIPT_PID" ]] \
		|| kill "$GENTOO_INSTALL_REPO_SCRIPT_PID"
	exit 1
}

# Prints an error with file:line info of the nth "stack frame".
# 0 is this function, 1 the calling function, 2 its parent, and so on.
function die_trace() {
	local idx="${1:-0}"
	shift
	echo "[1m${BASH_SOURCE[$((idx + 1))]}:${BASH_LINENO[$idx]}: [1;31merror:[m ${FUNCNAME[$idx]}: $*" >&2
	exit 1
}

function for_line_in() {
	while IFS="" read -r line || [[ -n $line ]]; do
		"$2" "$line"
	done <"$1"
}

function flush_stdin() {
	local empty_stdin
	# Unused variable is intentional.
	# shellcheck disable=SC2034
	while read -r -t 0.01 empty_stdin; do true; done
}

function ask() {
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

function try() {
	local response
	local cmd_status
	local prompt_parens="([1mS[mhell/[1mr[metry/[1ma[mbort/[1mc[montinue/[1mp[mrint)"

	# Outer loop, allows us to retry the command
	while true; do
		# Try command
		"$@"
		cmd_status="$?"

		if [[ $cmd_status != 0 ]]; then
			echo "[1;31m * Command failed: [1;33m\$[m $*"
			echo "Last command failed with exit code $cmd_status"

			# Prompt until input is valid
			while true; do
				echo -n "Specify next action $prompt_parens "
				flush_stdin
				read -r response \
					|| die "Error in read"
				case "${response,,}" in
					''|s|shell)
						echo "You will be prompted for action again after exiting this shell."
						/bin/bash --init-file <(echo "init_bash")
						;;
					r|retry) continue 2 ;;
					a|abort) die "Installation aborted" ;;
					c|continue) return 0 ;;
					p|print) echo "[1;33m\$[m $*" ;;
					*) ;;
				esac
			done
		fi

		return
	done
}

function countdown() {
	echo -n "$1" >&2

	local i="$2"
	while [[ $i -gt 0 ]]; do
		echo -n "[1;31m$i[m " >&2
		i=$((i - 1))
		sleep 1
	done
	echo >&2
}

function download_stdout() {
	wget --quiet --https-only --secure-protocol=PFS -O - -- "$1"
}

function download() {
	wget --quiet --https-only --secure-protocol=PFS --show-progress -O "$2" -- "$1"
}

function get_blkid_field_by_device() {
	local blkid_field="$1"
	local device="$2"
	blkid -g -c /dev/null \
		|| die "Error while executing blkid"
	partprobe &>/dev/null
	local val
	val="$(blkid -c /dev/null -o export "$device")" \
		|| die "Error while executing blkid '$device'"
	val="$(grep -- "^$blkid_field=" <<< "$val")" \
		|| die "Could not find $blkid_field=... in blkid output"
	val="${val#"$blkid_field="}"
	echo -n "$val"
}

function get_blkid_uuid_for_id() {
	local dev
	dev="$(resolve_device_by_id "$1")" \
		|| die "Could not resolve device with id=$dev"
	local uuid
	uuid="$(get_blkid_field_by_device 'UUID' "$dev")" \
		|| die "Could not get UUID from blkid for device=$dev"
	echo -n "$uuid"
}

function get_device_by_blkid_field() {
	local blkid_field="$1"
	local field_value="$2"
	blkid -g -c /dev/null \
		|| die "Error while executing blkid"
	type partprobe &>/dev/null && partprobe &>/dev/null
	local dev
	dev="$(blkid -c /dev/null -o export -t "$blkid_field=$field_value")" \
		|| die "Error while executing blkid to find $blkid_field=$field_value"
	dev="$(grep DEVNAME <<< "$dev")" \
		|| die "Could not find DEVNAME=... in blkid output"
	dev="${dev#"DEVNAME="}"
	echo -n "$dev"
}

function get_device_by_partuuid() {
	if [[ -e "/dev/disk/by-partuuid/$1" ]]; then
		echo -n "/dev/disk/by-partuuid/$1"
	else
		get_device_by_blkid_field 'PARTUUID' "$1"
	fi
}

function get_device_by_uuid() {
	if [[ -e "/dev/disk/by-uuid/$1" ]]; then
		echo -n "/dev/disk/by-uuid/$1"
	else
		get_device_by_blkid_field 'UUID' "$1"
	fi
}

function cache_lsblk_output() {
	CACHED_LSBLK_OUTPUT="$(lsblk --all --path --pairs --output NAME,PTUUID,PARTUUID)" \
		|| die "Error while executing lsblk to cache output"
}

function get_device_by_ptuuid() {
	local ptuuid="${1,,}"
	local dev
	if [[ -v CACHED_LSBLK_OUTPUT && -n "$CACHED_LSBLK_OUTPUT" ]]; then
		dev="$CACHED_LSBLK_OUTPUT"
	else
		dev="$(lsblk --all --path --pairs --output NAME,PTUUID,PARTUUID)" \
			|| die "Error while executing lsblk to find PTUUID=$ptuuid"
	fi
	dev="$(grep "ptuuid=\"$ptuuid\" partuuid=\"\"" <<< "${dev,,}")" \
		|| die "Could not find PTUUID=... in lsblk output"
	dev="${dev%'" ptuuid='*}"
	dev="${dev#'name="'}"
	echo -n "$dev"
}

function uuid_to_mduuid() {
	local mduuid="${1,,}"
	mduuid="${mduuid//-/}"
	mduuid="${mduuid:0:8}:${mduuid:8:8}:${mduuid:16:8}:${mduuid:24:8}"
	echo -n "$mduuid"
}

function get_device_by_mdadm_uuid() {
	local mduuid
	mduuid="$(uuid_to_mduuid "$1")" \
		|| die "Could not resolve mduuid from uuid=$1"
	local dev
	dev="$(mdadm --examine --scan)" \
		|| die "Error while executing mdadm to find array with UUID=$mduuid"
	dev="$(grep "uuid=$mduuid" <<< "${dev,,}")" \
		|| die "Could not find UUID=... in mdadm output"
	dev="${dev%'metadata='*}"
	dev="${dev#'array'}"
	dev="${dev#"${dev%%[![:space:]]*}"}"
	dev="${dev%"${dev##*[![:space:]]}"}"
	echo -n "$dev"
}

function get_device_by_luks_name() {
	echo -n "/dev/mapper/$1"
}

function create_resolve_entry() {
	local id="$1"
	local type="$2"
	local arg="${3,,}"

	DISK_ID_TO_RESOLVABLE[$id]="$type:$arg"
}

function create_resolve_entry_device() {
	local id="$1"
	local dev="$2"

	DISK_ID_TO_RESOLVABLE[$id]="device:$dev"
}

function resolve_device_by_id() {
	local id="$1"
	[[ -v DISK_ID_TO_RESOLVABLE[$id] ]] \
		|| die "Cannot resolve id='$id' to a block device (no table entry)"

	local type="${DISK_ID_TO_RESOLVABLE[$id]%%:*}"
	local arg="${DISK_ID_TO_RESOLVABLE[$id]#*:}"

	case "$type" in
		'partuuid') get_device_by_partuuid   "$arg" ;;
		'ptuuid')   get_device_by_ptuuid     "$arg" ;;
		'uuid')     get_device_by_uuid       "$arg" ;;
		'mdadm')    get_device_by_mdadm_uuid "$arg" ;;
		'luks')     get_device_by_luks_name  "$arg" ;;
		'device')   echo -n "$arg" ;;
		*) die "Cannot resolve '$type:$arg' to device (unknown type)"
	esac
}

function load_or_generate_uuid() {
	local uuid
	local uuid_file="$UUID_STORAGE_DIR/$1"

	if [[ -e $uuid_file ]]; then
		uuid="$(cat "$uuid_file")"
	else
		uuid="$(uuidgen -r)"
		mkdir -p "$UUID_STORAGE_DIR"
		echo -n "$uuid" > "$uuid_file"
	fi

	echo -n "$uuid"
}

# Parses named arguments and stores them in the associative array `arguments`.
# If given, the associative array `known_arguments` must contain a list of arguments
# prefixed with + (mandatory) or ? (optional). "at least one of" can be expressed by +a|b|c.
function parse_arguments() {
	local key
	local value
	local a
	for a in "$@"; do
		key="${a%%=*}"
		value="${a#*=}"

		if [[ $key == "$a" ]]; then
			extra_arguments+=("$a")
			continue
		fi

		arguments[$key]="$value"
	done

	declare -A allowed_keys
	if [[ -v known_arguments ]]; then
		local m
		for m in "${known_arguments[@]}"; do
			case "${m:0:1}" in
				'+')
					m="${m:1}"
					local has_opt=false
					local m_opt
					# Splitting is intentional here
					# shellcheck disable=SC2086
					for m_opt in ${m//|/ }; do
						allowed_keys[$m_opt]=true
						if [[ -v arguments[$m_opt] ]]; then
							has_opt=true
						fi
					done

					[[ $has_opt == "true" ]] \
						|| die_trace 2 "Missing mandatory argument $m=..."
					;;

				'?')
					allowed_keys[${m:1}]=true
					;;

				*) die_trace 2 "Invalid start character in known_arguments, in argument '$m'" ;;
			esac
		done

		for a in "${!arguments[@]}"; do
			[[ -v allowed_keys[$a] ]] \
				|| die_trace 2 "Unknown argument '$a'"
		done
	fi
}

function check_has_programs() {
	local failed=()
	local tuple
	local program
	local checkfile
	for tuple in "$@"; do
		program="${tuple%%=*}"
		checkfile="${tuple##*=}"
		if [[ -z "$checkfile" ]]; then
			type "$program" &>/dev/null \
				|| failed+=("$program")
		elif [[ "${checkfile:0:1}" == "/" ]]; then
			[[ -e "$checkfile" ]] \
				|| failed+=("$program")
		else
			type "$checkfile" &>/dev/null \
				|| failed+=("$program")
		fi
	done

	[[ "${#failed[@]}" -eq 0 ]] \
		&& return

	elog "The following programs are required for the installer to work, but are currently missing on your system:" >&2
	elog "  ${failed[*]}" >&2

	if type pacman &>/dev/null; then
		declare -A pacman_packages
		pacman_packages=(
			[ntpd]=ntp
			[zfs]=""
		)
		elog "We have detected that pacman is available."
		if ask "Do you want to install the missing programs automatically?"; then
			local packages
			local need_zfs=false

			for program in "${failed[@]}"; do
				[[ "$program" == "zfs" ]] \
					&& need_zfs=true

				if [[ -v "pacman_packages[$program]" ]]; then
					# Assignments to the empty string are explcitly ignored,
					# as for example zfs needs to be handeled separately.
					[[ -n "${pacman_packages[$program]}" ]] \
						&& packages+=("${pacman_packages[$program]}")
				else
					packages+=("$program")
				fi
			done
			pacman -Sy "${packages[@]}"

			if [[ "$need_zfs" == true ]]; then
				elog "On an Arch live-stick you need the archzfs repository and some tools and modifications to use zfs."
				elog "There is an automated installer available at https://eoli3n.github.io/archzfs/init."
				if ask "Do you want to automatically download and execute this zfs installation script?"; then
					curl -s "https://eoli3n.github.io/archzfs/init" | bash
				fi
			fi

			return
		fi
	fi

	die "Aborted installer because of missing required programs."
}
