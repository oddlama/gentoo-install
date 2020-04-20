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
	[[ -n $DISK_ID_EFI ]] || [[ -n $DISK_ID_BOOT ]] \
		|| die "You must assign DISK_ID_EFI or DISK_ID_BOOT"

	if [[ $INSTALL_ANSIBLE == true ]]; then
		[[ $INSTALL_SSHD == true ]] \
			|| die "You must enable INSTALL_SSHD for ansible"
		[[ -n $ANSIBLE_SSH_AUTHORIZED_KEYS ]] \
			|| die "Missing pubkey for ansible user"
	fi
}

prepare_installation_environment() {
	einfo "Preparing installation environment"

	check_config

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
		"$DISK_ID_BOOT")  ptr="[1;32m← boot[m" ;;
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

disk_create_gpt() {
	if [[ $disk_action_summarize_only == true ]]; then
		if [[ -v arguments[id] ]]; then
			add_summary_entry "${arguments[id]}" "${arguments[new_id]}" "gpt" "" ""
		else
			add_summary_entry __root__ "${arguments[new_id]}" "${arguments[device]}" "(gpt)" ""
		fi
		return 0
	fi
}

disk_create_partition() {
	if [[ $disk_action_summarize_only == true ]]; then
		add_summary_entry "${arguments[id]}" "${arguments[new_id]}" "part" "(${arguments[type]})" "$(summary_color_args size)"
		return 0
	fi
}

