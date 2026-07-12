#!/bin/bash
#
# Instala los git hooks del repo.
#
# Los hooks viven en .githooks/ (versionados, revisables) en vez de en .git/hooks/ (que no se
# commitea y se pierde al clonar). `core.hooksPath` le dice a git que los busque ahí.
#
# Uso:  ./scripts/setup-hooks.sh

set -euo pipefail

RAIZ=$(git rev-parse --show-toplevel)
cd "$RAIZ"

chmod +x .githooks/*
git config core.hooksPath .githooks

echo "✔ Hooks instalados (core.hooksPath = .githooks)"
echo ""
echo "  pre-commit  escaneo de datos personales y secretos   (< 2 s)"
echo "  pre-push    tests unitarios + integración            (~40 s)"
echo ""
echo "Para desactivarlos:  git config --unset core.hooksPath"
