#!/bin/bash

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

export GENTOO_INSTALL_REPO_DIR_ORIGINAL="$(dirname "$(get_source_dir)")"
export GENTOO_INSTALL_REPO_DIR="$GENTOO_INSTALL_REPO_DIR_ORIGINAL"
export GENTOO_INSTALL_REPO_SCRIPT_ACTIVE=true
export GENTOO_INSTALL_REPO_SCRIPT_PID=$$

umask 0077

source "$GENTOO_INSTALL_REPO_DIR/scripts/utils.sh"
source "$GENTOO_INSTALL_REPO_DIR/scripts/config.sh"
source "$GENTOO_INSTALL_REPO_DIR/scripts/functions.sh"

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

configure_base_system() {
	# Set hostname
	einfo "Selecting hostname"
	sed -i "/hostname=/c\\hostname=\"$HOSTNAME\"" /etc/conf.d/hostname \
		|| die "Could not sed replace in /etc/conf.d/hostname"

	# Set timezone
	einfo "Selecting timezone"
	echo "$TIMEZONE" > /etc/timezone \
		|| die "Could not write /etc/timezone"
	try emerge -v --config sys-libs/timezone-data

	# Set keymap
	einfo "Selecting keymap"
	sed -i "/keymap=/c\\keymap=\"$KEYMAP\"" /etc/conf.d/keymaps \
		|| die "Could not sed replace in /etc/conf.d/keymaps"

	# Set locale
	einfo "Selecting locale"
	echo "$LOCALES" > /etc/locale.gen \
		|| die "Could not write /etc/locale.gen"
	locale-gen \
		|| die "Could not generate locales"
	try eselect locale set "$LOCALE"

	# Update environment
	env_update
}

install_sshd() {
	einfo "Installing sshd"
	install -m0600 -o root -g root "$GENTOO_INSTALL_REPO_DIR/configs/sshd_config" /etc/ssh/sshd_config \
		|| die "Could not install /etc/ssh/sshd_config"
	rc-update add sshd default \
		|| die "Could not add sshd to default services"
	groupadd -r sshusers \
		|| die "Could not create group 'sshusers'"
}

install_kernel() {
	# Install vanilla kernel and efibootmgr, to be able to boot the system.
	einfo "Installing binary vanilla kernel"
	try emerge --verbose sys-kernel/vanilla-kernel-bin sys-boot/efibootmgr

	# Copy kernel to EFI
	local kernel_version
	kernel_version="$(find "/boot" -name "vmlinuz-*" -printf '%f\n' | sort -V | tail -1)" \
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
	try efibootmgr --verbose --create --disk "$PARTITION_DEVICE" --part "$efipartnum" --label "gentoo" --loader '\EFI\vmlinuz.efi' --unicode "root=$linuxdev initrd=\\EFI\\initramfs.img"
}

install_ansible() {
	einfo "Installing ansible"
	try emerge --verbose app-admin/ansible

	einfo "Creating ansible user"
	useradd -r -d "$ANSIBLE_HOME" -s /bin/bash ansible \
		|| die "Could not create user 'ansible'"
	mkdir_or_die 0700 "$ANSIBLE_HOME"
	mkdir_or_die 0700 "$ANSIBLE_HOME/.ssh"

	if [[ -n "$ANSIBLE_SSH_AUTHORIZED_KEYS" ]]; then
		einfo "Adding authorized keys for ansible"
		touch_or_die 0600 "$ANSIBLE_HOME/.ssh/authorized_keys"
		echo "$ANSIBLE_SSH_AUTHORIZED_KEYS" >> "$ANSIBLE_HOME/.ssh/authorized_keys" \
			|| die "Could not add ssh key to authorized_keys"
	fi

	chown -R ansible: "$ANSIBLE_HOME" \
		|| die "Could not change ownership of ansible home"

	einfo "Adding ansible to sshusers"
	usermod -a -G sshusers ansible \
		|| die "Could not add ansible to sshusers group"
}

