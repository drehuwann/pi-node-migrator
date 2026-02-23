#!/bin/bash
# Traps globaux pour nettoyage
trap 'cleanup_all' EXIT
trap 'cleanup_all; exit 130' INT
#Noms des fichiers produits. $CUSTOMISO est detruit apres usage.
CUSTOMISO="win10-custom.iso"
QCOW2="win10.qcow2"
#Basename du script
SELFPATH="$(cd "$(dirname "$0")" && pwd)"
LOGDIR="$SELFPATH/logs"
ISOSRCDIR="$SELFPATH/isosrc"
WORKDIR="$SELFPATH/patches"
#reinit $WORKDIR
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
#racines points de montages
WIMPTS="$ISOSRCDIR/wims"
ISOPTS="$ISOSRCDIR/mnt"
#pipes
CMD_FIFO=cmdpipe
RESP_FIFO=resppipe
cleanup_all() {
    # 1. Stop g4
    stop_g4_streaming
    # 2. Demonter les ISO via le daemon
    if [[ -n "$ISOPTS" ]]; then
        if [[ -d "$ISOPTS/win" ]]; then
            d_umount "$ISOPTS/win" || echo "WARN: Echec du demontage de $ISOPTS/win"
        fi
        if [[ -d "$ISOPTS/virtio" ]]; then
            d_umount "$ISOPTS/virtio" || echo "WARN: Echec du demontage de $ISOPTS/virtio"
        fi
    fi 
    # 3. Tuer le daemon des qu'on a fini de s'en servir
    stop_daemon
    # 4. Nettoyage des repertoires ISO
    if [[ -n "$ISOPTS" ]]; then
        [[ -d "$ISOPTS/win" ]] && rmdir "$ISOPTS/win" 2>/dev/null || true
        [[ -d "$ISOPTS/virtio" ]] && rmdir "$ISOPTS/virtio" 2>/dev/null || true
    fi
    # 5. Nettoyage des repertoires WIM extraits
    if [[ -n "$WIMPTS" ]]; then
        [[ -d "$WIMPTS/boot" ]] && rm -rf "$WIMPTS/boot" 2>/dev/null || true
        [[ -d "$WIMPTS/install" ]] && rm -rf "$WIMPTS/install" 2>/dev/null || true
    fi
}
start_daemon() {
    DAEMON_SH="$SELFPATH/tools/daemon.sh"
    DAEMON_LOG="$LOGDIR/host/d.log"
    if [ ! -p "$CMD_FIFO" ] || [ ! -p "$RESP_FIFO" ]; then
        echo "ERROR: FIFOs not found. They must be created before calling start_daemon()."
        return 1
    fi
    echo "Le daemon va demarrer sous sudo."
    echo "Si un mot de passe est demande, entrez le maintenant."
    echo "En attente du signal READY..."
    chmod 644 "$DAEMON_SH"
    chmod +x "$DAEMON_SH"
    sudo RUNNER="$USER" bash "$DAEMON_SH" "$CMD_FIFO" "$RESP_FIFO" "$DAEMON_LOG" &
    local wrapper_pid=$!
    chmod 644 "$DAEMON_SH"
    local ready_word=""
    local ready_pid=""
    if ! read -r -t 15 ready_word ready_pid < "$RESP_FIFO"; then
        echo "ERROR: daemon did not send READY"
        kill "$wrapper_pid" 2>/dev/null
        return 1
    fi
    if [ "$ready_word" != "READY" ] || [ -z "$ready_pid" ]; then
        echo "ERROR: invalid READY line: [$ready_word $ready_pid]"
        kill "$wrapper_pid" 2>/dev/null
        return 1
    fi
    if ! ps -p "$ready_pid" > /dev/null 2>&1; then
        echo "ERROR: daemon died immediately after READY (PID=$ready_pid)"
        kill "$wrapper_pid" 2>/dev/null
        return 1
    fi
    DAEMON_REAL_PID="$ready_pid"
    DAEMON_WRAPPER_PID="$wrapper_pid"
    echo "Daemon pret (wrapper PID=$wrapper_pid, daemon PID=$DAEMON_REAL_PID)"
    return 0
}
stop_daemon() {
    if [ -z "$DAEMON_REAL_PID" ] || [ -z "$DAEMON_WRAPPER_PID" ]; then
        echo "No daemon PID recorded, nothing to stop."
        return 0
    fi
    # Ask daemon to quit
    echo "quit" >&3 2>/dev/null
    # Wait up to 2 seconds for wrapper to exit
    for i in {1..10}; do
        if ! ps -p "$DAEMON_REAL_PID" > /dev/null 2>&1; then
            break
        fi
        sleep 0.2
    done
    # If wrapper still alive, kill it
    if ps -p "$DAEMON_WRAPPER_PID" > /dev/null 2>&1; then
        echo "Wrapper still alive, killing..."
        sudo kill "$DAEMON_WRAPPER_PID"
    fi
    rm -f "$CMD_FIFO" "$RESP_FIFO"
    unset DAEMON_REAL_PID DAEMON_WRAPPER_PID
    echo "Daemon stopped and FIFOs removed."
    exec 3>&- # fermer le FD à la toute fin 
}
########################################################
#  Make the daemon umount $1
########################################################
d_umount() {
    local mntpt="$1"
    # Si le repertoire n'existe pas ne rien faire
    [[ ! -d "$mntpt" ]] && return 0
    # Si ce n'est pas un point de montage juste supprimer
    if ! mountpoint -q "$mntpt"; then
        rm -rf "$mntpt"
        return 0
    fi
    # Demander au daemon de demonter
    echo "umount $mntpt" >&3
    # Lire la reponse
    local resp
    read -r resp < "$RESP_FIFO"
    if [[ "$resp" != OK ]]; then
        echo "ERREUR: impossible de demonter $mntpt"
        echo "Reponse du daemon: $resp"
        return 1
    fi
    rm -rf "$mntpt"
    return 0
}
########################################################
#  Make the daemon mount device $1 on mountpoint $2 
########################################################
d_mount() {
    local dev="$1"
    local mntpt="$2"
    if [[ ! -f "$dev" ]]; then
        echo "ERREUR: ISO introuvable : $dev"
        return 1
    fi
    mkdir -p "$mntpt"
    if [[ -n "$(ls -A "$mntpt" 2>/dev/null)" ]]; then
        echo "ERREUR: $mntpt doit etre vide avant montage"
        return 1
    fi
    printf '%s\n' "mount $dev $mntpt" >&3
    local resp
    if ! read -r -t 2 resp < "$RESP_FIFO"; then
        if ! kill -0 "$DAEMON_REAL_PID" 2>/dev/null; then
            echo "ERREUR: daemon mort pendant le montage de $dev"
        else
            echo "ERREUR: timeout en attendant la reponse du daemon pour $dev"
        fi
        return 1
    fi
    if [[ "$resp" != OK ]]; then
        echo "ERREUR: impossible de monter $dev sur $mntpt"
        echo "Reponse du daemon: $resp"
        return 1
    fi
    return 0
}
###############################################
# g4 : Panther live streaming
###############################################
enable_g4() {
    DBG_PANTHER=1
    DEBUG_UUID=$(uuidgen)
    DEBUG_DISK="./debug.qcow2"
    DEBUG_MNT="./debug"
    PANTHER_DIR="$LOGDIR/panther"
    mkdir -p "$DEBUG_MNT"
    mkdir -p "$PANTHER_DIR"
    qemu-img create -f qcow2 "$DEBUG_DISK" 16M
    # Dtection de la partition
    PART=$(guestfish --ro -a "$DEBUG_DISK" run : list-filesystems | awk '{print $1}')
    if [[ -z "$PART" ]]; then
        echo "[g4] Erreur : impossible de detecter la partition dans $DEBUG_DISK" >&2
        return 1
    fi
    # Montage pour ecrire l'UUID
    guestmount -a "$DEBUG_DISK" -m "$PART" "$DEBUG_MNT"
    echo "$DEBUG_UUID" > "$DEBUG_MNT/debug.uuid"
    guestunmount "$DEBUG_MNT"
}
###############################################
# Streaming live apres lancement de QEMU
###############################################
start_g4_streaming() {
    [[ $DBG_PANTHER -ne 1 ]] && return
    # Verification stricte : les variables doivent exister
    if [[ -z "$DEBUG_DISK" || -z "$DEBUG_MNT" || -z "$PANTHER_DIR" ]]; then
        echo "[g4] Erreur : g4 n'a pas ete initialise" >&2
        return 1
    fi
    mkdir -p "$DEBUG_MNT"    
    # Montage en lecture seule
    guestmount -a "$DEBUG_DISK" -m "$PART" --ro "$DEBUG_MNT"
    # Tails
    mkdir -p "$PANTHER_DIR"
    touch "$PANTHER_DIR/setupact.log"
    chmod 600 "$PANTHER_DIR/setupact.log"
    tail -F "$DEBUG_MNT/setupact.log"   >> "$PANTHER_DIR/setupact.log" &
    G4_TAIL_ACT=$!
    touch "$PANTHER_DIR/setuperr.log"
    chmod 600 "$PANTHER_DIR/setuperr.log"
    tail -F "$DEBUG_MNT/setuperr.log"  >> "$PANTHER_DIR/setuperr.log" &
    G4_TAIL_ERR=$!
}
###############################################
# Arret du streaming
###############################################
stop_g4_streaming() {
    # Si g4 nest pas active, on sort proprement
    [[ "$DBG_PANTHER" -ne 1 ]] && return 0
    # 1. Tuer les tails s'ils existent
    if [[ -n "$G4_TAIL_ACT" ]]; then
        kill "$G4_TAIL_ACT" 2>/dev/null || true
        G4_TAIL_ACT=
    fi
    if [[ -n "$G4_TAIL_ERR" ]]; then
        kill "$G4_TAIL_ERR" 2>/dev/null || true
        G4_TAIL_ERR=
    fi
    # 2. Demonter le point de montage si encore monte
    if [[ -n "$DEBUG_MNT" ]] && mountpoint -q "$DEBUG_MNT" 2>/dev/null; then
        guestunmount "$DEBUG_MNT" 2>/dev/null || true
    fi
    # 3. Nettoyer le repertoire de montage
    if [[ -n "$DEBUG_MNT" ]]; then
        rmdir "$DEBUG_MNT" 2>/dev/null || true
    fi
}
check_or_create_qcow2() {
    echo "[CHECK] Verification du disque QCOW2..."
    if [[ ! -f "$QCOW2" ]]; then
        echo "[CREATE] Aucun disque trouve, creation de $QCOW2..."
        qemu-img create -f qcow2 "$QCOW2" 40G \
        && echo "[OK] Disque QCOW2 cr." \
        || { echo "[ERREUR] Impossible de creer $QCOW2."; exit 1; }
    else
        echo "[OK] Disque QCOW2 deja present."
    fi
}
phase_install() {
    qemu-system-x86_64 \
        -enable-kvm \
        -m 2048 \
        -cpu host \
        -smp 2 \
        -device virtio-scsi-pci,id=scsi0 \
        -drive file="$QCOW2",if=none,id=drive0 \
        -device scsi-hd,drive=drive0,bus=scsi0.0 \
        -drive file="$CUSTOMISO",media=cdrom \
        -boot d \
        -net none \
        -display none \
        -no-reboot \
        $QEMU_DEBUG_OPTS \
        -name "WIN-Install"
}
phase_firstboot() {
    qemu-system-x86_64 \
        -enable-kvm \
        -m 2048 \
        -cpu host \
        -smp 2 \
        -device virtio-scsi-pci,id=scsi0 \
        -drive file="$QCOW2",if=none,id=drive0 \
        -device scsi-hd,drive=drive0,bus=scsi0.0 \
        -boot c \
        -net none \
        -display none \
        -no-reboot \
        $QEMU_DEBUG_OPTS \
        -name "WIN-FirstBoot"
}
phase_secondboot() {
    qemu-system-x86_64 \
        -enable-kvm \
        -m 2048 \
        -cpu host \
        -smp 2 \
        -device virtio-scsi-pci,id=scsi0 \
        -drive file="$QCOW2",if=none,id=drive0 \
        -device scsi-hd,drive=drive0,bus=scsi0.0 \
        -boot c \
        -net none \
        -display none \
        -no-reboot \
        $QEMU_DEBUG_OPTS \
        -name "WIN-SecondBoot"
}
shrink_qcow2() {
    echo
    echo "===================================================="
    echo " SHRINK DU DISQUE QCOW2"
    echo "===================================================="
    echo
    echo "  Assure-toi que Windows est eteint proprement."
    echo " Appuie sur Entree pour shrinker..."
    read
    echo " ][CHECK] Verification du disque..."
    qemu-img check "$QCOW2"
    echo "[SHRINK] Conversion vers un QCOW2 compact..."
    qemu-img convert -O qcow2 -o compat=1.1 "$QCOW2" win-shrink.qcow2
    echo "[REPLACE] Remplacement du disque..."
    mv "$QCOW2" win-old.qcow2
    mv win-shrink.qcow2 "$QCOW2"
    echo "[DONE] Shrink termine !"
    echo "Ancien disque : win-old.qcow2"
    echo "Nouveau disque : $QCOW2"
    echo
    echo "===================================================="
    echo " FIN DU PIPELINE WINDOWS"
    echo "===================================================="
}
###########################################################
# Gestion des parametres
######################### Switches de Debug #################################
# Mode	# Nom	                # Fonction                                  #
#############################################################################
#  -g1	# Serial Windows	    # -serial stdio : console COM1 Windows      #
#  -g2	# QEMU Monitor          # -monitor telnet:4444                      #
#  -g3	# Console WinPE auto	# Ouverture automatique d'un CMD dans WinPE #
#  -g4  # Logs Panther	        # Dump automatique des logs Setup           #
#  -g5	# Kernel Debug          # -debugcon stdio + BCD debug               #
#############################################################################
DEBUG_MODES=()
DBG_SERIAL=0   # -g1
DBG_MONITOR=0  # -g2
DBG_WINPE=0    # -g3
DBG_PANTHER=0  # -g4
DBG_KERNEL=0   # -g5
while [[ $# -gt 0 ]]; do
    case "$1" in
        -g*)
            DEBUG_MODES+=("${1#-g}")
            shift
            ;;
        *)
            shift
            ;;
    esac
