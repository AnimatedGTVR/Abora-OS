.PHONY: audit build check clean install package release-check test

build:
	cargo build --release --locked

clean:
	cargo clean

install:
	cargo install --path . --locked

test:
	cargo test --locked

check:
	cargo fmt --check
	cargo clippy --all-targets --all-features --locked -- -D warnings
	cargo test --locked

audit:
	cargo audit --deny warnings

package:
	cargo package --locked --allow-dirty

release-check: check audit package build
