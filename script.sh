#!/bin/bash
set -e

VERSION_FILE="/usr/local/share/dbos-v.txt"
VERSIONE_UPDATE="0.9"
SCRIPT_PATH="$(realpath "$0")"


install_db() {
     cat > "/usr/local/bin/db" << 'EOF'
#!/bin/bash

# DB Package Manager - Unified package manager for Arch, Kali, Debian, Fedora
# Usage: db [OPERATION] [TARGET] [PACKAGE(S)]

KALI_CONTAINER="kali"
KALI_ROOT="/var/lib/machines/kali"
DEBIAN_ROOT="/var/lib/machines/debian"
FEDORA_ROOT="/var/lib/machines/fedora"
VERSION="4.0.0"
LOG_FILE="/var/log/db-package-manager.log"

# Flags globali
NOCONFIRM=false
VERBOSE=false

show_help() {
    echo "DB Package Manager v${VERSION}"
    echo "Gestore pacchetti unificato per Arch Linux, Kali, Debian e Fedora (systemd-nspawn)"
    echo
    echo "UTILIZZO:"
    echo "    sudo db [OPZIONI] [OPERAZIONE] [TARGET] [PACCHETTO(I)]"
    echo
    echo "TARGET:"
    echo "    1    - Arch Linux (pacman)"
    echo "    2    - Kali container (apt)"
    echo "    3    - Debian container (apt)"
    echo "    4    - Fedora container (dnf)"
    echo
    echo "OPERAZIONI INSTALLAZIONE/RIMOZIONE:"
    echo "    -S      - Installa pacchetto/i"
    echo "    -R      - Rimuove pacchetto/i"
    echo "    -Rns    - Rimozione completa (con config e dipendenze)"
    echo "    -U      - Installa pacchetto locale (.pkg.tar.zst / .deb / .rpm)"
    echo "    -Sw     - Scarica pacchetto senza installare"
    echo
    echo "RICERCA E INFO:"
    echo "    -Ss     - Cerca pacchetto/i nei repository"
    echo "    -Si     - Info pacchetto (repository)"
    echo "    -Qi     - Info pacchetto installato"
    echo "    -Qc     - Mostra changelog pacchetto"
    echo
    echo "AGGIORNAMENTO:"
    echo "    -Syu    - Aggiorna sistema"
    echo "    -Syy    - Forza aggiornamento database pacchetti"
    echo "    -Qu     - Lista pacchetti aggiornabili"
    echo
    echo "QUERY PACCHETTI INSTALLATI:"
    echo "    -Q      - Lista tutti i pacchetti installati"
    echo "    -Qe     - Lista pacchetti installati esplicitamente"
    echo "    -Qm     - Lista pacchetti esterni (AUR/sorgenti esterne)"
    echo "    -Ql     - Lista file di un pacchetto"
    echo "    -Qo     - Trova pacchetto che possiede un file"
    echo "    -Qdt    - Lista pacchetti orfani"
    echo "    -Qk     - Verifica integrità file pacchetto"
    echo
    echo "DIPENDENZE:"
    echo "    -Qii    - Info dettagliate + dipendenze di un pacchetto"
    echo "    -D      - Marca pacchetto come dipendenza"
    echo "    -De     - Marca pacchetto come esplicito"
    echo
    echo "MANUTENZIONE:"
    echo "    -Sc     - Pulizia cache pacchetti"
    echo "    -Scc    - Pulizia COMPLETA cache (rimuove tutto)"
    echo "    status  - Mostra stato del sistema"
    echo "    backup  - Backup lista pacchetti installati"
    echo "    restore - Restore pacchetti da backup"
    echo "    diff    - Confronta pacchetti tra i sistemi"
    echo "    fix     - Ripara dipendenze rotte"
    echo
    echo "OPZIONI GLOBALI:"
    echo "    --noconfirm    - Non chiedere conferma"
    echo "    --verbose      - Output dettagliato"
    echo
    echo "ESEMPI:"
    echo "    sudo db -S 1 vim neofetch        # Installa su Arch"
    echo "    sudo db -S 2 nmap metasploit     # Installa su Kali"
    echo "    sudo db -S 3 curl wget           # Installa su Debian"
    echo "    sudo db -S 4 htop git            # Installa su Fedora"
    echo "    sudo db --noconfirm -Syu 4       # Aggiorna Fedora senza conferma"
    echo "    sudo db -Qu 3                    # Lista aggiornamenti Debian"
    echo "    sudo db status 3                 # Stato sistema Debian"
    echo "    sudo db fix 4                    # Ripara dipendenze Fedora"
    echo "    sudo db diff                     # Confronta tutti i sistemi"
}

show_version() {
    echo "DB Package Manager v${VERSION}"
    echo "Copyright (c) 2025"
    echo "Licenza: MIT"
}

log_operation() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@" >> "$LOG_FILE"
    [[ "$VERBOSE" == true ]] && echo "[LOG] $@"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Errore: questo script richiede privilegi root (usa sudo)"
        exit 1
    fi
}

check_container() {
    local root="$1"
    local name="$2"
    local setup_cmd="$3"
    if [ ! -d "$root" ] || [ ! "$(ls -A $root 2>/dev/null)" ]; then
        echo "Errore: rootfs $name non trovato in $root"
        echo "Installa con: sudo dbos-setup $setup_cmd"
        exit 1
    fi
}

