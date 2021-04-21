#!/bin/bash
set -o pipefail

################################################
# Script setup

# TODO check install dialog
echo "Please install dialog on your system to use the configurator"


################################################
# Configuration storage

UNSAVED_CHANGES=false
SAVE_AS_FILENAME="gentoo.conf"

HOSTNAME="gentoo"
# TODO get from current system
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


################################################
# Menu definition

MENU_ITEMS=(
	"HOSTNAME"
	"TIMEZONE"
	"KEYMAP"
	"LOCALE"
	"INIT_SYSTEM"
	"KEYFILE"
)

function HOSTNAME_tag()   { echo "Hostname"; }
function HOSTNAME_label() { echo "($HOSTNAME)"; }
function HOSTNAME_menu()  {
	local sel
	sel="$(dialog --clear \
		--help-button --help-label "Menu" \
		--ok-label "Next" --cancel-label "Exit" \
		--extra-button --extra-label "Back" \
		--title "Select hostname" \
		--inputbox "Enter the hostname for your new system." \
		8 72 "$HOSTNAME" 3>&2 2>&1 1>&3 3>&-)"
	UNSAVED_CHANGES=true
}

function TIMEZONE_tag()   { echo "Timezone"; }
function TIMEZONE_label() { echo "($TIMEZONE)"; }
function TIMEZONE_help()  { echo "ajajaejaejgj jagj etjghoajf iajgpiajroianer goinaeirogn oairg arga lnaorignap ojkjaprogj iarrgona og"; }

function KEYMAP_tag()   { echo "Keymap"; }
function KEYMAP_label() { echo "($KEYMAP)"; }
function KEYMAP_menu()  {
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

	local sel
	sel="$(dialog --clear \
		--help-button --help-label "Menu" \
		--ok-label "Next" --cancel-label "Exit" \
		--extra-button --extra-label "Back" \
		--noitem \
		--title "Select keymap" \
		--radiolist "Select which keymap to use in the vconsole." \
		16 72 8 "${items[@]}" 3>&2 2>&1 1>&3 3>&-)"
}

function LOCALE_tag()   { echo "Locale"; }
function LOCALE_label() { echo "($LOCALE)"; }

function INIT_SYSTEM_tag()   { echo "Init system"; }
function INIT_SYSTEM_label() { echo "($INIT_SYSTEM)"; }

function KEYFILE_tag()   { echo "Key file"; }
function KEYFILE_label() { echo "($KEYFILE)"; }


################################################
# Menu functions

# $1: filename
function save() {
	echo save to "$1"
}

function msgbox_help() {
	dialog --clear \
		--msgbox "$1" \
		8 66 3>&2 2>&1 1>&3 3>&-
}

function menu_exit() {
	if [[ $UNSAVED_CHANGES == "true" ]]; then
		local sel
		sel="$(dialog --clear \
			--help-button --help-label "Back" \
			--yes-label "Save" --no-label "Discard" \
			--yesno "Do you want to save your configuration?\n(Press <ESC><ESC>, or choose <Back> to continue gentoo configuration)." \
			8 66 3>&2 2>&1 1>&3 3>&-)"

		local diag_exit="$?"
		if [[ $diag_exit == 0 ]]; then
			# <Save>
			save "gentoo.conf"
			exit 0
		elif [[ $diag_exit == 1 ]]; then
			# <Discard>
			exit 0
		else
			# Back to menu (<ESC><ESC>, <Back>)
			true
		fi
	else
		# Nothing was changed. Exit immediately.
		exit 0
	fi
}

function menu_save_as() {
	local sel
	sel="$(dialog --clear \
		--ok-label "Save" \
		--inputbox "Enter a filename to which this configuration should be saved.\n(Press <ESC><ESC>, or choose <Cancel> to abort)." \
		8 66 "$SAVE_AS_FILENAME" 3>&2 2>&1 1>&3 3>&-)"

	local diag_exit="$?"
	if [[ $diag_exit == 0 ]]; then
		# <Save>
		SAVE_AS_FILENAME="$sel"
		save "$SAVE_AS_FILENAME"
		UNSAVED_CHANGES=false
	else
		# Back to menu (<ESC><ESC>, <Cancel>)
		true
	fi
}

function menu() {
	local item
	local item_tag
	local tag_item_list=()
	declare -A reverse_lookup

	# Create menu list
	for item in "${MENU_ITEMS[@]}"; do
		item_tag="$("${item}_tag")"
		tag_item_list+=("$item_tag" "$("${item}_label")")
		reverse_lookup["$item_tag"]="$item"
	done

	local sel
	sel="$(dialog --clear \
		--title "Gentoo configuration" \
		--extra-button --extra-label "Exit" \
		--help-button \
		--ok-label "Select" --cancel-label "Save" \
		--menu "Main config menu" \
		16 72 8 "${tag_item_list[@]}" 3>&2 2>&1 1>&3 3>&-)"

	local diag_exit="$?"
	if [[ $diag_exit == 0 ]]; then
		# <Select>
		"${reverse_lookup[$sel]}_menu"
	elif [[ $diag_exit == 1 ]]; then
		# <Save>
		menu_save_as
	elif [[ $diag_exit == 2 ]]; then
		# <Help>
		msgbox_help "$("${reverse_lookup[${sel#HELP }]}_help")"
	else
		# Exit (<ESC><ESC>, <Exit>)
		menu_exit
		true
	fi
}

while true; do
	menu
done
