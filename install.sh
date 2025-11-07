#!/usr/bin/env sh
set -eu

SCRIPT_NAME="hexmat"

# Source locations relative to this install script
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC_SCRIPT="$SELF_DIR/hexmat"
SRC_LIB_DIR="$SELF_DIR/hexmat_profile_library"

# Where to install (per-user by default)
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hexmat_profile_library"

echo "Installing script to: $BIN_DIR"
echo "Installing profile library to: $CONFIG_DIR"
echo

# Create dirs
mkdir -p "$BIN_DIR"
mkdir -p "$CONFIG_DIR"

# Install script
install -m 755 "$SRC_SCRIPT" "$BIN_DIR/$SCRIPT_NAME"

# Install / update library
cp -r "$SRC_LIB_DIR"/. "$CONFIG_DIR/"

echo "Done."
echo "  Script:  $BIN_DIR/$SCRIPT_NAME"
echo "  Library: $CONFIG_DIR"
echo

# Hint about PATH
case ":$PATH:" in
  *:"$BIN_DIR":*) ;;
  *)
    echo "Note: $BIN_DIR is not in your PATH."
    echo "Add something like this to your shell config:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac
