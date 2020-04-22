source "$GENTOO_INSTALL_REPO_DIR/scripts/protection.sh" || exit 1


################################################
# Functions

check_has_program() {
	type "$1" &>/dev/null \
		|| die "Missing program: '$1'"
}

sync_time() {
	einfo "Syncing time"
	ntpd -g -q \
		|| die "Could not sync time with remote server"

	einfo "Current date: $(LANG=C date)"
	einfo "Writing time to hardware clock"
	hwclock --systohc --utc \
		|| die "Could not save time to hardware clock"
}

check_config() {
	[[ $KEYMAP =~ ^[0-9A-Za-z-]*$ ]] \
		|| die "KEYMAP contains invalid characters"

	# Check hostname per RFC1123
	local hostname_regex='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
	[[ $HOSTNAME =~ $hostname_regex ]] \
		|| die "'$HOSTNAME' is not a valid hostname"

	[[ -n $DISK_ID_ROOT ]] \
		|| die "You must assign DISK_ID_ROOT"
	[[ -n $DISK_ID_EFI ]] || [[ -n $DISK_ID_BIOS ]] \
		|| die "You must assign DISK_ID_EFI or DISK_ID_BIOS"

	[[ -v "DISK_ID_BIOS" ]] && [[ ! -v "DISK_ID_TO_UUID[$DISK_ID_BIOS]" ]] \
		&& die "Missing uuid for DISK_ID_BIOS, have you made sure it is used?"
	[[ -v "DISK_ID_EFI" ]] && [[ ! -v "DISK_ID_TO_UUID[$DISK_ID_EFI]" ]] \
		&& die "Missing uuid for DISK_ID_EFI, have you made sure it is used?"
	[[ -v "DISK_ID_SWAP" ]] && [[ ! -v "DISK_ID_TO_UUID[$DISK_ID_SWAP]" ]] \
		&& die "Missing uuid for DISK_ID_SWAP, have you made sure it is used?"
	[[ -v "DISK_ID_ROOT" ]] && [[ ! -v "DISK_ID_TO_UUID[$DISK_ID_ROOT]" ]] \
		&& die "Missing uuid for DISK_ID_ROOT, have you made sure it is used?"

	if [[ -v "DISK_ID_EFI" ]]; then
		IS_EFI=true
	else
		IS_EFI=false
	fi

	if [[ $INSTALL_ANSIBLE == true ]]; then
		[[ $INSTALL_SSHD == true ]] \
			|| die "You must enable INSTALL_SSHD for ansible"
		[[ -n $ANSIBLE_SSH_AUTHORIZED_KEYS ]] \
			|| die "Missing pubkey for ansible user"
	fi
}

preprocess_config() {
	check_config
}

prepare_installation_environment() {
	einfo "Preparing installation environment"

	check_has_program gpg
	check_has_program hwclock
	check_has_program lsblk
	check_has_program ntpd
	check_has_program partprobe
	check_has_program python3
	check_has_program rhash
	check_has_program sgdisk
	check_has_program uuidgen
	check_has_program wget

	[[ $USED_RAID == true ]] \
		&& check_has_program mdadm
	[[ $USED_LUKS == true ]] \
		&& check_has_program cryptsetup

	sync_time
}

add_summary_entry() {
	local parent="$1"
	local id="$2"
	local name="$3"
	local hint="$4"
	local desc="$5"

	local ptr
	case "$id" in
		"$DISK_ID_BIOS")  ptr="[1;32m← bios[m" ;;
		"$DISK_ID_EFI")   ptr="[1;32m← efi[m"  ;;
		"$DISK_ID_SWAP")  ptr="[1;34m← swap[m" ;;
		"$DISK_ID_ROOT")  ptr="[1;33m← root[m" ;;
		# \x1f characters compensate for printf byte count and unicode character count mismatch due to '←'
		*)                ptr="[1;32m[m$(echo -e "\x1f\x1f")" ;;
	esac

	summary_tree[$parent]+=";$id"
	summary_name[$id]="$name"
	summary_hint[$id]="$hint"
	summary_ptr[$id]="$ptr"
	summary_desc[$id]="$desc"
}

