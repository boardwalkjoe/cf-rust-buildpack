# Cloud Foundry Rust Buildpack Implementation Guide

## Overview
A Cloud Foundry buildpack consists of three main executable scripts that handle the application lifecycle: `detect`, `compile`, and `release`.

## Directory Structure
```
rust-buildpack/
├── bin/
│   ├── detect
│   ├── compile
│   └── release
├── lib/
│   └── common.sh
└── README.md
```

## 1. Detection Script (`bin/detect`)

This script determines if the buildpack should be used for an application.

```bash
#!/usr/bin/env bash
# bin/detect

BUILD_DIR=$1

# Check for Cargo.toml (primary indicator of a Rust project)
if [ -f "$BUILD_DIR/Cargo.toml" ]; then
    echo "Rust"
    exit 0
fi

# Check for main.rs or lib.rs as secondary indicators
if [ -f "$BUILD_DIR/src/main.rs" ] || [ -f "$BUILD_DIR/src/lib.rs" ]; then
    echo "Rust"
    exit 0
fi

# Not a Rust application
exit 1
```

## 2. Compilation Script (`bin/compile`)

This is the main script that installs Rust and compiles the application.

```bash
#!/usr/bin/env bash
# bin/compile

set -eo pipefail

BUILD_DIR=$1
CACHE_DIR=$2
ENV_DIR=$3
BUILDPACK_DIR=$(cd $(dirname $0); cd ..; pwd)

# Load common functions
source $BUILDPACK_DIR/lib/common.sh

# Configuration - Get latest stable version if not specified
if [ -z "$RUST_VERSION" ]; then
    echo "-----> Fetching latest stable Rust version..."
    RUST_VERSION=$(curl -s https://api.github.com/repos/rust-lang/rust/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    # Remove any non-numeric prefix (like 'v' or 'rust-')
    RUST_VERSION=$(echo "$RUST_VERSION" | sed 's/^[^0-9]*//')
    echo "       Latest stable version: $RUST_VERSION"
fi

# Fallback to a known stable version if API call fails
RUST_VERSION=${RUST_VERSION:-"1.75.0"}

echo "-----> Installing Rust $RUST_VERSION"

# Create cache directory for Rust installation
RUST_CACHE_DIR="$CACHE_DIR/rust"
mkdir -p "$RUST_CACHE_DIR"

# Install Rust if not cached
if [ ! -d "$RUST_CACHE_DIR/bin" ]; then
    echo "       Downloading and installing Rust..."
    
    # Download rustup installer
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > /tmp/rustup-init.sh
    chmod +x /tmp/rustup-init.sh
    
    # Install Rust to cache directory
    RUSTUP_HOME="$RUST_CACHE_DIR" CARGO_HOME="$RUST_CACHE_DIR" \
        /tmp/rustup-init.sh -y --default-toolchain $RUST_VERSION --no-modify-path
    
    rm /tmp/rustup-init.sh
else
    echo "       Using cached Rust installation"
fi

# Set up Rust environment
export RUSTUP_HOME="$RUST_CACHE_DIR"
export CARGO_HOME="$RUST_CACHE_DIR"
export PATH="$RUST_CACHE_DIR/bin:$PATH"

# Copy Rust installation to build directory
echo "-----> Setting up Rust environment"
cp -r "$RUST_CACHE_DIR" "$BUILD_DIR/.rust"

# Set up Cargo cache
CARGO_CACHE_DIR="$CACHE_DIR/cargo"
mkdir -p "$CARGO_CACHE_DIR"

# Link cargo cache to build directory
mkdir -p "$BUILD_DIR/.cargo"
if [ -d "$CARGO_CACHE_DIR/registry" ]; then
    ln -sf "$CARGO_CACHE_DIR/registry" "$BUILD_DIR/.cargo/registry"
fi
if [ -d "$CARGO_CACHE_DIR/git" ]; then
    ln -sf "$CARGO_CACHE_DIR/git" "$BUILD_DIR/.cargo/git"
fi

# Set environment for compilation
export CARGO_HOME="$BUILD_DIR/.cargo"
export RUSTUP_HOME="$BUILD_DIR/.rust"
export PATH="$BUILD_DIR/.rust/bin:$PATH"

echo "-----> Building Rust application"
cd "$BUILD_DIR"

# Check if this is a web application (has dependencies like actix-web, warp, etc.)
if grep -q -E "(actix-web|warp|rocket|axum|tide)" Cargo.toml; then
    echo "       Detected web framework"
    WEB_APP=true
else
    WEB_APP=false
fi

# Build the application in release mode
cargo build --release

# Copy cargo cache back for next build
cp -r "$BUILD_DIR/.cargo/registry" "$CARGO_CACHE_DIR/" 2>/dev/null || true
cp -r "$BUILD_DIR/.cargo/git" "$CARGO_CACHE_DIR/" 2>/dev/null || true

# Create start script
echo "-----> Creating startup script"
cat > "$BUILD_DIR/start.sh" << 'EOF'
#!/usr/bin/env bash

export RUSTUP_HOME="/app/.rust"
export CARGO_HOME="/app/.cargo"
export PATH="/app/.rust/bin:$PATH"

# Find the binary to run
BINARY_NAME=$(find target/release -maxdepth 1 -type f -executable ! -name "*.so" ! -name "*.d" | head -1)

if [ -z "$BINARY_NAME" ]; then
    echo "Error: No executable binary found in target/release"
    exit 1
fi

echo "Starting $(basename $BINARY_NAME)..."
exec "$BINARY_NAME" "$@"
EOF

chmod +x "$BUILD_DIR/start.sh"

echo "-----> Rust buildpack compilation complete"
```

