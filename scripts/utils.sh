# shellcheck source=./scripts/protection.sh
source "$GENTOO_INSTALL_REPO_DIR/scripts/protection.sh" || exit 1

# =============================================================================
# Logging Functions
# =============================================================================

function elog() {
	echo "[\033[1m+\033[m] $*"
}

function einfo() {
	echo "[\033[1m+\033[m] \033[1;33m$*\033[m"
}

function ewarn() {
	echo "[\033[1;31m!\033[m] \033[1;33m$*\033[m" >&2
}

function eerror() {
	echo "\033[1;31merror:\033[m $*" >&2
}

function edebug() {
	if [[ "${GENTOO_INSTALL_DEBUG:-false}" == "true" ]]; then
		echo "[\033[1;36mDEBUG\033[m] $*" >&2
	fi
}

# =============================================================================
# Error Handling Functions
# =============================================================================

function die() {
	eerror "$*"
	# Kill the main script process if we're in a subshell
	if [[ -v GENTOO_INSTALL_REPO_SCRIPT_PID && $$ -ne $GENTOO_INSTALL_REPO_SCRIPT_PID ]]; then
		kill "$GENTOO_INSTALL_REPO_SCRIPT_PID" 2>/dev/null || true
	fi
	exit 1
}

# Prints an error with file:line info of the nth "stack frame".
# 0 is this function, 1 the calling function, 2 its parent, and so on.
function die_trace() {
	local idx="${1:-0}"
	shift
	local source_file="${BASH_SOURCE[$((idx + 1))]:-unknown}"
	local line_no="${BASH_LINENO[$idx]:-0}"
	local func_name="${FUNCNAME[$idx]:-main}"
	echo "\033[1m${source_file}:${line_no}: \033[1;31merror:\033[m ${func_name}: $*" >&2
	exit 1
}

# =============================================================================
# Utility Functions
# =============================================================================

function for_line_in() {
	local file="$1"
	local callback="$2"
	
	[[ -r "$file" ]] || die "Cannot read file: $file"
	[[ -n "$callback" ]] || die "No callback function specified"
	type "$callback" &>/dev/null || die "Callback function '$callback' not found"
	
	local line
	while IFS="" read -r line || [[ -n $line ]]; do
		"$callback" "$line"
	done <"$file"
}

function flush_stdin() {
	local empty_stdin
	# Unused variable is intentional - we're just draining stdin
	# shellcheck disable=SC2034
	while read -r -t 0.01 empty_stdin; do true; done
	return 0
}

function ask() {
	local response
	local prompt="$* (Y/n) "
	
	while true; do
		flush_stdin
		read -r -p "$prompt" response \
			|| die "Error in read"
		case "${response,,}" in
			'') return 0 ;;
			y|yes) return 0 ;;
			n|no) return 1 ;;
			*) 
				ewarn "Please answer 'y' or 'n'"
				continue 
				;;
		esac
	done
}

function try() {
	local response
	local cmd_status
	local prompt_parens="(\033[1mS\033[mhell/\033[1mr\033[metry/\033[1ma\033[mbort/\033[1mc\033[montinue/\033[1mp\033[mrint)"

	# Outer loop, allows us to retry the command
	while true; do
		# Try command
		"$@"
		cmd_status="$?"

		if [[ $cmd_status != 0 ]]; then
			echo -e "\033[1;31m * Command failed: \033[1;33m\$\033[m $*"
			echo "Last command failed with exit code $cmd_status"

			# Prompt until input is valid
			while true; do
				echo -en "Specify next action $prompt_parens "
				flush_stdin
				read -r response \
					|| die "Error in read"
				case "${response,,}" in
					''|s|shell)
						echo "You will be prompted for action again after exiting this shell."
						/bin/bash --init-file <(echo "init_bash")
						;;
					r|retry) continue 2 ;;
					a|abort) die "Installation aborted by user" ;;
					c|continue) return 0 ;;
					p|print) echo -e "\033[1;33m\$\033[m $*" ;;
					*) ewarn "Invalid option. Please choose: s/r/a/c/p" ;;
				esac
			done
		fi

		return 0
	done
}

function countdown() {
	local message="$1"
	local seconds="${2:-5}"
	
	[[ "$seconds" =~ ^[0-9]+$ ]] || seconds=5
	
	echo -n "$message" >&2

	local i="$seconds"
	while [[ $i -gt 0 ]]; do
		echo -n "\033[1;31m$i\033[m " >&2
		i=$((i - 1))
		sleep 1
	done
	echo >&2
}

# =============================================================================
# Download Functions
# =============================================================================

