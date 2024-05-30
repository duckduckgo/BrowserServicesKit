#!/bin/bash
set -eo pipefail
#
## The following URLs shall match the one in the client.
## Danger checks that the URLs match on every PR. If the code changes, the regex that Danger uses may need an update.
API_URL="http://localhost:3000"
API_STAGING_URL="https://tbd.unknown.duckduckgo.com"
#
# If -c is passed, then check the URLs in the Configuration file is correct.
if [ "$1" == "-c" ]; then
	grep 'static let' Sources/PhishingDetection/PhishingDetectionClient.swift | grep 'http' | while read -r line
	do
		if [[ $line == *"$API_URL"* || $line == *"$API_STAGING_URL"* ]]; then
			if [[ $line =~ ^.*\"(http[^\"]*)\".*$ ]]; then
				echo "URL matches: ${BASH_REMATCH[1]}"
			else
				echo "URL does not match API_URL or API_STAGING_URL: $line"
                exit 1
			fi
		fi
	done

	exit 0
fi

temp_filename="phishing_data_new_file"
new_revision=$(curl -s "${API_URL}/revision" | jq -r '.revision')

rm -f "$temp_filename"

performUpdate() {
	local data_type=$1
	local provider_path=$2
	local data_path=$3
	printf "Processing: %s\n" "${data_type}"

	if test ! -f "$data_path"; then
		printf "Error: %s does not exist\n" "${data_path}"
		exit 1
	fi

	if test ! -f "$provider_path"; then
		printf "Error: %s does not exist\n" "${provider_path}"
		exit 1
	fi

	old_sha=$(grep 'public static let '${data_type}'DataSHA' "${provider_path}" | awk -F '"' '{print $2}')
	old_revision=$(grep 'public static let revision' "${provider_path}" | awk -F '=' '{print $2}' | tr -d ' ')

	printf "Existing SHA256: %s\n" "${old_sha}"
	printf "Existing revision: %s\n" "${old_revision}"

	if [ $old_revision -lt $new_revision ]; then
        curl -o $temp_filename -s "${API_URL}/${data_type}"
		cat "$temp_filename" | jq -r '.insert' > "$data_path"

		new_sha=$(shasum -a 256 "$data_path" | awk -F ' ' '{print $1}')

		printf "New SHA256: %s\n" "$new_sha"

        sed -i '' -e "s/$old_sha/$new_sha/g" "${provider_path}"

		printf 'Files updated\n\n'
	else
		printf 'Nothing to update\n\n'
	fi

	rm -f "$temp_filename"
}

updateRevision() {
    local new_revision=$1
	local provider_path=$2
	old_revision=$(grep 'public static let revision' "${provider_path}" | awk -F '=' '{print $2}' | tr -d ' ')

	if [ $old_revision -lt $new_revision ]; then
		sed -i '' -e "s/public static let revision =.*/public static let revision = $new_revision/" "${provider_path}"
        printf "Updated revision from $old_revision to $new_revision\n"
	fi
}

performUpdate hashPrefix \
		"${PWD}/Sources/PhishingDetection/PhishingDetectionDataProvider.swift" \
		"${PWD}/Sources/PhishingDetection/hashPrefixes.json"

performUpdate filterSet \
		"${PWD}/Sources/PhishingDetection/PhishingDetectionDataProvider.swift" \
		"${PWD}/Sources/PhishingDetection/filterSet.json"

updateRevision $new_revision "${PWD}/Sources/PhishingDetection/PhishingDetectionDataProvider.swift" 