## 3. Release Script (`bin/release`)

This script provides metadata about how to run the application.

```bash
#!/usr/bin/env bash
# bin/release

BUILD_DIR=$1

# Check if this appears to be a web application
if [ -f "$BUILD_DIR/Cargo.toml" ] && grep -q -E "(actix-web|warp|rocket|axum|tide)" "$BUILD_DIR/Cargo.toml"; then
    # Web application - default to PORT environment variable
    cat << EOF
---
default_process_types:
  web: ./start.sh
config_vars:
  RUST_LOG: info
EOF
else
    # CLI application
    cat << EOF
---
default_process_types:
  console: ./start.sh
config_vars:
  RUST_LOG: info
EOF
fi
```

## 4. Common Functions (`lib/common.sh`)

Shared utilities for the buildpack scripts.

```bash
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
```

## 5. Configuration Options

You can configure the buildpack through environment variables:

- `RUST_VERSION`: Specify Rust version (default: stable)
- `CARGO_BUILD_FLAGS`: Additional flags for cargo build
- `RUST_LOG`: Set logging level for the application

## 6. Usage

1. **Package the buildpack:**
   ```bash
   tar czf rust-buildpack.tgz rust-buildpack/
   ```

2. **Deploy with cf CLI:**
   ```bash
   cf push myapp -b https://github.com/yourusername/rust-buildpack.git
   ```

3. **Or specify in manifest.yml:**
   ```yaml
   applications:
   - name: rust-app
     buildpack: https://github.com/yourusername/rust-buildpack.git
     command: ./start.sh
   ```

## 7. Advanced Features

### Custom Build Commands
Add support for custom build commands in `bin/compile`:

```bash
# Check for custom build command
if [ -f "$BUILD_DIR/.buildpack-build-cmd" ]; then
    BUILD_CMD=$(cat "$BUILD_DIR/.buildpack-build-cmd")
    echo "-----> Running custom build command: $BUILD_CMD"
    eval "$BUILD_CMD"
else
    cargo build --release
fi
```

### Multi-Binary Support
Handle projects with multiple binaries:

```bash
# In start.sh, allow specifying which binary to run
BINARY_NAME=${1:-$(find target/release -maxdepth 1 -type f -executable ! -name "*.so" ! -name "*.d" | head -1)}
```

## 8. Testing

Create a simple test application:

```toml
# Cargo.toml
[package]
name = "hello-rust"
version = "0.1.0"
edition = "2021"

[dependencies]
actix-web = "4.0"
tokio = { version = "1.0", features = ["full"] }
```

```rust
// src/main.rs
use actix_web::{web, App, HttpResponse, HttpServer, Result};
use std::env;

async fn hello() -> Result<HttpResponse> {
    Ok(HttpResponse::Ok().body("Hello from Rust on Cloud Foundry!"))
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let port = env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let port: u16 = port.parse().expect("PORT must be a number");

    println!("Starting server on port {}", port);

    HttpServer::new(|| {
        App::new()
            .route("/", web::get().to(hello))
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await
}
```

This buildpack will detect Rust applications, install the Rust toolchain, compile the application, and provide appropriate runtime configuration for Cloud Foundry deployment.