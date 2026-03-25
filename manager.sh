#!/bin/bash
set -e

CORE_DIR=$(dirname "$(readlink -f "$0")")
MACRO_ENV=$(basename "$(dirname "$CORE_DIR")")

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
    > "$temp_env" # Create or clear temp file

    # Read template line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Keep comments and empty lines intact
        if [[ -z "$line" || "$line" == \#* ]]; then
            echo "$line" >> "$temp_env"
            continue
        fi

        # Extract Key
        local key=$(echo "$line" | cut -d '=' -f 1)
        local current_val=""

        # If .env exists, extract the current value
        if [ -f "$target_dir/.env" ]; then
            current_val=$(grep "^${key}=" "$target_dir/.env" | cut -d '=' -f 2- || true)
        fi

        # Prompt the user
        local user_val=""
        if [ -n "$current_val" ]; then
            read -p "🔑 $key [$current_val]: " user_val
            user_val="${user_val:-$current_val}" # Use current if input is empty
        else
            read -p "🔑 $key []: " user_val
        fi

        echo "${key}=${user_val}" >> "$temp_env"
    done < "$target_dir/template.env"

    # Replace old .env with the new one
    mv "$temp_env" "$target_dir/.env"
    echo "[Manager] ✅ .env file saved successfully."
}

# ---------------------------------------------------------
# COMMAND TARGET ROUTING
# ---------------------------------------------------------

do_install() {
    local repo_name=$1
    local target_dir="$CORE_DIR/../$repo_name"
    
    echo "========================================="
    echo "🚀 INSTALLING NEW SATELLITE: $repo_name"
    echo "========================================="
    
    echo "[Manager] 📥 Cloning from GitHub (TechITSimple/$repo_name)..."
    cd "$CORE_DIR/.."
    sudo -u tis git clone "git@github.com:TechITSimple/${repo_name}.git" "$repo_name"
    
    # Fix permissions so web-admins can work on it
    sudo chown -R tis:web-admins "$repo_name"
    sudo chmod -R 775 "$repo_name"

    build_env_interactively "$target_dir"

    echo "[Manager] ⚙️ Injecting managed update script..."
    cp "$CORE_DIR/update.sh" "$target_dir/update.sh"
    chmod +x "$target_dir/update.sh"

    echo "[Manager] 🚀 Delegating first deployment to satellite..."
    (cd "$target_dir" && ./update.sh --force)
}

do_edit() {
    local site_name=$1
    local target_dir="$CORE_DIR/../$site_name"
    
    echo "========================================="
    echo "✏️ EDITING CONFIG FOR: $site_name"
    echo "========================================="
    
    build_env_interactively "$target_dir"
    
    echo "[Manager] 🔄 Delegating redeployment to satellite..."
    (cd "$target_dir" && ./update.sh --force)
}

do_update_single() {
    local site_name=$1
    local force_flag=$2
    local target_dir="$CORE_DIR/../$site_name"

    echo "========================================="
    echo "🔄 UPDATING SATELLITE: $site_name"
    echo "========================================="
    
    # Sync update script just in case
    cp "$CORE_DIR/update.sh" "$target_dir/update.sh"
    chmod +x "$target_dir/update.sh"

    echo "[Manager] 🚀 Delegating update to satellite..."
    (cd "$target_dir" && ./update.sh $force_flag)
}

do_update_all() {
    local force_flag=$1
    
    echo "========================================="
    echo "🌐 TIS MASTER UPDATE-ALL ($MACRO_ENV)"
    echo "========================================="

    cd "$CORE_DIR"
    
    # 1. Update Core via Git
    local local_commit=$(git rev-parse HEAD)
    sudo -u tis git pull > /dev/null
    local remote_commit=$(git rev-parse HEAD)

    local core_args="$force_flag"
    if [ "$local_commit" != "$remote_commit" ]; then
        echo "[Manager] 📦 Core repository updated."
        core_args="--force"
    fi

    # 2. Propagate Global Env
    if [ -f "../.env" ]; then
        if ! cmp -s global.env ../.env; then
            echo "[Manager] ⚠️ Global .env changed. Forcing rebuild."
            cp global.env ../.env
            force_flag="--force"
            core_args="--force"
        fi
    else
        echo "[Manager] 🆕 Initializing global .env..."
        cp global.env ../.env
    fi

    # 3. Apply Core Updates
    echo "[Manager] 🏗️ Delegating update to Core..."
    ./update.sh $core_args

    # 4. Apply Satellite Updates
    echo "[Manager] 🚀 Delegating updates to all Satellites..."
    for dir in "$CORE_DIR"/../*/; do
        if [ "$dir" != "$CORE_DIR/" ]; then
            local sat_name=$(basename "$dir")
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

# Check if target is missing for specific commands
if [[ "$COMMAND" =~ ^(install|edit|update|force-update)$ ]] && [ -z "$TARGET" ]; then
    echo "❌ Error: You must specify a target site for the '$COMMAND' command."
    echo "Example: ./tis-manager.sh $COMMAND my-site-repo"
    exit 1
fi

# Check if target actually exists (except for install)
if [[ "$COMMAND" =~ ^(edit|update|force-update)$ ]] && [ ! -d "$CORE_DIR/../$TARGET" ]; then
    echo "❌ Error: Site '$TARGET' does not exist in this environment."
    exit 1
fi

case "$COMMAND" in
    install)
        do_install "$TARGET"
        ;;
    edit)
        do_edit "$TARGET"
        ;;
    update)
        do_update_single "$TARGET" ""
        ;;
    force-update)
        do_update_single "$TARGET" "--force"
        ;;
    update-all)
        do_update_all ""
        ;;
    force-update-all)
        do_update_all "--force"
        ;;
    *)
        echo "❌ Unknown or missing command."
        echo "Available commands:"
        echo "  install <repo>       - Clone and setup a new satellite"
        echo "  edit <site>          - Interactively edit secrets and redeploy"
        echo "  update <site>        - Standard sync and update for ONE site"
        echo "  force-update <site>  - Force rebuild ONE site"
        echo "  update-all           - Standard sync for core and ALL sites"
        echo "  force-update-all     - Force rebuild core and ALL sites"
        exit 1
        ;;
esac
