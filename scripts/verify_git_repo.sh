#!/usr/bin/env bash
# Quick check — am I in the plugin repo? / Comprobar repo correcto
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "FAIL: no es un repositorio git"
	exit 1
}

REMOTE=$(git remote get-url origin 2>/dev/null || echo "")

echo "Raíz git: $ROOT"

if [ ! -f "$ROOT/plugin.cfg" ]; then
	echo "FAIL: no hay plugin.cfg — probablemente estás en el repo del JUEGO"
	exit 1
fi

case "$REMOTE" in
	*Godot-AI-Assistant*)
		echo "OK: origin = $REMOTE"
		;;
	"")
		echo "WARN: sin remote origin (commits locales OK)"
		;;
	*)
		echo "FAIL: origin incorrecto = $REMOTE"
		exit 1
		;;
esac

echo "OK: repo del plugin Golem-AI"
