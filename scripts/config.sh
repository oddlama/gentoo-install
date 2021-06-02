# shellcheck source=./scripts/protection.sh
source "$GENTOO_INSTALL_REPO_DIR/scripts/protection.sh" || exit 1


################################################
# Script internal configuration

# The temporary directory for this script,
# must reside in /tmp to allow the chrooted system to access the files
TMP_DIR="/tmp/gentoo-install"
# Mountpoint for the new system
ROOT_MOUNTPOINT="$TMP_DIR/root"
# Mountpoint for the script files for access from chroot
GENTOO_INSTALL_REPO_BIND="$TMP_DIR/bind"
# Mountpoint for the script files for access from chroot
UUID_STORAGE_DIR="$TMP_DIR/uuids"
# Backup dir for luks headers
LUKS_HEADER_BACKUP_DIR="$TMP_DIR/luks-headers"

# Flag to track usage of raid (needed to check for mdadm existence)
USED_RAID=false
# Flag to track usage of luks (needed to check for cryptsetup existence)
USED_LUKS=false
# Flag to track usage of zfs
USED_ZFS=false
# Flag to track usage of btrfs
USED_BTRFS=false
# Flag to track usage of encryption
USED_ENCRYPTION=false

# An array of disk related actions to perform
DISK_ACTIONS=()
# An array of dracut parameters needed to boot the selected configuration
DISK_DRACUT_CMDLINE=()
# An associative array from disk id to a resolvable string
declare -gA DISK_ID_TO_RESOLVABLE
# An associative array from disk id to parent gpt disk id (only for partitions)
declare -gA DISK_ID_PART_TO_GPT_ID
# An associative array to check for existing ids (maps to uuids)
declare -gA DISK_ID_TO_UUID
# An associative set to check for correct usage of size=remaining in gpt tables
declare -gA DISK_GPT_HAD_SIZE_REMAINING

function only_one_of() {
	local previous=""
	local a
	for a in "$@"; do
		if [[ -v arguments[$a] ]]; then
			if [[ -z $previous ]]; then
				previous="$a"
			else
				die_trace 2 "Only one of the arguments ($*) can be given"
			fi
		fi
	done
}

function create_new_id() {
	local id="${arguments[$1]}"
	[[ $id == *';'* ]] \
		&& die_trace 2 "Identifier contains invalid character ';'"
	[[ ! -v DISK_ID_TO_UUID[$id] ]] \
		|| die_trace 2 "Identifier '$id' already exists"
	DISK_ID_TO_UUID[$id]="$(load_or_generate_uuid "$(base64 -w 0 <<< "$id")")"
}

function verify_existing_id() {
	local id="${arguments[$1]}"
	[[ -v DISK_ID_TO_UUID[$id] ]] \
		|| die_trace 2 "Identifier $1='$id' not found"
}

