#!/usr/bin/env bash
# Install git hooks for this plugin repo / Instala hooks git del plugin
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

if [ ! -d .git ]; then
	echo "ERROR: no hay .git aquí. Ejecuta desde addons/ai_assistant_plugin/"
	echo "  git init   # solo si aún no existe repo propio"
	exit 1
fi

if [ ! -f plugin.cfg ]; then
	echo "ERROR: plugin.cfg no encontrado — ¿estás en la carpeta correcta?"
	exit 1
fi

mkdir -p .git/hooks
cp scripts/git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

echo "OK: pre-commit instalado en .git/hooks/pre-commit"
echo "    Remote actual: $(git remote get-url origin 2>/dev/null || echo '(sin origin)')"
echo "    Raíz git:      $(git rev-parse --show-toplevel)"
