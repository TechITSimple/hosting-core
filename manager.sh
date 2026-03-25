#!/bin/bash
set -e

# 1. PATH RESOLUTION
# Detect if running from the environment root or inside hosting-core
REAL_SCRIPT_PATH=$(readlink -f "$0")
CURRENT_DIR_NAME=$(basename "$(dirname "$REAL_SCRIPT_PATH")")

if [ "$CURRENT_DIR_NAME" == "hosting-core" ]; then
    CORE_DIR=$(dirname "$REAL_SCRIPT_PATH")
    ENV_DIR=$(dirname "$CORE_DIR")
else
    ENV_DIR=$(dirname "$REAL_SCRIPT_PATH")
    CORE_DIR="$ENV_DIR/hosting-core"
fi

MACRO_ENV=$(basename "$ENV_DIR")

# ---------------------------------------------------------
# UTILITY: Interactive .env Builder
# ---------------------------------------------------------
build_env_interactively() {
    local target_dir=$1
    echo "[Manager] 📝 Configuring environment variables for $(basename "$target_dir")"
    
    if [ ! -f "$target_dir/template.env" ]; then
        echo "[Manager] ℹ️ No template.env found. Skipping configuration."
        return
    fi

    local temp_env="$target_dir/.env.tmp"
    > "$temp_env"

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ -z "$line" || "$line" == \#* ]]; then
            echo "$line" >> "$temp_env"
            continue
        fi

        local key=$(echo "$line" | cut -d '=' -f 1)
        local current_val=""

        if [ -f "$target_dir/.env" ]; then
            current_val=$(grep "^${key}=" "$target_dir/.env" | cut -d '=' -f 2- || true)
        fi

        local user_val=""
        # Read from /dev/tty to ensure input works inside loops
        if [ -n "$current_val" ]; then
            read -p "🔑 $key [$current_val]: " user_val < /dev/tty
            user_val="${user_val:-$current_val}"
        else
            read -p "🔑 $key []: " user_val < /dev/tty
        fi

        echo "${key}=${user_val}" >> "$temp_env"
    done < "$target_dir/template.env"

    mv "$temp_env" "$target_dir/.env"
    echo "[Manager] ✅ .env file saved successfully."
}

# ---------------------------------------------------------
# COMMAND TARGET ROUTING
# ---------------------------------------------------------

do_update_single() {
    local site_name=$1
    local force_flag=$2
    local target_dir="$ENV_DIR/$site_name"

    echo "========================================="
    echo "🔄 UPDATING SATELLITE: $site_name"
    echo "========================================="
    
    # Propagate latest update.sh and ensure it's executable
    cp "$CORE_DIR/update.sh" "$target_dir/update.sh"
    chmod +x "$target_dir/update.sh"

    # Set executable for hooks if they exist
    for hook in "pre-update.sh" "post-update.sh"; do
        if [ -f "$target_dir/$hook" ]; then
            chmod +x "$target_dir/$hook"
        fi
    done

    (cd "$target_dir" && ./update.sh $force_flag)
}

do_update_all() {
    local force_flag=$1
    
    echo "========================================="
    echo "🌐 TIS SATELLITE UPDATE-ALL ($MACRO_ENV)"
    echo "========================================="

    # 1. Update Core Logic via Git (pulls manager and update scripts)
    cd "$CORE_DIR"
    sudo -u tis git pull > /dev/null

    # 2. Propagate Global Env and Manager to environment root
    local target_env="$ENV_DIR/.env"
    if [ ! -f "$target_env" ] || ! cmp -s "$CORE_DIR/global.env" "$target_env"; then
        echo "[Manager] ⚠️ Global .env synced to root."
        cp "$CORE_DIR/global.env" "$target_env"
    fi
    
    local master_manager="$CORE_DIR/manager.sh"
    local proxy_manager="$ENV_DIR/manager.sh"
    
    if [ "$REAL_SCRIPT_PATH" != "$proxy_manager" ]; then
        echo "[Manager] 🔄 Upgrading root manager script..."
        cp "$master_manager" "$proxy_manager"
        chmod +x "$proxy_manager"
    fi

    # 3. Apply Satellite Updates (Excluding Core container update)
    echo "[Manager] 🚀 Updating all satellites..."
    for dir in "$ENV_DIR"/*/; do
        local dir_name=$(basename "$dir")
        if [ "$dir_name" != "hosting-core" ] && [ -d "$dir" ]; then
            do_update_single "$dir_name" "$force_flag"
        fi
    done

    echo "[Manager] 🧹 Cleaning up Docker system..."
    docker image prune -f > /dev/null
    echo "✅ Satellites update complete. (Core infrastructure untouched)"
}

do_install() {
    local repo_name=$1
    local target_dir="$ENV_DIR/$repo_name"
    
    echo "========================================="
    echo "🚀 INSTALLING NEW SATELLITE: $repo_name"
    echo "========================================="
    
    cd "$ENV_DIR"
    sudo -u tis git clone "git@github.com:TechITSimple/${repo_name}.git" "$repo_name"
    
    sudo chown -R tis:web-admins "$repo_name"
    sudo chmod -R 775 "$repo_name"

    build_env_interactively "$target_dir"
    
    # Use the common update logic to handle script injection and hooks
    do_update_single "$repo_name" "--force"
}

do_edit() {
    local site_name=$1
    local target_dir="$ENV_DIR/$site_name"
    
    echo "========================================="
    echo "✏️ EDITING CONFIG FOR: $site_name"
    echo "========================================="
    
    build_env_interactively "$target_dir"
    
    # Re-apply update with force to propagate .env changes
    do_update_single "$site_name" "--force"
}

# ---------------------------------------------------------
# MAIN ROUTING LOGIC
# ---------------------------------------------------------
COMMAND=$1
TARGET=$2

if [[ "$COMMAND" =~ ^(install|edit|update|force-update)$ ]] && [ -z "$TARGET" ]; then
    echo "❌ Error: You must specify a target site for the '$COMMAND' command."
    exit 1
fi

if [[ "$COMMAND" =~ ^(edit|update|force-update)$ ]] && [ ! -d "$ENV_DIR/$TARGET" ]; then
    echo "❌ Error: Site '$TARGET' does not exist in this environment."
    exit 1
fi

case "$COMMAND" in
    install)          do_update_all ""; do_install "$2" ;; # Ensure scripts are fresh before install
    edit)             do_edit "$2" ;;
    update)           do_update_single "$2" "" ;;
    force-update)     do_update_single "$2" "--force" ;;
    update-all)       do_update_all "" ;;
    force-update-all) do_update_all "--force" ;;
    *)                echo "❌ Unknown command"; exit 1 ;;
esac
