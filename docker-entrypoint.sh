#!/bin/sh
set -e

# Default config file location if not set
export STASH_CONFIG_FILE="${STASH_CONFIG_FILE:-/root/.stash/config.yml}"

# Ensure config directory exists before stash starts
CONFIG_DIR=$(dirname "$STASH_CONFIG_FILE")
mkdir -p "$CONFIG_DIR"

# Ensure all standard stash storage directories exist
mkdir -p /root/.stash /data /metadata /cache /blobs /generated /config

# Adapt to dynamic PORT environment variable (e.g. Render, Railway, Heroku)
if [ -n "$PORT" ] && [ -z "$STASH_PORT" ]; then
  export STASH_PORT="$PORT"
fi

# If first arg starts with '-' (e.g. -c /path/config.yml), prepend stash
if [ "${1#-}" != "$1" ]; then
  exec stash "$@"
fi

# If first arg is 'stash', execute it
if [ "$1" = "stash" ]; then
  exec "$@"
fi

# If no command passed, run stash
if [ $# -eq 0 ]; then
  exec stash
fi

# Otherwise execute custom command passed
exec "$@"
