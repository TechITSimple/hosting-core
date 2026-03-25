#!/bin/bash
# MANAGED BY TIS CORE - DO NOT EDIT THIS LINE

set -e

FORCE_UPDATE=0
if [[ "$*" == *"--force"* || "$*" == *"-f"* ]]; then
    FORCE_UPDATE=1
fi

SITE_NAME=$(basename "$PWD")
# Extract macro-environment name from the parent directory
ENV_NAME=$(basename "$(dirname "$PWD")")

# 1. EXPORT ISOLATION VARIABLES
# These tell Docker Compose which network to use and how to prefix containers
export COMPOSE_PROJECT_NAME="${ENV_NAME}-${SITE_NAME}"
export NETWORK_NAME="${ENV_NAME}-net"

# 2. COLD START CHECK
# If no containers exist for this specific project, force the build
if [ -z "$(docker compose ps -q 2>/dev/null)" ]; then
    echo "[$SITE_NAME] 🚀 Cold start detected. Forcing initial build..."
    FORCE_UPDATE=1
fi

echo "[$SITE_NAME] 🔄 Checking for updates..."

# 3. PRE-UPDATE HOOK
if [ -f "pre-update.sh" ]; then
    echo "[$SITE_NAME] 🔗 Preparing and executing pre-update hook..."
    sudo chmod +x pre-update.sh
    source pre-update.sh
fi

# 4. GIT PULL (AS SERVICE USER)
LOCAL_COMMIT=$(git rev-parse HEAD)
# Pulling as 'tis' ensures the Bot SSH key is used and prevents permission conflicts
sudo -u tis git pull > /dev/null
REMOTE_COMMIT=$(git rev-parse HEAD)

if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ] && [ "$FORCE_UPDATE" -eq 0 ]; then
    echo "[$SITE_NAME] ⏭️ No new Git changes. Skipping Docker process."
    echo ""
    exit 0
fi

# 5. DOCKER DEPLOYMENT
echo "[$SITE_NAME] 🏗️ Processing containers (Network: $NETWORK_NAME)..."
docker compose up -d --build --force-recreate> /dev/null

# 6. POST-UPDATE HOOK
if [ -f "post-update.sh" ]; then
    echo "[$SITE_NAME] 🔗 Preparing and executing post-update hook..."
    sudo chmod +x post-update.sh
    source post-update.sh
fi

echo "[$SITE_NAME] ✅ Update complete."
echo ""
