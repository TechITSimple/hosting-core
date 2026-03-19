#!/bin/bash
set -e

# Base arguments passed by the user
ARGS="$@"
SCRIPT_PATH=$(readlink -f "$0")

# Hash the master script to detect self-updates later
SCRIPT_HASH_BEFORE=$(md5sum "$SCRIPT_PATH" | awk '{ print $1 }')

# Hash the parent .env to detect global configuration changes
ENV_HASH_BEFORE=$(md5sum ../.env 2>/dev/null | awk '{ print $1 }' || echo "none")

echo "========================================="
echo "🌐 TIS MASTER UPDATE INITIATED"
echo "========================================="
echo ""

echo ">>> [Master]  🔄 SYNCING CORE INFRASTRUCTURE"
cd "$(dirname "$0")/hosting-core" || exit 1

# Check commits to see if the core repository actually receives updates
LOCAL_COMMIT=$(git rev-parse HEAD)
git pull > /dev/null
REMOTE_COMMIT=$(git rev-parse HEAD)

CORE_CHANGED=0
if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
    echo ">>> [Master]  ⚠️ Core repository updated."
    CORE_CHANGED=1
fi
echo ""

echo ">>> [Master]  🌐 PROPAGATING GLOBAL CONFIGS"
cp global.env ../.env
cp global.update.sh ../update.sh
chmod +x ../update.sh

# Check if the global environment file changed
ENV_HASH_AFTER=$(md5sum ../.env | awk '{ print $1 }')

GLOBAL_ENV_CHANGED=0
if [ "$ENV_HASH_BEFORE" != "$ENV_HASH_AFTER" ]; then
    echo ">>> [Master]  ⚠️ Global .env changed. Forcing rebuild across all sites..."
    GLOBAL_ENV_CHANGED=1
else
    echo "Configs propagated (no changes detected)."
fi
echo ""

# Self-update check
SCRIPT_HASH_AFTER=$(md5sum "$SCRIPT_PATH" | awk '{ print $1 }')
if [ "$SCRIPT_HASH_BEFORE" != "$SCRIPT_HASH_AFTER" ]; then
    echo ">>> [Master]  ⚠️ Master script updated itself. Restarting execution..."
    exec "$SCRIPT_PATH" $ARGS
fi

# Determine specific arguments for satellites
SATELLITE_ARGS="$ARGS"
if [ "$GLOBAL_ENV_CHANGED" -eq 1 ]; then
    SATELLITE_ARGS="$SATELLITE_ARGS --force"
fi

# Determine specific arguments for the core
CORE_ARGS="$ARGS"
if [ "$CORE_CHANGED" -eq 1 ] || [ "$GLOBAL_ENV_CHANGED" -eq 1 ]; then
    CORE_ARGS="$CORE_ARGS --force"
fi

echo ">>> [Master]  MANAGING AND UPDATING SATELLITE WEBSITES"
for dir in ../*/; do
    SATELLITE_NAME=$(basename "$dir")
    
    if [ "$SATELLITE_NAME" != "hosting-core" ]; then
        TARGET_UPDATE="${dir}update.sh"
        
        # Unconditionally sync the universal update script to all satellites
        # This ensures every site benefits from core script improvements
        cp update.sh "$TARGET_UPDATE"
        chmod +x "$TARGET_UPDATE"

        # Execute the satellite update process
        (cd "$dir" && ./update.sh $SATELLITE_ARGS)
    fi
done

echo ">>> [Master]  🧹 CLEANING UP DOCKER SYSTEM"
docker image prune -f > /dev/null
echo ""

echo "========================================="
echo "✅ ALL SYSTEMS UPDATED SUCCESSFULLY"
echo "========================================="
