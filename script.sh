#!/bin/bash
set -e

VERSION_FILE="/usr/local/share/dbos-v.txt"
VERSIONE_UPDATE="0.6"
SCRIPT_PATH="$(realpath "$0")"

install_pycompress() {
    cat > "/usr/local/bin/pycompress" << 'EOF'
#!/bin/bash

# Script wrapper per pycompress
# Copia temporaneamente pycompress.py nella directory corrente, lo esegue e poi lo rimuove

# Percorso dello script originale
ORIGINAL_SCRIPT="/usr/local/bin/pycompress.py"

# Directory di lavoro corrente
WORK_DIR="$(pwd)"

# Nome del file temporaneo nella directory corrente
TEMP_SCRIPT="$WORK_DIR/pycompress.py"

# Controlla che lo script originale esista
if [ ! -f "$ORIGINAL_SCRIPT" ]; then
    echo "Errore: $ORIGINAL_SCRIPT non trovato!"
    exit 1
fi

# Copia lo script nella directory corrente
cp "$ORIGINAL_SCRIPT" "$TEMP_SCRIPT"

# Controlla che la copia sia andata a buon fine
if [ $? -ne 0 ]; then
    echo "Errore durante la copia dello script!"
    exit 1
fi

# Esegue lo script con gli argomenti passati
python3 "$TEMP_SCRIPT" "$@"

# Salva il codice di uscita del comando python
EXIT_CODE=$?

# Rimuove lo script temporaneo
rm -f "$TEMP_SCRIPT"

# Esce con lo stesso codice di uscita del comando python
exit $EXIT_CODE
EOF

cat > "/usr/local/bin/pycompress.py" << 'EOF'
     import zipfile
import os
import sys

def pycompress(target_folder, main_file):
    # Converti in percorsi assoluti
    target_folder = os.path.abspath(target_folder)
    
    folder_name = os.path.basename(os.path.normpath(target_folder))
    zip_name = f"{folder_name}.pycomp"
    runner_name = f"{folder_name}.py"

    # Creazione iniziale dello ZIP
    with zipfile.ZipFile(zip_name, 'w', zipfile.ZIP_STORED) as zipf:
        for root, dirs, files in os.walk(target_folder):
            for file in files:
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, target_folder)
                zipf.write(file_path, arcname)
    
    # Launcher con VERSION CHECK (non download!)
    runner_content = f"""import zipfile
import os
import subprocess
import sys
import shutil
import tempfile
import platform
import re

# Percorsi assoluti basati sulla posizione dello script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
zip_file = os.path.join(SCRIPT_DIR, "{zip_name}")
main_script = "{main_file}"

def parse_python_version(req_file):
    \"\"\"Legge versione Python da requirements.txt (pyv[...])\"\"\"
    if not os.path.exists(req_file):
        return None
    with open(req_file, 'r') as f:
        for line in f:
            line = line.strip()
            match = re.match(r'pyv\\[([^\\]]+)\\]', line)
            if match:
                return match.group(1)
    return None

def parse_version_tuple(version_str):
    \"\"\"Converte '3.13.1' in (3, 13, 1)\"\"\"
    parts = version_str.split('.')
    return tuple(int(p) for p in parts if p.isdigit())

def check_python_version(requirement):
    \"\"\"Verifica se Python di sistema soddisfa i requisiti\"\"\"
    if requirement == "os":
        return True, None  # pyv[os] = accetta qualsiasi versione
    
    current = sys.version_info
    current_str = f"{{current.major}}.{{current.minor}}.{{current.micro}}"
    
    # pyv[<3.13.5] = versione deve essere < 3.13.5
    if requirement.startswith('<'):
        required_ver = parse_version_tuple(requirement[1:])
        if current[:len(required_ver)] < required_ver:
            return True, None
        else:
            return False, f"Richiede Python < {{requirement[1:]}}, hai {{current_str}}"
    
    # pyv[>3.13.5] = versione deve essere >= 3.13.5
    elif requirement.startswith('>'):
        required_ver = parse_version_tuple(requirement[1:])
        if current[:len(required_ver)] >= required_ver:
            return True, None
        else:
            return False, f"Richiede Python >= {{requirement[1:]}}, hai {{current_str}}"
    
    # pyv[3.13.1] = versione esatta (match su major.minor)
    else:
        required_ver = parse_version_tuple(requirement)
        # Match su major.minor, tollerante su micro
        if len(required_ver) >= 2:
            if current.major == required_ver[0] and current.minor == required_ver[1]:
                return True, None
            else:
                return False, f"Richiede Python {{required_ver[0]}}.{{required_ver[1]}}.x, hai {{current_str}}"
        else:
            return True, None

def save_changes_back(extract_dir):
    \"\"\"Salva modifiche nello ZIP (atomic)\"\"\"
    print(f"[*] Salvataggio modifiche...")
    temp_zip = zip_file + ".tmp"
    with zipfile.ZipFile(temp_zip, 'w', zipfile.ZIP_STORED) as zipf:
        for root, dirs, files in os.walk(extract_dir):
            for file in files:
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, extract_dir)
                zipf.write(file_path, arcname)
    # Usa os.replace invece di shutil.move per essere atomico
    os.replace(temp_zip, zip_file)

def install_deps(extract_dir):
    \"\"\"Installa dipendenze con pip (mostra output)\"\"\"
    req_file = os.path.join(extract_dir, "requirements.txt")
    if not os.path.exists(req_file):
        return
    
    # Filtra le righe pyv[...] dal requirements.txt
    temp_req = os.path.join(extract_dir, "requirements_pip.txt")
    with open(req_file, 'r') as f_in:
        with open(temp_req, 'w') as f_out:
            for line in f_in:
                # Salta righe pyv[...], vuote o commenti
                stripped = line.strip()
                if stripped and not stripped.startswith('#') and not re.match(r'pyv\\[', stripped):
                    f_out.write(line)
    
    # Controlla se ci sono pacchetti da installare
    if os.path.getsize(temp_req) == 0:
        os.remove(temp_req)
        return
    
    print("[*] Installazione dipendenze...")
    print("=" * 60)
    
    # Usa --user per installare senza permessi root se necessario
    cmd = [sys.executable, "-m", "pip", "install", "-r", temp_req]
    
    # Su Linux potrebbe servire --break-system-packages
    if platform.system() != "Windows":
        cmd.append("--break-system-packages")
    
    try:
        subprocess.check_call(cmd)
        print("=" * 60)
        print("[✓] Dipendenze installate")
    except subprocess.CalledProcessError:
        print("=" * 60)
        print("[!] ATTENZIONE: Alcune dipendenze potrebbero non essere installate")
    finally:
        # Rimuovi file temporaneo
        if os.path.exists(temp_req):
            os.remove(temp_req)

def main():
    print(f"[*] Script directory: {{SCRIPT_DIR}}")
    print(f"[*] Zip file path: {{zip_file}}")
    
    if not os.path.exists(zip_file):
        print(f"[!] Errore: {{zip_file}} non trovato")
        print(f"[!] Working directory corrente: {{os.getcwd()}}")
        sys.exit(1)
    
    extract_dir = tempfile.mkdtemp(prefix="pycomp_")
    
    try:
        # Estrazione
        print(f"[*] Estrazione...")
        with zipfile.ZipFile(zip_file, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
        
        # Legge e verifica versione Python
        req_file = os.path.join(extract_dir, "requirements.txt")
        python_requirement = parse_python_version(req_file)
        
        if python_requirement and python_requirement != "os":
            compatible, error_msg = check_python_version(python_requirement)
            
            if not compatible:
                print("=" * 60)
                print("⚠️  INCOMPATIBILITÀ VERSIONE PYTHON")
                print("=" * 60)
                print(f"\\n{{error_msg}}\\n")
                print("Questo programma potrebbe non funzionare correttamente.")
                print("\\nOpzioni:")
                print("  1. Installa la versione Python corretta")
                print("  2. Prova comunque (a tuo rischio)")
                print("=" * 60)
                
                choice = input("\\nContinuare comunque? [s/N]: ").lower()
                if choice != 's':
                    print("[*] Esecuzione annullata")
                    return
                print()
        
        # Installa dipendenze (senza venv!)
        install_deps(extract_dir)
        
        # RUN!
        print(f"\\n[*] Esecuzione {{main_script}}...")
        print("=" * 60)
        original_cwd = os.getcwd()
        os.chdir(extract_dir)
        result = subprocess.run([sys.executable, main_script])
        os.chdir(original_cwd)
        print("=" * 60)
        
    finally:
        # Salva e cleanup
        save_changes_back(extract_dir)
        print("[*] Cleanup...")
        shutil.rmtree(extract_dir, ignore_errors=True)
        print("[✓] Done!")

if __name__ == "__main__":
    main()
"""
    
    with open(runner_name, "w", encoding="utf-8") as f:
        f.write(runner_content.strip())

    print(f"✓ Creati: {zip_name} e {runner_name}")
    print(f"✓ Launcher con version check integrato!")
    print(f"\nSintassi requirements.txt:")
    print(f"  pyv[os]      → Accetta qualsiasi versione")
    print(f"  pyv[3.13.1]  → Richiede Python 3.13.x")
    print(f"  pyv[>3.11.0] → Richiede Python >= 3.11.0")
    print(f"  pyv[<3.14.0] → Richiede Python < 3.14.0")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Utilizzo: python pycompress.py <cartella_target> <file_main.py>")
    else:
        pycompress(sys.argv[1], sys.argv[2])
