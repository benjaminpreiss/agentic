#!/usr/bin/env bash
# Compatibility launcher for the workflow path (GitHub App cannot edit workflows).
# Test implementation and all fixtures live under tests/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
exec bash "$ROOT/tests/deployment.sh" "$@"
