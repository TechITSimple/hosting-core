# hosting-core 🚀

This repository contains the core infrastructure for the **TechItSimple (TIS)** VPS environments. It acts as the central engine for a specific "macro-environment" (e.g., Production, Testing), providing shared networking and secure connectivity via a dedicated Cloudflare Tunnel.

## 🏗 System Architecture & Isolation

To ensure maximum security and prevent conflicts, the server is divided into isolated **macro-environments** (e.g., `personal-prod`, `clients-test`). 

Each macro-environment contains its own clone of this `hosting-core` repository and its own set of satellite websites. The update scripts dynamically generate Docker network names and container prefixes based on the folder structure, ensuring that a test site can **never** accidentally interact with a production database.

### Filesystem Layout

Follow this exact structure for each environment to maintain isolation and avoid nested Git repositories:

```text
/home/tis/websites/[ENV]/  <-- e.g., personal-prod, clients-test
├── .env                      # SHARED GLOBAL CONFIG (Auto-copied from core's global.env)
├── update.sh                 # MACRO-ENV UPDATE SCRIPT (Auto-copied from core's global.update.sh)
│
├── hosting-core/             # THIS REPOSITORY (The "Engine" of the environment)
│   ├── global.env                # SHARED CONFIG TEMPLATE (Auto-copied to parent ../.env)
│   ├── global.update.sh          # MASTER SCRIPT TEMPLATE (Auto-copied to parent ../update.sh)
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

```bash
nano /home/tis/websites/setup-env.sh
```

Copy-paste the following code:
```bash
#!/bin/bash
set -e

# Check if environment name is provided
if [ -z "$1" ]; then
    echo "❌ Error: Please provide an environment name."
    echo "Usage: ./setup-env.sh <environment-name>"
    echo "Example: ./setup-env.sh clients-prod"
    exit 1
fi

ENV_NAME=$1
TARGET_DIR="/home/tis/websites/$ENV_NAME"

echo "========================================="
echo "🏗️ BOOTSTRAPPING ENVIRONMENT: $ENV_NAME"
echo "========================================="

# 1. Create the macro-environment directory
if [ -d "$TARGET_DIR" ]; then
    echo "❌ Error: Directory $TARGET_DIR already exists."
    exit 1
fi

echo "[Installer] 📁 Creating directory: $TARGET_DIR"
mkdir -p "$TARGET_DIR"

# 2. Clone the hosting-core repository
echo "[Installer] 📥 Cloning hosting-core repository..."
cd "$TARGET_DIR"
# Clone using the 'tis' service user to ensure correct SSH key usage
sudo -u tis git clone git@github.com:TechITSimple/hosting-core.git hosting-core

# 3. Apply correct ownership and permissions
echo "[Installer] 🔐 Applying permissions (tis:web-admins)..."
sudo chown -R tis:web-admins "$TARGET_DIR"
sudo chmod -R 775 "$TARGET_DIR"

# Ensure setgid bit is applied so future files inherit the web-admins group
sudo find "$TARGET_DIR" -type d -exec chmod g+s {} +

# 4. Bootstrap files to the environment root
echo "[Installer] ⚙️ Setting up manager.sh and global configs..."
cp hosting-core/global.env .env
cp hosting-core/manager.sh manager.sh
chmod +x manager.sh

# 5. Prepare the local secret template for the tunnel
echo "[Installer] 📝 Initializing tunnel configuration..."
if [ -f "hosting-core/template.env" ]; then
    cp hosting-core/template.env hosting-core/.env
fi

echo "========================================="
echo "✅ ENVIRONMENT '$ENV_NAME' READY!"
echo "========================================="
echo "Next steps:"
echo "1. cd $TARGET_DIR"
echo "2. Edit the tunnel token: nano hosting-core/.env"
echo "3. Start the core: ./manager.sh update-all"
```

and finally:
```bash
chmod +x /home/tis/websites/setup-env.sh
```

## 🚀 Quick Environment Setup

To initialize a brand new macro-environment on the VPS, use the root setup script. This will automatically create the folder, clone this repository, and set up the necessary file permissions.

```bash
cd /home/tis/websites/
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

*Note: The `update.sh` script automatically handles the injection of `${NETWORK_NAME}` and `${COMPOSE_PROJECT_NAME}` into the Docker environment before running `docker compose up`.*
