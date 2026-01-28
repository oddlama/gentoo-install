#!/bin/bash
# Dispatch script for chroot environment
# This script sets up the environment and executes commands within the chroot

set -euo pipefail

# Verify we're running in chroot context
[[ ${EXECUTED_IN_CHROOT:-false} == "true" ]] \
	|| { echo "This script must not be executed directly!" >&2; exit 1; }

# Source the system's profile
# shellcheck disable=SC1091
source /etc/profile

# Set safe umask
umask 0077

# Export variables (used to determine processor count by some applications)
# Use a more robust method to get processor count with multiple fallbacks
get_nproc() {
	local nproc
	if nproc=$(nproc 2>/dev/null) && [[ "$nproc" =~ ^[0-9]+$ ]] && [[ "$nproc" -gt 0 ]]; then
		echo "$nproc"
	elif [[ -f /proc/cpuinfo ]]; then
		nproc=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null) || nproc=1
		[[ "$nproc" -gt 0 ]] && echo "$nproc" || echo "1"
	else
		echo "1"
	fi
}

export NPROC
NPROC="$(get_nproc)"
export NPROC_ONE="$((NPROC + 1))"

# Set default makeflags and emerge flags for parallel emerges
# Limit to reasonable values to prevent system overload
if [[ "$NPROC" -gt 1 ]]; then
	export MAKEFLAGS="-j$NPROC"
	export EMERGE_DEFAULT_OPTS="--jobs=$NPROC_ONE --load-average=$NPROC"
else
	export MAKEFLAGS="-j1"
	export EMERGE_DEFAULT_OPTS="--jobs=1"
fi

# Unset potentially sensitive variables
unset key
unset GENTOO_INSTALL_ENCRYPTION_KEY 2>/dev/null || true

# Validate that we have arguments to execute
[[ $# -gt 0 ]] || { echo "No command specified to execute" >&2; exit 1; }

# Execute the requested command
exec "$@"