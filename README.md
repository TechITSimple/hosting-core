# hosting-core 🚀

This repository contains the core infrastructure for the **TechItSimple (TIS)** VPS environments. It acts as the central engine for a specific "macro-environment" (e.g., Production, Testing), providing shared networking and secure connectivity via a dedicated Cloudflare Tunnel.

## 🏗 System Architecture & Isolation

To ensure maximum security and prevent conflicts, the server is divided into isolated **macro-environments** (e.g., `personal-prod`, `clients-test`). 

Each macro-environment contains its own clone of this `hosting-core` repository and its own set of satellite websites. The update scripts dynamically generate Docker network names and container prefixes based on the folder structure, ensuring that a test site can **never** accidentally interact with a production database.

### Filesystem Layout

Follow this exact structure for each environment to maintain isolation and avoid nested Git repositories:

```text
/home/tis/websites/[ENV]/       <-- e.g., personal-prod, clients-test
├── .env                      # SHARED GLOBAL CONFIG (Auto-copied from core's global.env)
├── manager.sh                # MACRO-ENV MANAGER CLI (Auto-copied from core's manager.sh)
│
├── hosting-core/             # THIS REPOSITORY (The "Engine" of the environment)
│   ├── global.env                # SHARED CONFIG TEMPLATE (Auto-copied to parent ../.env)
│   ├── manager.sh                # MASTER SCRIPT (Auto-copied to parent ../manager.sh)
│   ├── template.env              # SECRET CONFIG TEMPLATE (Pushed to GitHub)
│   ├── .env                      # SECRET CONFIG (Manually written, ignored by Git)
│   ├── update.sh                 # CORE UPDATE SCRIPT
│   └── docker-compose.yml        # CLOUDFLARE TUNNEL & DYNAMIC NETWORK
│
└── [website-satellite]/      # WEBSITE REPOSITORY (One for each website in this env)
    ├── .gitignore                # MUST ignore .env and auto-generated update.sh
    ├── template.env              # SECRET CONFIG TEMPLATE (Pushed to GitHub)
    ├── .env                      # SECRET CONFIG (Manually written, ignored by Git)
    ├── update.sh                 # UPDATE SCRIPT (Auto-managed by the core script)
    ├── pre-update.sh             # PRE-UPDATE SCRIPT (Optional hook)
    ├── post-update.sh            # POST-UPDATE SCRIPT (Optional hook)
    └── docker-compose.yml        # WP & DB CONFIG
```

## 🔐 Secrets Management (`template.env` vs `.env`)

To prevent accidental leaks of credentials:
* **`template.env`**: Tracked by Git. Contains empty variables or safe defaults.
* **`.env`**: **Ignored by Git**. You must manually create this file by copying `template.env` and filling in the actual secrets (passwords, tokens).

## 🛠 Installation & Bootstrap

To initialize a brand new macro-environment on the VPS, use the root setup script. This will automatically create the folder, clone this repository, ask for your Cloudflare token, and set up the necessary file permissions.

Create the setup script on your server:
```bash
nano /home/tis/websites/setup-env.sh
```

Copy-paste the following code into the file:
```bash
#!/bin/bash
set -e

# Step 1: Validate input
if [ -z "$1" ]; then
    echo "Error: Please provide an environment name."
    echo "Usage: ./setup-env.sh <environment-name>"
    echo "Example: ./setup-env.sh clients-prod"
    exit 1
fi

ENV_NAME=$1
TARGET_DIR="/home/tis/websites/$ENV_NAME"

echo "========================================="
echo "🏗️ BOOTSTRAPPING ENVIRONMENT: $ENV_NAME"
echo "========================================="

# Step 2: Create directory
if [ -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR already exists."
    exit 1
fi

echo "[Installer] 📁 Creating directory: $TARGET_DIR"
mkdir -p "$TARGET_DIR"

# Step 3: Clone the core repository as 'tis' user
echo "[Installer] 📥 Cloning hosting-core repository..."
cd "$TARGET_DIR"
sudo -u tis git clone git@github.com:TechITSimple/hosting-core.git hosting-core

# Step 4: Apply permissions and setgid bit
echo "[Installer] 🔐 Applying permissions (tis:web-admins)..."
sudo chown -R tis:web-admins "$TARGET_DIR"
sudo chmod -R 775 "$TARGET_DIR"
sudo find "$TARGET_DIR" -type d -exec chmod g+s {} +

# Step 5: Bootstrap the manager and global environment file
echo "[Installer] ⚙️ Setting up manager.sh and global configs..."
cp hosting-core/global.env .env
cp hosting-core/manager.sh manager.sh
chmod +x manager.sh

# Step 6: Interactively prompt for the Tunnel Token
echo "[Installer] 📝 Configuring Cloudflare Tunnel Token..."
if [ -f "hosting-core/template.env" ]; then
    cp hosting-core/template.env hosting-core/.env
    
    read -p "🔑 Enter Cloudflare TUNNEL_TOKEN for $ENV_NAME: " tunnel_token
    sed -i "s/^TUNNEL_TOKEN=.*/TUNNEL_TOKEN=${tunnel_token}/" hosting-core/.env
    
    echo "[Installer] ✅ Token saved to hosting-core/.env."
else
    echo "[Installer] ⚠️ template.env not found in hosting-core. Skipping token setup."
fi

# Step 7: Trigger the initial update for the entire environment
echo "========================================="
echo "🚀 STARTING INITIAL DEPLOYMENT"
echo "========================================="
./manager.sh update-all
```

Make it executable and run it:
```bash
chmod +x /home/tis/websites/setup-env.sh
./setup-env.sh new-environment-name
```

## 🛰 Connecting Satellites

Because networks are generated dynamically (e.g., `personal-prod-net`), satellite `docker-compose.yml` files must reference the network using the injected `${NETWORK_NAME}` variable.

Add this at the bottom of your satellite's `docker-compose.yml`:

```yaml
networks:
  tis_proxy:
    name: ${NETWORK_NAME}
    external: true
```

and this in your satellite's `.gitignore` to prevent secret leaks and update conflicts:
```text
# Ignore secret environment variables
.env
.env.*

# Track the template for environment variables
!template.env

# Ignore the auto-generated update script managed by the core
update.sh
```

*Note: The `update.sh` script automatically handles the injection of `${NETWORK_NAME}` and `${COMPOSE_PROJECT_NAME}` into the Docker environment before running `docker compose up`.*
