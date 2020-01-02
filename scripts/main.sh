################################################
# Initialize script environment

# Find the directory this script is stored in. (from: http://stackoverflow.com/questions/59895)
get_source_dir() {
	local source="${BASH_SOURCE[0]}"
	while [[ -h "${source}" ]]
	do
		local tmp="$(cd -P "$(dirname "${source}")" && pwd)"
		source="$(readlink "${source}")"
		[[ "${source}" != /* ]] && source="${tmp}/${source}"
	done

	echo -n "$(realpath "$(dirname "${source}")")"
}

export GENTOO_BOOTSTRAP_DIR_ORIGINAL="$(dirname "$(get_source_dir)")"
export GENTOO_BOOTSTRAP_DIR="$GENTOO_BOOTSTRAP_DIR_ORIGINAL"
export GENTOO_BOOTSTRAP_SCRIPT_ACTIVE=true
export GENTOO_BOOTSTRAP_SCRIPT_PID=$$
LOGDATE="$(date +%Y%m%d-%H%M%S)"

umask 0077

source "$GENTOO_BOOTSTRAP_DIR/scripts/utils.sh"
source "$GENTOO_BOOTSTRAP_DIR/scripts/config.sh"
source "$GENTOO_BOOTSTRAP_DIR/scripts/functions.sh"

mkdir -p "$TMP_DIR"
[[ $EUID == 0 ]] \
	|| die "Must be root"


################################################
# Functions

install_stage3() {
	[[ $# == 0 ]] || die "Too many arguments"

	prepare_installation_environment
	partition_device
	format_partitions
	download_stage3
	extract_stage3
}

main_install_gentoo_in_chroot() {
	[[ $# == 0 ]] || die "Too many arguments"

	# Lock the root password, making the account unaccessible for the
	# period of installation, except by chrooting
	einfo "Locking root account"
	passwd -l root

	einfo "Selecting portage mirrors"
	# TODO mirrorselect
	# TODO gpg portage sync
	# TODO additional binary repos
	# TODO safe dns settings (claranet)

	einfo "Mounting efi"
	mount_by_partuuid "$PARTITION_UUID_EFI" "/boot/efi"

	einfo "Syncing portage tree"
	emerge-webrsync

	einfo "Selecting portage profile '$'"

	#get kernel

	#compile minimal kernel to boot system

	#reboot?

	#mount boot partition

	#create kernel

	#create_ansible_user
	#generate_fresh keys to become mgmnt ansible user
	#install_ansible

	einfo "Gentoo installation complete"
	einfo "Dropping into chrooted shell"
	su
}

main_install() {
	[[ $# == 0 ]] || die "Too many arguments"

	install_stage3 \
		|| die "Failed to install stage3"

	gentoo_chroot "$GENTOO_BOOTSTRAP_DIR/scripts/main.sh" install_gentoo_in_chroot \
		|| die "Failed to install gentoo in chroot"
}

main_chroot() {
	gentoo_chroot "$@" \
		|| die "Failed to execute script in chroot"
}

main_umount() {
	gentoo_umount
}


################################################
# Main dispatch

einfo "Verbose script output will be logged to: '$GENTOO_BOOTSTRAP_DIR/log-$LOGDATE.out'"
# Save old stdout
exec 3>&1
# Restore old filedescriptor on certain signals
trap 'exec 1>&3' 0 1 2 3 RETURN
# Replace stdout with logfole
exec 1>"$GENTOO_BOOTSTRAP_DIR/log-$LOGDATE.out"
# Link to latest log file
ln -sf "$GENTOO_BOOTSTRAP_DIR/log-$LOGDATE.out" "$GENTOO_BOOTSTRAP_DIR/log.out"

SCRIPT_ALIAS="$(basename "$0")"
if [[ "$SCRIPT_ALIAS" == "main.sh" ]]; then
	SCRIPT_ALIAS="$1"
	shift
fi

case "$SCRIPT_ALIAS" in
	"chroot") main_chroot "$@" ;;
	"install") main_install "$@" ;;
	"install_gentoo_in_chroot") main_install_gentoo_in_chroot "$@" ;;
	"umount") main_umount "$@" ;;
	*) die "Invalid alias '$SCRIPT_ALIAS' was used to execute this script" ;;
esac
