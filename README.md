# Cloud Foundry Rust Buildpack

A Cloud Foundry buildpack for Rust applications.

## Usage

Deploy your Rust application with:

```bash
cf push myapp -b https://github.com/yourusername/rust-buildpack.git


##Features

- Automatic Rust toolchain installation
- Cargo dependency caching
- Web framework detection (Actix, Warp, Rocket, etc.)
- Configurable Rust versions

##Configuration
Set environment variables to customize the build:

`RUST_VERSION`: Specify Rust version (default: stable)
`CARGO_BUILD_FLAGS`: Additional cargo build flags
`RUST_LOG`: Application logging level

##Example Application
See the example/ directory for a sample Rust web application.





