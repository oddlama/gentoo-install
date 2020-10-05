#!/bin/bash
set -o pipefail

################################################
# Initialize script environment

# Find the directory this script is stored in. (from: http://stackoverflow.com/questions/59895)
get_source_dir() {
	local source="${BASH_SOURCE[0]}"
	while [[ -h $source ]]
	do
		local tmp="$(cd -P "$(dirname "${source}")" && pwd)"
		source="$(readlink "${source}")"
		[[ $source != /* ]] && source="${tmp}/${source}"
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

[[ $I_HAVE_READ_AND_EDITED_THE_CONFIG_PROPERLY == "true" ]] \
	|| die "You have not properly read the config. Set I_HAVE_READ_AND_EDITED_THE_CONFIG_PROPERLY=true to continue."

preprocess_config

mkdir_or_die 0755 "$TMP_DIR"
[[ $EUID == 0 ]] \
	|| die "Must be root"


################################################
# Functions

install_stage3() {
	[[ $# == 0 ]] || die "Too many arguments"

	prepare_installation_environment
	apply_disk_configuration
	download_stage3
	extract_stage3
}

configure_base_system() {
	einfo "Generating locales"
	echo "$LOCALES" > /etc/locale.gen \
		|| die "Could not write /etc/locale.gen"
	locale-gen \
		|| die "Could not generate locales"

	if [[ $SYSTEMD == "true" ]]; then
		einfo "Setting machine-id"
		systemd-machine-id-setup \
			|| die "Could not setup systemd machine id"

		# Set hostname
		einfo "Selecting hostname"
		hostnamectl set-hostname "$HOSTNAME" \
			|| die "Could not set hostname"

		# Set timezone
		einfo "Selecting timezone"
		timedatectl set-timezone "$TIMEZONE" \
			|| die "Could not set timezone"

		einfo "Setting time to UTC"
		timedatectl set-local-rtc 0 \
			|| die "Could not set local rtc to UTC"

		# Set keymap
		einfo "Selecting keymap"
		localectl set-keymap "$KEYMAP" \
			|| die "Could not set keymap"

		# Set locale
		einfo "Selecting locale"
		localectl set-locale LANG="$LOCALE" \
			|| die "Could not set locale"
	else
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
		try eselect locale set "$LOCALE"
	fi

	# Update environment
	env_update
}

configure_portage() {
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

generate_initramfs() {
	local output="$1"

	# Generate initramfs
	einfo "Generating initramfs"

	local modules=()
	[[ $USED_RAID == "true" ]] \
		&& modules+=("mdraid")
	[[ $USED_LUKS == "true" ]] \
		&& modules+=("crypt crypt-gpg")

	local kver="$(readlink /usr/src/linux)"
	kver="${kver#linux-}"

	# Generate initramfs
	try dracut \
		--conf          "/dev/null" \
		--confdir       "/dev/null" \
		--kver          "$kver" \
		--no-compress \
		--no-hostonly \
		--ro-mnt \
		--add           "bash ${modules[*]}" \
		--force \
		"$output"
}

get_cmdline() {
	echo -n "${DISK_DRACUT_CMDLINE[*]} root=UUID=$(get_blkid_uuid_for_id "$DISK_ID_ROOT")"
}

install_kernel_efi() {
	try emerge --verbose sys-boot/efibootmgr

	# Copy kernel to EFI
	local kernel_file
	kernel_file="$(find "/boot" -name "vmlinuz-*" -printf '%f\n' | sort -V | tail -n 1)" \
		|| die "Could not list newest kernel file"

	mkdir_or_die 0755 "/boot/efi/EFI"
	cp "/boot/$kernel_file" "/boot/efi/EFI/vmlinuz.efi" \
		|| die "Could not copy kernel to EFI partition"

	# Generate initramfs
	generate_initramfs "/boot/efi/EFI/initramfs.img"

	# Create boot entry
	einfo "Creating efi boot entry"
	local efipartdev="$(resolve_device_by_id "$DISK_ID_EFI")"
	local efipartnum="${efipartdev: -1}"
	local gptdev="$(resolve_device_by_id "${DISK_ID_PART_TO_GPT_ID[$DISK_ID_EFI]}")"
	try efibootmgr --verbose --create --disk "$gptdev" --part "$efipartnum" --label "gentoo" --loader '\EFI\vmlinuz.efi' --unicode 'initrd=\EFI\initramfs.img'" $(get_cmdline)"
}

generate_syslinux_cfg() {
	cat <<EOF
DEFAULT gentoo
PROMPT 0
TIMEOUT 0

LABEL gentoo
	LINUX ../vmlinuz-current
	APPEND initrd=../initramfs.img $(get_cmdline)
EOF
}

install_kernel_bios() {
	try emerge --verbose sys-boot/syslinux

	# Link kernel to known name
	local kernel_file
	kernel_file="$(find "/boot" -name "vmlinuz-*" -printf '%f\n' | sort -V | tail -n 1)" \
		|| die "Could not list newest kernel file"

	cp "/boot/$kernel_file" "/boot/bios/vmlinuz-current" \
		|| die "Could copy kernel to /boot/bios/vmlinuz-current"

	# Generate initramfs
	generate_initramfs "/boot/bios/initramfs.img"

	# Install syslinux
	einfo "Installing syslinux"
	local biosdev="$(resolve_device_by_id "$DISK_ID_BIOS")"
	mkdir_or_die 0700 "/boot/bios/syslinux"
	try syslinux --directory syslinux --install "$biosdev"

	# Create syslinux.cfg
	generate_syslinux_cfg > /boot/bios/syslinux/syslinux.cfg \
		|| die "Could save generated syslinux.cfg"

	# Install syslinux MBR record
	einfo "Copying syslinux MBR record"
	local gptdev="$(resolve_device_by_id "${DISK_ID_PART_TO_GPT_ID[$DISK_ID_BIOS]}")"
	try dd bs=440 conv=notrunc count=1 if=/usr/share/syslinux/gptmbr.bin of="$gptdev"
}

install_kernel() {
	# Install vanilla kernel
	einfo "Installing vanilla kernel and related tools"
	try emerge --verbose sys-kernel/dracut sys-kernel/gentoo-kernel-bin

	if [[ $IS_EFI == "true" ]]; then
		install_kernel_efi
	else
		install_kernel_bios
	fi
}

add_fstab_entry() {
	printf '%-46s  %-24s  %-6s  %-96s %s\n' "$1" "$2" "$3" "$4" "$5" >> /etc/fstab \
		|| die "Could not append entry to fstab"
}

generate_fstab() {
	einfo "Generating fstab"
	install -m0644 -o root -g root "$GENTOO_INSTALL_REPO_DIR/configs/fstab" /etc/fstab \
		|| die "Could not overwrite /etc/fstab"
	add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_ROOT")" "/" "$DISK_ID_ROOT_TYPE" "$DISK_ID_ROOT_MOUNT_OPTS" "0 1"
	if [[ $IS_EFI == "true" ]]; then
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_EFI")" "/boot/efi" "vfat" "defaults,noatime,fmask=0177,dmask=0077,noexec,nodev,nosuid,discard" "0 2"
	else
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_BIOS")" "/boot/bios" "vfat" "defaults,noatime,fmask=0177,dmask=0077,noexec,nodev,nosuid,discard" "0 2"
	fi
	if [[ -v "DISK_ID_SWAP" ]]; then
		add_fstab_entry "UUID=$(get_blkid_uuid_for_id "$DISK_ID_SWAP")" "none" "swap" "defaults,discard" "0 0"
	fi
}

install_ansible() {
	einfo "Installing ansible"
	try emerge --verbose app-admin/ansible

	einfo "Creating ansible user"
	useradd -r -d "$ANSIBLE_HOME" -s /bin/bash ansible \
		|| die "Could not create user 'ansible'"
	mkdir_or_die 0700 "$ANSIBLE_HOME"
	mkdir_or_die 0700 "$ANSIBLE_HOME/.ssh"

	if [[ -n $ANSIBLE_SSH_AUTHORIZED_KEYS ]]; then
		einfo "Adding authorized keys for ansible"
		touch_or_die 0600 "$ANSIBLE_HOME/.ssh/authorized_keys"
		echo "$ANSIBLE_SSH_AUTHORIZED_KEYS" >> "$ANSIBLE_HOME/.ssh/authorized_keys" \
			|| die "Could not add ssh key to authorized_keys"
	fi

	chown -R ansible: "$ANSIBLE_HOME" \
		|| die "Could not change ownership of ansible home"

	einfo "Adding ansible to some auxiliary groups"
	usermod -a -G wheel,sshusers ansible \
		|| die "Could not add ansible to auxiliary groups"
}

main_install_gentoo_in_chroot() {
	[[ $# == 0 ]] || die "Too many arguments"

	# Lock the root password, making the account unaccessible for the
	# period of installation, except by chrooting
	einfo "Locking root account"
	passwd -l root \
		|| die "Could not change root password"

	if [[ $IS_EFI == "true" ]]; then
		# Mount efi partition
		mount_efivars
		einfo "Mounting efi partition"
		mount_by_id "$DISK_ID_EFI" "/boot/efi"
	else
		# Mount bios partition
		einfo "Mounting bios partition"
		mount_by_id "$DISK_ID_BIOS" "/boot/bios"
	fi

	# Sync portage
	einfo "Syncing portage tree"
	try emerge-webrsync

	# Configure basic system things like timezone, locale, ...
	configure_base_system

	# Prepare portage environment
	configure_portage

	# Install git (for git portage overlays)
	einfo "Installing git"
	try emerge --verbose dev-vcs/git

	# Install mdadm if we used raid (needed for uuid resolving)
	if [[ $USED_RAID == "true" ]]; then
		einfo "Installing mdadm"
		try emerge --verbose sys-fs/mdadm
	fi

	# Install cryptsetup if we used luks
	if [[ $USED_LUKS == "true" ]]; then
		einfo "Installing cryptsetup"
		try emerge --verbose sys-fs/cryptsetup
	fi

	# Install kernel and initramfs
	install_kernel

	# Generate a valid fstab file
	generate_fstab

	# Install and enable dhcpcd
	einfo "Installing gentoolkit"
	try emerge --verbose app-portage/gentoolkit

	# Install and enable sshd
	if [[ $INSTALL_SSHD == "true" ]]; then
		install_sshd
	fi

	# Install and enable dhcpcd
	einfo "Installing dhcpcd"
	try emerge --verbose net-misc/dhcpcd
	rc-update add dhcpcd default \
		|| die "Could not add dhcpcd to default services"

	# Install ansible
	if [[ $INSTALL_ANSIBLE == "true" ]]; then
		install_ansible
	fi

	# Install additional packages, if any.
	if [[ ${#ADDITIONAL_PACKAGES[@]} -gt 0 ]]; then
		einfo "Installing additional packages"
		# shellcheck disable=SC2086
		try emerge --verbose --autounmask-continue=y -- "${ADDITIONAL_PACKAGES[@]}"
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

	[[ $IS_EFI == "true" ]] \
		&& mount_efivars
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
if [[ $SCRIPT_ALIAS == main.sh ]]; then
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
