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

export GENTOO_BOOTSTRAP_DIR="$(dirname "$(get_source_dir)")"
export GENTOO_BOOTSTRAP_SCRIPT_ACTIVE=true
export GENTOO_BOOTSTRAP_SCRIPT_PID=$$

umask 0077

source "$GENTOO_BOOTSTRAP_DIR/scripts/utils.sh"
source "$GENTOO_BOOTSTRAP_DIR/scripts/config.sh"
source "$GENTOO_BOOTSTRAP_DIR/scripts/functions.sh"

mkdir -p "$TMP_DIR"
[[ $EUID == 0 ]] \
	|| die "Must be root"


################################################
# Functions

main_install_stage3() {
	[[ $# == 0 ]] || die "Too many arguments"

	prepare_installation_environment
	partition_device
	format_partitions
	download_stage3
	extract_stage3
}

main_chroot() {
	gentoo_chroot "$@"
}

main_install_gentoo() {
	[[ $# == 0 ]] || die "Too many arguments"

	#remove root password
	passwd -d root

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

main_install_full() {
	[[ $# == 0 ]] || die "Too many arguments"

	"$GENTOO_BOOTSTRAP_DIR/install_stage3" \
		|| die "Failed to install stage3"
	"$GENTOO_BOOTSTRAP_DIR/chroot" "$GENTOO_BOOTSTRAP_DIR/install_gentoo" \
		|| die "Failed to prepare gentoo in chroot"
}


################################################
# Main dispatch

SCRIPT_ALIAS="$(basename "$0")"
case "$SCRIPT_ALIAS" in
	"chroot")          main_chroot "$@" ;;
	"install")         main_install_full "$@" ;;
	"install_gentoo")  main_install_gentoo "$@" ;;
	"install_stage3")  main_install_stage3 "$@" ;;
	*) die "Invalid alias '$SCRIPT_ALIAS' was used to execute this script" ;;
esac
