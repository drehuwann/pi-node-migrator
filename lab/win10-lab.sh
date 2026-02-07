#!/bin/bash
set -e

###############################################
#  CONFIGURATION — URLs DES FICHIERS À FETCH  #
###############################################
VIRTIO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso"

###############################################
#  NOMS DES FICHIERS LOCAUX                   #
###############################################
WIN_ISO="Win10.iso"
# Cherche un fichier virtio-win*.iso dans le dossier courant
VIRTIO_ISO=$(ls virtio-win*.iso 2>/dev/null | head -n 1)
QCOW2="win10.qcow2"
OPTIMIZE_ISO="optimize.iso"
OPTIMIZE_PS1="optimWin/optimWinQcow.ps1"
BASENAME_OPTIMIZE=$(basename "$OPTIMIZE_PS1")
FIX_OOBE="optimWin/fix-oobe.cmd"
RUN_FIX_OOBE="optimWin/run-fix-oobe.cmd"

####################################################
#  test availability of <ARG> in path. exit if not #
####################################################
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Error: required command '$1' not found in PATH." >&2
        exit 1
    }
}

##################################################
# check ovmf presence and put its path in stdout #
##################################################
detect_ovmf() {
  for dir in \
    /usr/share/OVMF \
    /usr/share/edk2-ovmf \
    /usr/share/edk2/ovmf \
    /usr/share/qemu \
  ; do
        if [ -r "$dir/OVMF_CODE.fd" ] && [ -r "$dir/OVMF_VARS.fd" ]; then
            echo "$dir"
            return 0
        fi
    done
    return 1
}

###############################################
#  FONCTION : CHECK + DOWNLOAD                #
###############################################
fetch_if_missing() {
    local file="$1"
    local url="$2"

    if [[ -f "$file" ]]; then
        echo "[OK] $file présent"
    else
        if [[ $file == $WIN_ISO ]]; then
            get_win10_iso
        else 
            echo "[DL] Téléchargement de $file..."
            wget -O "$file" "$url"
        fi
    fi
}

###############################################
#  FONCTION : CHECK DU DISQUE QCOW2           #
###############################################
# Retourne :
#   0 = OK (existe + valide)
#   1 = absent
#   2 = corrompu
###############################################
check_qcow2() {
    local file="win10.qcow2"
    if [[ ! -f "$file" ]]; then
        QCOW2_STATUS=1
        return 1
    fi
    if qemu-img check "$file" >/dev/null 2>&1; then
        QCOW2_STATUS=0
        return 0
    else
        QCOW2_STATUS=2
        return 2
    fi
}

get_win10_iso() {
    echo "=== Windows 10 ISO requis ==="
    echo "Microsoft ne permet plus le téléchargement automatisé de Windows 10."
    echo "Veuillez télécharger manuellement l'ISO Windows 10 22H2 (x64, FR) depuis une source officielle."
    echo "Placez ensuite le fichier dans ce dossier sous le nom : Win10.iso"
    exit 1
}

###############################################
# ÉTAPE 0 — VERIFICATION DES DEPENDANCES      #
###############################################
require_cmd qemu-system-x86_64
require_cmd qemu-img
if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    echo "Error: need either 'wget' or 'curl' for downloads." >&2
    exit 1
fi
OVMF_DIR="$(detect_ovmf || true)"
if [ -z "$OVMF_DIR" ]; then
    echo "Error: could not find OVMF_CODE.fd and OVMF_VARS.fd in common locations." >&2
    echo "Hint: install OVMF/edk2-ovmf (e.g. on Gentoo: emerge --ask sys-firmware/edk2-ovmf)." >&2
    exit 1
fi
# Definitions issues de la verif dependances
OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
if [[ ! -f OVMFVARS.fd ]]; then
    OVMF_VARS="./OVMF_VARS.fd"
    cp "$OVMF_DIR/OVMF_VARS.fd" "$OVMF_VARS"
fi

###############################################
#  ÉTAPE 1 — CHECK DES FICHIERS SOURCES       #
###############################################
echo "=== Vérification des fichiers requis ==="

fetch_if_missing "$WIN_ISO" "$WIN_ISO_URL"
fetch_if_missing "$VIRTIO_ISO" "$VIRTIO_URL"

