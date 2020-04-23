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

# An array of disk related actions to perform
DISK_ACTIONS=()
# An associative array from disk id to a resolvable string
declare -Ax DISK_ID_TO_RESOLVABLE
# An associative array from disk id to parent gpt disk id (only for partitions)
declare -Ax DISK_ID_PART_TO_GPT_ID
# An associative array to check for existing ids (maps to uuids)
declare -A DISK_ID_TO_UUID
# An associative set to check for correct usage of size=remaining in gpt tables
declare -A DISK_GPT_HAD_SIZE_REMAINING
# An associative from PTUUID to device
declare -Ax DISK_PTUUID_TO_DEVICE
# An associative from MDADM uuid to device
declare -Ax DISK_MDADM_UUID_TO_DEVICE

only_one_of() {
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

create_new_id() {
	local id="${arguments[$1]}"
	[[ $id == *';'* ]] \
		&& die_trace 2 "Identifier contains invalid character ';'"
	[[ ! -v DISK_ID_TO_UUID[$id] ]] \
		|| die_trace 2 "Identifier '$id' already exists"
	DISK_ID_TO_UUID[$id]="$(load_or_generate_uuid "$(base64 -w 0 <<< "$id")")"
}

verify_existing_id() {
	local id="${arguments[$1]}"
	[[ -v DISK_ID_TO_UUID[$id] ]] \
		|| die_trace 2 "Identifier $1='$id' not found"
}

verify_existing_unique_ids() {
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

verify_option() {
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
# new_id:    Id for the new gpt table
# device:  The operand block device
create_gpt() {
	local known_arguments=('+new_id' '+device|id')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	only_one_of device id
	create_new_id new_id
	[[ -v arguments[id] ]] \
		&& verify_existing_id id

	DISK_ACTIONS+=("action=create_gpt" "$@" ";")
}

# Named arguments:
# new_id:  Id for the new partition
# size:    Size for the new partition, or 'remaining' to allocate the rest
# type:    The parition type, either (bios, efi, swap, raid, luks, linux) (or a 4 digit hex-code for gdisk).
# id:      The operand device id
create_partition() {
	local known_arguments=('+new_id' '+id' '+size' '+type')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	create_new_id new_id
	verify_existing_id id
	verify_option type bios efi swap raid luks linux

	[[ -v "DISK_GPT_HAD_SIZE_REMAINING[${arguments[id]}]" ]] \
		&& die_trace 1 "Cannot add another partition to table (${arguments[id]}) after size=remaining was used"

	[[ ${arguments[size]} == "remaining" ]] \
		&& DISK_GPT_HAD_SIZE_REMAINING[${arguments[id]}]=true

	DISK_ID_PART_TO_GPT_ID[${arguments[new_id]}]="${arguments[id]}"
	DISK_ACTIONS+=("action=create_partition" "$@" ";")
}

# Named arguments:
# new_id:  Id for the new raid
# level:   Raid level
# name:    Raid name (/dev/md/<name>)
# ids:     Comma separated list of all member ids
create_raid() {
	USED_RAID=true

	local known_arguments=('+new_id' '+level' '+name' '+ids')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	create_new_id new_id
	verify_option level 0 1 5 6
	verify_existing_unique_ids ids

	DISK_ACTIONS+=("action=create_raid" "$@" ";")
}

# Named arguments:
# new_id:  Id for the new luks
# id:      The operand device id
create_luks() {
	USED_LUKS=true

	local known_arguments=('+new_id' '+id')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	create_new_id new_id
	verify_existing_id id

	DISK_ACTIONS+=("action=create_luks" "$@" ";")
}

# Named arguments:
# id:     Id of the device / partition created earlier
# type:   One of (bios, efi, swap, ext4)
# label:  The label for the formatted disk
format() {
	local known_arguments=('+id' '+type' '?label')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	verify_existing_id id
	verify_option type bios efi swap ext4

	DISK_ACTIONS+=("action=format" "$@" ";")
}

# Returns a comma separated list of all registered ids matching the given regex.
expand_ids() {
	local regex="$1"
	for id in "${!DISK_ID_TO_UUID[@]}"; do
		[[ $id =~ $regex ]] \
			&& echo -n "$id;"
	done
}

# Example 1: Single disk, 3 partitions (efi, swap, root)
# Parameters:
#   swap=<size>      create a swap partition with given size, or no swap if set to false
#   type=[efi|bios]  defaults to efi. Selects the boot type.
create_default_disk_layout() {
	local known_arguments=('+swap' '?type')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	[[ ${#extra_arguments[@]} -eq 1 ]] \
		|| die_trace 1 "Expected exactly one positional argument (the device)"
	local device="${extra_arguments[0]}"
	local size_swap="${arguments[swap]}"
	local type="${arguments[type]}"
	local efi=true
	case "$type" in
		'bios')   efi=false type=bios ;;
		'efi'|'') efi=true  type=efi  ;;
		*)        die_trace 1 "Invalid argument type=$type, must be one of (bios, efi)" ;;
	esac

	create_gpt new_id=gpt device="$device"
	create_partition new_id="part_$type" id=gpt size=128MiB       type="$type"
	[[ $size_swap != "false" ]] && \
	create_partition new_id=part_swap    id=gpt size="$size_swap" type=swap
	create_partition new_id=part_root    id=gpt size=remaining    type=linux

	format id="part_$type" type="$type" label="$type"
	[[ $size_swap != "false" ]] && \
	format id=part_swap type=swap label=swap
	format id=part_root type=ext4 label=root

	if [[ $type == "efi" ]]; then
		DISK_ID_EFI="part_$type"
	else
		DISK_ID_BIOS="part_$type"
	fi
	DISK_ID_SWAP=part_swap
	DISK_ID_ROOT=part_root
}

# Example 2: Multiple disks, with raid 0 and luks
# - efi:  partition on all disks, but only first disk used
# - swap: raid 0 → fs
# - root: raid 0 → luks → fs
# Parameters:
#   swap=<size>      create a swap partition with given size, or no swap if set to false
#   type=[efi|bios]  defaults to efi. Selects the boot type.
create_raid0_luks_layout() {
	local known_arguments=('+swap' '?type')
	local extra_arguments=()
	declare -A arguments; parse_arguments "$@"

	[[ ${#extra_arguments[@]} -gt 0 ]] \
		|| die_trace 1 "Expected at least one positional argument (the devices)"
	local size_swap="${arguments[swap]}"
	local type="${arguments[type]}"
	local efi=true
	case "$type" in
		'bios')   efi=false type=bios ;;
		'efi'|'') efi=true  type=efi  ;;
		*)        die_trace 1 "Invalid argument type=$type, must be one of (bios, efi)" ;;
	esac

	for i in "${!extra_arguments[@]}"; do
		create_gpt new_id="gpt_dev${i}" device="${extra_arguments[$i]}"
		create_partition new_id="part_${type}_dev${i}" id="gpt_dev${i}" size=128MiB       type="$type"
		[[ $size_swap != "false" ]] && \
		create_partition new_id="part_swap_dev${i}"    id="gpt_dev${i}" size="$size_swap" type=raid
		create_partition new_id="part_root_dev${i}"    id="gpt_dev${i}" size=remaining    type=raid
	done

	[[ $size_swap != "false" ]] && \
	create_raid new_id=part_raid_swap name="swap" level=0 ids="$(expand_ids '^part_swap_dev[[:digit:]]$')"
	create_raid new_id=part_raid_root name="root" level=0 ids="$(expand_ids '^part_root_dev[[:digit:]]$')"
	create_luks new_id=part_luks_root id=part_raid_root

	format id="part_${type}_dev0" type="$type" label="$type"
	[[ $size_swap != "false" ]] && \
	format id=part_raid_swap type=swap label=swap
	format id=part_luks_root type=ext4 label=root

	if [[ $type == "efi" ]]; then
		DISK_ID_EFI="part_${type}_dev0"
	else
		DISK_ID_BIOS="part_${type}_dev0"
	fi
	[[ $size_swap != "false" ]] && \
	DISK_ID_SWAP=part_raid_swap
	DISK_ID_ROOT=part_luks_root
}