EOF

     sudo chmod +x /usr/local/bin/pycompress
}

install_db() {
     cat > "/usr/local/bin/db" << 'EOF'
#!/bin/bash

# DB Package Manager - Unified package manager for Arch and Kali container
# Usage: db [OPERATION] [TARGET] [PACKAGE(S)]

KALI_CONTAINER="kali"
KALI_ROOT="/var/lib/machines/kali"
VERSION="3.1.0"
LOG_FILE="/var/log/db-package-manager.log"

# Flags globali
NOCONFIRM=false
VERBOSE=false

show_help() {
    echo "DB Package Manager v${VERSION}"
    echo "Gestore pacchetti unificato per Arch Linux e Kali (systemd-nspawn)"
    echo
    echo "UTILIZZO:"
    echo "    sudo db [OPZIONI] [OPERAZIONE] [TARGET] [PACCHETTO(I)]"
    echo
    echo "TARGET:"
    echo "    1    - Arch Linux (pacman)"
    echo "    2    - Kali container (apt in systemd-nspawn)"
    echo
    echo "OPERAZIONI INSTALLAZIONE/RIMOZIONE:"
    echo "    -S      - Installa pacchetto/i"
    echo "    -R      - Rimuove pacchetto/i"
    echo "    -Rns    - Rimozione completa (con config e dipendenze)"
    echo "    -U      - Installa pacchetto locale (.pkg.tar.zst / .deb)"
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
    echo "    diff    - Confronta pacchetti tra Arch e Kali"
    echo "    fix     - Ripara dipendenze rotte"
    echo
    echo "OPZIONI GLOBALI:"
    echo "    --noconfirm    - Non chiedere conferma"
    echo "    --verbose      - Output dettagliato"
    echo
    echo "ALTRO:"
    echo "    -h, --help     - Mostra questo messaggio"
    echo "    --version      - Mostra versione"
    echo
    echo "ESEMPI:"
    echo "    sudo db -S 1 vim neofetch        # Installa vim e neofetch su Arch"
    echo "    sudo db -S 2 nmap metasploit     # Installa nmap e metasploit su Kali"
    echo "    sudo db --noconfirm -Syu 1       # Aggiorna Arch senza conferma"
    echo "    sudo db -Qu 1                    # Lista aggiornamenti disponibili Arch"
    echo "    sudo db -Qk 2 nmap               # Verifica integrità nmap su Kali"
    echo "    sudo db -D 1 package             # Marca come dipendenza"
    echo "    sudo db -De 1 package            # Marca come esplicito"
    echo "    sudo db -Scc 2                   # Pulizia completa cache Kali"
    echo "    sudo db backup 1                 # Backup pacchetti Arch"
    echo "    sudo db restore 1                # Restore pacchetti Arch"
    echo "    sudo db diff                     # Confronta sistemi"
    echo "    sudo db fix 2                    # Ripara dipendenze Kali"
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
    log_operation "ARCH: Installazione $@"
    echo "[ARCH] Installazione: $@"
    local confirm_flag=""
    [[ "$NOCONFIRM" == true ]] && confirm_flag="--noconfirm"
    if ! pacman -S $confirm_flag "$@"; then
        echo "Errore: installazione fallita"
        log_operation "ARCH: Installazione FALLITA $@"
        return 1
    fi
    log_operation "ARCH: Installazione COMPLETATA $@"
}

arch_remove() {
    log_operation "ARCH: Rimozione $@"
    echo "[ARCH] Rimozione: $@"
    local confirm_flag=""
    [[ "$NOCONFIRM" == true ]] && confirm_flag="--noconfirm"
    if ! pacman -R $confirm_flag "$@"; then
        echo "Errore: rimozione fallita"
        log_operation "ARCH: Rimozione FALLITA $@"
        return 1
    fi
    log_operation "ARCH: Rimozione COMPLETATA $@"
}

arch_purge() {
    log_operation "ARCH: Rimozione completa $@"
    echo "[ARCH] Rimozione completa (con dipendenze): $@"
    local confirm_flag=""
    [[ "$NOCONFIRM" == true ]] && confirm_flag="--noconfirm"
    if ! pacman -Rns $confirm_flag "$@"; then
        echo "Errore: rimozione completa fallita"
        log_operation "ARCH: Rimozione completa FALLITA $@"
        return 1
    fi
    log_operation "ARCH: Rimozione completa COMPLETATA $@"
}

arch_install_local() {
    log_operation "ARCH: Installazione locale $@"
    echo "[ARCH] Installazione locale: $@"
    local confirm_flag=""
    [[ "$NOCONFIRM" == true ]] && confirm_flag="--noconfirm"
    if ! pacman -U $confirm_flag "$@"; then
        echo "Errore: installazione locale fallita"
        log_operation "ARCH: Installazione locale FALLITA $@"
        return 1
    fi
    log_operation "ARCH: Installazione locale COMPLETATA $@"
}

arch_download() {
    log_operation "ARCH: Download $@"
    echo "[ARCH] Download pacchetto: $@"
    local confirm_flag=""
    [[ "$NOCONFIRM" == true ]] && confirm_flag="--noconfirm"
    if ! pacman -Sw $confirm_flag "$@"; then
        echo "Errore: download fallito"
        return 1
    fi
}

arch_search() {
    echo "[ARCH] Ricerca: $@"
    pacman -Ss "$@"
}

arch_update() {
    log_operation "ARCH: Aggiornamento sistema"
    echo "[ARCH] Aggiornamento sistema"
    local confirm_flag=""
    [[ "$NOCONFIRM" == true ]] && confirm_flag="--noconfirm"
    if ! pacman -Syu $confirm_flag; then
        echo "Errore: aggiornamento fallito"
        log_operation "ARCH: Aggiornamento FALLITO"
        return 1
    fi
    log_operation "ARCH: Aggiornamento COMPLETATO"
}

arch_refresh() {
    log_operation "ARCH: Refresh database"
    echo "[ARCH] Aggiornamento forzato database pacchetti"
    if ! pacman -Syy; then
        echo "Errore: aggiornamento database fallito"
        return 1
    fi
}

arch_upgradable() {
    echo "[ARCH] Pacchetti aggiornabili:"
    pacman -Qu
}

arch_info() {
    echo "[ARCH] Info pacchetto (repository): $@"
    pacman -Si "$@"
}

arch_info_installed() {
    echo "[ARCH] Info pacchetto installato: $@"
    pacman -Qi "$@"
}

arch_info_detailed() {
    echo "[ARCH] Info dettagliate con dipendenze: $@"
    pacman -Qii "$@"
}

arch_changelog() {
    echo "[ARCH] Changelog: $@"
    pacman -Qc "$@"
}

arch_list() {
    echo "[ARCH] Pacchetti installati:"
    pacman -Q
}

arch_list_explicit() {
    echo "[ARCH] Pacchetti installati esplicitamente:"
    pacman -Qe
}

arch_foreign() {
    echo "[ARCH] Pacchetti esterni (AUR/repos esterni):"
    pacman -Qm
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

arch_check() {
    echo "[ARCH] Verifica integrità: $@"
    pacman -Qk "$@"
}

arch_mark_dep() {
    log_operation "ARCH: Marca come dipendenza $@"
    echo "[ARCH] Marca come dipendenza: $@"
    if ! pacman -D --asdeps "$@"; then
        echo "Errore: operazione fallita"
        return 1
    fi
}

arch_mark_explicit() {
    log_operation "ARCH: Marca come esplicito $@"
    echo "[ARCH] Marca come esplicito: $@"
    if ! pacman -D --asexplicit "$@"; then
        echo "Errore: operazione fallita"
        return 1
    fi
}

arch_clean() {
    log_operation "ARCH: Pulizia cache"
    echo "[ARCH] Pulizia cache pacchetti"
    local confirm_flag=""
    [[ "$NOCONFIRM" == true ]] && confirm_flag="--noconfirm"
    if ! pacman -Sc $confirm_flag; then
        echo "Errore: pulizia cache fallita"
        return 1
    fi
}

arch_clean_all() {
    log_operation "ARCH: Pulizia completa cache"
    echo "[ARCH] Pulizia COMPLETA cache (rimuove tutto)"
    local confirm_flag=""
    [[ "$NOCONFIRM" == true ]] && confirm_flag="--noconfirm"
    if ! pacman -Scc $confirm_flag; then
        echo "Errore: pulizia completa cache fallita"
        return 1
    fi
}

arch_status() {
    echo "[ARCH] Stato sistema:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Pacchetti installati: $(pacman -Q | wc -l)"
    echo "Pacchetti espliciti: $(pacman -Qe | wc -l)"
    echo "Pacchetti esterni (AUR): $(pacman -Qm 2>/dev/null | wc -l)"
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
    log_operation "KALI: Installazione $@"
    echo "[KALI] Installazione: $@"
    if ! systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y $@
    "; then
        echo "Errore: installazione fallita"
        log_operation "KALI: Installazione FALLITA $@"
        return 1
    fi
    log_operation "KALI: Installazione COMPLETATA $@"
}

kali_remove() {
    log_operation "KALI: Rimozione $@"
    echo "[KALI] Rimozione: $@"
    if ! systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get remove -y $@
    "; then
        echo "Errore: rimozione fallita"
        log_operation "KALI: Rimozione FALLITA $@"
        return 1
    fi
    log_operation "KALI: Rimozione COMPLETATA $@"
}

kali_purge() {
    log_operation "KALI: Rimozione completa $@"
    echo "[KALI] Rimozione completa (con config): $@"
    if ! systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get purge -y $@
        apt-get autoremove -y
    "; then
        echo "Errore: rimozione completa fallita"
        log_operation "KALI: Rimozione completa FALLITA $@"
        return 1
    fi
    log_operation "KALI: Rimozione completa COMPLETATA $@"
}

kali_install_local() {
    log_operation "KALI: Installazione locale $@"
    echo "[KALI] Installazione locale: $@"
    
    # Stringa per salvare i nomi dei file
    local deb_files=""
    
    # Copia file .deb nel container (usa /root invece di /tmp)
    for pkg in "$@"; do
        # Converti percorso relativo in assoluto se necessario
        local full_path
        if [[ "$pkg" = /* ]]; then
            full_path="$pkg"
        else
            full_path="$(pwd)/$pkg"
        fi
        
        if [[ ! -f "$full_path" ]]; then
            echo "Errore: file $full_path non trovato"
            return 1
        fi
        
        local basename_file=$(basename "$full_path")
        echo "Copia $full_path → $KALI_ROOT/root/$basename_file"
        cp "$full_path" "$KALI_ROOT/root/"
        deb_files="$deb_files /root/$basename_file"
    done
    
    # Installa i pacchetti (usa percorso assoluto /root/)
    if ! systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        dpkg -i $deb_files
        apt-get install -f -y
        rm -f $deb_files
    "; then
        echo "Errore: installazione locale fallita"
        log_operation "KALI: Installazione locale FALLITA $@"
        return 1
    fi
    log_operation "KALI: Installazione locale COMPLETATA $@"
}

kali_download() {
    log_operation "KALI: Download $@"
    echo "[KALI] Download pacchetto: $@"
    if ! systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install --download-only -y $@
    "; then
        echo "Errore: download fallito"
        return 1
    fi
}

kali_search() {
    echo "[KALI] Ricerca: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "apt-cache search $@"
}

kali_update() {
    log_operation "KALI: Aggiornamento sistema"
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
        log_operation "KALI: Aggiornamento FALLITO"
        return 1
    fi
    log_operation "KALI: Aggiornamento COMPLETATO"
}

kali_refresh() {
    log_operation "KALI: Refresh database"
    echo "[KALI] Aggiornamento database pacchetti"
    if ! systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "apt-get update"; then
        echo "Errore: aggiornamento database fallito"
        return 1
    fi
}

kali_upgradable() {
    echo "[KALI] Pacchetti aggiornabili:"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        apt-get update > /dev/null 2>&1
        apt list --upgradable 2>/dev/null
    "
}

kali_info() {
    echo "[KALI] Info pacchetto (repository): $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "apt-cache show $@"
}

kali_info_installed() {
    echo "[KALI] Info pacchetto installato: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "dpkg -s $@"
}

kali_info_detailed() {
    echo "[KALI] Info dettagliate con dipendenze: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        apt-cache show $@
        echo ''
        echo '=== DIPENDENZE ==='
        apt-cache depends $@
        echo ''
        echo '=== REVERSE DEPENDENCIES ==='
        apt-cache rdepends $@
    "
}

kali_changelog() {
    echo "[KALI] Changelog: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "apt-get changelog $@"
}

kali_list() {
    echo "[KALI] Pacchetti installati:"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "dpkg -l"
}

kali_list_explicit() {
    echo "[KALI] Pacchetti installati manualmente:"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "apt-mark showmanual"
}

kali_foreign() {
    echo "[KALI] Pacchetti da sorgenti esterne:"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        aptitude search '~i!~OKali' 2>/dev/null || echo 'aptitude non installato, usa: sudo db -S 2 aptitude'
    "
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

kali_check() {
    echo "[KALI] Verifica integrità: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        if command -v debsums &> /dev/null; then
            debsums -c $@
        else
            echo 'debsums non installato. Installa con: sudo db -S 2 debsums'
        fi
    "
}

kali_mark_dep() {
    log_operation "KALI: Marca come dipendenza $@"
    echo "[KALI] Marca come automatico: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "apt-mark auto $@"
}

kali_mark_explicit() {
    log_operation "KALI: Marca come esplicito $@"
    echo "[KALI] Marca come manuale: $@"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "apt-mark manual $@"
}

kali_clean() {
    log_operation "KALI: Pulizia cache"
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

kali_clean_all() {
    log_operation "KALI: Pulizia completa cache"
    echo "[KALI] Pulizia COMPLETA cache (rimuove tutto)"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        apt-get clean
        rm -rf /var/cache/apt/archives/*
        apt-get autoremove -y --purge
    "
}

kali_fix() {
    log_operation "KALI: Fix dipendenze rotte"
    echo "[KALI] Riparazione dipendenze rotte"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -f -y
        dpkg --configure -a
        apt-get autoremove -y
    "
}

kali_status() {
    echo "[KALI] Stato sistema:"
    systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
        echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
        echo \"Pacchetti installati: \$(dpkg -l | grep ^ii | wc -l)\"
        echo \"Pacchetti manuali: \$(apt-mark showmanual | wc -l)\"
        apt-get update > /dev/null 2>&1
        updates=\$(apt list --upgradable 2>/dev/null | grep -c upgradable)
        echo \"Aggiornamenti disponibili: \$updates\"
        cache_size=\$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
        echo \"Cache size: \$cache_size\"
        echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    "
}

# ============================================================================
# FUNZIONI SPECIALI
# ============================================================================

backup_packages() {
    log_operation "Backup pacchetti target=$1"
    if [[ "$1" == "1" ]]; then
        echo "[ARCH] Backup pacchetti espliciti..."
        pacman -Qe > /root/arch-packages-$(date +%Y%m%d).txt
        echo "✓ Backup salvato in: /root/arch-packages-$(date +%Y%m%d).txt"
    else
        check_container
        echo "[KALI] Backup pacchetti manuali..."
        systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
            apt-mark showmanual > /root/kali-packages-$(date +%Y%m%d).txt
        "
        cp "$KALI_ROOT/root/kali-packages-$(date +%Y%m%d).txt" /root/
        echo "✓ Backup salvato in: /root/kali-packages-$(date +%Y%m%d).txt"
    fi
}

restore_packages() {
    log_operation "Restore pacchetti target=$1"
    if [[ "$1" == "1" ]]; then
        if [[ ! -f "$2" ]]; then
            echo "Errore: file backup non trovato: $2"
            echo "Usa: sudo db restore 1 /root/arch-packages-YYYYMMDD.txt"
            exit 1
        fi
        echo "[ARCH] Restore pacchetti da: $2"
        echo "Pacchetti da installare:"
        cat "$2" | awk '{print $1}'
        read -p "Procedere? [s/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            pacman -S --needed --noconfirm $(cat "$2" | awk '{print $1}')
            echo "✓ Restore completato"
        fi
    else
        check_container
        if [[ ! -f "$2" ]]; then
            echo "Errore: file backup non trovato: $2"
            echo "Usa: sudo db restore 2 /root/kali-packages-YYYYMMDD.txt"
            exit 1
        fi
        echo "[KALI] Restore pacchetti da: $2"
        echo "Pacchetti da installare:"
        cat "$2"
        read -p "Procedere? [s/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            cp "$2" "$KALI_ROOT/tmp/restore-packages.txt"
            systemd-nspawn --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "
                export DEBIAN_FRONTEND=noninteractive
                apt-get update
                xargs apt-get install -y < /tmp/restore-packages.txt
                rm /tmp/restore-packages.txt
            "
            echo "✓ Restore completato"
        fi
    fi
}

diff_packages() {
    log_operation "Diff pacchetti Arch vs Kali"
    echo "Confronto pacchetti tra Arch e Kali"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local arch_count=$(pacman -Q | wc -l)
    echo "Arch - Pacchetti totali: $arch_count"
    
    check_container
    local kali_count=$(systemd-nspawn --quiet --directory="$KALI_ROOT" --machine=kali-pkg /bin/bash -c "dpkg -l | grep ^ii | wc -l")
    echo "Kali - Pacchetti totali: $kali_count"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Differenza: $((arch_count - kali_count)) pacchetti"
}

arch_fix() {
    log_operation "ARCH: Fix sistema"
    echo "[ARCH] Riparazione sistema"
    pacman -Syy
    pacman -S --noconfirm archlinux-keyring
    pacman-key --populate archlinux
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

main() {
    # Array per salvare gli argomenti originali
    local ORIGINAL_ARGS=("$@")
    
    # Parse opzioni globali PRIMA di tutto
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --noconfirm)
                NOCONFIRM=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    if [[ $# -lt 1 ]]; then
        show_help
        exit 1
    fi

    # Gestione --version
    if [[ "$1" == "--version" ]]; then
        show_version
        exit 0
    fi

    check_root

    OPERATION=$1
    
    # Gestione comandi speciali
    case "$OPERATION" in
        status)
            if [[ $# -lt 2 ]]; then
                echo "Errore: specifica target (1=Arch, 2=Kali)"
                exit 1
            fi
            TARGET=$2
            if [[ "$TARGET" == "2" ]]; then
                check_container
                kali_status
            elif [[ "$TARGET" == "1" ]]; then
                arch_status
            else
                echo "Errore: target non valido"
                exit 1
            fi
            exit 0
            ;;
        backup)
            if [[ $# -lt 2 ]]; then
                echo "Errore: specifica target (1=Arch, 2=Kali)"
                exit 1
            fi
            backup_packages $2
            exit 0
            ;;
        restore)
            if [[ $# -lt 3 ]]; then
                echo "Errore: specifica target e file backup"
                echo "Uso: sudo db restore [1|2] /path/to/backup.txt"
                exit 1
            fi
            restore_packages $2 $3
            exit 0
            ;;
        diff)
            diff_packages
            exit 0
            ;;
        fix)
            if [[ $# -lt 2 ]]; then
                echo "Errore: specifica target (1=Arch, 2=Kali)"
                exit 1
            fi
            TARGET=$2
            if [[ "$TARGET" == "2" ]]; then
                check_container
                kali_fix
            elif [[ "$TARGET" == "1" ]]; then
                arch_fix
            else
                echo "Errore: target non valido"
                exit 1
            fi
            exit 0
            ;;
    esac

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
            if [[ "$TARGET" == "1" ]]; then
                arch_install $PACKAGES
            else
                kali_install $PACKAGES
            fi
            ;;
        -R)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica almeno un pacchetto"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_remove $PACKAGES
            else
                kali_remove $PACKAGES
            fi
            ;;
        -Rns)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica almeno un pacchetto"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_purge $PACKAGES
            else
                kali_purge $PACKAGES
            fi
            ;;
        -U)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica almeno un file pacchetto"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_install_local $PACKAGES
            else
                kali_install_local $PACKAGES
            fi
            ;;
        -Sw)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica almeno un pacchetto"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_download $PACKAGES
            else
                kali_download $PACKAGES
            fi
            ;;
        -Ss)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica un termine di ricerca"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_search $PACKAGES
            else
                kali_search $PACKAGES
            fi
            ;;
        -Syu)
            if [[ "$TARGET" == "1" ]]; then
                arch_update
            else
                kali_update
            fi
            ;;
        -Syy)
            if [[ "$TARGET" == "1" ]]; then
                arch_refresh
            else
                kali_refresh
            fi
            ;;
        -Qu)
            if [[ "$TARGET" == "1" ]]; then
                arch_upgradable
            else
                kali_upgradable
            fi
            ;;
        -Si)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica un pacchetto"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_info $PACKAGES
            else
                kali_info $PACKAGES
            fi
            ;;
        -Qi)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica un pacchetto"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_info_installed $PACKAGES
            else
                kali_info_installed $PACKAGES
            fi
            ;;
        -Qii)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica un pacchetto"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_info_detailed $PACKAGES
            else
                kali_info_detailed $PACKAGES
            fi
            ;;
        -Qc)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica un pacchetto"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_changelog $PACKAGES
            else
                kali_changelog $PACKAGES
            fi
            ;;
        -Q)
            if [[ "$TARGET" == "1" ]]; then
                arch_list
            else
                kali_list
            fi
            ;;
        -Qe)
            if [[ "$TARGET" == "1" ]]; then
                arch_list_explicit
            else
                kali_list_explicit
            fi
            ;;
        -Qm)
            if [[ "$TARGET" == "1" ]]; then
                arch_foreign
            else
                kali_foreign
            fi
            ;;
        -Ql)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica un pacchetto"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_list_files $PACKAGES
            else
                kali_list_files $PACKAGES
            fi
            ;;
        -Qo)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica un file"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_owns $PACKAGES
            else
                kali_owns $PACKAGES
            fi
            ;;
        -Qdt)
            if [[ "$TARGET" == "1" ]]; then
                arch_orphans
            else
                kali_orphans
            fi
            ;;
        -Qk)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica un pacchetto"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_check $PACKAGES
            else
                kali_check $PACKAGES
            fi
            ;;
        -D)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica almeno un pacchetto"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_mark_dep $PACKAGES
            else
                kali_mark_dep $PACKAGES
            fi
            ;;
        -De)
            if [[ -z "$PACKAGES" ]]; then
                echo "Errore: specifica almeno un pacchetto"
                exit 1
            fi
            if [[ "$TARGET" == "1" ]]; then
                arch_mark_explicit $PACKAGES
            else
                kali_mark_explicit $PACKAGES
            fi
            ;;
        -Sc)
            if [[ "$TARGET" == "1" ]]; then
                arch_clean
            else
                kali_clean
            fi
            ;;
        -Scc)
            if [[ "$TARGET" == "1" ]]; then
                arch_clean_all
            else
                kali_clean_all
            fi
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
}

update() { 
    echo "Aggiornamento in corso..."
    sudo rm /usr/local/bin/db
    install_db
    sudo chmod +x /usr/local/bin/db
    install_pycompress
    echo -e "\e[32m[db v3.1.0 installed]\e[0m"

    echo "$VERSIONE_UPDATE" > "$VERSION_FILE"
    echo "Completato!"
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
        install_pycompress
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
