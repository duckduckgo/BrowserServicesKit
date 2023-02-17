#!/bin/bash

# Get the directory where the script is stored
script_dir=$(dirname "$(readlink -f "$0")")

# Define the source and destination variables
source="$script_dir/assets/Swift File For Package.xctemplate"
destination="/Applications/Xcode.app/Contents/Developer/Library/Xcode/Templates/File Templates/MultiPlatform/Source/Swift File For Package.xctemplate"

# Store the current working directory
original_dir=$(pwd)

# Change the working directory to the assets directory to ensure that the symbolic
# link is created with the correct relative paths and only in the intended destination directory.
# Without this, the ln command would create the symbolic link in the current working directory 
# as well as the destination directory.
(
  cd "$script_dir/assets" || exit
  ln -sF "$source" "$destination"
)

# Restore the original working directory
cd "$original_dir" || exit

# Check if the symlink was created successfully
if [[ ! -L "$destination" ]]; then
	echo "Symlink creation failed."
	exit 1
fi

echo "Symlink created successfully."