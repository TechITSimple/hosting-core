#!/bin/bash
set -e

# Parse arguments for the force flag
FORCE_UPDATE=0
if [[ "$1" == "--force" || "$1" == "-f" ]]; then
    FORCE_UPDATE=1
fi

# Dynamically get the repository (directory) name
REPO_NAME=$(basename "$PWD")

echo "[$REPO_NAME]  🔄 Checking for updates..."

LOCAL_COMMIT=$(git rev-parse HEAD)
git pull
REMOTE_COMMIT=$(git rev-parse HEAD)

if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ] && [ "$FORCE_UPDATE" -eq 0 ]; then
    echo "[$REPO_NAME]  ⏭️ No new Git changes. Skipping Docker build."
    echo ""
    exit 0
fi

echo "[$REPO_NAME]  🏗️ Building and restarting containers..."
docker compose up -d --build

echo "[$REPO_NAME]  ✅ Update complete."
echo ""