summary_color_args() {
	for arg in "$@"; do
		if [[ -v "arguments[$arg]" ]]; then
			printf '%-28s ' "[1;34m$arg[2m=[m${arguments[$arg]}"
		fi
	done
}

resolve_device_by_id() {
	local id="$1"
	[[ -v disk_id_to_resolvable[$id] ]] \
		|| die "Cannot resolve id='$id' to a block device (no table entry)"

	local type="${disk_id_to_resolvable[$id]%%:*}"
	local arg="${disk_id_to_resolvable[$id]#*:}"

	case "$type" in
		'partuuid') get_device_by_partuuid   "$arg" ;;
		'ptuuid')   get_device_by_ptuuid     "$arg" ;;
		'uuid')     get_device_by_uuid       "$arg" ;;
		'mdadm')    get_device_by_mdadm_uuid "$arg" ;;
		'luks')     get_device_by_luks_uuid  "$arg" ;;
		*) die "Cannot resolve '$type:$arg' to device (unkown type)"
	esac
}

disk_create_gpt() {
	local new_id="${arguments[new_id]}"
	if [[ $disk_action_summarize_only == true ]]; then
		if [[ -v arguments[id] ]]; then
			add_summary_entry "${arguments[id]}" "$new_id" "gpt" "" ""
		else
			add_summary_entry __root__ "$new_id" "${arguments[device]}" "(gpt)" ""
		fi
		return 0
	fi

	local device
	local device_desc=""
	if [[ -v arguments[id] ]]; then
		device="$(resolve_device_by_id "${arguments[id]}")"
		device_desc="$device ($id)"
	else
		device="${arguments[device]}"
		device_desc="$device"
	fi

	local ptuuid="${DISK_ID_TO_UUID[$new_id]}"
	DISK_PTUUID_TO_DEVICE[${ptuuid,,}]="$device"
	disk_id_to_resolvable[$new_id]="ptuuid:$ptuuid"

	einfo "Creating new gpt partition table ($new_id) on $device_desc"
	sgdisk -Z -U "$ptuuid" "$device" >/dev/null \
		|| die "Could not create new gpt partition table ($new_id) on '$device'"
	partprobe "$device"
}

disk_create_partition() {
	local new_id="${arguments[new_id]}"
	local id="${arguments[id]}"
	local size="${arguments[size]}"
	local type="${arguments[type]}"
	if [[ $disk_action_summarize_only == true ]]; then
		add_summary_entry "$id" "$new_id" "part" "($type)" "$(summary_color_args size)"
		return 0
	fi

	if [[ $size == "remaining" ]]; then
		arg_size=0
	else
		arg_size="+$size"
	fi

	local device="$(resolve_device_by_id "$id")"
	local partuuid="${DISK_ID_TO_UUID[$new_id]}"
	local extra_args=""
	case "$type" in
		'bios')  type='ef02' extra_args='--attributes=0:set:2';;
		'efi')   type='ef00' ;;
		'swap')  type='8200' ;;
		'raid')  type='fd00' ;;
		'luks')  type='8309' ;;
		'linux') type='8300' ;;
		*) ;;
	esac

	disk_id_to_resolvable[$new_id]="partuuid:$partuuid"

	einfo "Creating partition ($new_id) with type=$type, size=$size on $device"
	# shellcheck disable=SC2086
	sgdisk -n "0:0:$arg_size" -t "0:$type" -u "0:$partuuid" $extra_args "$device" >/dev/null \
		|| die "Could not create new gpt partition ($new_id) on '$device' ($id)"
	partprobe "$device"
}

