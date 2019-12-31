#!/bin/bash

[[ "${EXECUTED_IN_CHROOT}" != true ]] \
	&& { echo "This script must not be executed directly!" >&2; exit 1; }

source /etc/profile
export NPROC="$(($(nproc || echo 2) + 1))"

hostname 'gentoo'

exec "$@"