# ============================================================================
# OPERAZIONI ARCH (pacman)
# ============================================================================

arch_install() {
    log_operation "ARCH: Installazione $@"
    echo "[ARCH] Installazione: $@"
    local confirm_flag=""
    [[ "$NOCONFIRM" == true ]] && confirm_flag="--noconfirm"
    pacman -S $confirm_flag "$@" || { log_operation "ARCH: Installazione FALLITA $@"; return 1; }
    log_operation "ARCH: Installazione COMPLETATA $@"
}

arch_remove() {
    log_operation "ARCH: Rimozione $@"
    echo "[ARCH] Rimozione: $@"
    local confirm_flag=""
    [[ "$NOCONFIRM" == true ]] && confirm_flag="--noconfirm"
    pacman -R $confirm_flag "$@" || { log_operation "ARCH: Rimozione FALLITA $@"; return 1; }
    log_operation "ARCH: Rimozione COMPLETATA $@"
}

arch_purge() {
    log_operation "ARCH: Rimozione completa $@"
    echo "[ARCH] Rimozione completa (con dipendenze): $@"
    local confirm_flag=""
    [[ "$NOCONFIRM" == true ]] && confirm_flag="--noconfirm"
    pacman -Rns $confirm_flag "$@" || { log_operation "ARCH: Rimozione completa FALLITA $@"; return 1; }
    log_operation "ARCH: Rimozione completa COMPLETATA $@"
}

arch_install_local() {
    log_operation "ARCH: Installazione locale $@"
    echo "[ARCH] Installazione locale: $@"
    local confirm_flag=""
    [[ "$NOCONFIRM" == true ]] && confirm_flag="--noconfirm"
    pacman -U $confirm_flag "$@" || { log_operation "ARCH: Installazione locale FALLITA $@"; return 1; }
    log_operation "ARCH: Installazione locale COMPLETATA $@"
}

arch_download() {
    echo "[ARCH] Download pacchetto: $@"
    local confirm_flag=""
    [[ "$NOCONFIRM" == true ]] && confirm_flag="--noconfirm"
    pacman -Sw $confirm_flag "$@"
}

arch_search()         { echo "[ARCH] Ricerca: $@"; pacman -Ss "$@"; }
arch_update()         { log_operation "ARCH: Aggiornamento"; echo "[ARCH] Aggiornamento sistema"; local f=""; [[ "$NOCONFIRM" == true ]] && f="--noconfirm"; pacman -Syu $f; }
arch_refresh()        { echo "[ARCH] Refresh database"; pacman -Syy; }
arch_upgradable()     { echo "[ARCH] Pacchetti aggiornabili:"; pacman -Qu; }
arch_info()           { echo "[ARCH] Info repository: $@"; pacman -Si "$@"; }
arch_info_installed() { echo "[ARCH] Info installato: $@"; pacman -Qi "$@"; }
arch_info_detailed()  { echo "[ARCH] Info dettagliate: $@"; pacman -Qii "$@"; }
arch_changelog()      { echo "[ARCH] Changelog: $@"; pacman -Qc "$@"; }
arch_list()           { echo "[ARCH] Pacchetti installati:"; pacman -Q; }
arch_list_explicit()  { echo "[ARCH] Pacchetti espliciti:"; pacman -Qe; }
arch_foreign()        { echo "[ARCH] Pacchetti esterni (AUR):"; pacman -Qm; }
arch_list_files()     { echo "[ARCH] File del pacchetto: $@"; pacman -Ql "$@"; }
arch_owns()           { echo "[ARCH] Proprietario: $@"; pacman -Qo "$@"; }
arch_orphans()        { echo "[ARCH] Pacchetti orfani:"; pacman -Qdt 2>/dev/null || echo "Nessun orfano"; }
arch_check()          { echo "[ARCH] Verifica integrità: $@"; pacman -Qk "$@"; }
arch_mark_dep()       { echo "[ARCH] Marca come dipendenza: $@"; pacman -D --asdeps "$@"; }
arch_mark_explicit()  { echo "[ARCH] Marca come esplicito: $@"; pacman -D --asexplicit "$@"; }
arch_clean()          { echo "[ARCH] Pulizia cache"; local f=""; [[ "$NOCONFIRM" == true ]] && f="--noconfirm"; pacman -Sc $f; }
arch_clean_all()      { echo "[ARCH] Pulizia COMPLETA cache"; local f=""; [[ "$NOCONFIRM" == true ]] && f="--noconfirm"; pacman -Scc $f; }
arch_fix()            { echo "[ARCH] Riparazione sistema"; pacman -Syy; pacman -S --noconfirm archlinux-keyring; pacman-key --populate archlinux; }