done
for m in "${DEBUG_MODES[@]}"; do
    case "$m" in
        1)  DBG_SERIAL=1 ;;
        2)  DBG_MONITOR=1 ;;
        3)  DBG_WINPE=1 ;;
        4)  DBG_PANTHER=1 ;;
        5)  DBG_KERNEL=1 ;;
        *)  echo "[WARN] Mode debug inconnu : g$m" ;;
    esac
done
if [[ ${#DEBUG_MODES[@]} -gt 0 ]]; then
    echo "[*] Modes debug : g${DEBUG_MODES[*]}"
fi
###########################################################
# Transfert variables d environnement host->guest
###########################################################
# copie vers la boite a patcher les patchs : $WORKDIR
cp "$SELFPATH/autounattend.xml" "$WORKDIR/"
cp "$SELFPATH/firstLogon.ps1" "$WORKDIR/"
cp "$SELFPATH/secondLogon.ps1" "$WORKDIR/"
# export env de l HOST vers GUEST via $WORKDIR
echo "[*] Detection de la locale hote ..."
HOSTLOC=$(printf '%s\n' "$LANG" | sed 's/\..*//; s/@.*//; s/"//g')
if [[ -z "$HOSTLOC" || "$HOSTLOC" == "C" ]]; then
    echo "    -> Locale HOST = C . Fallback to en-US"
    GUESTLOC="en-US"
else
    GUESTLOC=$(echo "$HOSTLOC" | tr '_' '-')
    echo "    -> Locale hote dtecte : $HOSTLOC  $GUESTLOC"
fi
echo "[*] Detection du clavier hote ..."
if [[ -f /etc/default/keyboard ]]; then
    HOSTKB=$(awk -F= '/XKBLAYOUT/{gsub(/"/,"",$2); print $2}' /etc/default/keyboard)
elif [[ -f /etc/vconsole.conf ]]; then
    HOSTKB=$(awk -F= '/KEYMAP/{print $2}' /etc/vconsole.conf)
else
    HOSTKB=$(locale | awk -F= '/^LANG=/{print $2}' | cut -d_ -f1)
fi
if [[ -z "$HOSTKB" ]]; then
    echo "    -> Impossible de detecter le clavier, fallback en_US"
    GUESTKB="en-US"
else
    echo "    -> Clavier hote detecte : $HOSTKB"
    case "$HOSTKB" in
        fr) GUESTKB="fr-FR" ;;
        be) GUESTKB="fr-BE" ;;
        ca) GUESTKB="fr-CA" ;;
        ch) GUESTKB="fr-CH" ;;
        de) GUESTKB="de-DE" ;;
        at) GUESTKB="de-AT" ;;
        us) GUESTKB="en-US" ;;
        uk|gb) GUESTKB="en-GB" ;;
        es) GUESTKB="es-ES" ;;
        it) GUESTKB="it-IT" ;;
        pt) GUESTKB="pt-PT" ;;
        br) GUESTKB="pt-BR" ;;
        *)
            echo "    -> Layout non reconnu, fallback en US"
            GUESTKB="en-US"
            ;;
    esac