disk_create_raid() {
	local new_id="${arguments[new_id]}"
	local level="${arguments[level]}"
	local name="${arguments[name]}"
	local ids="${arguments[ids]}"
	if [[ $disk_action_summarize_only == true ]]; then
		local id
		# Splitting is intentional here
		# shellcheck disable=SC2086
		for id in ${ids//';'/ }; do
			add_summary_entry "$id" "_$new_id" "raid$level" "" "$(summary_color_args name)"
		done

		add_summary_entry __root__ "$new_id" "raid$level" "" "$(summary_color_args name)"
		return 0
	fi

	local devices_desc=""
	local devices=()
	local id
	# Splitting is intentional here
	# shellcheck disable=SC2086
	for id in ${ids//';'/ }; do
		local dev="$(resolve_device_by_id "$id")"
		devices+=("$dev")
		devices_desc+="$dev ($id), "
	done
	devices_desc="${devices_desc:0:-2}"

	local mddevice="/dev/md/$name"
	local uuid="${DISK_ID_TO_UUID[$new_id]}"
	DISK_MDADM_UUID_TO_DEVICE[${uuid,,}]="$mddevice"
	disk_id_to_resolvable[$new_id]="mdadm:$uuid"

	einfo "Creating raid$level ($new_id) on $devices_desc"
	mdadm \
			--create "$mddevice" \
			--verbose \
			--homehost="$HOSTNAME" \
			--metadata=1.2 \
			--raid-devices="${#devices[@]}" \
			--uuid="$uuid" \
			--level="$level" \
			"${devices[@]}" \
		|| die "Could not create raid$level array '$mddevice' ($new_id) on $devices_desc"
}

disk_create_luks() {
	local new_id="${arguments[new_id]}"
	local id="${arguments[id]}"
	if [[ $disk_action_summarize_only == true ]]; then
		add_summary_entry "$id" "$new_id" "luks" "" ""
		return 0
	fi

	local device="$(resolve_device_by_id "$id")"
	local uuid="${DISK_ID_TO_UUID[$new_id]}"
	disk_id_to_resolvable[$new_id]="luks:$uuid"

	einfo "Creating luks ($new_id) on $device ($id)"
	local keyfile
	keyfile="$(luks_getkeyfile "$new_id")" \
		|| die "Error in luks_getkeyfile for id=$id"
	cryptsetup luksFormat \
			--type luks2 \
			--uuid "$uuid" \
			--key-file "$keyfile" \
			--cipher aes-xts-plain64 \
			--hash sha512 \
			--pbkdf argon2id \
			--iter-time 4000 \
			--key-size 512 \
			"$device" \
		|| die "Could not create luks on '$device' ($id)"
	mkdir -p "$LUKS_HEADER_BACKUP_DIR" \
		|| die "Could not create luks header backup dir '$LUKS_HEADER_BACKUP_DIR'"
	cryptsetup luksHeaderBackup "$device" \
			--header-backup-file "$LUKS_HEADER_BACKUP_DIR/luks-header-$id-${uuid,,}.img" \
		|| die "Could not backup luks header on '$device' ($id)"
	cryptsetup open --type luks2 \
			--key-file "$keyfile" \
			"$device" "${uuid,,}" \
		|| die "Could not open luks header on '$device' ($id)"
}

disk_format() {
	local id="${arguments[id]}"
	local type="${arguments[type]}"
	local label="${arguments[label]}"
	if [[ $disk_action_summarize_only == true ]]; then
		add_summary_entry "${arguments[id]}" "__fs__${arguments[id]}" "${arguments[type]}" "(fs)" "$(summary_color_args label)"
		return 0
	fi

	local device="$(resolve_device_by_id "$id")"
	einfo "Formatting $device ($id) with $type"
	case "$type" in
		'bios'|'efi')
			if [[ -v "arguments[label]" ]]; then
				mkfs.fat -F 32 -n "$label" "$device" \
					|| die "Could not format device '$device' ($id)"
			else
				mkfs.fat -F 32 "$device" \
					|| die "Could not format device '$device' ($id)"
			fi
			;;
		'swap')
			if [[ -v "arguments[label]" ]]; then
				mkswap -L "$label" "$device" \
					|| die "Could not format device '$device' ($id)"
			else
				mkswap "$device" \
					|| die "Could not format device '$device' ($id)"
			fi
			;;
		'ext4')
			if [[ -v "arguments[label]" ]]; then
				mkfs.ext4 -q -L "$label" "$device" \
					|| die "Could not format device '$device' ($id)"
			else
				mkfs.ext4 -q "$device" \
					|| die "Could not format device '$device' ($id)"
			fi
			;;
		*) die "Unknown filesystem type" ;;
	esac
}

apply_disk_action() {
	unset known_arguments
	unset arguments; declare -A arguments; parse_arguments "$@"
	case "${arguments[action]}" in
		'create_gpt')       disk_create_gpt       ;;
		'create_partition') disk_create_partition ;;
		'create_raid')      disk_create_raid      ;;
		'create_luks')      disk_create_luks      ;;
		'format')           disk_format           ;;
		*) echo "Ignoring invalid action: ${arguments[action]}" ;;
	esac
}

