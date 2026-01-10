#!/bin/bash
set -e

VERSION_FILE="/usr/local/share/dbos-v.txt"
VERSIONE_UPDATE="0.3"
SCRIPT_PATH="$(realpath "$0")"

update() {
    echo "🔄 Aggiornamento in corso..."
    
    cat > "/usr/local/bin/dbos-message.txt" << 'EOF'
QUESTO È UN MESSAGGIO DI DEBUG 
[BY DarkBit117]
EOF
    
    echo "$VERSIONE_UPDATE" > "$VERSION_FILE"
    echo "✅ Completato!"
}

auto_delete() {
    # Crea uno script che si cancella DA SOLO
    cat > "/tmp/dbos-cleanup-$$" << EOF
#!/bin/bash
sleep 1
rm -f "$SCRIPT_PATH"
rm -f "\$0"
EOF
    chmod +x "/tmp/dbos-cleanup-$$"
    nohup "/tmp/dbos-cleanup-$$" >/dev/null 2>&1 &
    echo "🗑️  Auto-cancellazione programmata"
}

# Main
if [ -f "$VERSION_FILE" ]; then
    VERSION=$(cat "$VERSION_FILE")
    echo "📦 Installata: $VERSION | Disponibile: $VERSIONE_UPDATE"
    
    ver_installed=$(echo "$VERSION" | tr -d '.')
    ver_update=$(echo "$VERSIONE_UPDATE" | tr -d '.')
    
    if [ "$ver_installed" -lt "$ver_update" ]; then
        echo "⬆️  Update: $VERSION → $VERSIONE_UPDATE"
        update
    else
        echo "✓ Già aggiornato"
    fi
else
    echo "🎉 Prima installazione (v$VERSIONE_UPDATE)"
    mkdir -p /usr/local/share
    echo "$VERSIONE_UPDATE" > "$VERSION_FILE"
    update
fi

# Auto-cancellazione
auto_delete