function download_stdout() {
	local url="$1"
	local max_retries="${2:-3}"
	local retry_delay="${3:-5}"
	local attempt=1
	
	while [[ $attempt -le $max_retries ]]; do
		if wget --quiet --https-only --secure-protocol=PFS -O - -- "$url" 2>/dev/null; then
			return 0
		fi
		
		if [[ $attempt -lt $max_retries ]]; then
			ewarn "Download failed (attempt $attempt/$max_retries), retrying in ${retry_delay}s..."
			sleep "$retry_delay"
		fi
		attempt=$((attempt + 1))
	done
	
	return 1
}

function download() {
	local url="$1"
	local output="$2"
	local max_retries="${3:-3}"
	local retry_delay="${4:-5}"
	local attempt=1
	
	while [[ $attempt -le $max_retries ]]; do
		if wget --quiet --https-only --secure-protocol=PFS --show-progress -O "$output" -- "$url" 2>/dev/null; then
			return 0
		fi
		
		if [[ $attempt -lt $max_retries ]]; then
			ewarn "Download failed (attempt $attempt/$max_retries), retrying in ${retry_delay}s..."
			sleep "$retry_delay"
			# Remove partial download
			rm -f "$output" 2>/dev/null || true
		fi
		attempt=$((attempt + 1))
	done
	
	return 1
}

# =============================================================================
# Block Device Functions
# =============================================================================

function get_blkid_field_by_device() {
	local blkid_field="$1"
	local device="$2"
	
	[[ -n "$blkid_field" ]] || die "blkid_field is empty"
	[[ -n "$device" ]] || die "device is empty"
	[[ -b "$device" ]] || die "Device '$device' is not a block device"
	
	blkid -g -c /dev/null \
		|| die "Error while executing blkid"
	partprobe "$device" &>/dev/null || true
	
	local val
	val="$(blkid -c /dev/null -o export "$device")" \
		|| die "Error while executing blkid '$device'"
	val="$(grep -- "^$blkid_field=" <<< "$val")" \
		|| die "Could not find $blkid_field=... in blkid output for device '$device'"
	val="${val#"$blkid_field="}"
	echo -n "$val"
}

function get_blkid_uuid_for_id() {
	local id="$1"
	local dev
	dev="$(resolve_device_by_id "$id")" \
		|| die "Could not resolve device with id='$id'"
	local uuid
	uuid="$(get_blkid_field_by_device 'UUID' "$dev")" \
		|| die "Could not get UUID from blkid for device='$dev' (id='$id')"
	echo -n "$uuid"
}

function get_device_by_blkid_field() {
	local blkid_field="$1"
	local field_value="$2"
	
	[[ -n "$blkid_field" ]] || die "blkid_field is empty"
	[[ -n "$field_value" ]] || die "field_value is empty"
	
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
	local partuuid="$1"
	[[ -n "$partuuid" ]] || die "partuuid is empty"
	
	if [[ -e "/dev/disk/by-partuuid/$partuuid" ]]; then
		echo -n "/dev/disk/by-partuuid/$partuuid"
	else
		get_device_by_blkid_field 'PARTUUID' "$partuuid"
	fi
}

function get_device_by_uuid() {
	local uuid="$1"
	[[ -n "$uuid" ]] || die "uuid is empty"
	
	if [[ -e "/dev/disk/by-uuid/$uuid" ]]; then
		echo -n "/dev/disk/by-uuid/$uuid"
	else
		get_device_by_blkid_field 'UUID' "$uuid"
	fi
}

function cache_lsblk_output() {
	CACHED_LSBLK_OUTPUT="$(lsblk --all --path --pairs --output NAME,PTUUID,PARTUUID 2>/dev/null)" \
		|| die "Error while executing lsblk to cache output"
}

function get_device_by_ptuuid() {
	local ptuuid="${1,,}"
	[[ -n "$ptuuid" ]] || die "ptuuid is empty"
	
	local dev
	if [[ -v CACHED_LSBLK_OUTPUT && -n "$CACHED_LSBLK_OUTPUT" ]]; then
		dev="$CACHED_LSBLK_OUTPUT"
	else
		dev="$(lsblk --all --path --pairs --output NAME,PTUUID,PARTUUID)" \
			|| die "Error while executing lsblk to find PTUUID=$ptuuid"
	fi
	dev="$(grep "ptuuid=&quot;$ptuuid&quot; partuuid=&quot;&quot;" <<< "${dev,,}")" \
		|| die "Could not find PTUUID=$ptuuid in lsblk output"
	dev="${dev%'" ptuuid='*}"
	dev="${dev#'name="'}"
	echo -n "$dev"
}