print_summary_tree_entry() {
	local indent_chars=""
	local indent="0"
	local d="1"
	local maxd="$((depth - 1))"
	while [[ $d -lt $maxd ]]; do
		if [[ ${summary_depth_continues[$d]} == true ]]; then
			indent_chars+='│ '
		else
			indent_chars+='  '
		fi
		indent=$((indent + 2))
		d="$((d + 1))"
	done
	if [[ $maxd -gt 0 ]]; then
		if [[ ${summary_depth_continues[$maxd]} == true ]]; then
			indent_chars+='├─'
		else
			indent_chars+='└─'
		fi
		indent=$((indent + 2))
	fi

	local name="${summary_name[$root]}"
	local hint="${summary_hint[$root]}"
	local desc="${summary_desc[$root]}"
	local ptr="${summary_ptr[$root]}"
	local id_name="[2m[m"
	if [[ $root != __* ]]; then
		if [[ $root == _* ]]; then
			id_name="[2m${root:1}[m"
		else
			id_name="[2m${root}[m"
		fi
	fi

	local align=0
	if [[ $indent -lt 33 ]]; then
		align="$((33 - indent))"
	fi

	elog "$indent_chars$(printf "%-${align}s %-47s %s" \
		"$name [2m$hint[m" \
		"$id_name $ptr" \
		"$desc")"
}

print_summary_tree() {
	local root="$1"
	local depth="$((depth + 1))"
	local has_children=false

	if [[ -v "summary_tree[$root]" ]]; then
		local children="${summary_tree[$root]}"
		has_children=true
		summary_depth_continues[$depth]=true
	else
		summary_depth_continues[$depth]=false
	fi

	if [[ $root != __root__ ]]; then
		print_summary_tree_entry "$root"
	fi

	if [[ $has_children == true ]]; then
		local count="$(tr ';' '\n' <<< "$children" | grep -c '\S')"
		local idx=0
		# Splitting is intentional here
		# shellcheck disable=SC2086
		for id in ${children//';'/ }; do
			idx="$((idx + 1))"
			[[ $idx == "$count" ]] \
				&& summary_depth_continues[$depth]=false
			print_summary_tree "$id"
			# separate blocks by newline
			[[ ${summary_depth_continues[0]} == true ]] && [[ $depth == 1 ]] && [[ $idx == "$count" ]] \
				&& elog
		done
	fi
}

apply_disk_actions() {
	declare -A disk_id_to_resolvable

	local param
	local current_params=()
	for param in "${DISK_ACTIONS[@]}"; do
		if [[ $param == ';' ]]; then
			apply_disk_action "${current_params[@]}"
			current_params=()
		else
			current_params+=("$param")
		fi
	done
}

summarize_disk_actions() {
	elog "[1mCurrent lsblk output:[m"
	for_line_in <(lsblk \
		|| die "Error in lsblk") elog

	local disk_action_summarize_only=true
	declare -A summary_tree
	declare -A summary_name
	declare -A summary_hint
	declare -A summary_ptr
	declare -A summary_desc
	declare -A summary_depth_continues
	apply_disk_actions

	local depth=-1
	elog
	elog "[1mConfigured disk layout:[m"
	elog ────────────────────────────────────────────────────────────────────────────────
	elog "$(printf '%-26s %-28s %s' NODE ID OPTIONS)"
	elog ────────────────────────────────────────────────────────────────────────────────
	print_summary_tree __root__
	elog ────────────────────────────────────────────────────────────────────────────────
}

apply_disk_configuration() {
	summarize_disk_actions

	ask "Do you really want to apply this disk configuration?" \
		|| die "Aborted"
	countdown "Applying in " 5

	einfo "Applying disk configuration"
	apply_disk_actions

	einfo "Disk configuration was applied successfully"
	elog "[1mNew lsblk output:[m"
	for_line_in <(lsblk \
		|| die "Error in lsblk") elog
}

mount_efivars() {
	# Skip if already mounted
	mountpoint -q -- "/sys/firmware/efi/efivars" \
		&& return

	# Mount efivars
	einfo "Mounting efivars"
	mount -t efivarfs efivarfs "/sys/firmware/efi/efivars" \
		|| die "Could not mount efivarfs"
}

mount_by_id() {
	local dev
	local id="$1"
	local mountpoint="$2"

	# Skip if already mounted
	mountpoint -q -- "$mountpoint" \
		&& return

	# Mount device
	einfo "Mounting device with id=$id to '$mountpoint'"
	mkdir -p "$mountpoint" \
		|| die "Could not create mountpoint directory '$mountpoint'"
	dev="$(resolve_device_by_id "$id")" \
		|| die "Could not resolve device with id=$id"
	mount "$dev" "$mountpoint" \
		|| die "Could not mount device '$dev'"
}

mount_root() {
	mount_by_id "$DISK_ID_ROOT" "$ROOT_MOUNTPOINT"
}

bind_repo_dir() {
	# Use new location by default
	export GENTOO_INSTALL_REPO_DIR="$GENTOO_INSTALL_REPO_BIND"

	# Bind the repo dir to a location in /tmp,
	# so it can be accessed from within the chroot
	mountpoint -q -- "$GENTOO_INSTALL_REPO_BIND" \
		&& return

	# Mount root device
	einfo "Bind mounting repo directory"
	mkdir -p "$GENTOO_INSTALL_REPO_BIND" \
		|| die "Could not create mountpoint directory '$GENTOO_INSTALL_REPO_BIND'"
	mount --bind "$GENTOO_INSTALL_REPO_DIR_ORIGINAL" "$GENTOO_INSTALL_REPO_BIND" \
		|| die "Could not bind mount '$GENTOO_INSTALL_REPO_DIR_ORIGINAL' to '$GENTOO_INSTALL_REPO_BIND'"
}

download_stage3() {
	cd "$TMP_DIR" \
		|| die "Could not cd into '$TMP_DIR'"

	local STAGE3_RELEASES="$GENTOO_MIRROR/releases/amd64/autobuilds/current-$STAGE3_BASENAME/"

	# Download upstream list of files
	CURRENT_STAGE3="$(download_stdout "$STAGE3_RELEASES")" \
		|| die "Could not retrieve list of tarballs"
	# Decode urlencoded strings
	CURRENT_STAGE3=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read()))' <<< "$CURRENT_STAGE3")
	# Parse output for correct filename
	CURRENT_STAGE3="$(grep -o "\"${STAGE3_BASENAME}-[0-9A-Z]*.tar.xz\"" <<< "$CURRENT_STAGE3" \
		| sort -u | head -1)" \
		|| die "Could not parse list of tarballs"
	# Strip quotes
	CURRENT_STAGE3="${CURRENT_STAGE3:1:-1}"
	# File to indiciate successful verification
	CURRENT_STAGE3_VERIFIED="${CURRENT_STAGE3}.verified"

	# Download file if not already downloaded
	if [[ -e $CURRENT_STAGE3_VERIFIED ]]; then
		einfo "$STAGE3_BASENAME tarball already downloaded and verified"
	else
		einfo "Downloading $STAGE3_BASENAME tarball"
		download "$STAGE3_RELEASES/${CURRENT_STAGE3}" "${CURRENT_STAGE3}"
		download "$STAGE3_RELEASES/${CURRENT_STAGE3}.DIGESTS.asc" "${CURRENT_STAGE3}.DIGESTS.asc"

		# Import gentoo keys
		einfo "Importing gentoo gpg key"
		local GENTOO_GPG_KEY="$TMP_DIR/gentoo-keys.gpg"
		download "https://gentoo.org/.well-known/openpgpkey/hu/wtktzo4gyuhzu8a4z5fdj3fgmr1u6tob?l=releng" "$GENTOO_GPG_KEY" \
			|| die "Could not retrieve gentoo gpg key"
		gpg --quiet --import < "$GENTOO_GPG_KEY" \
			|| die "Could not import gentoo gpg key"

		# Verify DIGESTS signature
		einfo "Verifying DIGEST.asc signature"
		gpg --quiet --verify "${CURRENT_STAGE3}.DIGESTS.asc" \
			|| die "Signature of '${CURRENT_STAGE3}.DIGESTS.asc' invalid!"

		# Check hashes
		einfo "Verifying tarball integrity"
		rhash -P --check <(grep -B 1 'tar.xz$' "${CURRENT_STAGE3}.DIGESTS.asc") \
			|| die "Checksum mismatch!"

		# Create verification file in case the script is restarted
		touch_or_die 0644 "$CURRENT_STAGE3_VERIFIED"
	fi
}