function verify_existing_unique_ids() {
	local arg="$1"
	local ids="${arguments[$arg]}"

	count_orig="$(tr ';' '\n' <<< "$ids" | grep -c '\S')"
	count_uniq="$(tr ';' '\n' <<< "$ids" | grep '\S' | sort -u | wc -l)"
	[[ $count_orig -gt 0 ]] \
		|| die_trace 2 "$arg=... must contain at least one entry"
	[[ $count_orig -eq $count_uniq ]] \
		|| die_trace 2 "$arg=... contains duplicate identifiers"

	local id
	# Splitting is intentional here
	# shellcheck disable=SC2086
	for id in ${ids//';'/ }; do
		[[ -v DISK_ID_TO_UUID[$id] ]] \
			|| die_trace 2 "$arg=... contains unknown identifier '$id'"
	done
}

function verify_option() {
	local opt="$1"
	shift

	local arg="${arguments[$opt]}"
	local i
	for i in "$@"; do
		[[ $i == "$arg" ]] \
			&& return 0
	done

	die_trace 2 "Invalid option $opt='$arg', must be one of ($*)"
}

# Named arguments:
# new_id:     Id for the new gpt table
# device|id:  The operand block device or previously allocated id
function create_gpt() {
	local known_arguments=('+new_id' '+device|id')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	only_one_of device id
	create_new_id new_id
	[[ -v arguments[id] ]] \
		&& verify_existing_id id

	local new_id="${arguments[new_id]}"
	create_resolve_entry "$new_id" ptuuid "${DISK_ID_TO_UUID[$new_id]}"
	DISK_ACTIONS+=("action=create_gpt" "$@" ";")
}

# Named arguments:
# new_id:  Id for the new partition
# size:    Size for the new partition, or 'remaining' to allocate the rest
# type:    The parition type, either (bios, efi, swap, raid, luks, linux) (or a 4 digit hex-code for gdisk).
# id:      The operand device id
function create_partition() {
	local known_arguments=('+new_id' '+id' '+size' '+type')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	create_new_id new_id
	verify_existing_id id
	verify_option type bios efi swap raid luks linux

	[[ -v "DISK_GPT_HAD_SIZE_REMAINING[${arguments[id]}]" ]] \
		&& die_trace 1 "Cannot add another partition to table (${arguments[id]}) after size=remaining was used"

	# shellcheck disable=SC2034
	[[ ${arguments[size]} == "remaining" ]] \
		&& DISK_GPT_HAD_SIZE_REMAINING[${arguments[id]}]=true

	local new_id="${arguments[new_id]}"
	DISK_ID_PART_TO_GPT_ID[$new_id]="${arguments[id]}"
	create_resolve_entry "$new_id" partuuid "${DISK_ID_TO_UUID[$new_id]}"
	DISK_ACTIONS+=("action=create_partition" "$@" ";")
}

# Named arguments:
# new_id:  Id for the new raid
# level:   Raid level
# name:    Raid name (/dev/md/<name>)
# ids:     Comma separated list of all member ids
function create_raid() {
	USED_RAID=true

	local known_arguments=('+new_id' '+level' '+name' '+ids')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	create_new_id new_id
	verify_option level 0 1 5 6
	verify_existing_unique_ids ids

	local new_id="${arguments[new_id]}"
	local uuid="${DISK_ID_TO_UUID[$new_id]}"
	create_resolve_entry "$new_id" mdadm "$uuid"
	DISK_DRACUT_CMDLINE+=("rd.md.uuid=$(uuid_to_mduuid "$uuid")")
	DISK_ACTIONS+=("action=create_raid" "$@" ";")
}

# Named arguments:
# new_id:  Id for the new luks
# id:      The operand device id
function create_luks() {
	USED_LUKS=true
	USED_ENCRYPTION=true

	local known_arguments=('+new_id' '+name' '+device|id')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	only_one_of device id
	create_new_id new_id
	[[ -v arguments[id] ]] \
		&& verify_existing_id id

	local new_id="${arguments[new_id]}"
	local name="${arguments[name]}"
	local uuid="${DISK_ID_TO_UUID[$new_id]}"
	create_resolve_entry "$new_id" luks "$name"
	DISK_DRACUT_CMDLINE+=("rd.luks.uuid=$uuid")
	DISK_ACTIONS+=("action=create_luks" "$@" ";")
}

# Named arguments:
# new_id:  Id for the new luks
# device:  The device
function create_dummy() {
	local known_arguments=('+new_id' '+device')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	create_new_id new_id

	local new_id="${arguments[new_id]}"
	local device="${arguments[device]}"
	local uuid="${DISK_ID_TO_UUID[$new_id]}"
	create_resolve_entry_device "$new_id" "$device"
	DISK_ACTIONS+=("action=create_dummy" "$@" ";")
}

# Named arguments:
# id:     Id of the device / partition created earlier
# type:   One of (bios, efi, swap, ext4)
# label:  The label for the formatted disk
function format() {
	local known_arguments=('+id' '+type' '?label')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	verify_existing_id id
	verify_option type bios efi swap ext4 btrfs

	local type="${arguments[type]}"
	if [[ "$type" == "btrfs" ]]; then
		USED_BTRFS=true
	fi

	DISK_ACTIONS+=("action=format" "$@" ";")
}

# Named arguments:
# ids:       List of ids for devices / partitions created earlier. Must contain at least 1 element.
# pool_type: The zfs pool type
# encrypt:   Whether or not to encrypt the pool
function format_zfs() {
	USED_ZFS=true

	local known_arguments=('+ids' '?pool_type' '?encrypt' '?compress')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	verify_existing_unique_ids ids

	USED_ENCRYPTION=${arguments[encrypt]:-false}
	DISK_ACTIONS+=("action=format_zfs" "$@" ";")
}

# Named arguments:
# ids:     List of ids for devices / partitions created earlier. Must contain at least 1 element.
# label:   The label for the formatted disk
function format_btrfs() {
	USED_BTRFS=true

	local known_arguments=('+ids' '?raid_type' '?label')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	verify_existing_unique_ids ids

	DISK_ACTIONS+=("action=format_btrfs" "$@" ";")
}

# Returns a comma separated list of all registered ids matching the given regex.
function expand_ids() {
	local regex="$1"
	for id in "${!DISK_ID_TO_UUID[@]}"; do
		[[ $id =~ $regex ]] \
			&& echo -n "$id;"
	done
}

# Single disk, 3 partitions (efi, swap, root)
# Parameters:
#   swap=<size>           Create a swap partition with given size, or no swap at all if set to false
#   type=[efi|bios]       Selects the boot type. Defaults to efi if not given.
#   luks=[true|false]     Encrypt root partition. Defaults to false if not given.
#   root_fs=[ext4|btrfs]  Root filesystem
function create_classic_single_disk_layout() {
	local known_arguments=('+swap' '?type' '?luks' '?root_fs')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	[[ ${#extra_arguments[@]} -eq 1 ]] \
		|| die_trace 1 "Expected exactly one positional argument (the device)"
	local device="${extra_arguments[0]}"
	local size_swap="${arguments[swap]}"
	local type="${arguments[type]:-efi}"
	local use_luks="${arguments[luks]:-false}"
	local root_fs="${arguments[root_fs]:-ext4}"

	create_gpt new_id=gpt device="$device"
	create_partition new_id="part_$type" id=gpt size=256MiB       type="$type"
	[[ $size_swap != "false" ]] \
		&& create_partition new_id=part_swap    id=gpt size="$size_swap" type=swap
	create_partition new_id=part_root    id=gpt size=remaining    type=linux

	local root_id="part_root"
	if [[ "$use_luks" == "true" ]]; then
		create_luks new_id=part_luks_root name="root" id=part_root
		root_id="part_luks_root"
	fi

	format id="part_$type" type="$type" label="$type"
	[[ $size_swap != "false" ]] \
		&& format id=part_swap type=swap label=swap
	format id="$root_id" type="$root_fs" label=root

	if [[ $type == "efi" ]]; then
		DISK_ID_EFI="part_$type"
	else
		DISK_ID_BIOS="part_$type"
	fi
	[[ $size_swap != "false" ]] \
		&& DISK_ID_SWAP=part_swap
	DISK_ID_ROOT="$root_id"

	if [[ $root_fs == "btrfs" ]]; then
		DISK_ID_ROOT_TYPE="btrfs"
		DISK_ID_ROOT_MOUNT_OPTS="defaults,noatime,compress-force=zstd,subvol=/root"
	elif [[ $root_fs == "ext4" ]]; then
		DISK_ID_ROOT_TYPE="ext4"
		DISK_ID_ROOT_MOUNT_OPTS="defaults,noatime,errors=remount-ro,discard"
	else
		die "Unsupported root filesystem type"
	fi
}

function create_single_disk_layout() {
	die "'create_single_disk_layout' is deprecated, please use 'create_classic_single_disk_layout' instead. It is fully option-compatible to the old version."
}

# Multiple disks, up to 3 partitions on first disk (efi, optional swap, root with zfs).
# Additional devices will be added to the zfs pool.
# Parameters:
#   swap=<size>                Create a swap partition with given size, or no swap at all if set to false
#   type=[efi|bios]            Selects the boot type. Defaults to efi if not given.
#   encrypt=[true|false]       Encrypt zfs pool. Defaults to false if not given.
#   pool_type=[stripe|mirror]  Select raid type. Defaults to stripe.
function create_zfs_centric_layout() {
	local known_arguments=('+swap' '?type' '?pool_type' '?encrypt' '?compress')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	[[ ${#extra_arguments[@]} -gt 0 ]] \
		|| die_trace 1 "Expected at least one positional argument (the devices)"
	local device="${extra_arguments[0]}"
	local size_swap="${arguments[swap]}"
	local pool_type="${arguments[pool_type]:-stripe}"
	local type="${arguments[type]:-efi}"
	local encrypt="${arguments[encrypt]:-false}"

	# Create layout on first disk
	create_gpt new_id="gpt_dev0" device="${extra_arguments[0]}"
	create_partition new_id="part_${type}_dev0" id="gpt_dev0" size=256MiB       type="$type"
	[[ $size_swap != "false" ]] \
		&& create_partition new_id="part_swap_dev0"    id="gpt_dev0" size="$size_swap" type=swap
	create_partition new_id="part_root_dev0"    id="gpt_dev0" size=remaining    type=linux

	local root_id="part_root_dev0"
	local root_ids="part_root_dev0;"
	local dev_id
	for i in "${!extra_arguments[@]}"; do
		[[ $i != 0 ]] || continue
		dev_id="root_dev$i"
		create_dummy new_id="$dev_id" device="${extra_arguments[$i]}"
		root_ids="${root_ids}$dev_id;"
	done

	format id="part_${type}_dev0" type="$type" label="$type"
	[[ $size_swap != "false" ]] \
		&& format id="part_swap_dev0" type=swap label=swap
	format_zfs ids="$root_ids" encrypt="$encrypt" pool_type="$pool_type"

	if [[ $type == "efi" ]]; then
		DISK_ID_EFI="part_${type}_dev0"
	else
		DISK_ID_BIOS="part_${type}_dev0"
	fi
	[[ $size_swap != "false" ]] \
		&& DISK_ID_SWAP=part_swap_dev0
	DISK_ID_ROOT="$root_id"
	DISK_ID_ROOT_TYPE="zfs"
}

# Multiple disks, with raid 0 and luks
# - efi:  partition on all disks, but only first disk used
# - swap: raid 0 → fs
# - root: raid 0 → luks → fs
# Parameters:
#   swap=<size>           Create a swap partition with given size for each disk, or no swap at all if set to false
#   type=[efi|bios]       Selects the boot type. Defaults to efi if not given.
#   root_fs=[ext4|btrfs]  Root filesystem
function create_raid0_luks_layout() {
	local known_arguments=('+swap' '?type' '?root_fs')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	[[ ${#extra_arguments[@]} -gt 0 ]] \
		|| die_trace 1 "Expected at least one positional argument (the devices)"
	local size_swap="${arguments[swap]}"
	local type="${arguments[type]:-efi}"
	local root_fs="${arguments[root_fs]:-ext4}"

	for i in "${!extra_arguments[@]}"; do
		create_gpt new_id="gpt_dev${i}" device="${extra_arguments[$i]}"
		create_partition new_id="part_${type}_dev${i}" id="gpt_dev${i}" size=256MiB       type="$type"
		[[ $size_swap != "false" ]] \
			&& create_partition new_id="part_swap_dev${i}"    id="gpt_dev${i}" size="$size_swap" type=raid
		create_partition new_id="part_root_dev${i}"    id="gpt_dev${i}" size=remaining    type=raid
	done

	[[ $size_swap != "false" ]] \
		&& create_raid new_id=part_raid_swap name="swap" level=0 ids="$(expand_ids '^part_swap_dev[[:digit:]]$')"
	create_raid new_id=part_raid_root name="root" level=0 ids="$(expand_ids '^part_root_dev[[:digit:]]$')"
	create_luks new_id=part_luks_root name="root" id=part_raid_root

	format id="part_${type}_dev0" type="$type" label="$type"
	[[ $size_swap != "false" ]] \
		&& format id=part_raid_swap type=swap label=swap
	format id=part_luks_root type="$root_fs" label=root

	if [[ $type == "efi" ]]; then
		DISK_ID_EFI="part_${type}_dev0"
	else
		DISK_ID_BIOS="part_${type}_dev0"
	fi
	[[ $size_swap != "false" ]] \
		&& DISK_ID_SWAP=part_raid_swap
	DISK_ID_ROOT=part_luks_root

	if [[ $root_fs == "btrfs" ]]; then
		DISK_ID_ROOT_TYPE="btrfs"
		DISK_ID_ROOT_MOUNT_OPTS="defaults,noatime,compress=zstd,subvol=/root"
	elif [[ $root_fs == "btrfs" ]]; then
		DISK_ID_ROOT_TYPE="ext4"
		DISK_ID_ROOT_MOUNT_OPTS="defaults,noatime,errors=remount-ro,discard"
	else
		die "Unsupported root filesystem type"
	fi
}

# Multiple disks, up to 3 partitions on first disk (efi, optional swap, root with btrfs).
# Additional devices will be first encrypted and then put directly into btrfs array.
# Parameters:
#   swap=<size>                Create a swap partition with given size, or no swap at all if set to false
#   type=[efi|bios]            Selects the boot type. Defaults to efi if not given.
#   luks=[true|false]          Encrypt root partition and btrfs devices. Defaults to false if not given.
#   raid_type=[raid0|raid1]    Select raid type. Defaults to raid0.
function create_btrfs_centric_layout() {
	local known_arguments=('+swap' '?type' '?raid_type' '?luks')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	[[ ${#extra_arguments[@]} -gt 0 ]] \
		|| die_trace 1 "Expected at least one positional argument (the devices)"
	local device="${extra_arguments[0]}"
	local size_swap="${arguments[swap]}"
	local raid_type="${arguments[raid_type]:-raid0}"
	local type="${arguments[type]:-efi}"
	local use_luks="${arguments[luks]:-false}"

	# Create layout on first disk
	create_gpt new_id="gpt_dev0" device="${extra_arguments[0]}"
	create_partition new_id="part_${type}_dev0" id="gpt_dev0" size=256MiB       type="$type"
	[[ $size_swap != "false" ]] \
		&& create_partition new_id="part_swap_dev0"    id="gpt_dev0" size="$size_swap" type=swap
	create_partition new_id="part_root_dev0"    id="gpt_dev0" size=remaining    type=linux

	local root_id
	local root_ids=""
	if [[ "$use_luks" == "true" ]]; then
		create_luks new_id=luks_dev0 name="luks_root_0" id=part_root_dev0
		root_id="luks_dev0"
		root_ids="${root_ids}luks_dev0;"
		for i in "${!extra_arguments[@]}"; do
			[[ $i != 0 ]] || continue
			create_luks new_id="luks_dev$i" name="luks_root_$i" device="${extra_arguments[$i]}"
			root_ids="${root_ids}luks_dev$i;"
		done
	else
		local dev_id=""
		root_id="part_root_dev0"
		root_ids="${root_ids}part_root_dev0;"
		for i in "${!extra_arguments[@]}"; do
			[[ $i != 0 ]] || continue
			dev_id="root_dev$i"
			create_dummy new_id="$dev_id" device="${extra_arguments[$i]}"
			root_ids="${root_ids}$dev_id;"
		done
	fi

	format id="part_${type}_dev0" type="$type" label="$type"
	[[ $size_swap != "false" ]] \
		&& format id="part_swap_dev0" type=swap label=swap
	format_btrfs ids="$root_ids" label=root raid_type="$raid_type"

	if [[ $type == "efi" ]]; then
		DISK_ID_EFI="part_${type}_dev0"
	else
		DISK_ID_BIOS="part_${type}_dev0"
	fi
	[[ $size_swap != "false" ]] \
		&& DISK_ID_SWAP=part_swap_dev0
	DISK_ID_ROOT="$root_id"
	DISK_ID_ROOT_TYPE="btrfs"
	DISK_ID_ROOT_MOUNT_OPTS="defaults,noatime,compress=zstd,subvol=/root"
}

function create_btrfs_raid_layout() {
	die "'create_btrfs_raid_layout' is deprecated, please use 'create_btrfs_centric_layout' instead. It is fully option-compatible to the old version."
}
