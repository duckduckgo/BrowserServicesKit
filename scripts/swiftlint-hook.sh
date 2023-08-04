#!/bin/bash

# Get the path to the git hooks directory
HOOK_DIR="$(git rev-parse --show-toplevel)/.git/hooks"
HOOK_PATH="$HOOK_DIR/pre-commit"

install_hook() {
  # Define the hook
  HOOK_SCRIPT="#!/bin/sh

  if ! command -v swiftlint >/dev/null; then
    echo 'error: SwiftLint not installed, download from https://github.com/realm/SwiftLint'
    exit 1
  fi

  swiftlint --fix
  git add .
  echo 'SwiftLint finished fixing files. Proceeding with commit...'
  "

  # Create the pre-commit file
  echo "$HOOK_SCRIPT" > "$HOOK_PATH"

  # Make the file executable
  chmod +x "$HOOK_PATH"

  echo "Pre-commit hook installed successfully!"
}

uninstall_hook() {
  # Remove the pre-commit hook if it exists
  if [ -f "$HOOK_PATH" ]; then
    rm "$HOOK_PATH"
    echo "Pre-commit hook uninstalled successfully!"
  else
    echo "No pre-commit hook found to uninstall."
  fi
}

# Check command-line options
if [ "$1" == "--install" ]; then
  install_hook
elif [ "$1" == "--uninstall" ]; then
  uninstall_hook
else
  echo "Usage: $0 --install | --uninstall"
  exit 1
fi