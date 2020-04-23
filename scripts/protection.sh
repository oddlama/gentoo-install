if [[ "$GENTOO_INSTALL_REPO_SCRIPT_ACTIVE" != "true" ]]; then
	echo "[1;31m * ERROR:[m This script must not be executed directly!" >&2
	exit 1
fi
