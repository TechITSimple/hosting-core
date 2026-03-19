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
    ├── .env                      # SECRET CONFIG TEMPLATE (Pushed to GitHub, locally copy to .env.local and add secrets)
    ├── .env.local                # SECRET CONFIG (Manually written from .env and not pushed to GitHub)
    ├── update.sh                 # UPDATE SCRIPT
    └── docker-compose.yml        # DOCKER COMPOSE
