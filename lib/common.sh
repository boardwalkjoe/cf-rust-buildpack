#!/usr/bin/env bash
# Copy the common.sh content from the guide

#!/usr/bin/env bash
# lib/common.sh

# Output formatting functions
function puts-step() {
    echo "-----> $@"
}

function puts-warn() {
    echo " !     $@"
}

function puts-verbose() {
    if [ -n "$VERBOSE" ]; then
        echo "       $@"
    fi
}

# Utility to get Rust version from Cargo.toml or rust-toolchain
function get_rust_version() {
    local build_dir=$1
    local version="stable"
    
    # Check for rust-toolchain file
    if [ -f "$build_dir/rust-toolchain" ]; then
        version=$(cat "$build_dir/rust-toolchain" | tr -d '\n\r')
    elif [ -f "$build_dir/rust-toolchain.toml" ]; then
        version=$(grep 'channel' "$build_dir/rust-toolchain.toml" | sed 's/.*=//g' | tr -d ' "')
    fi
    
    echo "$version"
}

# Check if binary exists in PATH
function check_command() {
    command -v "$1" >/dev/null 2>&1
}
