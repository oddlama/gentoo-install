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

# The desired efi partition mountpoint for the actual system
EFI_MOUNTPOINT="/boot/efi"

# Flag to track usage of raid (needed to check for mdadm existence)
USED_RAID=false
# Flag to track usage of luks (needed to check for cryptsetup existence)
USED_LUKS=false

# An array of disk related actions to perform
DISK_ACTIONS=()
# An associative set to check for existing ids
declare -A DISK_KNOWN_IDS

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
	[[ ! -v DISK_KNOWN_IDS[$id] ]] \
		|| die_trace 2 "Identifier '$id' already exists"
	DISK_KNOWN_IDS[$id]=true
}

verify_existing_id() {
	local id="${arguments[$1]}"
	[[ -v DISK_KNOWN_IDS[$id] ]] \
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
		[[ -v DISK_KNOWN_IDS[$id] ]] \
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

#create_luks() {
#	gpg --decrypt /tmp/efiboot/luks-key.gpg | \
#		cryptsetup --cipher serpent-xts-plain64 --key-size 512 --hash whirlpool --key-file - luksFormat /dev/sdZn
#	local dev
#	cryptsetup luksFormat \
#		--type=luks2 \
#		--cipher aes-xts-plain64 \
#		--key-size 512 \
#		--pbkdf argon2id \
#		--iter-time=4000 "$dev"
#}

# Named arguments:
# new_id:    Id for the new gpt table
# device:  The operand block device
create_gpt() {
	local known_arguments=('+new_id' '+device|id')
	unset arguments; declare -A arguments; parse_arguments "$@"

	only_one_of device id
	create_new_id new_id
	[[ -v arguments[id] ]] \
		&& verify_existing_id id

	DISK_ACTIONS+=("action=create_gpt" "$@" ";")
}

# Named arguments:
# new_id:  Id for the new partition
# size:    Size for the new partition, or auto to allocate the rest
# type:    The parition type, either (boot, efi, swap, raid, luks, linux) (or a 4 digit hex-code for gdisk).
# id:      The operand device id
create_partition() {
	local known_arguments=('+new_id' '+id' '+size' '+type')
	unset arguments; declare -A arguments; parse_arguments "$@"

	create_new_id new_id
	verify_existing_id id
	verify_option type boot efi swap raid luks linux

	DISK_ACTIONS+=("action=create_partition" "$@" ";")
}

# Named arguments:
# new_id:  Id for the new raid
# level:   Raid level
# ids:     Comma separated list of all member ids
create_raid() {
	USED_RAID=true

	local known_arguments=('+new_id' '+level' '+ids')
	unset arguments; declare -A arguments; parse_arguments "$@"

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
	unset arguments; declare -A arguments; parse_arguments "$@"

	create_new_id new_id
	verify_existing_id id

	DISK_ACTIONS+=("action=create_luks" "$@" ";")
}

# Named arguments:
# id:     Id of the device / partition created earlier
# type:   One of (boot, efi, swap, ext4)
# label:  The label for the formatted disk
format() {
	local known_arguments=('+id' '+type' '?label')
	unset arguments; declare -A arguments; parse_arguments "$@"

	verify_existing_id id
	verify_option type boot efi swap ext4

	DISK_ACTIONS+=("action=format" "$@" ";")
}

# Returns a comma separated list of all registered ids matching the given regex.
expand_ids() {
	local regex="$1"
	for id in "${!DISK_KNOWN_IDS[@]}"; do
		[[ $id =~ $regex ]] \
			&& echo -n "$id;"
	done
}
