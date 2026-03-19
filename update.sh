#!/bin/bash
set -e

FORCE_UPDATE=0
# Use $* to check all arguments for the force flags
if [[ "$*" == *"--force"* || "$*" == *"-f"* ]]; then
    FORCE_UPDATE=1
fi

REPO_NAME=$(basename "$PWD")

echo "[$REPO_NAME]  🔄 Checking for updates..."

LOCAL_COMMIT=$(git rev-parse HEAD)
git pull > /dev/null
REMOTE_COMMIT=$(git rev-parse HEAD)

if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ] && [ "$FORCE_UPDATE" -eq 0 ]; then
    echo "[$REPO_NAME]  ⏭️ No new Git changes. Skipping Docker process."
    echo ""
    exit 0
fi

echo "[$REPO_NAME]  🏗️ Processing containers..."
# Redirect stdout to /dev/null to keep it clean.
# Stderr is NOT redirected, so build errors or compose warnings will still show up.
docker compose up -d --build > /dev/null

echo "[$REPO_NAME]  ✅ Update complete."
echo ""
