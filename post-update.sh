#!/bin/bash
# FILE: post-update.sh (inside hosting-core)
# This hook synchronizes the master manager script to the environment root 
# whenever the core infrastructure is updated.

CORE_DIR=$(dirname "$(readlink -f "$0")")
ENV_DIR=$(dirname "$CORE_DIR")

echo "[Core-Hook] Propagating updated manager.sh to environment root..."

# Copy from core to root. manager.sh in core doesn't need to be executable,
# but the one in the root must be.
cp "manager.sh" "$ENV_DIR/manager.sh"
chmod +x "$ENV_DIR/manager.sh"

echo "[Core-Hook] Manager script is now synchronized and executable in $ENV_DIR"
