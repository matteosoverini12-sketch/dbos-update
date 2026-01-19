#!/bin/bash
set -e

VERSION_FILE="/usr/local/share/dbos-v.txt"
VERSIONE_UPDATE="0.5"
SCRIPT_PATH="$(realpath "$0")"

update() {
    echo "🔄 Aggiornamento in corso..."
    sudo rm /usr/local/bin/db
    
    cat > "/usr/local/bin/db" << 'EOF'
#!/bin/bash

# DB Package Manager - Unified package manager for Arch and Kali container
# Usage: db [OPERATION] [TARGET] [PACKAGE(S)]

KALI_CONTAINER="kali"
KALI_ROOT="/var/lib/machines/kali"
VERSION="2.0.0"

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
    echo "OPERAZIONI PRINCIPALI:"
    echo "    -S      - Installa pacchetto/i"
    echo "    -R      - Rimuove pacchetto/i"
    echo "    -Rns    - Rimozione completa (con config e dipendenze)"
    echo "    -Ss     - Cerca pacchetto/i"
    echo "    -Syu    - Aggiorna sistema"
    echo "    -Si     - Info pacchetto"
    echo
    echo "QUERY PACCHETTI:"
    echo "    -Q      - Lista pacchetti installati"
    echo "    -Qe     - Lista pacchetti installati esplicitamente"
    echo "    -Ql     - Lista file di un pacchetto"
    echo "    -Qo     - Trova pacchetto che possiede un file"
    echo "    -Qdt    - Lista pacchetti orfani"
    echo
    echo "MANUTENZIONE:"
    echo "    -Sc     - Pulizia cache pacchetti"
    echo "    status  - Mostra stato del sistema"
    echo
    echo "ESEMPI:"
    echo "    sudo db -S 1 vim neofetch        # Installa vim e neofetch su Arch"
    echo "    sudo db -S 2 nmap metasploit     # Installa nmap e metasploit su Kali"
    echo "    sudo db -Ss 1 firefox            # Cerca firefox su Arch"
    echo "    sudo db -Syu 2                   # Aggiorna Kali"
    echo "    sudo db -R 1 vim                 # Rimuove vim da Arch"
    echo "    sudo db -Rns 2 nmap              # Rimuove completamente nmap da Kali"
    echo "    sudo db -Q 2                     # Lista pacchetti Kali"
    echo "    sudo db -Ql 1 vim                # Lista file di vim su Arch"
    echo "    sudo db -Qo 1 /usr/bin/vim       # Trova pacchetto che possiede vim"
    echo "    sudo db -Qdt 1                   # Lista pacchetti orfani Arch"
    echo "    sudo db -Sc 2                    # Pulisci cache Kali"
    echo "    sudo db status 1                 # Stato sistema Arch"
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

# ============================================================================
# OPERAZIONI ARCH (pacman)
# ============================================================================

arch_install() {
    echo "[ARCH] Installazione: $@"
    if ! pacman -S --noconfirm "$@"; then
        echo "Errore: installazione fallita"
        return 1
    fi
}

arch_remove() {
    echo "[ARCH] Rimozione: $@"
    if ! pacman -R --noconfirm "$@"; then
        echo "Errore: rimozione fallita"
        return 1
    fi
}

arch_purge() {
    echo "[ARCH] Rimozione completa (con dipendenze): $@"
    if ! pacman -Rns --noconfirm "$@"; then
        echo "Errore: rimozione completa fallita"
        return 1
    fi
}

arch_search() {
    echo "[ARCH] Ricerca: $@"
    pacman -Ss "$@"
}

arch_update() {
    echo "[ARCH] Aggiornamento sistema"
    if ! pacman -Syu --noconfirm; then
        echo "Errore: aggiornamento fallito"
        return 1
    fi
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

arch_list_files() {
    echo "[ARCH] File del pacchetto: $@"
    pacman -Ql "$@"
}

arch_owns() {
    echo "[ARCH] Ricerca proprietario: $@"
    pacman -Qo "$@"
}

arch_orphans() {
    echo "[ARCH] Pacchetti orfani:"
    pacman -Qdt 2>/dev/null || echo "Nessun pacchetto orfano trovato"
}

arch_clean() {
    echo "[ARCH] Pulizia cache pacchetti"
    if ! pacman -Sc --noconfirm; then
        echo "Errore: pulizia cache fallita"
        return 1
    fi
}

arch_status() {
    echo "[ARCH] Stato sistema:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Pacchetti installati: $(pacman -Q | wc -l)"
    local updates=$(pacman -Qu 2>/dev/null | wc -l)
    echo "Aggiornamenti disponibili: $updates"
    local orphans=$(pacman -Qdt 2>/dev/null | wc -l)
    echo "Pacchetti orfani: $orphans"
    echo "Cache size: $(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================================================
# OPERAZIONI KALI (apt in container)
# ============================================================================

kali_install() {
    echo "[KALI] Installazione: $@"
    if ! systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y $@
    "; then
        echo "Errore: installazione fallita"
        return 1
    fi
}

kali_remove() {
    echo "[KALI] Rimozione: $@"
    if ! systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get remove -y $@
    "; then
        echo "Errore: rimozione fallita"
        return 1
    fi
}

kali_purge() {
    echo "[KALI] Rimozione completa (con config): $@"
    if ! systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get purge -y $@
        apt-get autoremove -y
    "; then
        echo "Errore: rimozione completa fallita"
        return 1
    fi
}

kali_search() {
    echo "[KALI] Ricerca: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "apt-cache search $@"
}

kali_update() {
    echo "[KALI] Aggiornamento sistema"
    if ! systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get upgrade -y
        apt-get dist-upgrade -y
        apt-get autoremove -y
        apt-get autoclean
    "; then
        echo "Errore: aggiornamento fallito"
        return 1
    fi
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

kali_list_files() {
    echo "[KALI] File del pacchetto: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "dpkg -L $@"
}

kali_owns() {
    echo "[KALI] Ricerca proprietario: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "dpkg -S $@"
}

kali_orphans() {
    echo "[KALI] Pacchetti orfani:"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        if command -v deborphan &> /dev/null; then
            deborphan
        else
            echo 'deborphan non installato. Installa con: sudo db -S 2 deborphan'
        fi
    "
}

kali_clean() {
    echo "[KALI] Pulizia cache pacchetti"
    if ! systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        apt-get clean
        apt-get autoclean
        apt-get autoremove -y
    "; then
        echo "Errore: pulizia cache fallita"
        return 1
    fi
}

kali_status() {
    echo "[KALI] Stato sistema:"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        echo \"Pacchetti installati: \$(dpkg -l | grep ^ii | wc -l)\"
        apt-get update > /dev/null 2>&1
        updates=\$(apt list --upgradable 2>/dev/null | grep -c upgradable)
        echo \"Aggiornamenti disponibili: \$updates\"
        cache_size=\$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
        echo \"Cache size: \$cache_size\"
        echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    "
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

main() {
    if [[ $# -lt 1 ]]; then
        show_help
        exit 1
    fi

    check_root

    OPERATION=$1
    
    # Gestione comando 'status' speciale
    if [[ "$OPERATION" == "status" ]]; then
        if [[ $# -lt 2 ]]; then
            echo "Errore: specifica target (1=Arch, 2=Kali)"
            exit 1
        fi
        TARGET=$2
        if [[ "$TARGET" == "2" ]]; then
            check_container
            kali_status
        else
            arch_status
        fi
        exit 0
    fi

    if [[ $# -lt 2 ]]; then
        show_help
        exit 1
    fi

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
        -Rns)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica almeno un pacchetto"
                exit 1
            fi
            [[ "$TARGET" == "1" ]] && arch_purge $PACKAGES || kali_purge $PACKAGES
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
        -Ql)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica un pacchetto"
                exit 1
            fi
            [[ "$TARGET" == "1" ]] && arch_list_files $PACKAGES || kali_list_files $PACKAGES
            ;;
        -Qo)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica un file"
                exit 1
            fi
            [[ "$TARGET" == "1" ]] && arch_owns $PACKAGES || kali_owns $PACKAGES
            ;;
        -Qdt)
            [[ "$TARGET" == "1" ]] && arch_orphans || kali_orphans
            ;;
        -Sc)
            [[ "$TARGET" == "1" ]] && arch_clean || kali_clean
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
    echo -e "\e[32m[db v2.0.0 installed]\e[0m"

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
