#!/bin/bash
set -e

ARGS="$@"
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_HASH_BEFORE=$(md5sum "$SCRIPT_PATH" | awk '{ print $1 }')

echo "========================================="
echo "🌐 TIS MASTER UPDATE INITIATED"
echo "========================================="
echo ""

echo "[Master]  🔄 SYNCING CORE INFRASTRUCTURE"
cd "$(dirname "$0")/hosting-core" || exit 1

LOCAL_COMMIT=$(git rev-parse HEAD)
git pull > /dev/null
REMOTE_COMMIT=$(git rev-parse HEAD)

CORE_CHANGED=0
if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
    echo "[Master]  📦 Core repository updated."
    CORE_CHANGED=1
fi
echo ""

GLOBAL_ENV_CHANGED=0
echo "[Master]  🌐 PROPAGATING GLOBAL CONFIGS"

# Use 'cmp' for a binary-exact comparison instead of brittle MD5 hashes
if [ -f "../.env" ]; then
    if ! cmp -s global.env ../.env; then
        echo "[Master]  ⚠️ Global .env changed. Forcing rebuild across all sites..."
        cp global.env ../.env
        GLOBAL_ENV_CHANGED=1
    else
        echo "[Master]  ✅ Configs propagated (no changes detected)."
    fi
else
    echo "[Master]  🆕 Initializing global .env for the first time..."
    cp global.env ../.env
    # The cold start in update.sh will naturally handle the initial build
fi

# Always sync the master script updater
cp global.update.sh ../update.sh
chmod +x ../update.sh
echo ""

SCRIPT_HASH_AFTER=$(md5sum "$SCRIPT_PATH" | awk '{ print $1 }')
if [ "$SCRIPT_HASH_BEFORE" != "$SCRIPT_HASH_AFTER" ]; then
    echo "[Master]  ⚠️ Master script updated itself. Restarting execution..."
    exec "$SCRIPT_PATH" $ARGS
fi

SATELLITE_ARGS="$ARGS"
if [ "$GLOBAL_ENV_CHANGED" -eq 1 ]; then
    SATELLITE_ARGS="$SATELLITE_ARGS --force"
fi

CORE_ARGS="$ARGS"
if [ "$CORE_CHANGED" -eq 1 ] || [ "$GLOBAL_ENV_CHANGED" -eq 1 ]; then
    CORE_ARGS="$CORE_ARGS --force"
fi

# --- CRITICAL FIX ---
# The core MUST be updated first to guarantee the 'tis_proxy' network exists
echo "[Master]  🏗️ UPDATING CORE CONTAINERS"
./update.sh $CORE_ARGS

echo "[Master]  🚀 MANAGING AND UPDATING SATELLITE WEBSITES"
for dir in ../*/; do
    SATELLITE_NAME=$(basename "$dir")
    
    if [ "$SATELLITE_NAME" != "hosting-core" ]; then
        TARGET_UPDATE="${dir}update.sh"
        
        # Install or sync the update script
        if [ ! -f "$TARGET_UPDATE" ]; then
            echo "[Master]  🆕 Installing update script for new satellite: $SATELLITE_NAME"
            cp update.sh "$TARGET_UPDATE"
            chmod +x "$TARGET_UPDATE"
        elif grep -q "# MANAGED BY TIS CORE" "$TARGET_UPDATE"; then
            cp update.sh "$TARGET_UPDATE"
            chmod +x "$TARGET_UPDATE"
        fi

        # Run the satellite update
        if [ -f "$TARGET_UPDATE" ]; then
            (cd "$dir" && ./update.sh $SATELLITE_ARGS)
        fi
    fi
done

echo "[Master]  🧹 CLEANING UP DOCKER SYSTEM"
docker image prune -f > /dev/null
echo ""

echo "========================================="
echo "✅ ALL SYSTEMS UPDATED SUCCESSFULLY"
echo "========================================="
