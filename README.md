# hosting-core 🚀

This repository contains the core infrastructure for the **TechItSimple (TIS)** VPS environment. It acts as the central hub for shared networking and secure connectivity, allowing multiple standalone services (satellites) to communicate and be exposed through a single Cloudflare Tunnel.

## 🏗 System Architecture

The infrastructure is designed to be modular. Each website or service lives in its own repository, while `hosting-core` provides the shared resources.

### Filesystem Layout
To maintain security and avoid nested Git repositories, follow this structure:

```text
/home/tis/websites/
├── global.env            # SHARED SECRETS (Manually created, NOT in Git)
├── hosting-core/         # THIS REPOSITORY (Network & Tunnel)
│   ├── .env.example      # Template for global.env
│   └── docker-compose.yml
└── [satellite-apps]/     # Other service repositories
    └── docker-compose.yml
