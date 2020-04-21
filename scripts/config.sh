source "$GENTOO_INSTALL_REPO_DIR/scripts/protection.sh" || exit 1
source "$GENTOO_INSTALL_REPO_DIR/scripts/internal_config.sh" || exit 1


################################################
# Disk configuration

# See the respective functions in internal_config.sh if you
# want to use a different disk configuration.
create_default_disk_layout /dev/sdX
#create_raid0_luks_layout /dev/sd{X,Y}

################################################
# System configuration

# Enter the desired system hostname here
HOSTNAME="gentoo"

# The timezone for the new system
TIMEZONE="Europe/Berlin"

# The default keymap for the system
KEYMAP="de-latin1-nodeadkeys"
#KEYMAP="us"

# A list of additional locales to generate. You should only
# add locales here if you really need them and want to localize
# your system. Otherwise, leave this list empty, and use C.utf8.
LOCALES=""
# The locale to set for the system. Be careful, this setting differs from the LOCALES
# list entries (e.g. .UTF-8 vs .utf8). Use the name as shown in `eselect locale`
LOCALE="C.utf8"
# For a german system you could use:
# LOCALES="
# de_DE.UTF-8 UTF-8
# de_DE ISO-8859-1
# de_DE@euro ISO-8859-15
# " # End of LOCALES
# LOCALE="de_DE.utf8"


################################################
# Gentoo configuration

# The selected gentoo mirror
GENTOO_MIRROR="https://mirror.eu.oneandone.net/linux/distributions/gentoo/gentoo"
#GENTOO_MIRROR="https://distfiles.gentoo.org"

# The architecture of the target system (only tested with amd64)
GENTOO_ARCH="amd64"

# The stage3 tarball to install
STAGE3_BASENAME="stage3-$GENTOO_ARCH-hardened+nomultilib"
#STAGE3_BASENAME="stage3-$GENTOO_ARCH-hardened-selinux+nomultilib"


################################################
# Additional (optional) configuration

# List of additional packages to install (will be directly passed to emerge)
ADDITIONAL_PACKAGES="app-editors/neovim"
# Install and enable dhcpcd
INSTALL_DHCPCD=true
# Install and configure sshd (a reasonably secure config is provided, which
# only allows the use of ed25519 keys, and requires pubkey authentication)
INSTALL_SSHD=true
# Install ansible, and add a user for it. This requires INSTALL_SSHD=true
INSTALL_ANSIBLE=true
# The home directory for the ansible user
ANSIBLE_HOME="/var/lib/ansible"
# An ssh key to add to the .authorized_keys file for the ansible user.
# This variable will become the content of the .authorized_keys file,
# so you may specify one key per line.
ANSIBLE_SSH_AUTHORIZED_KEYS=""


################################################
# Prove that you have read the config

# To prove that you have read and edited the config
# properly, set the following value to true.
I_HAVE_READ_AND_EDITED_THE_CONFIG_PROPERLY=false
