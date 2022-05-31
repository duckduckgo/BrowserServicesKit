#!/bin/bash

set -eo pipefail

cwd="$(dirname "${BASH_SOURCE[0]}")"

printf '%s' 'Fetching public_suffix_list.dat ... '

curl -sL https://publicsuffix.org/list/public_suffix_list.dat \
	-o "${cwd}/../Sources/BrowserServicesKit/Resources/public_suffix_list.dat"

echo 'Done'
