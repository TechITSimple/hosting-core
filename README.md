# hosting-core 🚀

This repository contains the core infrastructure for the **TechItSimple (TIS)** VPS environment. It acts as the central hub for shared networking and secure connectivity, allowing multiple standalone services (satellites) to communicate and be exposed through a single Cloudflare Tunnel.

## 🏗 System Architecture

The infrastructure is designed to be modular. Each website or service lives in its own repository, while `hosting-core` provides the shared resources.

### Filesystem Layout
To maintain security and avoid nested Git repositories, follow this structure:

```text
/home/tis/websites/
├── .env                      # SHARED CONFIG (Automatically copied from this repo's global.env)
├── update.sh                 # UPDATE SCRIPT (Automatically copied from this repo's global.update.sh)
├── hosting-core/             # THIS REPOSITORY (Network & Tunnel)
│   ├── global.env                # SHARED CONFIG (Automatically copied to parent .env)
│   ├── global.update.sh          # UPDATE SCRIPT (Automatically copied to parent update.sh)
|   ├── .env                      # SECRET CONFIG TEMPLATE (Pushed to GitHub, locally copy to .env.local and add secrets)
|   ├── .env.local                # SECRET CONFIG (Manually written from .env and not pushed to GitHub)
|   ├── update.sh                 # UPDATE SCRIPT
│   └── docker-compose.yml        # DOCKER COMPOSE
└── [website]/                # WEBSITE REPOSITORY (One for each website)
    ├── .gitignore                # GITIGNORE (must include .env.local and update.sh)
    ├── .env                      # SECRET CONFIG TEMPLATE (Pushed to GitHub, locally copy to .env.local and add secrets)
    ├── .env.local                # SECRET CONFIG (Manually written from .env and not pushed to GitHub)
    ├── update.sh                 # UPDATE SCRIPT (Automatically copied from this repo's update.sh)
    ├── pre-update.sh             # PRE-UPDATE SCRIPT (Optional hook pre-update)
    ├── post-update.sh            # POST-UPDATE SCRIPT (Optional hook post-update)
    └── docker-compose.yml        # DOCKER COMPOSE
```

## 🛠 Installation & Bootstrap

After cloning the repository, you need to perform a one-time manual bootstrap to initialize the environment and the master update script.

### 1. Configure Secrets
Copy the provided template to create your local environment file (which is safely ignored by Git):
```bash
cp .env .env.local
nano .env.local
```
Inside the editor, add your actual Cloudflare token:
```ini
TUNNEL_TOKEN=your_actual_token_here
```

### 2. Manual Bootstrap
Run the following commands from inside the `hosting-core` directory to propagate the global configuration and the master script to the parent directory:
```bash
cp global.env ../.env
cp global.update.sh ../update.sh
chmod +x ../update.sh
```

### 3. First Execution
Move to the parent directory and start the infrastructure using the newly copied master script:
```bash
cd ..
./update.sh
```