disk_create_raid() {
	if [[ $disk_action_summarize_only == true ]]; then
		local id
		# Splitting is intentional here
		# shellcheck disable=SC2086
		for id in ${arguments[ids]//';'/ }; do
			add_summary_entry "$id" "_${arguments[new_id]}" "raid${arguments[level]}" "" ""
		done

		add_summary_entry __root__ "${arguments[new_id]}" "raid${arguments[level]}" "" ""
		return 0
	fi
}

disk_create_luks() {
	if [[ $disk_action_summarize_only == true ]]; then
		add_summary_entry "${arguments[id]}" "${arguments[new_id]}" "luks" "" ""
		return 0
	fi
}

disk_format() {
	if [[ $disk_action_summarize_only == true ]]; then
		add_summary_entry "${arguments[id]}" "__fs__${arguments[id]}" "${arguments[type]}" "(fs)" "$(summary_color_args label)"
		return 0
	fi
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

summarize_disk_actions() {
	elog "[1mCurrent lsblk output[m"
	for_line_in <(lsblk \
		|| die "Error in lsblk") elog

	disk_action_summarize_only=true
	declare -A summary_tree
	declare -A summary_name
	declare -A summary_hint
	declare -A summary_ptr
	declare -A summary_desc
	declare -A summary_depth_continues
	apply_disk_actions
	unset disk_action_summarize_only

	local depth=-1
	elog
	elog "[1mConfigured disk layout[m"
	elog ────────────────────────────────────────────────────────────────────────────────
	elog "$(printf '%-26s %-28s %s' NODE ID OPTIONS)"
	elog ────────────────────────────────────────────────────────────────────────────────
	print_summary_tree __root__
	elog ────────────────────────────────────────────────────────────────────────────────
}

apply_disk_actions() {
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

partition_device_print_config_summary() {
	elog "-------- Partition configuration --------"
	elog "Device: [1;33m$PARTITION_DEVICE[m"
	elog "Existing partition table:"
	for_line_in <(lsblk -n "$PARTITION_DEVICE" \
		|| die "Error in lsblk") elog
	elog "New partition table:"
	elog "[1;33m$PARTITION_DEVICE[m"
	elog "├─efi   size=[1;32m$PARTITION_EFI_SIZE[m"
	if [[ $ENABLE_SWAP == true ]]; then
	elog "├─swap  size=[1;32m$PARTITION_SWAP_SIZE[m"
	fi
	elog "└─linux size=[1;32m[remaining][m"
	if [[ $ENABLE_SWAP != true ]]; then
	elog "swap: [1;31mdisabled[m"
	fi
}

partition_device() {
	[[ $ENABLE_PARTITIONING == true ]] \
		|| return 0

	einfo "Preparing partitioning of device '$PARTITION_DEVICE'"

	[[ -b $PARTITION_DEVICE ]] \
		|| die "Selected device '$PARTITION_DEVICE' is not a block device"

	partition_device_print_config_summary
	ask "Do you really want to apply this partitioning?" \
		|| die "For manual partitioning formatting please set ENABLE_PARTITIONING=false in config.sh"
	countdown "Partitioning in " 5

	einfo "Partitioning device '$PARTITION_DEVICE'"

	# Delete any existing partition table
	sgdisk -Z "$PARTITION_DEVICE" >/dev/null \
		|| die "Could not delete existing partition table"

	# Create efi/boot partition
	sgdisk -n "0:0:+$PARTITION_EFI_SIZE" -t 0:ef00 -c 0:"efi" -u 0:"$PARTITION_UUID_EFI" "$PARTITION_DEVICE" >/dev/null \
		|| die "Could not create efi partition"

	# Create swap partition
	if [[ $ENABLE_SWAP == true ]]; then
		sgdisk -n "0:0:+$PARTITION_SWAP_SIZE" -t 0:8200 -c 0:"swap" -u 0:"$PARTITION_UUID_SWAP" "$PARTITION_DEVICE" >/dev/null \
			|| die "Could not create swap partition"
	fi

	# Create system partition
	sgdisk -n 0:0:0 -t 0:8300 -c 0:"linux" -u 0:"$PARTITION_UUID_LINUX" "$PARTITION_DEVICE" >/dev/null \
		|| die "Could not create linux partition"

	# Print partition table
	einfo "Applied partition table"
	sgdisk -p "$PARTITION_DEVICE" \
		|| die "Could not print partition table"

	# Inform kernel of partition table changes
	partprobe "$PARTITION_DEVICE" \
		|| die "Could not probe partitions"
}

format_partitions() {
	[[ $ENABLE_FORMATTING == true ]] \
		|| return 0

	if [[ $ENABLE_PARTITIONING != true ]]; then
		einfo "Preparing to format the following partitions:"

		blkid -t PARTUUID="$PARTITION_UUID_EFI" \
			|| die "Error while listing efi partition"
		if [[ $ENABLE_SWAP == true ]]; then
			blkid -t PARTUUID="$PARTITION_UUID_SWAP" \
				|| die "Error while listing swap partition"
		fi
		blkid -t PARTUUID="$PARTITION_UUID_LINUX" \
			|| die "Error while listing linux partition"

		ask "Do you really want to format these partitions?" \
			|| die "For manual formatting please set ENABLE_FORMATTING=false in config.sh"
		countdown "Formatting in " 5
	fi

	einfo "Formatting partitions"

	local dev
	dev="$(get_device_by_partuuid "$PARTITION_UUID_EFI")" \
		|| die "Could not resolve partition UUID '$PARTITION_UUID_EFI'"
	einfo "  $dev (efi)"
	mkfs.fat -F 32 -n "efi" "$dev" \
		|| die "Could not format EFI partition"

	if [[ $ENABLE_SWAP == true ]]; then
		dev="$(get_device_by_partuuid "$PARTITION_UUID_SWAP")" \
			|| die "Could not resolve partition UUID '$PARTITION_UUID_SWAP'"
		einfo "  $dev (swap)"
		mkswap -L "swap" "$dev" \
			|| die "Could not create swap"
	fi

	dev="$(get_device_by_partuuid "$PARTITION_UUID_LINUX")" \
		|| die "Could not resolve partition UUID '$PARTITION_UUID_LINUX'"
	einfo "  $dev (linux)"
	mkfs.ext4 -q -L "linux" "$dev" \
		|| die "Could not create ext4 filesystem"
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

mount_by_partuuid() {
	local dev
	local partuuid="$1"
	local mountpoint="$2"

	# Skip if already mounted
	mountpoint -q -- "$mountpoint" \
		&& return

	# Mount device
	einfo "Mounting device partuuid=$partuuid to '$mountpoint'"
	mkdir -p "$mountpoint" \
		|| die "Could not create mountpoint directory '$mountpoint'"
	dev="$(get_device_by_partuuid "$partuuid")" \
		|| die "Could not resolve partition UUID '$PARTITION_UUID_LINUX'"
	mount "$dev" "$mountpoint" \
		|| die "Could not mount device '$dev'"
}

mount_root() {
	mount_by_partuuid "$PARTITION_UUID_LINUX" "$ROOT_MOUNTPOINT"
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