extract_stage3() {
	mount_root

	[[ -n $CURRENT_STAGE3 ]] \
		|| die "CURRENT_STAGE3 is not set"
	[[ -e "$TMP_DIR/$CURRENT_STAGE3" ]] \
		|| die "stage3 file does not exist"

	# Go to root directory
	cd "$ROOT_MOUNTPOINT" \
		|| die "Could not move to '$ROOT_MOUNTPOINT'"
	# Ensure the directory is empty
	find . -mindepth 1 -maxdepth 1 -not -name 'lost+found' \
		| grep -q . \
		&& die "root directory '$ROOT_MOUNTPOINT' is not empty"

	# Extract tarball
	einfo "Extracting stage3 tarball"
	tar xpf "$TMP_DIR/$CURRENT_STAGE3" --xattrs --numeric-owner \
		|| die "Error while extracting tarball"
	cd "$TMP_DIR" \
		|| die "Could not cd into '$TMP_DIR'"
}

gentoo_umount() {
	if mountpoint -q -- "$ROOT_MOUNTPOINT"; then
		einfo "Unmounting root filesystem"
		umount -R -l "$ROOT_MOUNTPOINT" \
			|| die "Could not unmount filesystems"
	fi
}

init_bash() {
	source /etc/profile
	umask 0077
	export PS1='(chroot) \[[0;31m\]\u\[[1;31m\]@\h \[[1;34m\]\w \[[m\]\$ \[[m\]'
}; export -f init_bash

