#!/bin/bash

# Find the directory this script is stored in. (from: http://stackoverflow.com/questions/59895)
function get_source_dir() {
	local source="${BASH_SOURCE[0]}"
	while [[ -h $source ]]
	do
		local tmp
		tmp="$(cd -P "$(dirname "${source}")" && pwd)"
		source="$(readlink "${source}")"
		[[ $source != /* ]] && source="${tmp}/${source}"
	done

	echo -n "$(realpath "$(dirname "${source}")")"
}

cd "$(get_source_dir)/.."
shellcheck -s bash --check-sourced --external-sources ./install
shellcheck -s bash --check-sourced --external-sources ./configure
