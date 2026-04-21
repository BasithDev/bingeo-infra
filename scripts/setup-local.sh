#!/bin/bash

# Bingeo Local Setup Script
# This is an alias for the main setup.sh script.
# Run this once to prepare your local k3s environment.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Running main setup script..."
chmod +x "$SCRIPT_DIR/setup.sh"
exec "$SCRIPT_DIR/setup.sh"