main_install_gentoo_in_chroot() {
	[[ $# == 0 ]] || die "Too many arguments"

	# Lock the root password, making the account unaccessible for the
	# period of installation, except by chrooting
	einfo "Locking root account"
	passwd -l root \
		|| die "Could not change root password"

	# Mount efi partition
	mount_efivars
	einfo "Mounting efi partition"
	mount_by_partuuid "$PARTITION_UUID_EFI" "/boot/efi"

	# Sync portage
	einfo "Syncing portage tree"
	try emerge-webrsync

	# Configure basic system things like timezone, locale, ...
	configure_base_system

	# Prepare /etc/portage for autounmask
	mkdir_or_die 0755 "/etc/portage/package.use"
	touch_or_die 0644 "/etc/portage/package.use/zz-autounmask"
	mkdir_or_die 0755 "/etc/portage/package.keywords"
	touch_or_die 0644 "/etc/portage/package.keywords/zz-autounmask"

	einfo "Temporarily installing mirrorselect"
	try emerge --verbose --oneshot app-portage/mirrorselect

	einfo "Selecting fastest portage mirrors"
	try mirrorselect -s 4 -b 10 -D

	einfo "Adding ~$GENTOO_ARCH to ACCEPT_KEYWORDS"
	echo "ACCEPT_KEYWORDS=\"~$GENTOO_ARCH\"" >> /etc/portage/make.conf \
		|| die "Could not modify /etc/portage/make.conf"

	# Install git (for git portage overlays)
	einfo "Installing git"
	try emerge --verbose dev-vcs/git

	install_kernel

	# Generate a valid fstab file
	einfo "Generating fstab"
	install -m0644 -o root -g root "$GENTOO_INSTALL_REPO_DIR/configs/fstab" /etc/fstab \
		|| die "Could not overwrite /etc/fstab"
	echo "PARTUUID=$PARTITION_UUID_LINUX    /            ext4    defaults,noatime,errors=remount-ro,discard                            0 1" >> /etc/fstab \
		|| die "Could not append entry to fstab"
	echo "PARTUUID=$PARTITION_UUID_EFI    /boot/efi    vfat    defaults,noatime,fmask=0022,dmask=0022,noexec,nodev,nosuid,discard    0 2" >> /etc/fstab \
		|| die "Could not append entry to fstab"
	if [[ "$ENABLE_SWAP" == true ]]; then
		echo "PARTUUID=$PARTITION_UUID_SWAP    none         swap    defaults,discard                                                      0 0" >> /etc/fstab \
			|| die "Could not append entry to fstab"
	fi

	# Install and enable dhcpcd
	einfo "Installing gentoolkit"
	try emerge --verbose app-portage/gentoolkit

	# Install and enable sshd
	if [[ "$INSTALL_SSHD" == true ]]; then
		install_sshd
	fi

	# Install and enable dhcpcd
	einfo "Installing dhcpcd"
	try emerge --verbose net-misc/dhcpcd
	rc-update add dhcpcd default \
		|| die "Could not add dhcpcd to default services"

	# Install ansible
	if [[ "$INSTALL_ANSIBLE" == true ]]; then
		install_ansible
	fi

	# Install additional packages, if any.
	if [[ -n "$ADDITIONAL_PACKAGES" ]]; then
		einfo "Installing additional packages"
		try emerge --verbose --autounmask-continue=y -- $ADDITIONAL_PACKAGES
	fi

	if ask "Do you want to assign a root password now?"; then
		try passwd root
		einfo "Root password assigned"
	else
		try passwd -d root
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
	mount_efivars
	gentoo_chroot "$GENTOO_INSTALL_REPO_BIND/scripts/main.sh" install_gentoo_in_chroot
	gentoo_umount
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
trap 'kill "$GENTOO_INSTALL_REPO_SCRIPT_PID"' INT

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