fi
echo "    -> Mapping clavier invite = $GUESTKB"
for f in autounattend.xml firstLogon.ps1 secondLogon.ps1; do
    if [[ ! -f "$SELFPATH/$f" ]]; then
        echo "ERREUR: $f introuvable dans $SELFPATH"
        exit 1
    fi
done
echo "[*] Application locale + clavier dans autounattend.xml"
sed -i "s/__LOCALE__/$GUESTLOC/g" "$WORKDIR/autounattend.xml"
sed -i "s/__KEYBOARD__/$GUESTKB/g" "$WORKDIR/autounattend.xml"
echo "[*] Verification des modifications"
diff -u "$SELFPATH/autounattend.xml" "$WORKDIR/autounattend.xml" \
    || echo "    -> Diff affiche ci-dessus"
echo "[ XML (xmllint)..."
xmllint --noout "$WORKDIR/autounattend.xml" \
    || { echo "[ERREUR] autounattend.xml invalide"; exit 1; }
echo "    -> XML valide"
if grep -q "__LOCALE__\|__KEYBOARD__" "$WORKDIR/autounattend.xml"; then
    echo "[ERREUR] Un ou plusieurs placeholders n'ont pas ete remplaces"
    exit 1
fi
echo "    -> Placeholders remplaces correctement"
echo "    -> autounattend.xml OK"
# Fin du patchage de patch
###################################################
# Spawn du sudoer-daemon et tout ce qui s'ensuit
###################################################
mkfifo "$CMD_FIFO" "$RESP_FIFO"
chmod 600 "$CMD_FIFO" "$RESP_FIFO"
start_daemon || { echo "ERROR: daemon startup failed"; cleanup_all; exit 1; }
# Phase d injections                 
ISO_WIN="$(ls "$ISOSRCDIR"/Win1*.iso 2>/dev/null | head -n 1 || true)"
if [[ -z "$ISO_WIN" ]]; then
    echo "ERREUR: Aucun ISO Windows trouve (Win1*.iso)"
    exit 1
