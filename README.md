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

When setting up a new macro-environment (e.g., `/home/tis/websites/new-env/`), clone this repository into it and perform a one-time manual bootstrap.

### 1. Configure Secrets
Navigate to the `hosting-core` directory and create your local secrets file:
```bash
cd /home/tis/websites/[environment-name]/hosting-core
cp template.env .env
nano .env
```
Add your actual Cloudflare token for this specific environment:
```ini
TUNNEL_TOKEN=your_actual_token_here
```

### 2. Manual Bootstrap
Run the following commands from inside the `hosting-core` directory to propagate the global configuration and the master script to the parent environment directory:
```bash
cp global.env ../.env
cp global.update.sh ../update.sh
chmod +x ../update.sh
```

### 3. First Execution
Move to the parent directory and start the infrastructure using the newly copied master script. This will set up the isolated network, start the Cloudflare tunnel, and update any satellites present:
```bash
cd ..
./update.sh
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