# Script d’optimisation (optionnel)
if [[ -f "$OPTIMIZE_PS1" ]]; then
    echo "[OK] Script PowerShell trouvé"
else
    echo "[INFO] Aucun script PowerShell local trouvé."
    echo "       Tu peux en mettre un dans un dossier 'optimWin' sous le dossier courant."
fi

###############################################
#  ÉTAPE 2 — CRÉATION DU DISQUE QCOW2         #
###############################################
if [[ -f "$QCOW2" ]]; then
    echo "[OK] Disque $QCOW2 déjà présent"
else
    echo "[CREATE] Création du disque QCOW2 (40G)..."
    qemu-img create -f qcow2 "$QCOW2" 40G
fi

###############################################
#  ÉTAPE 3 — CRÉATION ISO OPTIMISATION        #
###############################################
# Preparation des fichiers a inclure
echo "reg add HKLM\\SYSTEM\\Setup\\Status\\ChildCompletion /v setup.exe /t REG_DWORD /d 3 /f" > "$FIX_OOBE"
echo "reg add HKLM\\SYSTEM\\Setup\\Status\\ChildCompletion /v oobeldr /t REG_DWORD /d 1 /f" >> "$FIX_OOBE"
echo "oobe\\msoobe" >> "$FIX_OOBE"

cat > "$RUN_FIX_OOBE" << 'EOF'
@echo off
setlocal enabledelayedexpansion
echo Recherche du lecteur contenant fix-oobe.cmd...
for %%d in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist %%d:\fix-oobe.cmd (
        echo Fichier trouvé sur %%d:
        call %%d:\fix-oobe.cmd
        exit /b
    )
)
echo Impossible de trouver fix-oobe.cmd sur un lecteur CD/DVD.
echo Vérifiez que l'ISO optimize.iso est bien monté.
EOF

###############################################
#  Vérification fichiers pour optimize.iso    #
###############################################
# Vérifie que run-fix-oobe.cmd existe
if [[ ! -f "$RUN_FIX_OOBE" ]]; then
    echo "[ERREUR] Le fichier $RUN_FIX_OOBE est introuvable."
    echo "         Impossible de créer l'ISO d'optimisation."
    echo "         Vérifie la génération du script run-fix-oobe.cmd."
    exit 1
fi
# Vérifie que fix-oobe.cmd existe
if [[ ! -f "$FIX_OOBE" ]]; then
    echo "[ERREUR] Le fichier $FIX_OOBE est introuvable."
    echo "         Impossible de créer l'ISO d'optimisation."
    echo "         Vérifie la génération du script fix-oobe.cmd."
    exit 1
fi
# Vérifie que le script PowerShell existe
if [[ ! -f "$OPTIMIZE_PS1" ]]; then
    echo "[ERREUR] Le fichier $OPTIMIZE_PS1 est introuvable."
    echo "         Impossible de créer l'ISO d'optimisation."
    exit 1
fi

echo "[ISO] Création de optimize.iso..."
TMPDIR=build
mkdir -p "$TMPDIR"
# 1) Copier $OPTIMIZE_PS1 sans toucher au repo
cp "$OPTIMIZE_PS1" "$TMPDIR/$BASENAME_OPTIMIZE"
# 2) Ajouter BOM uniquement à la copie
if ! head -c 3 "$TMPDIR/$BASENAME_OPTIMIZE" | grep -q $'\xEF\xBB\xBF'; then
    printf '\xEF\xBB\xBF' | cat - "$TMPDIR/$BASENAME_OPTIMIZE" > "$TMPDIR/$BASENAME_OPTIMIZE.tmp"
    mv "$TMPDIR/$BASENAME_OPTIMIZE.tmp" "$TMPDIR/$BASENAME_OPTIMIZE"
fi
# 3) Générer optimize.config.ps1 (ignoré par Git)
cat > "$TMPDIR/optimize.config.ps1" <<EOF
\$OptimizeScriptName = '$BASENAME_OPTIMIZE'
EOF
# 4) Construire l’ISO propre
mkisofs -o "$OPTIMIZE_ISO" -J -joliet-long -R \
    "$TMPDIR/$BASENAME_OPTIMIZE" \
    "$TMPDIR/optimize.config.ps1" \
    "$FIX_OOBE" "$RUN_FIX_OOBE"
