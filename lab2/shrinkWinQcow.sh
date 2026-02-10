#!/bin/bash
# Trap global pour nettoyage
trap 'cleanup-all' EXIT

CMD_FIFO=cmdpipe
RESP_FIFO=resppipe
mkfifo "$CMD_FIFO" "$RESP_FIFO"
export RUNNER="$USER"
# Lancer le démon inline en root
sudo RUNNER="$RUNNER" "$0" --daemon "$CMD_FIFO" "$RESP_FIFO" &
MOUNTD_PID=$!
# Vérifier que le démon est bien lancé
sleep 0.1
if ! kill -0 "$MOUNTD_PID" 2>/dev/null; then
    echo "ERREUR: le démon n’a pas démarré"
    exit 1
fi
echo "Daemon lancé pid $MOUNTD_PID
# LOCK : empêcher toute écriture externe
chmod 600 "$CMD_FIFO" "$RESP_FIFO"

######################### Switches de Debug #################################
# Mode	# Nom	                # Fonction                                  #
#############################################################################
#  -g1	# Serial Windows	    # -serial stdio → console COM1 Windows      #
#  -g2	# QEMU Monitor          # -monitor telnet:4444                      #
#  -g3	# Console WinPE auto	# Ouverture automatique d’un CMD dans WinPE #
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
        5) DBG_KERNEL=1 ;;
        *) echo "[WARN] Mode debug inconnu : g$m" ;;
    esac
