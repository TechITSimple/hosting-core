#!/bin/bash
set -e

# 1. PATH RESOLUTION (Improved Detection)
REAL_SCRIPT_PATH=$(readlink -f "$0")
CURRENT_DIR_NAME=$(basename "$(dirname "$REAL_SCRIPT_PATH")")

if [ "$CURRENT_DIR_NAME" == "hosting-core" ]; then
    # Running from MASTER (inside hosting-core)
    CORE_DIR=$(dirname "$REAL_SCRIPT_PATH")
    ENV_DIR=$(dirname "$CORE_DIR")
else
    # Running from PROXY (environment root)
    ENV_DIR=$(dirname "$REAL_SCRIPT_PATH")
    CORE_DIR="$ENV_DIR/hosting-core"
fi

MACRO_ENV=$(basename "$ENV_DIR")

# Debug per sicurezza (puoi rimuoverlo dopo il primo test)
# echo "DEBUG: CORE=$CORE_DIR | ENV=$ENV_DIR"

# Forza l'esecuzione dalla CORE_DIR per i comandi Git
cd "$CORE_DIR"

# ---------------------------------------------------------
# UTILITY: Interactive .env Builder (Fixed Stdin)
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
        # CRITICAL FIX: Redirect stdin from /dev/tty to allow user input during file read loop
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
    
    # 1. Sync and set executable for the main update script
    cp "$CORE_DIR/update.sh" "$target_dir/update.sh"
    chmod +x "$target_dir/update.sh"

    # 2. Automatically detect and set executable for local hooks if they exist
    for hook in "pre-update.sh" "post-update.sh"; do
        if [ -f "$target_dir/$hook" ]; then
            echo "[Manager] 🔗 Making hook executable: $hook"
            chmod +x "$target_dir/$hook"
        fi
    done

    # 3. Delegate execution
    (cd "$target_dir" && ./update.sh $force_flag)
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

do_update_all() {
    local force_flag=$1
    
    echo "========================================="
    echo "🌐 TIS MASTER UPDATE-ALL ($MACRO_ENV)"
    echo "========================================="

    # 1. Update Core via Git
    local local_commit=$(git rev-parse HEAD)
    sudo -u tis git pull > /dev/null
    local remote_commit=$(git rev-parse HEAD)

    local core_args="$force_flag"
    if [ "$local_commit" != "$remote_commit" ]; then
        echo "[Manager] 📦 Core repository updated."
        core_args="--force"
    fi

    # 2. Propagate Global Env and Manager to parent
    if [ -f "$ENV_DIR/.env" ]; then
        if ! cmp -s "$CORE_DIR/global.env" "$ENV_DIR/.env"; then
            echo "[Manager] ⚠️ Global .env changed. Forcing rebuild."
            cp "$CORE_DIR/global.env" "$ENV_DIR/.env"
            force_flag="--force"
            core_args="--force"
        fi
    else
        echo "[Manager] 🆕 Initializing global .env..."
        cp "$CORE_DIR/global.env" "$ENV_DIR/.env"
    fi
    
    # Sincronizza il manager.sh stesso nella cartella superiore
    cp "$REAL_SCRIPT_PATH" "$ENV_DIR/manager.sh"
    chmod +x "$ENV_DIR/manager.sh"

    # 3. Apply Core Updates
    echo "[Manager] 🏗️ Delegating update to Core..."
    ./update.sh $core_args

    # 4. Apply Satellite Updates
    echo "[Manager] 🚀 Delegating updates to all Satellites..."
    for dir in "$ENV_DIR"/*/; do
        local dir_name=$(basename "$dir")
        # SALTA la cartella hosting-core confrontando il nome della cartella
        if [ "$dir_name" != "hosting-core" ] && [ -d "$dir" ]; then
            local target_update="${dir}update.sh"
            
            cp "$CORE_DIR/update.sh" "$target_update"
            chmod +x "$target_update"

            (cd "$dir" && ./update.sh $force_flag)
        fi
    done

    echo "[Manager] 🧹 Cleaning up Docker system..."
    docker image prune -f > /dev/null
    echo "✅ Update-All complete."
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
    install)          do_install "$TARGET" ;;
    edit)             do_edit "$TARGET" ;;
    update)           do_update_single "$TARGET" "" ;;
    force-update)     do_update_single "$TARGET" "--force" ;;
    update-all)       do_update_all "" ;;
    force-update-all) do_update_all "--force" ;;
    *)
        echo "❌ Unknown command: $COMMAND"
        exit 1
        ;;
esac
