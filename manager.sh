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
# UTILITY: Smart Interactive .env Builder with Auto-Resolve
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
        local default_val=$(echo "$line" | cut -d '=' -f 2- || true)
        
        # --- AUTO-RESOLVE LOGIC ---
        # If default_val starts with $, we resolve it from already defined variables
        if [[ "$default_val" == \$* ]]; then
            local ref_key=${default_val#$}
            local resolved_val=$(grep "^${ref_key}=" "$temp_env" | cut -d '=' -f 2- || true)
            
            if [ -n "$resolved_val" ]; then
                echo "[Manager] 🔗 Auto-linked $key -> $ref_key ($resolved_val)"
                echo "${key}=${resolved_val}" >> "$temp_env"
                continue
            fi
        fi

        # Standard interactive logic
        local current_val=""
        if [ -f "$target_dir/.env" ]; then
            current_val=$(grep "^${key}=" "$target_dir/.env" | cut -d '=' -f 2- || true)
        fi

        local suggested_val="${current_val:-$default_val}"
        local user_val=""
        read -p "🔑 $key [$suggested_val]: " user_val < /dev/tty
        
        local final_val="${user_val:-$suggested_val}"
        echo "${key}=${final_val}" >> "$temp_env"
    done < "$target_dir/template.env"

    mv "$temp_env" "$target_dir/.env"
    echo "[Manager] ✅ .env file saved successfully."
}

# ---------------------------------------------------------
# SATELLITE UPDATE (With Sudo for Hooks)
# ---------------------------------------------------------
do_update_single() {
    local site_name=$1
    local force_flag=$2
    local target_dir="$ENV_DIR/$site_name"

    echo "========================================="
    echo "🔄 UPDATING SATELLITE: $site_name"
    echo "========================================="
    
    cp "$CORE_DIR/update.sh" "$target_dir/update.sh"
    sudo chmod +x "$target_dir/update.sh"

    # Use sudo for hooks as they might be owned by 'tis' user
    for hook in "pre-update.sh" "post-update.sh"; do
        if [ -f "$target_dir/$hook" ]; then
            echo "[Manager] 🔗 Setting permissions for hook: $hook"
            sudo chmod +x "$target_dir/$hook"
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

do_remove() {
    local site_name=$1
    local target_dir="$ENV_DIR/$site_name"

    if [ ! -d "$target_dir" ]; then
        echo "❌ Site '$site_name' not found in $ENV_DIR"
        exit 1
    fi

    echo "⚠️  WARNING: You are about to PERMANENTLY remove '$site_name'."
    echo "This will stop containers, delete volumes (DB data), and remove all files."
    read -p "Are you absolutely sure? [y/N]: " confirm < /dev/tty
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "❌ Aborted."
        exit 0
    fi

    echo "[Manager] 🛑 Stopping containers and removing volumes..."
    if [ -f "$target_dir/docker-compose.yml" ]; then
        (cd "$target_dir" && docker compose down -v)
    fi

    echo "[Manager] 🗑️  Deleting directory: $target_dir"
    sudo rm -rf "$target_dir"

    echo "✅ '$site_name' has been completely removed."
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
    install)          do_update_all ""; do_install "$2" ;; 
    edit)             do_edit "$2" ;;
    remove)           do_remove "$2" ;;
    update)           do_update_single "$2" "" ;;
    force-update)     do_update_single "$2" "--force" ;;
    update-all)       do_update_all "" ;;
    force-update-all) do_update_all "--force" ;;
    *)                echo "❌ Unknown command"; exit 1 ;;
esac