done
if [[ ${#DEBUG_MODES[@]} -gt 0 ]]; then
    echo "[*] Modes debug : g${DEBUG_MODES[*]}"
fi

########################################################
#  Make the daemon umount $1
########################################################
d_umount() {
    local mntpt="$1"
    # Si le répertoire n'existe pas → rien à faire
    [[ ! -d "$mntpt" ]] && return 0
    # Si ce n'est pas un point de montage → juste supprimer
    if ! mountpoint -q "$mntpt"; then
        rm -rf "$mntpt"
        return 0
    fi
    # Demander au démon de démonter
    echo "umount $mntpt" > "$MOUNT_FIFO"
    # Lire la réponse
    local resp
    read -r resp < "$RESP_FIFO"
    if [[ "$resp" != OK ]]; then
        echo "ERREUR: impossible de démonter $mntpt"
        echo "Réponse du démon: $resp"
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
    # Vérifier que l'ISO existe
    if [[ ! -f "$dev" ]]; then
        echo "ERREUR: ISO introuvable : $iso"
        return 1
    fi
    # Créer le point de montage si nécessaire
    mkdir -p "$mntpt"
    # Vérifier qu'il est vide
    if [[ -n "$(ls -A "$mntpt" 2>/dev/null)" ]]; then
        echo "ERREUR: $mntpt doit être vide avant montage"
        return 1
    fi
    # Envoyer la commande au démon
    echo "mount $iso $mntpt" > "$MOUNT_FIFO"
    # Lire la réponse
    local resp
    read -r resp < "$RESP_FIFO"
    if [[ "$resp" != OK ]]; then
        echo "ERREUR: impossible de monter $iso sur $mntpt"
        echo "Réponse du démon: $resp"
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
    PANTHER_DIR="$SELFPATH/logs/panther"
    mkdir -p "$DEBUG_MNT"
    mkdir -p "$PANTHER_DIR"
    qemu-img create -f qcow2 "$DEBUG_DISK" 16M
    # Détection de la partition
    PART=$(guestfish --ro -a "$DEBUG_DISK" run : list-filesystems | awk '{print $1}')
    if [[ -z "$PART" ]]; then
        echo "[g4] Erreur : impossible de détecter la partition dans $DEBUG_DISK" >&2
        return 1
    fi
    # Montage pour écrire l’UUID
    guestmount -a "$DEBUG_DISK" -m "$PART" "$DEBUG_MNT"
    echo "$DEBUG_UUID" > "$DEBUG_MNT/debug.uuid"
    guestunmount "$DEBUG_MNT"
}

###############################################
# Streaming live après lancement de QEMU
###############################################
start_g4_streaming() {
    [[ $DBG_PANTHER -ne 1 ]] && return
    # Vérification stricte : les variables doivent exister
    if [[ -z "$DEBUG_DISK" || -z "$DEBUG_MNT" || -z "$PANTHER_DIR" ]]; then
        echo "[g4] Erreur : g4 n’a pas été initialisé (enable_g4 non appelé)" >&2
        return 1
    fi
    mkdir -p "$PANTHER_DIR"
    mkdir -p "$DEBUG_MNT"
    # Montage en lecture seule
    guestmount -a "$DEBUG_DISK" -m "$PART" --ro "$DEBUG_MNT"
    # Tails
    tail -F "$DEBUG_MNT/setupact.log"   >> "$PANTHER_DIR/setupact.log" &
    G4_TAIL_ACT=$!
    tail -F "$DEBUG_MNT/setuperr.log"  >> "$PANTHER_DIR/setuperr.log" &
    G4_TAIL_ERR=$!
}

###############################################
# Arrêt du streaming
###############################################
stop_g4_streaming() {
    # Si g4 n’est pas activé, on sort proprement
    [[ "$DBG_PANTHER" -ne 1 ]] && return 0
    # 1. Tuer les tails s’ils existent
    if [[ -n "$G4_TAIL_ACT" ]]; then
        kill "$G4_TAIL_ACT" 2>/dev/null || true
        G4_TAIL_ACT=
    fi
    if [[ -n "$G4_TAIL_ERR" ]]; then
        kill "$G4_TAIL_ERR" 2>/dev/null || true
        G4_TAIL_ERR=
    fi
    # 2. Démonter le point de montage si encore monté
    if [[ -n "$DEBUG_MNT" ]] && mountpoint -q "$DEBUG_MNT" 2>/dev/null; then
        guestunmount "$DEBUG_MNT" 2>/dev/null || true
    fi
    # 3. Nettoyer le répertoire de montage
    if [[ -n "$DEBUG_MNT" ]]; then
        rmdir "$DEBUG_MNT" 2>/dev/null || true
    fi
}

CUSTOMISO="win10-custom.iso"
QCOW2="win10.qcow2"

SELFPATH="$(cd "$(dirname "$0")" && pwd)"
echo "[*] SELFPATH = $SELFPATH"

WORKDIR="$SELFPATH/hacks"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

#racines points de montages
WIMPTS="./wims"
ISOPTS="./mnt"

cleanup_all() {
    # 1. Stop g4
    stop_g4_streaming
    # 2. Demonter les ISO via le démon
    if [[ -n "$ISOPTS" ]]; then
        if [[ -d "$ISOPTS/win" ]]; then
            if d_umount "$ISOPTS/win"; then
                echo "WARN: échec du démontage de $ISOPTS/win"
            fi
        fi
        if [[ -d "$ISOPTS/virtio" ]]; then
            if d_umount "$ISOPTS/virtio"; then
                echo "WARN: échec du démontage de $ISOPTS/virtio"
            fi
        fi
    fi 
    # 3. Tuer le démon des qu'on a fini de s'en servir
    if [[ -n "$MOUNTD_PID" ]]; then
        echo "quit" > "$MOUNT_FIFO" 2>/dev/null || true
        wait "$MOUNTD_PID" 2>/dev/null || true
        rm -f "$MOUNT_FIFO" 2>/dev/null || true
    fi
    # 4. Nettoyage des répertoires ISO
    if [[ -n "$ISOPTS" ]]; then
        [[ -d "$ISOPTS/win" ]] && rmdir "$ISOPTS/win" 2>/dev/null || true
        [[ -d "$ISOPTS/virtio" ]] && rmdir "$ISOPTS/virtio" 2>/dev/null || true
    fi
    # 5. Nettoyage des répertoires WIM extraits
    if [[ -n "$WIMPTS" ]]; then
        [[ -d "$WIMPTS/boot" ]] && rm -rf "$WIMPTS/boot" 2>/dev/null || true
        [[ -d "$WIMPTS/install" ]] && rm -rf "$WIMPTS/install" 2>/dev/null || true
    fi
}

# copie vers la boite a patcher les patchs : $WORKDIR
###########################################################
cp "$SELFPATH/autounattend.xml" "$WORKDIR/"
cp "$SELFPATH/firstLogon.ps1" "$WORKDIR/"
cp "$SELFPATH/secondLogon.ps1" "$WORKDIR/"
# export env de l HOST vers GUEST via $WORKDIR
###########################################################
echo "[*] Détection de la locale hôte ..."
HOSTLOC=$(locale | awk -F= '/^LANG=/{print $2}' | cut -d. -f1)
if [[ -z "$HOSTLOC" || "$HOSTLOC" == "C" ]]; then
    echo "    -> Locale hôte = C (fallback)"
    GUESTLOC="en-US"
else
    GUESTLOC=$(echo "$HOSTLOC" | tr '_' '-')
    echo "    -> Locale hôte détectée : $HOSTLOC → $GUESTLOC"
fi
echo "[*] Détection du clavier hôte ..."
if [[ -f /etc/default/keyboard ]]; then
    HOSTKB=$(awk -F= '/XKBLAYOUT/{gsub(/"/,"",$2); print $2}' /etc/default/keyboard)
elif [[ -f /etc/vconsole.conf ]]; then
    HOSTKB=$(awk -F= '/KEYMAP/{print $2}' /etc/vconsole.conf)
else
    HOSTKB=$(locale | awk -F= '/^LANG=/{print $2}' | cut -d_ -f1)
fi
if [[ -z "$HOSTKB" ]]; then
    echo "    -> Impossible de détecter le clavier, fallback en US"
    GUESTKB="en-US"
else
    echo "    -> Clavier hôte détecté : $HOSTKB"
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
echo "    -> Mapping clavier invité = $GUESTKB"
for f in autounattend.xml firstLogon.ps1 secondLogon.ps1; do
    if [[ ! -f "$SELFPATH/$f" ]]; then
        echo "ERREUR: $f introuvable dans $SELFPATH"
        exit 1
    fi
done
echo "[*] Application locale + clavier dans autounattend.xml"
sed -i "s/__LOCALE__/$GUESTLOC/g" "$WORKDIR/autounattend.xml"
sed -i "s/__KEYBOARD__/$GUESTKB/g" "$WORKDIR/autounattend.xml"
echo "[*] Vérification des modifications (diff)..."
diff -u "$WORKDIR/autounattend.original.xml" "$WORKDIR/autounattend.xml" \
    || echo "    -> Diff affiché ci-dessus"
echo "[*] Vérification XML (xmllint)..."
xmllint --noout "$WORKDIR/autounattend.xml" \
    || { echo "[ERREUR] autounattend.xml invalide"; exit 1; }
echo "    -> XML valide"
if grep -q "__LOCALE__\|__KEYBOARD__" "$WORKDIR/autounattend.xml"; then
    echo "[ERREUR] Un ou plusieurs placeholders n'ont pas été remplacés"
    exit 1
fi
echo "    -> Placeholders remplacés correctement"
echo "    -> autounattend.xml OK"
# Fin du patchage de patch
###########################################################

###########################################################
# Phase d injections                 
ISO_WIN="$(ls Win1*.iso 2>/dev/null | head -n 1 || true)"
if [[ -z "$ISO_WIN" ]]; then
    echo "ERREUR: Aucun ISO Windows trouvé (Win1*.iso)"
    exit 1
fi
echo "[*] ISO Windows détecté : $ISO_WIN"
echo "[*] Recherche de l’ISO VirtIO…"
ISO_VIRTIO="$(ls virtio-wi*.iso 2>/dev/null | head -n 1 || true)"
if [[ -z "$ISO_VIRTIO" ]]; then
    echo "ERREUR: Aucun ISO VirtIO trouvé (virtio-win*.iso)"
    echo "Télécharge-le depuis https://fedorapeople.org/groups/virt/virtio-win/"
    exit 1
fi
echo "    -> ISO VirtIO détecté : $ISO_VIRTIO"
echo "Création des points de montage."
mkdir -p "$ISOPTS"/win "$ISOPTS"/virtio
if [[ ! -z $(ls -A "$ISOPTS"/win) ]]; then
    echo "ERREUR: $ISOPTS/win doit être vide"
    exit 1
fi
if [[ ! -z $(ls -A "$ISOPTS"/virtio) ]]; then
    echo "ERREUR: $ISOPTS/virtio doit être vide"
    exit 1
fi
d_mount $ISO_WIN $ISOPTS/win"
read -r resp < "$RESP_FIFO"
[[ "$resp" == OK ]] || { echo "ERREUR: montage $ISO_WIN"; exit 1; }
d_mount $ISO_VIRTIO $ISOPTS/virtio"
read -r resp < "$RESP_FIFO"
[[ "$resp" == OK ]] || { echo "ERREUR: montage $ISO_VIRTIO"; exit 1; }
echo "  -> ISOs montés avec succès"
# Dossier de travail pour l’ISO modifié
mkdir iso_work
echo "Génération d'une copie writable de l'ISO win ..."
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
:: Détection du disque debug par UUID
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
# 6 est l'index win pro
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
echo "[*] Drivers injectés dans les WIM"
#Démontage propre via le démon
if [[ -d "$ISOPTS/win" ]]; then
    d_umount "$ISOPTS/win" && echo "WARN: échec du démontage de $ISO_WIN"
fi 
if [[ -d "$ISOPTS/virtio" ]]; then
    d_umount "$ISOPTS/virtio" && echo "WARN: échec du démontage de virtio"
fi 

# --- ICI ON DECHARGE LA BOITE A PATCHER LES PATCHS ---
mv "$WORKDIR"/* iso_work/
# --- RECONSTRUCTION ISO ---
mkisofs -U -udf \
    -b boot/etfsboot.com \
        -no-emul-boot -boot-load-size 8 -boot-info-table \
    -eltorito-alt-boot -eltorito-platform efi \
        -eltorito-boot EFI/boot/bootx64.efi -no-emul-boot \
    -o "$CUSTOMISO" iso_work || exit 1
d_umount "$ISOPTS"/win && echo "[WARN] $ISO_WIN n a pas pu etre démonté"
    || rm -r "$ISOPTS"/win
rm -r iso_work
echo "[*] ISO reconstruite : $CUSTOMISO"

check_or_create_qcow2() {
    echo "[CHECK] Vérification du disque QCOW2..."
    if [[ ! -f "$QCOW2" ]]; then
        echo "[CREATE] Aucun disque trouvé, création de $QCOW2..."
        qemu-img create -f qcow2 "$QCOW2" 40G \
        && echo "[OK] Disque QCOW2 créé." \
        || { echo "[ERREUR] Impossible de créer le QCOW2."; exit 1; }
    else
        echo "[OK] Disque QCOW2 déjà présent."
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
    echo "⚠️  Assure-toi que Windows est éteint proprement."
    echo "Appuie sur Entrée pour shrinker..."
    read
    echo "[CHECK] Vérification du disque..."
    qemu-img check "$QCOW2"
    echo "[SHRINK] Conversion vers un QCOW2 compacté..."
    qemu-img convert -O qcow2 -o compat=1.1 "$QCOW2" win-shrink.qcow2
    echo "[REPLACE] Remplacement du disque..."
    mv "$QCOW2" win-old.qcow2
    mv win-shrink.qcow2 "$QCOW2"
    echo "[DONE] Shrink terminé !"
    echo "Ancien disque : win-old.qcow2"
    echo "Nouveau disque : $QCOW2"
    echo
    echo "===================================================="
    echo " FIN DU PIPELINE WINDOWS"
    echo "===================================================="
}

# 0. Création du QCOW2 si absent
check_or_create_qcow2 \
&& echo "[OK] QCOW2 prêt." \
|| { echo "[ERREUR] $QCOW2 manquant ou impossible à créer."; exit 1; }

# 1- Rappels sur les modes de debug
QEMU_DEBUG_OPTS=""
[[ $DBG_SERIAL  -eq 1 ]] && QEMU_DEBUG_OPTS+=" -serial stdio"
[[ $DBG_MONITOR -eq 1 ]] && QEMU_DEBUG_OPTS+=" -monitor telnet:127.0.0.1:4444,server,nowait"
[[ $DBG_KERNEL  -eq 1 ]] && QEMU_DEBUG_OPTS+=" -debugcon file:kernel_debug.log"
echo "[*] QEMU debug opts : $QEMU_DEBUG_OPTS"
if [[ $DBG_PANTHER -eq 1 ]]; then
    echo "[*] Mode g4 activé : capture en direct des logs Panther (setupact / setuperr)"
    echo "    Les logs seront streamés en temps réel vers :"
    echo "      $SELFPATH/logs/panther/setupact.log"
    echo "      $SELFPATH/logs/panther/setuperr.log"
    echo "    Un disque debug.qcow2 temporaire est utilisé comme tampon de lecture."
fi

# 1. Installation
phase_install \
&& echo "[OK] Phase 1 terminée." \
|| { echo "[ERREUR] Phase 1 a échoué."; exit 1; }

# 2. First boot
phase_firstboot \
&& echo "[OK] Phase 2 terminée." \
|| { echo "[ERREUR] Phase 2 a échoué."; exit 1; }

# 3. Second boot
phase_secondboot \
&& echo "[OK] Phase 3 terminée." \
|| { echo "[ERREUR] Phase 3 a échoué."; exit 1; }

# 4. Shrink final
shrink_qcow2 \
&& echo "[OK] Shrink $QCOW2 terminée." \
|| { echo "[ERREUR] Phase 4 a échoué."; exit 1; }
exit 0;

###############################################
#               DÉMON INLINE
###############################################
if [[ "$1" == "--daemon" ]]; then
    CMD_FIFO="$2"
    RESP_FIFO="$3"
    # Sécurité : RUNNER doit exister
    : "${RUNNER:?RUNNER non défini}"
    # Boucle principale
    while read -r cmd arg1 arg2; do
        case "$cmd" in
            mount)
                if mount -o loop,ro "$arg1" "$arg2" 2>/dev/null; then
                    chown -R "$RUNNER:$RUNNER" "$arg2" 2>/dev/null
                    echo "OK" > "$RESP_FIFO"
                else
                    echo "ERR mount $arg1" > "$RESP_FIFO"
                fi
                ;;
            umount)
                if umount "$arg1" 2>/dev/null; then
                    echo "OK" > "$RESP_FIFO"
                else
                    echo "ERR umount $arg1" > "$RESP_FIFO"
                fi
                ;;
            quit)
                echo "OK" > "$RESP_FIFO"
                break
                ;;
            *)
                echo "ERR unknown_cmd $cmd" > "$RESP_FIFO"
                ;;
        esac
    done < "$CMD_FIFO"
    exit 0
fi
