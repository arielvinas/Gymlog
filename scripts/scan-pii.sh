#!/bin/bash
#
# Escaneo de datos personales y secretos. Lee el texto a revisar por STDIN.
#
# Es la ÚNICA fuente de los patrones: la usan el hook de pre-commit (que le pasa el diff a
# commitear) y el CI (que le pasa el árbol entero, por si alguien pusheó con --no-verify). Dos
# copias de esta lista se desincronizarían, y la que quedara vieja daría una falsa sensación de
# estar cubierto.
#
# Uso:
#   git diff --cached | ./scripts/scan-pii.sh
#   git ls-files -z | xargs -0 cat | ./scripts/scan-pii.sh
#
# Devuelve 1 si encuentra algo.

set -uo pipefail

texto=$(cat)
[ -z "$texto" ] && exit 0

hallazgos=0

reportar() {
    # Los nombres de variable van SIN tildes: bash no las acepta como identificadores y el script
    # revienta con "not a valid identifier". Encima falla con código 1, así que *parece* que el
    # escaneo funcionó. Un falso verde es peor que no tener escaneo.
    local titulo="$1" lineas="$2"
    echo ""
    echo "  ✘ $titulo"
    echo "$lineas" | sed 's/^/      /' | head -5
    hallazgos=$((hallazgos + 1))
}

# --- Emails personales ---
# Se permiten los dominios de ejemplo y el trailer de Claude, que son deliberados.
emails=$(echo "$texto" \
    | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
    | grep -viE '@(example|test|localhost|invalid)\.' \
    | grep -viE '^noreply@anthropic\.com$' \
    | sort -u || true)
[ -n "$emails" ] && reportar "Email personal" "$emails"

# --- UDIDs de dispositivos Apple ---
# Formato nuevo (iPhone/Watch modernos): 8 hex, guion, 16 hex.
udids=$(echo "$texto" | grep -oE '\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b' | sort -u || true)
[ -n "$udids" ] && reportar "UDID de dispositivo (formato 8-16)" "$udids"

# Formato viejo: 40 hex de corrido.
# Ojo: un SHA-1 de git también son 40 hex. En el diff de un commit normal no aparecen enteros, pero
# si esto empieza a dar falsos positivos, acá es donde hay que aflojarlo.
udids40=$(echo "$texto" | grep -oE '\b[0-9a-fA-F]{40}\b' | sort -u || true)
[ -n "$udids40" ] && reportar "UDID de dispositivo (40 hex)" "$udids40"

# --- CoreDevice IDs ---
# Son UUIDs, y los UUIDs sueltos aparecen legítimamente en el código: los tests usan constantes
# fijas y el engine genera sessionIDs. Así que NO se prohíben los UUIDs — se marca uno solo cuando
# la línea habla de un dispositivo. Un hook que grita por todo se termina ignorando, y entonces no
# sirve para nada.
coredevice=$(echo "$texto" \
    | grep -iE 'udid|coredevice|device[-_ ]?id|identifier.*device' \
    | grep -E '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
    | sort -u || true)
[ -n "$coredevice" ] && reportar "UUID en una línea que habla de un dispositivo" "$coredevice"

# --- Secretos ---
claves=$(echo "$texto" | grep -E -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' | sort -u || true)
[ -n "$claves" ] && reportar "Clave privada" "$claves"

tokens=$(echo "$texto" \
    | grep -oE '(ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|sk-[A-Za-z0-9]{32,}|AKIA[0-9A-Z]{16})' \
    | sort -u || true)
[ -n "$tokens" ] && reportar "Token / API key" "$tokens"

if [ "$hallazgos" -gt 0 ]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo " $hallazgos tipo(s) de dato sensible encontrados"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo " El repo es PÚBLICO. Una vez pusheado, sacarlo del historial es caro"
    echo " y no garantiza nada: queda en los forks, en la caché de GitHub y en"
    echo " los clones de cualquiera."
    echo ""
    echo " Para los datos de dispositivos, HANDOFF.md usa marcadores:"
    echo "   <TU-APPLE-ID>  <UDID-IPHONE>  <COREDEVICE-ID-IPHONE>"
    echo ""
    exit 1
fi

exit 0
