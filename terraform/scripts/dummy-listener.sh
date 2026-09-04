#!/bin/bash
# Dummy PostgreSQL Listener
# Site 5 - MSP Multi-Client Estate
#
# Listens on TCP 5432 and simulates a PostgreSQL server banner.
# Used for Client C neglected test scenario.
# Does NOT implement PostgreSQL protocol - just accepts connections and sends a banner.

set -euo pipefail

PORT=5432
BANNER="PostgreSQL 14.0 (dummy)"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting dummy PostgreSQL listener on port ${PORT}"

# Use socat to listen and respond
# TCP-LISTEN:5432,fork,reuseaddr - listen on port 5432, fork for each connection, reuse address
# SYSTEM:'echo "PostgreSQL 14.0 (dummy)"; sleep 1' - send banner and close after 1 second

exec socat TCP-LISTEN:${PORT},fork,reuseaddr SYSTEM:"echo '${BANNER}'; sleep 1"