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

umask 0077

source "$GENTOO_BOOTSTRAP_DIR/scripts/utils.sh"
source "$GENTOO_BOOTSTRAP_DIR/scripts/config.sh"
source "$GENTOO_BOOTSTRAP_DIR/scripts/functions.sh"

[[ $I_HAVE_READ_AND_EDITED_THE_CONFIG_PROPERLY == true ]] \
	|| die "You have not properly read the config. Set I_HAVE_READ_AND_EDITED_THE_CONFIG_PROPERLY=true to continue."

mkdir_or_die 0755 "$TMP_DIR"
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
	passwd -l root \
		|| die "Could not change root password"

	# Mount efi partition
	einfo "Mounting efi"
	mount_by_partuuid "$PARTITION_UUID_EFI" "/boot/efi"

	# Sync portage
	einfo "Syncing portage tree"
	try emerge-webrsync

	# Set timezone
	einfo "Selecting timezone"
	echo "$TIMEZONE" > /etc/timezone \
		|| die "Could not write /etc/timezone"
	try emerge -v --config sys-libs/timezone-data

	# Set locale
	einfo "Selecting locale"
	echo "$LOCALES" > /etc/locale.gen \
		|| die "Could not write /etc/locale.gen"
	locale-gen \
		|| die "Could not generate locales"
	try eselect locale set "$LOCALE"

	# Set keymap
	einfo "Selecting keymap"
	sed -i "/keymap=/c\\$KEYMAP" /etc/conf.d/keymaps \
		|| die "Could not sed replace in /etc/conf.d/keymaps"

	# Update environment
	env_update

	# Prepare /etc/portage for autounmask
	mkdir_or_die 0755 "/etc/portage/package.use"
	touch_or_die 0644 "/etc/portage/package.use/zz-autounmask"
	mkdir_or_die 0755 "/etc/portage/package.keywords"
	touch_or_die 0644 "/etc/portage/package.keywords/zz-autounmask"

	einfo "Temporarily installing mirrorselect"
	try emerge --verbose --oneshot app-portage/mirrorselect

	einfo "Selecting fastest portage mirrors"
	try mirrorselect -s 4 -b 10 -D

	# Install git (for git portage overlays)
	einfo "Installing git"
	try emerge --verbose dev-vcs/git

	# Install vanilla kernel and efibootmgr, to be able to boot the system.
	einfo "Installing vanilla kernel"
	try emerge --verbose sys-kernel/vanilla-kernel sys-boot/efibootmgr

	# Copy kernel to EFI
	local kernel_version
	kernel_version="$(find "/boot" -name "vmlinuz-*" | sort -V | tail -1)" \
		|| die "Could not list newest kernel file"
	kernel_version="${kernel_version#vmlinuz-}" \
		|| die "Could not find kernel version"

	mkdir_or_die 0755 "/boot/efi/EFI"
	cp "/boot/initramfs-$kernel_version"* "/boot/efi/EFI/initramfs.img" \
		|| die "Could not copy initramfs to EFI partition"
	cp "/boot/vmlinuz-$kernel_version"* "/boot/efi/EFI/vmlinuz.efi" \
		|| die "Could not copy kernel to EFI partition"

	# Create boot entry
	einfo "Creating efi boot entry"
	local linuxdev
	linuxdev="$(get_device_by_partuuid "$PARTITION_UUID_LINUX")" \
		|| die "Could not resolve partition UUID '$PARTITION_UUID_LINUX'"
	local efidev
	efidev="$(get_device_by_partuuid "$PARTITION_UUID_EFI")" \
		|| die "Could not resolve partition UUID '$PARTITION_UUID_EFI'"
	local efipartnum="${efidev: -1}"
	efibootmgr --verbose --create --disk "$PARTITION_DEVICE" --part "$efipartnum" --label "gentoo" --loader '\EFI\vmlinuz.efi' --unicode "root=$linuxdev initrd=initramfs.img" \
		|| die "Could not add efi boot entry"

	# Install additional packages, if any.
	if [[ -n "$ADDITIONAL_PACKAGES" ]]; then
		einfo "Installing additional packages"
		try emerge --verbose --autounmask-continue=y -- $ADDITIONAL_PACKAGES
	fi

	# Generate a valid fstab file
	einfo "Generating fstab"
	install -m0644 -o root -g root "$GENTOO_BOOTSTRAP_DIR/configs/fstab" /etc/fstab \
		|| die "Could not overwrite /etc/fstab"
	echo "PARTUUID=$PARTITION_UUID_LINUX    /            ext4    defaults,noatime,errors=remount-ro,discard                            0 1" >> /etc/fstab \
		|| die "Could not append entry to fstab"
	echo "PARTUUID=$PARTITION_UUID_EFI    /boot/efi    vfat    defaults,noatime,fmask=0022,dmask=0022,noexec,nodev,nosuid,discard    0 2" >> /etc/fstab \
		|| die "Could not append entry to fstab"
	if [[ "$ENABLE_SWAP" == true ]]; then
		echo "PARTUUID=$PARTITION_UUID_SWAP    none         swap    defaults,discard                                                      0 0" >> /etc/fstab \
			|| die "Could not append entry to fstab"
	fi

	# Install and enable sshd
	einfo "Installing sshd"
	install -m0600 -o root -g root "$GENTOO_BOOTSTRAP_DIR/configs/sshd_config" /etc/ssh/sshd_config \
		|| die "Could not install /etc/ssh/sshd_config"
	rc-update add sshd default \
		|| die "Could not add sshd to default services"

	# Install and enable dhcpcd
	einfo "Installing dhcpcd"
	try emerge --verbose net-misc/dhcpcd sys-apps/iproute2
	rc-update add dhcpcd default \
		|| die "Could not add dhcpcd to default services"

	# Install ansible
	if [[ "$INSTALL_ANSIBLE" == true ]]; then
		einfo "Installing ansible"
		try emerge --verbose app-admin/ansible

		einfo "Creating ansible user"
		useradd -r -d "$ANSIBLE_HOME" -s /bin/bash ansible
		mkdir_or_die 0700 "$ANSIBLE_HOME"
		mkdir_or_die 0700 "$ANSIBLE_HOME/.ssh"

		if [[ -n "$ANSIBLE_SSH_PUBKEY" ]]; then
			einfo "Adding ssh key for ansible"
			touch_or_die 0600 "$ANSIBLE_HOME/.ssh/authorized_keys"
			echo "$ANSIBLE_SSH_PUBKEY" >> "$ANSIBLE_HOME/.ssh/authorized_keys" \
				|| die "Could not add ssh key to authorized_keys"
		fi

		einfo "Allowing ansible for ssh"
		echo "AllowUsers ansible" >> "/etc/ssh/sshd_config" \
			|| die "Could not append to /etc/ssh/sshd_config"
	fi

	if ask "Do you want to assign a root password now?"; then
		passwd root
		einfo "Root password assigned"
	else
		passwd -d root
		ewarn "Root password cleared, set one as soon as possible!"
	fi

	einfo "Gentoo installation complete."
	einfo "To chroot into the new system, simply execute the provided 'chroot' wrapper."
	einfo "Otherwise, you may now reboot your system."
}

main_install() {
	[[ $# == 0 ]] || die "Too many arguments"

	gentoo_umount
	install_stage3
	gentoo_chroot "$GENTOO_BOOTSTRAP_BIND/scripts/main.sh" install_gentoo_in_chroot
}

main_chroot() {
	gentoo_chroot "$@"
}

main_umount() {
	gentoo_umount
}


################################################
# Main dispatch

# Instantly kill when pressing ctrl-c
trap 'kill "$GENTOO_BOOTSTRAP_SCRIPT_PID"' INT

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
