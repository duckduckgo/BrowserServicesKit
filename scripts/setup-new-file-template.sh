#!/bin/bash

# Get the directory where the script is stored
script_dir=$(dirname "$(readlink -f "$0")")

# Define the source and destination variables
source="$script_dir/assets/Swift File For Package.xctemplate"
destdir="${HOME}/Library/Developer/Xcode/Templates/File Templates/Source"
destination="${destdir}/Swift File For Package.xctemplate"

mkdir -p  "${destdir}"
# Create a symbolic link
ln -sFn "$source" "$destination"

# Check if the symlink was created successfully
if [[ ! -L "$destination" ]]; then
	echo "Symlink creation failed."
	exit 1
fi

echo "Symlink created successfully."
