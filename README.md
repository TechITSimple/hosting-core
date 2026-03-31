# hosting-core 🚀

This repository contains the core infrastructure for the **TechItSimple (TIS)** VPS environments. It acts as the central engine for a specific "macro-environment" (e.g., Production, Testing), providing shared networking and secure connectivity via a dedicated Cloudflare Tunnel.

## 🏗 System Architecture & Isolation

To ensure maximum security and prevent conflicts, the server is divided into isolated **macro-environments** (e.g., `personal-prod`, `clients-test`). 

Each macro-environment contains its own clone of this `hosting-core` repository and its own set of satellite websites. The global `tis-web` CLI dynamically generates Docker network names and container prefixes based on the folder structure, ensuring that a test site can **never** accidentally interact with a production database.

### Filesystem Layout

Follow this exact structure for each environment to maintain isolation. Management is handled entirely by the global `tis-web` CLI tool:

```text
/home/tis/websites/[ENV]/       <-- e.g., personal-prod, clients-test
├── .env                      # SHARED GLOBAL CONFIG (Auto-copied from core's global.env)
│
├── hosting-core/             # THIS REPOSITORY (The "Engine" of the environment)
│   ├── global.env                # SHARED CONFIG TEMPLATE (Auto-copied to parent ../.env)
│   ├── template.env              # SECRET CONFIG TEMPLATE (Pushed to GitHub)
│   ├── .env                      # SECRET CONFIG (Auto-generated interactively, ignored by Git)
│   └── docker-compose.yml        # CLOUDFLARE TUNNEL & DYNAMIC NETWORK
│
└── [website-satellite]/      # WEBSITE REPOSITORY (One for each website in this env)
    ├── .gitignore                # MUST ignore .env
    ├── template.env              # SECRET CONFIG TEMPLATE (Pushed to GitHub)
    ├── .env                      # SECRET CONFIG (Auto-generated interactively, ignored by Git)
    ├── pre-update.sh             # PRE-UPDATE SCRIPT (Optional hook)
    ├── post-update.sh            # POST-UPDATE SCRIPT (Optional hook)
    └── docker-compose.yml        # WP & DB CONFIG
```

## 🔐 Secrets Management (`template.env` vs `.env`)

To prevent accidental leaks of credentials:
* **`template.env`**: Tracked by Git. Contains empty variables or safe defaults.
* **`.env`**: **Ignored by Git**. The `tis-web` CLI will automatically read your `template.env` and prompt you interactively to fill in the actual secrets (like the Cloudflare Tunnel token) during installation or when running `tis-web edit`.

## 🛠 Installation & Bootstrap

First, install tis-web script (https://github.com/TechITSimple/tis-web)

To initialize a brand new environment on the server, simply run:

```bash
tis-web create-env <environment-name>
```

This command will automatically:
1. Create the environment directory.
2. Clone this `hosting-core` repository.
3. Apply the correct `tis:web-admins` permissions.
4. Copy the global configuration (`global.env`).
5. Interactively prompt you for the `TUNNEL_TOKEN` and other variables.
6. Pull and start the core Docker containers.

## 🛰 Connecting Satellites

Because environments are generated and managed dynamically (e.g., `personal-prod-net`), satellite `docker-compose.yml` files must reference the container_name and network using the auto-injected `${ENV_NAME}` and `${NETWORK_NAME}` variables.

Add this to your satellite's `docker-compose.yml`:

```yaml
...
   container_name: ${ENV_NAME}_    # add here the container's name
...
networks:
  tis_proxy:
    name: ${NETWORK_NAME}
    external: true
```

And ensure this is in your satellite's `.gitignore` to prevent secret leaks:
```text
# Ignore secret environment variables
.env
.env.*

# Track the template for environment variables
!template.env
```
*Note: The `tis-web` CLI automatically handles the injection of `${NETWORK_NAME}` and `${COMPOSE_PROJECT_NAME}` into the environment before running Docker commands.*