# 5) Nettoyer $TMPDIR
rm -rf "$TMPDIR" 

###############################################
#  ÉTAPE 4 — DÉTECT. DISQUE WINDOWS(QCOW2)    #
###############################################
echo
echo "===================================================="
echo " VÉRIFICATION DU DISQUE WINDOWS (win10.qcow2)"
echo "===================================================="

check_qcow2

case $QCOW2_STATUS in
    0)
        echo "[OK] Windows déjà installé — skip installation"
        INSTALL_WINDOWS=0
        ;;
    1)
        echo "[INFO] Aucun disque Windows — installation requise"
        INSTALL_WINDOWS=1
        ;;
    2)
        echo "[ERREUR] Le disque QCOW2 est corrompu."
        echo "         Supprime win10.qcow2 et relance le script."
        exit 1
        ;;
esac

###############################################
#  ÉTAPE 4+ — Installe WINDOWS(si nécessaire) #
###############################################
if [[ "$INSTALL_WINDOWS" -eq 1 ]]; then
    echo
    echo "===================================================="
    echo " INSTALLATION DE WINDOWS 10"
    echo "===================================================="
    echo
    echo "⚠️  Instructions utilisateur :"
    echo "  - Quand Windows demande où installer → Charger pilote → vioscsi/w10/amd64"
    echo "  - Si OOBE bloque → Shift+F10 → oobe\\bypassnro"
    echo
    echo "Appuie sur Entrée pour démarrer l'installation..."
    read

    qemu-system-x86_64 \
        -enable-kvm \
        -cpu host \
        -smp 1 \
        -m 2200 \
        -device virtio-balloon \
        -device virtio-scsi-pci,id=scsi0 \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$OVMF_VARS" \
        -drive file="$QCOW2",if=none,id=drive0 \
        -device scsi-hd,drive=drive0,bus=scsi0.0 \
        -drive file="$WIN_ISO",media=cdrom \
        -drive file="$VIRTIO_ISO",media=cdrom \
        $( [[ -f "$OPTIMIZE_ISO" ]] && echo "-drive file=$OPTIMIZE_ISO,media=cdrom" ) \
        -netdev user,id=net0 \
        -device virtio-net,netdev=net0 \
        -display gtk,gl=off

    echo
    echo "===================================================="
    echo " INSTALLATION TERMINÉE"
    echo "===================================================="
    echo
    echo "[INFO] Vérification du disque après installation..."

    check_qcow2
    if [[ $QCOW2_STATUS -ne 0 ]]; then
        echo "[ERREUR] Le disque Windows devrait être valide après installation."
        echo "         Quelque chose s'est mal passé."
        exit 1
    fi
    
    echo "[OK] Installation confirmée — démarrage de Windows..."
    echo "Tu peux maintenant passer à l'étape d'optimisation."
    echo "Appuie sur Entrée pour continuer..."
    read
else
    echo
    echo "===================================================="
    echo " INSTALLATION DÉJÀ EFFECTUÉE — SKIP"
    echo "===================================================="
fi

###############################################
#  ÉTAPE 5 — OPTIMISATION WINDOWS             #
###############################################
echo
echo "===================================================="
echo " ÉTAPE POST-INSTALLATION : OPTIMISATION WINDOWS"
echo "===================================================="
echo
echo "1. Démarre Windows normalement"
###############################################
#  ÉTAPE 5a — LANCEMENT DU WINDOWS INSTALLÉ   #
###############################################
echo
echo "===================================================="
echo " DÉMARRAGE DE WINDOWS 10"
echo "===================================================="
echo
echo "⚠️  Astuce :"
echo "  - Si Windows demande un compte Microsoft → Shift+F10 → oobe\\bypassnro"
echo
echo "⚠️  Si Windows affiche l’erreur 'redémarrage inattendu' :"
echo "    - Appuie sur Shift+F10"
echo "    - Tape :  $(basename "$RUN_FIX_OOBE")"
echo "      (ce script détectera automatiquement la bonne lettre du lecteur CD)"
echo
echo "ℹ️  Pendant l'installation Windows :"
echo "    Si l'écran 'Il est temps de vous connecter"
echo "    à un réseau' apparaît :"
echo "      → Cliquez sur 'Je n’ai pas Internet'"
echo "      → Puis 'Continuer avec une configuration limitée'"
echo
echo "ℹ️  Pendant la configuration Windows :"
echo "    Une page 'Protection des données personnelles'"
echo "    apparaîtra juste avant la finalisation."
echo "      → Décoche toutes les options"
echo "      → Puis clique sur 'Accepter' ou 'Suivant'"
echo
echo
echo "Appuie sur Entrée pour démarrer Windows..."
read

qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -smp 1 \
    -m 2200 \
    -device virtio-balloon \
    -device virtio-scsi-pci,id=scsi0 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$OVMF_VARS" \
    -drive file=win10.qcow2,if=none,id=drive0 \
    -device scsi-hd,drive=drive0,bus=scsi0.0 \
    -drive file="$OPTIMIZE_ISO",media=cdrom,if=none,id=cd1 \
    -device scsi-cd,drive=cd1,bus=scsi0.0 \
    -netdev user,id=net0 \
    -device virtio-net,netdev=net0 \
    -display gtk,gl=off \
    &

echo "Dès que le nouveau desktop windows est lancé, appuie sur Entrée pour continuer"
read

echo "2. Ouvre PowerShell (pwsh) en administrateur :"
echo "   - Appuie sur :  Windows + R"
echo "   - Tape :        powershell"
echo "   - Puis :        Ctrl + Shift + Entrée"
echo "   - Accepte la demande d'autorisation (UAC)"
echo "3. Dans PowerShell, exécute le script d’optimisation :"
echo
echo "   Set-ExecutionPolicy Bypass -Scope Process -Force"
echo "   D:\\$BASENAME_OPTIMIZE"
echo
echo "Si cela ne fonctionne pas verifier que $OPTIMIZE_ISO est bien monté sur le lecteur D:"
echo "Un moyen rapide de le faire :"
echo "  ouvrir explorer.exe en cliquant sur la corbeille"
echo "  cliquer sur 'Ordinateur'. La liste des volumes s'affiche"
echo "Dans cette liste, ignorer 'A:' et 'C:' : la lettre qui reste devrait etre la bonne"
echo "Réécrire alors, dans PowerShell, la commande D:\\$BASENAME_OPTIMIZE"
echo "en remplaçant 'D:' par le bon nom de volume."
echo
echo
echo "Le script va clore la machine Windows après avoir planifié la défragmentation au prochain démarrage."
echo "Assure-toi que Windows est éteint puis appuie sur Entrée"
read
echo "Démarrage de la machine Windows pour défragmentation ..."
echo "La défrag est automatique,"
echo "attends que la machine s'éteigne une dernière fois pour passer à la suite ..."

qemu-system-x86_64 \
  -enable-kvm \
  -m 4G \
  -cpu host \
  -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$OVMF_VARS" \
  -drive file="$QCOW2",if=virtio \
  -boot c \
  -nic user,model=virtio-net-pci \
  -display default \
  -vga virtio

###############################################
#  ÉTAPE 6 — SHRINK QCOW2                     #
###############################################
echo
echo "===================================================="
echo " SHRINK DU DISQUE QCOW2 (alignement CHS propre)"
echo "===================================================="
echo
echo "⚠️  Assure-toi que Windows est éteint proprement."
echo "Appuie sur Entrée pour shrinker..."
read

echo "[CHECK] Vérification du disque..."
qemu-img check "$QCOW2"

echo "[SHRINK] Conversion vers un QCOW2 compacté..."
qemu-img convert -O qcow2 -o compat=1.1 "$QCOW2" win10-shrink.qcow2

echo "[REPLACE] Remplacement du disque..."
mv "$QCOW2" win10-old.qcow2
mv win10-shrink.qcow2 "$QCOW2"

echo "[DONE] Shrink terminé !"
echo "Ancien disque : win10-old.qcow2"
echo "Nouveau disque : $QCOW2"
echo
echo "===================================================="
echo " FIN DU SCRIPT — LE LAB WINDOWS 10 EST PRÊT"
echo "===================================================="