env_update() {
	env-update \
		|| die "Error in env-update"
	source /etc/profile \
		|| die "Could not source /etc/profile"
	umask 0077
}

mkdir_or_die() {
	# shellcheck disable=SC2174
	mkdir -m "$1" -p "$2" \
		|| die "Could not create directory '$2'"
}

touch_or_die() {
	touch "$2" \
		|| die "Could not touch '$2'"
	chmod "$1" "$2"
}

gentoo_chroot() {
	if [[ $# -eq 0 ]]; then
		gentoo_chroot /bin/bash --init-file <(echo 'init_bash')
	fi

	[[ $EXECUTED_IN_CHROOT != true ]] \
		|| die "Already in chroot"

	gentoo_umount
	mount_root
	bind_repo_dir

	# Copy resolv.conf
	einfo "Preparing chroot environment"
	install --mode=0644 /etc/resolv.conf "$ROOT_MOUNTPOINT/etc/resolv.conf" \
		|| die "Could not copy resolv.conf"

	# Mount virtual filesystems
	einfo "Mounting virtual filesystems"
	(
		mountpoint -q -- "$ROOT_MOUNTPOINT/proc" || mount -t proc /proc "$ROOT_MOUNTPOINT/proc" || exit 1
		mountpoint -q -- "$ROOT_MOUNTPOINT/tmp"  || mount --rbind /tmp  "$ROOT_MOUNTPOINT/tmp"  || exit 1
		mountpoint -q -- "$ROOT_MOUNTPOINT/sys"  || {
			mount --rbind /sys  "$ROOT_MOUNTPOINT/sys" &&
			mount --make-rslave "$ROOT_MOUNTPOINT/sys"; } || exit 1
		mountpoint -q -- "$ROOT_MOUNTPOINT/dev"  || {
			mount --rbind /dev  "$ROOT_MOUNTPOINT/dev" &&
			mount --make-rslave "$ROOT_MOUNTPOINT/dev"; } || exit 1
	) || die "Could not mount virtual filesystems"

	# Execute command
	einfo "Chrooting..."
	EXECUTED_IN_CHROOT=true \
		TMP_DIR=$TMP_DIR \
		exec chroot -- "$ROOT_MOUNTPOINT" "$GENTOO_INSTALL_REPO_DIR/scripts/main_chroot.sh" "$@" \
			|| die "Failed to chroot into '$ROOT_MOUNTPOINT'"
}