function uuid_to_mduuid() {
	local uuid="$1"
	[[ -n "$uuid" ]] || die "uuid is empty"
	
	local mduuid="${uuid,,}"
	mduuid="${mduuid//-/}"
	mduuid="${mduuid:0:8}:${mduuid:8:8}:${mduuid:16:8}:${mduuid:24:8}"
	echo -n "$mduuid"
}

function get_device_by_mdadm_uuid() {
	local uuid="$1"
	[[ -n "$uuid" ]] || die "uuid is empty"
	
	local mduuid
	mduuid="$(uuid_to_mduuid "$uuid")" \
		|| die "Could not resolve mduuid from uuid=$uuid"
	local dev
	dev="$(mdadm --examine --scan 2>/dev/null)" \
		|| die "Error while executing mdadm to find array with UUID=$mduuid"
	dev="$(grep "uuid=$mduuid" <<< "${dev,,}")" \
		|| die "Could not find UUID=$mduuid in mdadm output"
	dev="${dev%'metadata='*}"
	dev="${dev#'array'}"
	# Trim leading and trailing whitespace
	dev="${dev#"${dev%%[![:space:]]*}"}"
	dev="${dev%"${dev##*[![:space:]]}"}"
	echo -n "$dev"
}

function get_device_by_luks_name() {
	local name="$1"
	[[ -n "$name" ]] || die "luks name is empty"
	echo -n "/dev/mapper/$name"
}

function create_resolve_entry() {
	local id="$1"
	local type="$2"
	local arg="${3,,}"
	
	[[ -n "$id" ]] || die "id is empty"
	[[ -n "$type" ]] || die "type is empty"
	
	DISK_ID_TO_RESOLVABLE[$id]="$type:$arg"
}

function create_resolve_entry_device() {
	local id="$1"
	local dev="$2"
	
	[[ -n "$id" ]] || die "id is empty"
	[[ -n "$dev" ]] || die "device is empty"

	DISK_ID_TO_RESOLVABLE[$id]="device:$dev"
}

# Returns the basename of the device, if its path starts with /dev/disk/by-id/
function shorten_device() {
	echo -n "${1#/dev/disk/by-id/}"
}

# Return matching device from /dev/disk/by-id/ if possible,
# otherwise return the parameter unchanged.
function canonicalize_device() {
	local given_dev
	given_dev="$(realpath "$1" 2>/dev/null)" || given_dev="$1"
	
	local dev
	for dev in /dev/disk/by-id/*; do
		[[ -e "$dev" ]] || continue
		if [[ "$(realpath "$dev" 2>/dev/null)" == "$given_dev" ]]; then
			echo -n "$dev"
			return 0
		fi
	done

	echo -n "$1"
}

function resolve_device_by_id() {
	local id="$1"
	[[ -n "$id" ]] || die "id is empty"
	[[ -v DISK_ID_TO_RESOLVABLE[$id] ]] \
		|| die "Cannot resolve id='$id' to a block device (no table entry)"

	local type="${DISK_ID_TO_RESOLVABLE[$id]%%:*}"
	local arg="${DISK_ID_TO_RESOLVABLE[$id]#*:}"

	local dev
	case "$type" in
		'partuuid') dev=$(get_device_by_partuuid   "$arg") ;;
		'ptuuid')   dev=$(get_device_by_ptuuid     "$arg") ;;
		'uuid')     dev=$(get_device_by_uuid       "$arg") ;;
		'mdadm')    dev=$(get_device_by_mdadm_uuid "$arg") ;;
		'luks')     dev=$(get_device_by_luks_name  "$arg") ;;
		'device')   dev="$arg" ;;
		*) die "Cannot resolve '$type:$arg' to device (unknown type)"
	esac

	canonicalize_device "$dev"
}

function load_or_generate_uuid() {
	local name="$1"
	[[ -n "$name" ]] || die "name is empty"
	
	local uuid
	local uuid_file="$UUID_STORAGE_DIR/$name"

	if [[ -e $uuid_file ]]; then
		uuid="$(cat "$uuid_file")" || die "Could not read UUID from '$uuid_file'"
	else
		uuid="$(uuidgen -r)" || die "Could not generate UUID"
		mkdir -p "$UUID_STORAGE_DIR" || die "Could not create UUID storage directory"
		echo -n "$uuid" > "$uuid_file" || die "Could not save UUID to '$uuid_file'"
	fi

	echo -n "$uuid"
}

# =============================================================================
# Argument Parsing Functions
# =============================================================================

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

# =============================================================================
# Program Dependency Functions
# =============================================================================

# $1: program
# $2: checkfile (optional)
function has_program() {
	local program="$1"
	local checkfile="${2:-}"
	
	if [[ -z "$checkfile" ]]; then
		type "$program" &>/dev/null || return 1
	elif [[ "${checkfile:0:1}" == "/" ]]; then
		[[ -e "$checkfile" ]] || return 1
	else
		type "$checkfile" &>/dev/null || return 1
	fi
	return 0
}

function check_wanted_programs() {
	local missing_required=()
	local missing_wanted=()
	local tuple
	local program
	local checkfile
	
	for tuple in "$@"; do
		program="${tuple%%=*}"
		checkfile=""
		[[ "$tuple" == *=* ]] && checkfile="${tuple##*=}"
		
		if ! has_program "${program#"?"}" "$checkfile"; then
			if [[ "$program" == "?"* ]]; then
				missing_wanted+=("${program#"?"}")
			else
				missing_required+=("$program")
			fi
		fi
	done

	[[ "${#missing_required[@]}" -eq 0 && "${#missing_wanted[@]}" -eq 0 ]] && return 0

	if [[ "${#missing_required[@]}" -gt 0 ]]; then
		elog "The following programs are required for the installer to work, but are currently missing on your system:" >&2
		elog "  ${missing_required[*]}" >&2
	fi
	if [[ "${#missing_wanted[@]}" -gt 0 ]]; then
		elog "Missing optional programs:" >&2
		elog "  ${missing_wanted[*]}" >&2
	fi

	if type pacman &>/dev/null; then
		declare -A pacman_packages
		pacman_packages=(
			[ntpd]=ntp
			[zfs]=""
		)
		elog "Detected pacman package manager."
		if ask "Do you want to install all missing programs automatically?"; then
			local packages=()
			local need_zfs=false

			for program in "${missing_required[@]}" "${missing_wanted[@]}"; do
				[[ "$program" == "zfs" ]] && need_zfs=true

				if [[ -v "pacman_packages[$program]" ]]; then
					# Assignments to the empty string are explicitly ignored,
					# as for example, zfs needs to be handled separately.
					[[ -n "${pacman_packages[$program]}" ]] \
						&& packages+=("${pacman_packages[$program]}")
				else
					packages+=("$program")
				fi
			done
			
			if [[ ${#packages[@]} -gt 0 ]]; then
				pacman -Sy --noconfirm "${packages[@]}" \
					|| ewarn "Some packages failed to install"
			fi

			if [[ "$need_zfs" == true ]]; then
				elog "On an Arch live-stick you need the archzfs repository and some tools and modifications to use zfs."
				elog "There is an automated installer available at https://raw.githubusercontent.com/eoli3n/archiso-zfs/master/init."
				if ask "Do you want to automatically download and execute this zfs installation script?"; then
					curl -s "https://raw.githubusercontent.com/eoli3n/archiso-zfs/master/init" | bash
				fi
			fi

			return 0
		fi
	elif type emerge &>/dev/null; then
		elog "Detected Portage (emerge) package manager."
		if ask "Do you want to install all missing programs automatically?"; then
			elog "Updating Portage repository cache..."
			emerge --sync || ewarn "Failed to synchronize Portage repositories."

			declare -A emerge_packages
			emerge_packages=(
				[ntpd]="net-misc/ntp"
				[gpg]="app-crypt/gnupg"
				[wget]="net-misc/wget"
				[python3]="dev-lang/python"
				[sgdisk]="sys-apps/gptfdisk"
				[cryptsetup]="sys-fs/cryptsetup"
				[mdadm]="sys-fs/mdadm"
				[btrfs]="sys-fs/btrfs-progs"
				[zfs]="sys-fs/zfs"
			)

			for program in "${missing_required[@]}" "${missing_wanted[@]}"; do
				local pkg="${emerge_packages[$program]:-}"
				if [[ -n "$pkg" ]]; then
					elog "Installing $program ($pkg)..."
					emerge --ask=n --quiet "$pkg" || ewarn "Failed to install $program."
				else
					ewarn "You need to manually install $program."
				fi
			done
			return 0
		fi
	fi

	if [[ "${#missing_required[@]}" -gt 0 ]]; then
		die "Aborted installer because of missing required programs."
	else
		ask "Continue without recommended programs?" || die "Aborted by user"
	fi
}

# =============================================================================
# Misc Functions
# =============================================================================

# exec function if defined
# $@ function name and arguments
function maybe_exec() {
	local func="$1"
	if type "$func" &>/dev/null; then
		"$@"
	fi
}