#!/bin/bash
# MANAGED BY TIS CORE - DO NOT EDIT THIS LINE

set -e

FORCE_UPDATE=0
if [[ "$*" == *"--force"* || "$*" == *"-f"* ]]; then
    FORCE_UPDATE=1
fi

REPO_NAME=$(basename "$PWD")

# --- COLD START CHECK ---
# Check if any container for this project is currently defined (running or stopped)
# If 'docker compose ps -q' returns an empty string, the project has never been started.
if [ -z "$(docker compose ps -q 2>/dev/null)" ]; then
    echo "[$REPO_NAME]  🚀 Cold start detected (no containers found). Forcing initial build..."
    FORCE_UPDATE=1
fi

echo "[$REPO_NAME]  🔄 Checking for updates..."

# --- PRE-UPDATE HOOK ---
if [ -f "pre-update.sh" ]; then
    echo "[$REPO_NAME]  🔗 Executing pre-update hook..."
    source pre-update.sh
fi

LOCAL_COMMIT=$(git rev-parse HEAD)
git pull > /dev/null
REMOTE_COMMIT=$(git rev-parse HEAD)

if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ] && [ "$FORCE_UPDATE" -eq 0 ]; then
    echo "[$REPO_NAME]  ⏭️ No new Git changes. Skipping Docker process."
    echo ""
    exit 0
fi

echo "[$REPO_NAME]  🏗️ Processing containers..."
docker compose up -d --build > /dev/null

# --- POST-UPDATE HOOK ---
if [ -f "post-update.sh" ]; then
    echo "[$REPO_NAME]  🔗 Executing post-update hook..."
    source post-update.sh
fi

echo "[$REPO_NAME]  ✅ Update complete."
echo ""
