#!/bin/bash

source "$GENTOO_BOOTSTRAP_DIR/scripts/protection.sh" || exit 1
source "$GENTOO_BOOTSTRAP_DIR/scripts/internal_config.sh" || exit 1


################################################
# Disk configuration

# Enable swap?
ENABLE_SWAP=false

# Enable partitioning (will still ask before doing anything critical)
ENABLE_PARTITIONING=true

# The device to partition
PARTITION_DEVICE="/dev/sda"
# Size of swap partition (if enabled)
PARTITION_SWAP_SIZE="8GiB"
# The size of the EFI partition
PARTITION_EFI_SIZE="128MiB"

# Partition UUIDs.
# You must insert these by hand, if you do not use automatic partitioning
PARTITION_UUID_EFI="$(load_or_generate_uuid 'efi')"
PARTITION_UUID_SWAP="$(load_or_generate_uuid 'swap')"
PARTITION_UUID_LINUX="$(load_or_generate_uuid 'linux')"

# Format the partitions with the correct filesystems,
# if you didn't chose automatic partitioning, you will be asked
# before any formatting is done.
ENABLE_FORMATTING=true


################################################
# Gentoo configuration

# The selected gentoo mirror
GENTOO_MIRROR="https://mirror.eu.oneandone.net/linux/distributions/gentoo/gentoo"
#GENTOO_MIRROR="https://distfiles.gentoo.org"

# The stage3 tarball to install
STAGE3_BASENAME="stage3-amd64-hardened+nomultilib"
#STAGE3_BASENAME="stage3-amd64-hardened-selinux+nomultilib"
