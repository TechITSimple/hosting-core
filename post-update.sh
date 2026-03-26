#!/bin/bash
# FILE: post-update.sh (inside hosting-core)

# 1. Trova la cartella dove si trova FISICAMENTE questo script (hosting-core)
# Usiamo BASH_SOURCE perché $0 punterebbe al comando globale 'tis-update'
CORE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# 2. La root dell'ambiente (es. tis-test) è la cartella superiore
ENV_DIR=$(dirname "$CORE_DIR")

echo "[Core-Hook] Propagating updated manager.sh to environment root..."

# 3. Verifica se il file esiste prima di copiare
if [ -f "$CORE_DIR/manager.sh" ]; then
    cp "$CORE_DIR/manager.sh" "$ENV_DIR/manager.sh"
    chmod +x "$ENV_DIR/manager.sh"
    echo "✅ Manager script synchronized and executable in $ENV_DIR"
else
    echo "❌ Error: manager.sh NOT FOUND in $CORE_DIR"
    exit 1
fi