arch_status() {
    echo "[ARCH] Stato sistema:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Pacchetti installati: $(pacman -Q | wc -l)"
    echo "Pacchetti espliciti:  $(pacman -Qe | wc -l)"
    echo "Pacchetti AUR:        $(pacman -Qm 2>/dev/null | wc -l)"
    echo "Aggiornamenti:        $(pacman -Qu 2>/dev/null | wc -l)"
    echo "Orfani:               $(pacman -Qdt 2>/dev/null | wc -l)"
    echo "Cache:                $(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================================================
# OPERAZIONI KALI / DEBIAN (apt — funzioni condivise con root parametrico)
# ============================================================================

_apt_nspawn() {
    local root="$1"; local machine="$2"; shift 2
    systemd-nspawn --directory="$root" --machine="$machine" /bin/bash -c "$@"
}

apt_install() {
    local root="$1"; local machine="$2"; local label="$3"; shift 3
    log_operation "$label: Installazione $@"
    echo "[$label] Installazione: $@"
    _apt_nspawn "$root" "$machine" "export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y $@" \
        || { log_operation "$label: Installazione FALLITA $@"; return 1; }
    log_operation "$label: Installazione COMPLETATA $@"
}

apt_remove() {
    local root="$1"; local machine="$2"; local label="$3"; shift 3
    log_operation "$label: Rimozione $@"
    echo "[$label] Rimozione: $@"
    _apt_nspawn "$root" "$machine" "export DEBIAN_FRONTEND=noninteractive; apt-get remove -y $@" \
        || { log_operation "$label: Rimozione FALLITA $@"; return 1; }
    log_operation "$label: Rimozione COMPLETATA $@"
}

apt_purge() {
    local root="$1"; local machine="$2"; local label="$3"; shift 3
    log_operation "$label: Rimozione completa $@"
    echo "[$label] Rimozione completa: $@"
    _apt_nspawn "$root" "$machine" "export DEBIAN_FRONTEND=noninteractive; apt-get purge -y $@ && apt-get autoremove -y" \
        || { log_operation "$label: Purge FALLITA $@"; return 1; }
    log_operation "$label: Purge COMPLETATA $@"
}

apt_install_local() {
    local root="$1"; local machine="$2"; local label="$3"; shift 3
    log_operation "$label: Installazione locale $@"
    echo "[$label] Installazione locale: $@"
    local deb_files=""
    for pkg in "$@"; do
        local full_path; [[ "$pkg" = /* ]] && full_path="$pkg" || full_path="$(pwd)/$pkg"
        [[ ! -f "$full_path" ]] && { echo "Errore: file $full_path non trovato"; return 1; }
        local bname=$(basename "$full_path")
        cp "$full_path" "$root/root/"
        deb_files="$deb_files /root/$bname"
    done
    _apt_nspawn "$root" "$machine" "export DEBIAN_FRONTEND=noninteractive; dpkg -i $deb_files; apt-get install -f -y; rm -f $deb_files" \
        || { log_operation "$label: Installazione locale FALLITA"; return 1; }
    log_operation "$label: Installazione locale COMPLETATA"
}

apt_download() {
    local root="$1"; local machine="$2"; local label="$3"; shift 3
    echo "[$label] Download: $@"
    _apt_nspawn "$root" "$machine" "export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install --download-only -y $@"
}

apt_search()         { local r="$1" m="$2" l="$3"; shift 3; echo "[$l] Ricerca: $@"; _apt_nspawn "$r" "$m" "apt-cache search $@"; }
apt_update()         { local r="$1" m="$2" l="$3"; log_operation "$l: Aggiornamento"; echo "[$l] Aggiornamento"; _apt_nspawn "$r" "$m" "export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get upgrade -y && apt-get dist-upgrade -y && apt-get autoremove -y && apt-get autoclean"; }
apt_refresh()        { local r="$1" m="$2" l="$3"; echo "[$l] Refresh database"; _apt_nspawn "$r" "$m" "apt-get update"; }
apt_upgradable()     { local r="$1" m="$2" l="$3"; echo "[$l] Pacchetti aggiornabili:"; _apt_nspawn "$r" "$m" "apt-get update > /dev/null 2>&1; apt list --upgradable 2>/dev/null"; }
apt_info()           { local r="$1" m="$2" l="$3"; shift 3; echo "[$l] Info repository: $@"; _apt_nspawn "$r" "$m" "apt-cache show $@"; }
apt_info_installed() { local r="$1" m="$2" l="$3"; shift 3; echo "[$l] Info installato: $@"; _apt_nspawn "$r" "$m" "dpkg -s $@"; }
apt_info_detailed()  { local r="$1" m="$2" l="$3"; shift 3; echo "[$l] Info dettagliate: $@"; _apt_nspawn "$r" "$m" "apt-cache show $@ && echo '' && echo '=== DIPENDENZE ===' && apt-cache depends $@ && echo '' && echo '=== REVERSE ===' && apt-cache rdepends $@"; }
apt_changelog()      { local r="$1" m="$2" l="$3"; shift 3; echo "[$l] Changelog: $@"; _apt_nspawn "$r" "$m" "apt-get changelog $@"; }
apt_list()           { local r="$1" m="$2" l="$3"; echo "[$l] Pacchetti installati:"; _apt_nspawn "$r" "$m" "dpkg -l"; }
apt_list_explicit()  { local r="$1" m="$2" l="$3"; echo "[$l] Pacchetti manuali:"; _apt_nspawn "$r" "$m" "apt-mark showmanual"; }
apt_foreign()        { local r="$1" m="$2" l="$3"; echo "[$l] Pacchetti esterni:"; _apt_nspawn "$r" "$m" "aptitude search '~i!~O${l}' 2>/dev/null || echo 'aptitude non installato'"; }
apt_list_files()     { local r="$1" m="$2" l="$3"; shift 3; echo "[$l] File del pacchetto: $@"; _apt_nspawn "$r" "$m" "dpkg -L $@"; }
apt_owns()           { local r="$1" m="$2" l="$3"; shift 3; echo "[$l] Proprietario: $@"; _apt_nspawn "$r" "$m" "dpkg -S $@"; }
apt_orphans()        { local r="$1" m="$2" l="$3"; echo "[$l] Pacchetti orfani:"; _apt_nspawn "$r" "$m" "command -v deborphan &>/dev/null && deborphan || echo 'Installa deborphan: sudo db -S $TARGET deborphan'"; }
apt_check()          { local r="$1" m="$2" l="$3"; shift 3; echo "[$l] Verifica integrità: $@"; _apt_nspawn "$r" "$m" "command -v debsums &>/dev/null && debsums -c $@ || echo 'Installa debsums: sudo db -S $TARGET debsums'"; }
apt_mark_dep()       { local r="$1" m="$2" l="$3"; shift 3; echo "[$l] Marca come automatico: $@"; _apt_nspawn "$r" "$m" "apt-mark auto $@"; }
apt_mark_explicit()  { local r="$1" m="$2" l="$3"; shift 3; echo "[$l] Marca come manuale: $@"; _apt_nspawn "$r" "$m" "apt-mark manual $@"; }
apt_clean()          { local r="$1" m="$2" l="$3"; echo "[$l] Pulizia cache"; _apt_nspawn "$r" "$m" "apt-get clean && apt-get autoclean && apt-get autoremove -y"; }
apt_clean_all()      { local r="$1" m="$2" l="$3"; echo "[$l] Pulizia COMPLETA cache"; _apt_nspawn "$r" "$m" "apt-get clean && rm -rf /var/cache/apt/archives/* && apt-get autoremove -y --purge"; }
apt_fix()            { local r="$1" m="$2" l="$3"; log_operation "$l: Fix dipendenze"; echo "[$l] Riparazione dipendenze rotte"; _apt_nspawn "$r" "$m" "export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -f -y && dpkg --configure -a && apt-get autoremove -y"; }

apt_status() {
    local root="$1"; local machine="$2"; local label="$3"
    echo "[$label] Stato sistema:"
    _apt_nspawn "$root" "$machine" "
        echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        echo \"Pacchetti installati: \$(dpkg -l | grep ^ii | wc -l)\"
        echo \"Pacchetti manuali:    \$(apt-mark showmanual | wc -l)\"
        apt-get update > /dev/null 2>&1
        echo \"Aggiornamenti:        \$(apt list --upgradable 2>/dev/null | grep -c upgradable)\"
        echo \"Cache:                \$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)\"
        echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    "
}

# ============================================================================
# OPERAZIONI FEDORA (dnf)
# ============================================================================

_dnf_nspawn() {
    local root="$1"; shift
    systemd-nspawn --directory="$root" --machine=fedora-pkg /bin/bash -c "$@"
}

dnf_install() {
    log_operation "FEDORA: Installazione $@"
    echo "[FEDORA] Installazione: $@"
    local y_flag="-y"; [[ "$NOCONFIRM" == false ]] && y_flag=""
    _dnf_nspawn "$FEDORA_ROOT" "dnf install $y_flag $@" \
        || { log_operation "FEDORA: Installazione FALLITA $@"; return 1; }
    log_operation "FEDORA: Installazione COMPLETATA $@"
}

dnf_remove() {
    log_operation "FEDORA: Rimozione $@"
    echo "[FEDORA] Rimozione: $@"
    local y_flag="-y"; [[ "$NOCONFIRM" == false ]] && y_flag=""
    _dnf_nspawn "$FEDORA_ROOT" "dnf remove $y_flag $@" \
        || { log_operation "FEDORA: Rimozione FALLITA $@"; return 1; }
    log_operation "FEDORA: Rimozione COMPLETATA $@"
}

dnf_purge() {
    log_operation "FEDORA: Rimozione completa $@"
    echo "[FEDORA] Rimozione completa: $@"
    local y_flag="-y"; [[ "$NOCONFIRM" == false ]] && y_flag=""
    _dnf_nspawn "$FEDORA_ROOT" "dnf remove $y_flag $@ && dnf autoremove $y_flag" \
        || { log_operation "FEDORA: Purge FALLITA $@"; return 1; }
    log_operation "FEDORA: Purge COMPLETATA $@"
}

dnf_install_local() {
    log_operation "FEDORA: Installazione locale $@"
    echo "[FEDORA] Installazione locale: $@"
    local rpm_files=""
    for pkg in "$@"; do
        local full_path; [[ "$pkg" = /* ]] && full_path="$pkg" || full_path="$(pwd)/$pkg"
        [[ ! -f "$full_path" ]] && { echo "Errore: file $full_path non trovato"; return 1; }
        local bname=$(basename "$full_path")
        cp "$full_path" "$FEDORA_ROOT/root/"
        rpm_files="$rpm_files /root/$bname"
    done
    _dnf_nspawn "$FEDORA_ROOT" "dnf install -y $rpm_files && rm -f $rpm_files" \
        || { log_operation "FEDORA: Installazione locale FALLITA"; return 1; }
    log_operation "FEDORA: Installazione locale COMPLETATA"
}

dnf_download()       { echo "[FEDORA] Download: $@"; _dnf_nspawn "$FEDORA_ROOT" "dnf download $@"; }
dnf_search()         { echo "[FEDORA] Ricerca: $@"; _dnf_nspawn "$FEDORA_ROOT" "dnf search $@"; }
dnf_update()         { log_operation "FEDORA: Aggiornamento"; echo "[FEDORA] Aggiornamento sistema"; local y="-y"; [[ "$NOCONFIRM" == false ]] && y=""; _dnf_nspawn "$FEDORA_ROOT" "dnf update $y && dnf autoremove $y"; }
dnf_refresh()        { echo "[FEDORA] Refresh metadata"; _dnf_nspawn "$FEDORA_ROOT" "dnf makecache --refresh"; }
dnf_upgradable()     { echo "[FEDORA] Pacchetti aggiornabili:"; _dnf_nspawn "$FEDORA_ROOT" "dnf check-update; true"; }
dnf_info()           { echo "[FEDORA] Info repository: $@"; _dnf_nspawn "$FEDORA_ROOT" "dnf info $@"; }
dnf_info_installed() { echo "[FEDORA] Info installato: $@"; _dnf_nspawn "$FEDORA_ROOT" "rpm -qi $@"; }
dnf_info_detailed()  { echo "[FEDORA] Info dettagliate: $@"; _dnf_nspawn "$FEDORA_ROOT" "dnf info $@ && echo '' && echo '=== DIPENDENZE ===' && rpm -qR $@ && echo '' && echo '=== REVERSE ===' && dnf repoquery --whatrequires $@"; }
dnf_changelog()      { echo "[FEDORA] Changelog: $@"; _dnf_nspawn "$FEDORA_ROOT" "dnf changelog $@ 2>/dev/null || rpm -q --changelog $@"; }
dnf_list()           { echo "[FEDORA] Pacchetti installati:"; _dnf_nspawn "$FEDORA_ROOT" "rpm -qa --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort"; }
dnf_list_explicit()  { echo "[FEDORA] Pacchetti installati esplicitamente:"; _dnf_nspawn "$FEDORA_ROOT" "dnf repoquery --userinstalled"; }
dnf_foreign()        { echo "[FEDORA] Pacchetti da repo esterni:"; _dnf_nspawn "$FEDORA_ROOT" "dnf list extras 2>/dev/null"; }
dnf_list_files()     { echo "[FEDORA] File del pacchetto: $@"; _dnf_nspawn "$FEDORA_ROOT" "rpm -ql $@"; }
dnf_owns()           { echo "[FEDORA] Proprietario: $@"; _dnf_nspawn "$FEDORA_ROOT" "rpm -qf $@"; }
dnf_orphans()        { echo "[FEDORA] Pacchetti orfani:"; _dnf_nspawn "$FEDORA_ROOT" "dnf repoquery --unneeded"; }
dnf_check()          { echo "[FEDORA] Verifica integrità: $@"; _dnf_nspawn "$FEDORA_ROOT" "rpm -V $@"; }
dnf_mark_dep()       { echo "[FEDORA] Marca come dipendenza: $@"; _dnf_nspawn "$FEDORA_ROOT" "dnf mark remove $@"; }
dnf_mark_explicit()  { echo "[FEDORA] Marca come esplicito: $@"; _dnf_nspawn "$FEDORA_ROOT" "dnf mark install $@"; }
dnf_clean()          { echo "[FEDORA] Pulizia cache"; _dnf_nspawn "$FEDORA_ROOT" "dnf clean packages && dnf autoremove -y"; }
dnf_clean_all()      { echo "[FEDORA] Pulizia COMPLETA cache"; _dnf_nspawn "$FEDORA_ROOT" "dnf clean all && dnf autoremove -y"; }
dnf_fix()            { log_operation "FEDORA: Fix dipendenze"; echo "[FEDORA] Riparazione dipendenze rotte"; _dnf_nspawn "$FEDORA_ROOT" "dnf check && dnf distro-sync -y && rpm --rebuilddb"; }

dnf_status() {
    echo "[FEDORA] Stato sistema:"
    _dnf_nspawn "$FEDORA_ROOT" "
        echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        echo \"Pacchetti installati: \$(rpm -qa | wc -l)\"
        echo \"Aggiornamenti:        \$(dnf check-update 2>/dev/null | grep -c '^[a-zA-Z]' || true)\"
        echo \"Cache:                \$(du -sh /var/cache/dnf 2>/dev/null | cut -f1)\"
        echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    "
}

# ============================================================================
# FUNZIONI SPECIALI
# ============================================================================

backup_packages() {
    log_operation "Backup pacchetti target=$1"
    local date_str=$(date +%Y%m%d)
    case "$1" in
        1) echo "[ARCH] Backup..."; pacman -Qe > /root/arch-packages-$date_str.txt; echo "✓ /root/arch-packages-$date_str.txt" ;;
        2) check_container "$KALI_ROOT" "Kali" "kali"
           _apt_nspawn "$KALI_ROOT" "kali-pkg" "apt-mark showmanual > /root/kali-packages-$date_str.txt"
           cp "$KALI_ROOT/root/kali-packages-$date_str.txt" /root/
           echo "✓ /root/kali-packages-$date_str.txt" ;;
        3) check_container "$DEBIAN_ROOT" "Debian" "debian"
           _apt_nspawn "$DEBIAN_ROOT" "debian-pkg" "apt-mark showmanual > /root/debian-packages-$date_str.txt"
           cp "$DEBIAN_ROOT/root/debian-packages-$date_str.txt" /root/
           echo "✓ /root/debian-packages-$date_str.txt" ;;
        4) check_container "$FEDORA_ROOT" "Fedora" "fedora"
           _dnf_nspawn "$FEDORA_ROOT" "dnf repoquery --userinstalled --queryformat '%{name}' > /root/fedora-packages-$date_str.txt"
           cp "$FEDORA_ROOT/root/fedora-packages-$date_str.txt" /root/
           echo "✓ /root/fedora-packages-$date_str.txt" ;;
        *) echo "Errore: target non valido (1=Arch, 2=Kali, 3=Debian, 4=Fedora)"; exit 1 ;;
    esac
}

restore_packages() {
    log_operation "Restore pacchetti target=$1"
    [[ ! -f "$2" ]] && { echo "Errore: file backup non trovato: $2"; exit 1; }
    echo "Pacchetti da installare:"; cat "$2"
    read -p "Procedere? [s/N] " -n 1 -r; echo
    [[ ! $REPLY =~ ^[Ss]$ ]] && { echo "Annullato"; exit 0; }
    case "$1" in
        1) pacman -S --needed --noconfirm $(cat "$2" | awk '{print $1}') ;;
        2) check_container "$KALI_ROOT" "Kali" "kali"
           cp "$2" "$KALI_ROOT/tmp/restore.txt"
           _apt_nspawn "$KALI_ROOT" "kali-pkg" "export DEBIAN_FRONTEND=noninteractive; apt-get update && xargs apt-get install -y < /tmp/restore.txt && rm /tmp/restore.txt" ;;
        3) check_container "$DEBIAN_ROOT" "Debian" "debian"
           cp "$2" "$DEBIAN_ROOT/tmp/restore.txt"
           _apt_nspawn "$DEBIAN_ROOT" "debian-pkg" "export DEBIAN_FRONTEND=noninteractive; apt-get update && xargs apt-get install -y < /tmp/restore.txt && rm /tmp/restore.txt" ;;
        4) check_container "$FEDORA_ROOT" "Fedora" "fedora"
           cp "$2" "$FEDORA_ROOT/tmp/restore.txt"
           _dnf_nspawn "$FEDORA_ROOT" "xargs dnf install -y < /tmp/restore.txt && rm /tmp/restore.txt" ;;
        *) echo "Errore: target non valido"; exit 1 ;;
    esac
    echo "✓ Restore completato"
}

diff_packages() {
    log_operation "Diff pacchetti"
    echo "Confronto pacchetti tra i sistemi installati"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Arch:   $(pacman -Q | wc -l) pacchetti"
    [ -d "$KALI_ROOT" ]   && echo "Kali:   $(systemd-nspawn --quiet --directory="$KALI_ROOT"   --machine=kali-diff   /bin/bash -c "dpkg -l | grep ^ii | wc -l" 2>/dev/null) pacchetti" || echo "Kali:   non installato"
    [ -d "$DEBIAN_ROOT" ] && echo "Debian: $(systemd-nspawn --quiet --directory="$DEBIAN_ROOT" --machine=debian-diff /bin/bash -c "dpkg -l | grep ^ii | wc -l" 2>/dev/null) pacchetti" || echo "Debian: non installato"
    [ -d "$FEDORA_ROOT" ] && echo "Fedora: $(systemd-nspawn --quiet --directory="$FEDORA_ROOT" --machine=fedora-diff /bin/bash -c "rpm -qa | wc -l" 2>/dev/null) pacchetti"           || echo "Fedora: non installato"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================================================
# HELPER: mappa TARGET → parametri
# ============================================================================

get_target_params() {
    case "$1" in
        1) echo "arch" ;;
        2) echo "apt $KALI_ROOT kali-pkg KALI" ;;
        3) echo "apt $DEBIAN_ROOT debian-pkg DEBIAN" ;;
        4) echo "dnf" ;;
        *) echo "invalid" ;;
    esac
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --noconfirm) NOCONFIRM=true; shift ;;
            --verbose)   VERBOSE=true;   shift ;;
            *) break ;;
        esac
    done

    [[ $# -lt 1 ]] && { show_help; exit 1; }
    [[ "$1" == "--version" ]] && { show_version; exit 0; }

    check_root

    OPERATION=$1

    # Comandi speciali (non richiedono TARGET come secondo argomento)
    case "$OPERATION" in
        status|fix)
            [[ $# -lt 2 ]] && { echo "Errore: specifica target (1=Arch, 2=Kali, 3=Debian, 4=Fedora)"; exit 1; }
            TARGET=$2
            case "$TARGET" in
                1) [[ "$OPERATION" == "status" ]] && arch_status  || arch_fix ;;
                2) check_container "$KALI_ROOT"   "Kali"   "kali";   [[ "$OPERATION" == "status" ]] && apt_status  "$KALI_ROOT"   "kali-pkg"   "KALI"   || apt_fix  "$KALI_ROOT"   "kali-pkg"   "KALI"   ;;
                3) check_container "$DEBIAN_ROOT" "Debian" "debian"; [[ "$OPERATION" == "status" ]] && apt_status  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" || apt_fix  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" ;;
                4) check_container "$FEDORA_ROOT" "Fedora" "fedora"; [[ "$OPERATION" == "status" ]] && dnf_status  || dnf_fix ;;
                *) echo "Errore: target non valido"; exit 1 ;;
            esac
            exit 0 ;;
        backup)
            [[ $# -lt 2 ]] && { echo "Errore: specifica target"; exit 1; }
            backup_packages $2; exit 0 ;;
        restore)
            [[ $# -lt 3 ]] && { echo "Uso: sudo db restore [1|2|3|4] /path/backup.txt"; exit 1; }
            restore_packages $2 $3; exit 0 ;;
        diff) diff_packages; exit 0 ;;
        -h|--help) show_help; exit 0 ;;
    esac

    [[ $# -lt 2 ]] && { show_help; exit 1; }
    TARGET=$2
    shift 2
    PACKAGES="$@"

    # Validazione e check container
    case "$TARGET" in
        1) ;;
        2) check_container "$KALI_ROOT"   "Kali"   "kali"   ;;
        3) check_container "$DEBIAN_ROOT" "Debian" "debian" ;;
        4) check_container "$FEDORA_ROOT" "Fedora" "fedora" ;;
        *) echo "Errore: target non valido. Usa 1 (Arch), 2 (Kali), 3 (Debian), 4 (Fedora)"; exit 1 ;;
    esac

    # Dispatch operazione
    case "$OPERATION" in
        -S)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica almeno un pacchetto"; exit 1; }
            case "$TARGET" in
                1) arch_install $PACKAGES ;;
                2) apt_install  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_install  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_install  $PACKAGES ;;
            esac ;;
        -R)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica almeno un pacchetto"; exit 1; }
            case "$TARGET" in
                1) arch_remove $PACKAGES ;;
                2) apt_remove  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_remove  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_remove  $PACKAGES ;;
            esac ;;
        -Rns)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica almeno un pacchetto"; exit 1; }
            case "$TARGET" in
                1) arch_purge $PACKAGES ;;
                2) apt_purge  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_purge  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_purge  $PACKAGES ;;
            esac ;;
        -U)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica almeno un file"; exit 1; }
            case "$TARGET" in
                1) arch_install_local $PACKAGES ;;
                2) apt_install_local  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_install_local  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_install_local  $PACKAGES ;;
            esac ;;
        -Sw)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica almeno un pacchetto"; exit 1; }
            case "$TARGET" in
                1) arch_download $PACKAGES ;;
                2) apt_download  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_download  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_download  $PACKAGES ;;
            esac ;;
        -Ss)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica un termine di ricerca"; exit 1; }
            case "$TARGET" in
                1) arch_search $PACKAGES ;;
                2) apt_search  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_search  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_search  $PACKAGES ;;
            esac ;;
        -Syu)
            case "$TARGET" in
                1) arch_update ;;
                2) apt_update  "$KALI_ROOT"   "kali-pkg"   "KALI"   ;;
                3) apt_update  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" ;;
                4) dnf_update  ;;
            esac ;;
        -Syy)
            case "$TARGET" in
                1) arch_refresh ;;
                2) apt_refresh  "$KALI_ROOT"   "kali-pkg"   "KALI"   ;;
                3) apt_refresh  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" ;;
                4) dnf_refresh  ;;
            esac ;;
        -Qu)
            case "$TARGET" in
                1) arch_upgradable ;;
                2) apt_upgradable  "$KALI_ROOT"   "kali-pkg"   "KALI"   ;;
                3) apt_upgradable  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" ;;
                4) dnf_upgradable  ;;
            esac ;;
        -Si)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica un pacchetto"; exit 1; }
            case "$TARGET" in
                1) arch_info $PACKAGES ;;
                2) apt_info  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_info  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_info  $PACKAGES ;;
            esac ;;
        -Qi)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica un pacchetto"; exit 1; }
            case "$TARGET" in
                1) arch_info_installed $PACKAGES ;;
                2) apt_info_installed  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_info_installed  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_info_installed  $PACKAGES ;;
            esac ;;
        -Qii)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica un pacchetto"; exit 1; }
            case "$TARGET" in
                1) arch_info_detailed $PACKAGES ;;
                2) apt_info_detailed  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_info_detailed  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_info_detailed  $PACKAGES ;;
            esac ;;
        -Qc)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica un pacchetto"; exit 1; }
            case "$TARGET" in
                1) arch_changelog $PACKAGES ;;
                2) apt_changelog  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_changelog  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_changelog  $PACKAGES ;;
            esac ;;
        -Q)
            case "$TARGET" in
                1) arch_list ;;
                2) apt_list  "$KALI_ROOT"   "kali-pkg"   "KALI"   ;;
                3) apt_list  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" ;;
                4) dnf_list  ;;
            esac ;;
        -Qe)
            case "$TARGET" in
                1) arch_list_explicit ;;
                2) apt_list_explicit  "$KALI_ROOT"   "kali-pkg"   "KALI"   ;;
                3) apt_list_explicit  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" ;;
                4) dnf_list_explicit  ;;
            esac ;;
        -Qm)
            case "$TARGET" in
                1) arch_foreign ;;
                2) apt_foreign  "$KALI_ROOT"   "kali-pkg"   "KALI"   ;;
                3) apt_foreign  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" ;;
                4) dnf_foreign  ;;
            esac ;;
        -Ql)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica un pacchetto"; exit 1; }
            case "$TARGET" in
                1) arch_list_files $PACKAGES ;;
                2) apt_list_files  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_list_files  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_list_files  $PACKAGES ;;
            esac ;;
        -Qo)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica un file"; exit 1; }
            case "$TARGET" in
                1) arch_owns $PACKAGES ;;
                2) apt_owns  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_owns  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_owns  $PACKAGES ;;
            esac ;;
        -Qdt)
            case "$TARGET" in
                1) arch_orphans ;;
                2) apt_orphans  "$KALI_ROOT"   "kali-pkg"   "KALI"   ;;
                3) apt_orphans  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" ;;
                4) dnf_orphans  ;;
            esac ;;
        -Qk)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica un pacchetto"; exit 1; }
            case "$TARGET" in
                1) arch_check $PACKAGES ;;
                2) apt_check  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_check  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_check  $PACKAGES ;;
            esac ;;
        -D)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica almeno un pacchetto"; exit 1; }
            case "$TARGET" in
                1) arch_mark_dep $PACKAGES ;;
                2) apt_mark_dep  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_mark_dep  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_mark_dep  $PACKAGES ;;
            esac ;;
        -De)
            [[ -z "$PACKAGES" ]] && { echo "Errore: specifica almeno un pacchetto"; exit 1; }
            case "$TARGET" in
                1) arch_mark_explicit $PACKAGES ;;
                2) apt_mark_explicit  "$KALI_ROOT"   "kali-pkg"   "KALI"   $PACKAGES ;;
                3) apt_mark_explicit  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" $PACKAGES ;;
                4) dnf_mark_explicit  $PACKAGES ;;
            esac ;;
        -Sc)
            case "$TARGET" in
                1) arch_clean ;;
                2) apt_clean  "$KALI_ROOT"   "kali-pkg"   "KALI"   ;;
                3) apt_clean  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" ;;
                4) dnf_clean  ;;
            esac ;;
        -Scc)
            case "$TARGET" in
                1) arch_clean_all ;;
                2) apt_clean_all  "$KALI_ROOT"   "kali-pkg"   "KALI"   ;;
                3) apt_clean_all  "$DEBIAN_ROOT" "debian-pkg" "DEBIAN" ;;
                4) dnf_clean_all  ;;
            esac ;;
        *)
            echo "Errore: operazione '$OPERATION' non riconosciuta"
            show_help; exit 1 ;;
    esac
}

main "$@"
EOF
    
    sudo chmod +x /usr/local/bin/db
    echo -e "\e[32m[db installed]\e[0m"
}

update() { 
    echo "Aggiornamento in corso..."
    if [ -f "/usr/local/bin/db" ]; then          
        sudo rm /usr/local/bin/db                 
        echo -e "\e[32m[old db removed]\e[0m"
    fi                                            
    install_db
    sudo chmod +x /usr/local/bin/db
    sudo curl -o /usr/local/bin/edit https://raw.githubusercontent.com/matteosoverini12-sketch/edit/main/edit
    sudo chmod +x /usr/local/bin/edit
    echo -e "\e[32m[db v5.0.0 installed]\e[0m"
    echo "$VERSIONE_UPDATE" > "$VERSION_FILE"
    echo "Completato!"
}    

auto_delete() {
    local script="$SCRIPT_PATH"
    local cleanup="/tmp/dbos-cleanup-$$"
    cat > "$cleanup" << EOF
#!/bin/bash
sleep 1
rm -f "$script"
rm -f "\$0"
EOF
    chmod +x "$cleanup"
    nohup "$cleanup" >/dev/null 2>&1 &
    echo "Auto-cancellazione programmata"
}

# Main
if [ -f "$VERSION_FILE" ]; then
    VERSION=$(cat "$VERSION_FILE")
    echo "Installata: $VERSION | Disponibile: $VERSIONE_UPDATE"
    
    ver_installed=$(echo "$VERSION" | tr -d '.')
    ver_update=$(echo "$VERSIONE_UPDATE" | tr -d '.')
    
    if [ "$ver_installed" -lt "$ver_update" ]; then
        echo "Update: $VERSION → $VERSIONE_UPDATE"
        update
        if [ -f "/usr/local/bin/pycompress.py" ]; then
            sudo rm /usr/local/bin/pycompress.py
            sudo rm /usr/local/bin/pycompress
        else
            echo " "
        fi
    else
        echo "Già aggiornato"
    fi
else
    echo "Prima installazione (v$VERSIONE_UPDATE)"
    mkdir -p /usr/local/share
    echo "$VERSIONE_UPDATE" > "$VERSION_FILE"
    install_db 
fi

# Auto-cancellazione
auto_delete
