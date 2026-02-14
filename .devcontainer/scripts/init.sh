#!/bin/bash
# Runs on the HOST before docker-compose up (devcontainer initializeCommand).
# 1. Ensures TLS certificates exist for Traefik (generated with mkcert).
# 2. Creates api.env from local defaults so docker-compose can start.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INFRA_DIR="$ROOT_DIR/infra"
CERT_DIR="$INFRA_DIR/docker/certs/local"
ENV_DIR="$SCRIPT_DIR/../env"

# ─── 1. TLS Certificates ──────────────────────────────────────────────────────

if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
	echo "Certificates already exist in $CERT_DIR — skipping."
else
	if ! command -v mkcert &>/dev/null; then
		echo "Error: mkcert is not installed."
		echo ""
		echo "Install it:"
		echo "  Linux:  sudo apt install mkcert  (or see https://github.com/FiloSottile/mkcert#installation)"
		echo "  macOS:  brew install mkcert"
		echo ""
		echo "Then re-open the devcontainer."
		exit 1
	fi

	# Ensure the mkcert local CA exists and is trusted.
	# "mkcert -install" requires sudo — if the CA isn't set up yet,
	# prompt the user to run it manually rather than failing here.
	CAROOT="$(mkcert -CAROOT 2>/dev/null)"
	if [ -z "$CAROOT" ] || [ ! -f "$CAROOT/rootCA.pem" ]; then
		echo "Error: mkcert local CA not found. Run this once (requires sudo):"
		echo "  mkcert -install"
		echo ""
		echo "Then re-open the devcontainer."
		exit 1
	fi

	echo "Generating local TLS certificates with mkcert..."
	mkdir -p "$CERT_DIR"
	mkcert -cert-file "$CERT_DIR/fullchain.pem" -key-file "$CERT_DIR/privkey.pem" \
		"dev.krakenkey.io" "api-dev.krakenkey.io" "*.krakenkey.io" \
		localhost 127.0.0.1
	echo "Certificates generated in $CERT_DIR"
fi

# ─── 2. Local dev api.env ─────────────────────────────────────────────────────
# Docker Compose reads env_file at container creation.
# Copy local defaults if api.env doesn't exist yet.

if [ ! -f "$ENV_DIR/api.env" ]; then
	echo "Creating api.env from local defaults..."
	cp "$ENV_DIR/api.env.local-defaults" "$ENV_DIR/api.env"
fi
