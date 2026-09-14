#!/bin/bash
set -e

ATLAS_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$ATLAS_SOURCE" ]]; do
    ATLAS_LINK_DIR="$(cd "$(dirname "$ATLAS_SOURCE")" && pwd)"
    ATLAS_SOURCE="$(readlink "$ATLAS_SOURCE")"
    [[ "$ATLAS_SOURCE" != /* ]] && ATLAS_SOURCE="$ATLAS_LINK_DIR/$ATLAS_SOURCE"
done
ATLAS_HOME="$(cd "$(dirname "$ATLAS_SOURCE")" && pwd)"
exec node "$ATLAS_HOME/lib/cli.js" "$@"