fi
echo "[*] ISO Windows detecte : $ISO_WIN"
echo "[*] Recherche de l'ISO VirtIO"
ISO_VIRTIO="$(ls "$ISOSRCDIR"/virtio-wi*.iso 2>/dev/null | head -n 1 || true)"
if [[ -z "$ISO_VIRTIO" ]]; then
    echo "ERREUR: Aucun ISO VirtIO trouve (virtio-win*.iso)"
    echo "Telecharge-le depuis https://fedorapeople.org/groups/virt/virtio-win/"
    exit 1
fi
echo "    -> ISO VirtIO detecte : $ISO_VIRTIO"
echo "Creation des points de montage."
mkdir -p "$ISOPTS"/win "$ISOPTS"/virtio
if [[ ! -z $(ls -A "$ISOPTS"/win) ]]; then
    echo "ERREUR: $ISOPTS/win doit etre vide"
    exit 1
fi
if [[ ! -z $(ls -A "$ISOPTS"/virtio) ]]; then
    echo "ERREUR: $ISOPTS/virtio doit etre vide"
    exit 1
fi
exec 3> "$CMD_FIFO" # ouvrir une fois
d_mount "$ISO_WIN" "$ISOPTS/win" || { 
    echo "ERREUR: montage $ISO_WIN"
    exit 1
}
d_mount "$ISO_VIRTIO" "$ISOPTS/virtio" || { 
    echo "ERREUR: montage $ISO_VIRTIO"
    exit 1
}
echo "  -> ISOs montes avec succes"
# Dossier de travail pour l'ISO modifie
mkdir iso_work
echo "Generation d'une copie writable de l'ISO win ..."
cp -r "$ISOPTS"/win/* iso_work/
# --- PATCH BOOT.WIM ---
mkdir -p "$WIMPTS"/boot/Windows/INF \
    "$WIMPTS"/boot/Windows/System32/drivers
echo "Extraction de l'image boot.wim ..."
wimlib-imagex extract --unix-data "$ISOPTS"/win/sources/boot.wim 2 \
     --dest-dir="$WIMPTS"/boot
STARTNET="$WIMPTS/boot/Windows/System32/startnet.cmd"
echo "wpeinit" | tee "$STARTNET" > /dev/null
if [[ $DBG_WINPE -eq 1 ]]; then
    echo "start cmd.exe" | tee -a "$STARTNET" > /dev/null
fi
if [[ $DBG_PANTHER -eq 1 ]]; then
    # Injection dans startnet.cmd
    echo "set DEBUG_UUID=$DEBUG_UUID" >> "$STARTNET"
    cat << 'EOF' >> "$STARTNET"
:: Dtection du disque debug par UUID
for %%d in (D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist %%d:\debug.uuid (
        for /f %%u in (%%d:\debug.uuid) do (
            if "%%u"=="%DEBUG_UUID%" set DEBUGDRIVE=%%d:
        )
    )
)
:: Copie des logs Panther
if exist X:\Windows\Panther\setupact.log copy X:\Windows\Panther\setupact.log %DEBUGDRIVE%\setupact.log
if exist X:\Windows\Panther\setuperr.log copy X:\Windows\Panther\setuperr.log %DEBUGDRIVE%\setuperr.log
EOF
fi
if [[ $DBG_KERNEL -eq 1 ]]; then
    cat << 'EOF' | tee -a "$STARTNET" > /dev/null
bcdedit /set {default} bootlog yes
bcdedit /set {default} debug yes
bcdedit /set {default} bootstatuspolicy ignoreallfailures
EOF
fi
echo "Injection des drivers virtio dans boot.wim..."
cp "$ISOPTS"/virtio/vioscsi/w10/amd64/*.{inf,cat} \
    "$WIMPTS"/boot/Windows/INF/
cp "$ISOPTS"/virtio/vioscsi/w10/amd64/*.sys \
    "$WIMPTS"/boot/Windows/System32/drivers/
cp "$ISOPTS"/virtio/viostor/w10/amd64/*.{inf,cat} \
    "$WIMPTS"/boot/Windows/INF/
cp "$ISOPTS"/virtio/viostor/w10/amd64/*.sys \
    "$WIMPTS"/boot/Windows/System32/drivers/
cp "$ISOPTS"/virtio/NetKVM/w10/amd64/*.{inf,cat} \
    "$WIMPTS"/boot/Windows/INF/
cp "$ISOPTS"/virtio/NetKVM/w10/amd64/*.sys \
    "$WIMPTS"/boot/Windows/System32/drivers/
wimlib-imagex capture --unix-data "$WIMPTS"/boot boot_patched.wim \
    --compress=LZX
rm -r "$WIMPTS"/boot
mv boot_patched.wim iso_work/sources/boot.wim
# --- PATCH INSTALL.WIM ---
mkdir -p "$WIMPTS"/install/Windows/INF \
             "$WIMPTS"/install/Windows/System32/drivers
echo "Extraction de l'image install.wim ..."
wimlib-imagex extract --unix-data "$ISOPTS"/win/sources/install.wim 6 \
    --dest-dir="$WIMPTS"/install
echo "Injection des drivers virtio dans install.wim..."
cp "$ISOPTS"/virtio/vioscsi/w10/amd64/*.{inf,cat} \
    "$WIMPTS"/install/Windows/INF/
cp "$ISOPTS"/virtio/vioscsi/w10/amd64/*.sys \
    "$WIMPTS"/install/Windows/System32/drivers/
cp "$ISOPTS"/virtio/viostor/w10/amd64/*.{inf,cat} \
    "$WIMPTS"/install/Windows/INF/
cp "$ISOPTS"/virtio/viostor/w10/amd64/*.sys \
    "$WIMPTS"/install/Windows/System32/drivers/
cp "$ISOPTS"/virtio/NetKVM/w10/amd64/*.{inf,cat} \
    "$WIMPTS"/install/Windows/INF/
cp "$ISOPTS"/virtio/NetKVM/w10/amd64/*.sys \
    "$WIMPTS"/install/Windows/System32/drivers/
wimlib-imagex capture --unix-data "$WIMPTS"/install install_patched.wim \
    --compress=LZX
rm -r "$WIMPTS"/install
mv install_patched.wim iso_work/sources/install.wim
echo "[*] Drivers injectes dans les WIM"
#Demontage propre via le daemon
if [[ -d "$ISOPTS/win" ]]; then
    d_umount "$ISOPTS/win" || echo "WARN: echec du demontage de $ISO_WIN"
fi
if [[ -d "$ISOPTS/virtio" ]]; then
    d_umount "$ISOPTS/virtio" || echo "WARN: echec du demontage de $ISO_VIRTIO"
fi
stop_daemon #we dont need this anymore
# --- ICI ON DECHARGE LA BOITE A PATCHER LES PATCHS ---
mv "$WORKDIR"/* iso_work/
# --- RECONSTRUCTION ISO ---
mkisofs -U -udf \
    -b boot/etfsboot.com \
        -no-emul-boot -boot-load-size 8 -boot-info-table \
    -eltorito-alt-boot -eltorito-platform efi \
        -eltorito-boot EFI/boot/bootx64.efi -no-emul-boot \
    -o "$CUSTOMISO" iso_work || exit 1
rm -r iso_work
echo "[*] ISO reconstruite : $CUSTOMISO"
# 0. Cration du QCOW2 si absent
check_or_create_qcow2 \
&& echo "[OK] QCOW2 pret." \
|| { echo "[ERREUR] $QCOW2 manquant ou impossible a creer."; exit 1; }
# 1- Rappels sur les modes de debug
QEMU_DEBUG_OPTS=""
[[ $DBG_SERIAL  -eq 1 ]] && QEMU_DEBUG_OPTS+=" -serial stdio"
[[ $DBG_MONITOR -eq 1 ]] && QEMU_DEBUG_OPTS+=" -monitor telnet:127.0.0.1:4444,server,nowait"
[[ $DBG_KERNEL  -eq 1 ]] && QEMU_DEBUG_OPTS+=" -debugcon file:kernel_debug.log"
echo "[*] QEMU debug opts : $QEMU_DEBUG_OPTS"
if [[ $DBG_PANTHER -eq 1 ]]; then
    echo "[*] Mode g4 active : capture en direct des logs Panther (setupact / setuperr)"
    echo "    Les logs seront streames en temps reel vers :"
    echo "      $SELFPATH/logs/panther/setupact.log"
    echo "      $SELFPATH/logs/panther/setuperr.log"
    echo "    Un disque debug.qcow2 temporaire est utilise comme tampon de lecture."
fi
# 1. Installation
phase_install \
&& echo "[OK] Phase 1 terminee." \
|| { echo "[ERREUR] Phase 1 a echoue."; exit 1; }
# 2. First boot
phase_firstboot \
&& echo "[OK] Phase 2 terminee." \
|| { echo "[ERREUR] Phase 2 a echoue."; exit 1; }
# 3. Second boot
phase_secondboot \
&& echo "[OK] Phase 3 terminee." \
|| { echo "[ERREUR] Phase 3 a echoue."; exit 1; }
# 4. Shrink final
shrink_qcow2 \
&& echo "[OK] Shrink $QCOW2 termine." \
|| { echo "[ERREUR] Phase shrink final a echoue."; exit 1; }
exit 0;
