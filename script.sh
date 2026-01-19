#!/bin/bash
set -e

VERSION_FILE="/usr/local/share/dbos-v.txt"
VERSIONE_UPDATE="0.4"
SCRIPT_PATH="$(realpath "$0")"

update() {
    echo "🔄 Aggiornamento in corso..."
    
    cat > "/usr/local/bin/db" << 'EOF'
#!/bin/bash

# DB Package Manager - Unified package manager for Arch and Kali container
# Usage: db [OPERATION] [TARGET] [PACKAGE(S)]

KALI_CONTAINER="kali"
KALI_ROOT="/var/lib/machines/kali"
VERSION="1.0.0"

show_help() {
    echo "DB Package Manager v${VERSION}"
    echo "Gestore pacchetti unificato per Arch Linux e Kali (systemd-nspawn)"
    echo
    echo "UTILIZZO:"
    echo "    sudo db [OPERAZIONE] [TARGET] [PACCHETTO(I)]"
    echo
    echo "TARGET:"
    echo "    1    - Arch Linux (pacman)"
    echo "    2    - Kali container (apt in systemd-nspawn)"
    echo
    echo "OPERAZIONI:"
    echo "    -S   - Installa pacchetto/i"
    echo "    -R   - Rimuove pacchetto/i"
    echo "    -Ss  - Cerca pacchetto/i"
    echo "    -Syu - Aggiorna sistema"
    echo "    -Si  - Info pacchetto"
    echo "    -Q   - Lista pacchetti installati"
    echo "    -Qe  - Lista pacchetti installati esplicitamente"
    echo
    echo "ESEMPI:"
    echo "    sudo db -S 1 vim neofetch        # Installa vim e neofetch su Arch"
    echo "    sudo db -S 2 nmap metasploit     # Installa nmap e metasploit su Kali"
    echo "    sudo db -Ss 1 firefox            # Cerca firefox su Arch"
    echo "    sudo db -Syu 2                   # Aggiorna Kali"
    echo "    sudo db -R 1 vim                 # Rimuove vim da Arch"
    echo "    sudo db -Q 2                     # Lista pacchetti Kali"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Errore: questo script richiede privilegi root (usa sudo)"
        exit 1
    fi
}

check_container() {
    if [ ! -d "$KALI_ROOT" ] || [ ! "$(ls -A $KALI_ROOT 2>/dev/null)" ]; then
        echo "Errore: Kali rootfs non trovato in $KALI_ROOT"
        echo "Installa con: sudo dbos-setup kali"
        exit 1
    fi
}

# Operazioni Arch (pacman)
arch_install() {
    echo "[ARCH] Installazione: $@"
    pacman -S --noconfirm "$@"
}

arch_remove() {
    echo "[ARCH] Rimozione: $@"
    pacman -R --noconfirm "$@"
}

arch_search() {
    echo "[ARCH] Ricerca: $@"
    pacman -Ss "$@"
}

arch_update() {
    echo "[ARCH] Aggiornamento sistema"
    pacman -Syu --noconfirm
}

arch_info() {
    echo "[ARCH] Info pacchetto: $@"
    pacman -Si "$@"
}

arch_list() {
    echo "[ARCH] Pacchetti installati:"
    pacman -Q
}

arch_list_explicit() {
    echo "[ARCH] Pacchetti installati esplicitamente:"
    pacman -Qe
}

# Operazioni Kali (apt in container)
kali_install() {
    echo "[KALI] Installazione: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y $@
    "
}

kali_remove() {
    echo "[KALI] Rimozione: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get remove -y $@
    "
}

kali_search() {
    echo "[KALI] Ricerca: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "apt-cache search $@"
}

kali_update() {
    echo "[KALI] Aggiornamento sistema"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get upgrade -y
        apt-get dist-upgrade -y
        apt-get autoremove -y
        apt-get autoclean
    "
}

kali_info() {
    echo "[KALI] Info pacchetto: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "apt-cache show $@"
}

kali_list() {
    echo "[KALI] Pacchetti installati:"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "dpkg -l"
}

kali_list_explicit() {
    echo "[KALI] Pacchetti installati manualmente:"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "apt-mark showmanual"
}

# Main logic
main() {
    if [[ $# -lt 2 ]]; then
        show_help
        exit 1
    fi

    check_root

    OPERATION=$1
    TARGET=$2
    shift 2
    PACKAGES="$@"

    # Validazione target
    if [[ "$TARGET" != "1" && "$TARGET" != "2" ]]; then
        echo "Errore: target non valido. Usa 1 (Arch) o 2 (Kali)"
        exit 1
    fi

    # Check container se target è Kali
    if [[ "$TARGET" == "2" ]]; then
        check_container
    fi

    # Esegui operazione
    case "$OPERATION" in
        -S)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica almeno un pacchetto"
                exit 1
            fi
            [[ "$TARGET" == "1" ]] && arch_install $PACKAGES || kali_install $PACKAGES
            ;;
        -R)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica almeno un pacchetto"
                exit 1
            fi
            [[ "$TARGET" == "1" ]] && arch_remove $PACKAGES || kali_remove $PACKAGES
            ;;
        -Ss)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica un termine di ricerca"
                exit 1
            fi
            [[ "$TARGET" == "1" ]] && arch_search $PACKAGES || kali_search $PACKAGES
            ;;
        -Syu)
            [[ "$TARGET" == "1" ]] && arch_update || kali_update
            ;;
        -Si)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica un pacchetto"
                exit 1
            fi
            [[ "$TARGET" == "1" ]] && arch_info $PACKAGES || kali_info $PACKAGES
            ;;
        -Q)
            [[ "$TARGET" == "1" ]] && arch_list || kali_list
            ;;
        -Qe)
            [[ "$TARGET" == "1" ]] && arch_list_explicit || kali_list_explicit
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Errore: operazione '$OPERATION' non riconosciuta"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
EOF
    
    sudo chmod +x /usr/local/bin/db
    echo -e "\e[32m[db installed]\e[0m"

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
