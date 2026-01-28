#!/bin/bash
# Protection script to prevent direct execution of sourced scripts
# This file should be sourced at the beginning of each script that
# should not be executed directly.

# Check if the main script has set the active flag
if [[ "${GENTOO_INSTALL_REPO_SCRIPT_ACTIVE:-}" != "true" ]]; then
	echo -e "\033[1;31m * ERROR:\033[m This script must not be executed directly!" >&2
	echo -e "\033[1;33m * INFO:\033[m  Please run the main installer script instead." >&2
	exit 1
fi

# Verify we have the required environment variables
if [[ -z "${GENTOO_INSTALL_REPO_DIR:-}" ]]; then
	echo -e "\033[1;31m * ERROR:\033[m GENTOO_INSTALL_REPO_DIR is not set!" >&2
	echo -e "\033[1;33m * INFO:\033[m  This variable should be set by the main installer." >&2
	exit 1
fi

# Verify the repo directory exists
if [[ ! -d "$GENTOO_INSTALL_REPO_DIR" ]]; then
	echo -e "\033[1;31m * ERROR:\033[m GENTOO_INSTALL_REPO_DIR does not exist: $GENTOO_INSTALL_REPO_DIR" >&2
	exit 1
fi