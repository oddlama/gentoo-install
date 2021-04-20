#!/bin/bash

################################################
# Script setup

# TODO check install dialog
echo "Please install dialog on your system to use the configurator"


################################################
# Configuration storage

HOSTNAME="gentoo"
TIMEZONE="Europe/London"
KEYMAP="us"
KEYMAP_INITRAMFS="$KEYMAP"
LOCALES=""
LOCALE="C.utf8"


GENTOO_MIRROR="https://mirror.eu.oneandone.net/linux/distributions/gentoo/gentoo"
GENTOO_ARCH="amd64"
STAGE3_BASENAME="stage3-$GENTOO_ARCH-systemd"

SELECT_MIRRORS=true
SELECT_MIRRORS_LARGE_FILE=false

INIT_SYSTEM=systemd



ADDITIONAL_PACKAGES=("app-editors/neovim")
INSTALL_SSHD=true

ROOT_SSH_AUTHORIZED_KEYS=""


I_HAVE_READ_AND_EDITED_THE_CONFIG_PROPERLY=false


################################################
# Menu

dialog_save() {
	true
}

dialog_cancel() {
	# TODO really cancel and discard changes?
	true
}

dialog_intro() {
	# TODO hi there, in the following configure.
	true
}

dialog_hostname() {
	HOSTNAME="$(dialog --clear --help-button --help-label "Menu" --ok-label "Next" --cancel-label "Exit" --extra-button --extra-label "Back" --title "Select hostname" --inputbox "Enter the hostname for your new system." 8 72 "$HOSTNAME" 3>&2 2>&1 1>&3 3>&-)"
}

dialog_keymap() {
	local items=()
	local map
	for map in $(find /usr/share/keymaps/ /usr/share/kbd/keymaps/ -type f -iname '*.map.gz' -printf "%f\n" 2>/dev/null | sort -u); do
		map="${map%%.map.gz}"
		if [[ $map == $KEYMAP ]]; then
			items+=("${map}" "off")
		else
			items+=("${map}" "off")
		fi
	done
	KEYMAP="$(dialog --clear --help-button --help-label "Menu" --ok-label "Next" --cancel-label "Exit" --extra-button --extra-label "Back" --noitem --title "Select keymap" --radiolist "Select which keymap to use in the vconsole." 16 72 8 "${items[@]}" 3>&2 2>&1 1>&3 3>&-)"
	dialog --title "Not ok" --msgbox "not ok bro" 10 62
	echo $? $KEYMAP
}

#create_btrfs_raid_layout swap=8GiB luks=true /dev/sdX
#luks_getkeyfile() {
#	case "$1" in
#		#'my_luks_partition') echo -n '/path/to/my_luks_partition_keyfile' ;;
#		*) echo -n "/path/to/luks-keyfile" ;;
#	esac
#}

#dialog_hostname
#dialog_keymap
echo
echo $HOSTNAME
echo $KEYMAP

MENU_ITEMS=(
	"HOSTNAME"
	"TIMEZONE"
	"KEYMAP"
	"LOCALE"
	"INIT_SYSTEM"
)

HOSTNAME_tag() {
	echo "Hostname"
}

HOSTNAME_item() {
	echo "($HOSTNAME)"
}

TIMEZONE_tag() {
	echo "Timezone"
}

TIMEZONE_item() {
	echo "($TIMEZONE)"
}

KEYMAP_tag() {
	echo "Keymap"
}

KEYMAP_item() {
	echo "($KEYMAP)"
}

LOCALE_tag() {
	echo "Locale"
}

LOCALE_item() {
	echo "($LOCALE)"
}

INIT_SYSTEM_tag() {
	echo "Init system"
}

INIT_SYSTEM_item() {
	echo "($INIT_SYSTEM)"
}

dialog_menu() {
	local item
	local tag_item_list=()
	for item in "${MENU_ITEMS[@]}"; do
		tag_item_list+=("$(${item}_tag)" "$(${item}_item)")
	done
	dialog --clear --title "Gentoo configuration" --ok-label "Select" --cancel-label "Exit" --menu "Main config menu" 16 72 8 "${tag_item_list[@]}"
	# TODO double escape -> same as exit -> confirm dialog
}


dialog_menu
