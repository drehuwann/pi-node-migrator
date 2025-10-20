# Script de Préparation de Migration de Node Pi Network

# Fonction pour afficher un message en français avec mise en forme
function Afficher-Message {
    param(
        [string]$Message, 
        [System.ConsoleColor]$Couleur = [System.ConsoleColor]::White
    )
    Write-Host $Message -ForegroundColor $Couleur
}

function Demander-InformationsHote {
    $global:hoteDebian = @{
        AdresseIP = $null
        Utilisateur = $null
        MotDePasse = $null
    }

    Clear-Host
    Afficher-Message "=== Configuration du Node Pi Network ===" -Couleur Cyan
    Afficher-Message "Guide de Récupération des Informations Réseau sur Debian (LXDE)" -Couleur Green

    # Instructions pour l'utilisateur
    Afficher-Message "`nÉtapes à suivre sur l'ordinateur Debian :" -Couleur Yellow
    Afficher-Message "1. Ouvrez le Terminal (Ctrl+Alt+T)" -Couleur White
    Afficher-Message "2. Tapez les commandes suivantes :" -Couleur Whit
    Afficher-Message "   - Pour l'adresse IP : " -Couleur Cyan
    Afficher-Message "     ip addr show" -Couleur Green
    Afficher-Message "   - Pour le nom d'utilisateur :" -Couleur Cyan  
    Afficher-Message "     whoami" -Couleur Green

    # Saisie de l'adresse IP
    do {
        $ip = Read-Host "`nEntrez l'adresse IP du node Debian (ex: 192.168.1.100)"
        if ($ip -match '^(\d{1,3}\.){3}\d{1,3}$') {
            $global:hoteDebian.AdresseIP = $ip
            break
        } else {
            Afficher-Message "Format d'adresse IP invalide. Réessayez." -Couleur Red
        }
    } while ($true)

    # Saisie du nom d'utilisateur
    do {
        $utilisateur = Read-Host "Entrez le nom d'utilisateur SSH"
        if (-not [string]::IsNullOrWhiteSpace($utilisateur)) {
            $global:hoteDebian.Utilisateur = $utilisateur
            break
        }
    } while ($true)

    # Saisie du mot de passe
    $motDePasse = Read-Host "Entrez le mot de passe SSH" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($motDePasse)
    $global:hoteDebian.MotDePasse = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

    # Vérification de la connexion SSH
    return (Tester-ConnexionSSH)
}

function Tester-ConnexionSSH {
    try {
        $result = ssh -o ConnectTimeout=5 "$($global:hoteDebian.Utilisateur)@$($global:hoteDebian.AdresseIP)" "echo CONNEXION_REUSSIE"
        if ($result -eq "CONNEXION_REUSSIE") {
            Afficher-Message "Connexion SSH réussie !" -Couleur Green
            return $true
        } else {
            Afficher-Message "Échec de la connexion SSH. Vérifiez les identifiants et le réseau." -Couleur Red
            return $false
        }
    } catch {
        Afficher-Message "Erreur de connexion SSH : $_" -Couleur Red
        return $false
    }
}
function Rechercher-FichierConfiguration {
    $dossierMigration = Join-Path $env:USERPROFILE "PiNodeMigration"

    # Créer le dossier de migration s'il n'existe pas
    if (-not (Test-Path -Path $dossierMigration)) {
        New-Item -ItemType Directory -Path $dossierMigration | Out-Null
    }

    # Modèles de recherche des fichiers de configuration
    $modelesRecherche = @(
        "mainnet.env", 
        "stellar-core.cfg", 
        "docker-compose.yml", 
        "config.json", 
        "node-config.yml"
    )

    # Emplacements de recherche
    $emplacementsRecherche = @(
        "C:\ProgramData\Docker",
        "C:\Program Files\Docker",
        "$env:USERPROFILE\.docker",
        "$env:USERPROFILE\Documents\Docker",
        "$env:APPDATA\Pi Network",
        "C:\ProgramData\Pi Network"
    )

    $fichiersTraouves = @()

    # Recherche des fichiers
    foreach ($emplacement in $emplacementsRecherche) {
        foreach ($modele in $modelesRecherche) {
            try {
                $resultats = Get-ChildItem -Path $emplacement -Recurse -Filter $modele -ErrorAction Stop
                $fichiersTraouves += $resultats
            } catch {
                Afficher-Message "Impossible de rechercher dans $emplacement" -Couleur Yellow
            }
        }
    }

    # Copier les fichiers trouvés dans le dossier de migration
    foreach ($fichier in $fichiersTraouves) {
        $cheminDestination = Join-Path $dossierMigration $fichier.Name
        try {
            Copy-Item -Path $fichier.FullName -Destination $cheminDestination -Force
            Afficher-Message "Copié : $($fichier.FullName) vers $cheminDestination" -Couleur Green
        } catch {
            Afficher-Message "Échec de la copie de $($fichier.FullName)" -Couleur Red
        }
    }

    return $fichiersTraouves
}

function Generer-ScriptPreparationDebian {
    param($AdresseIP, $Utilisateur)

    $scriptContenu = @"
#!/bin/bash

# Script de Préparation du node Pi Network
set -e

# Fonction de journalisation
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Étape 1 : Mise à jour des packages et installation des prérequis
log "Mise à jour des listes de packages APT"
sudo apt-get update 

log "Installation des packages prérequis"
sudo apt-get install -y ca-certificates curl gnupg 
sudo apt-get install -y docker.io docker-compose

# Étape 2 : Ajout du dépôt Pi Network
log "Ajout de la clé GPG Pi Network"
sudo install -m 0755 -d /etc/apt/keyrings 
curl -fsSL https://apt.minepi.com/repository.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/pinetwork-archive-keyring.gpg 
sudo chmod a+r /etc/apt/keyrings/pinetwork-archive-keyring.gpg 

log "Ajout du dépôt APT Pi Network"
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/pinetwork-archive-keyring.gpg] https://apt.minepi.com stable main' | sudo tee /etc/apt/sources.list.d/pinetwork.list > /dev/null

# Mise à jour de l'index des packages APT
sudo apt-get update

# Étape 2 : Installation du package Pi Node
log "Installation du package Pi Node"
sudo apt-get install -y pi-node 

# Vérification de l'installation
pi-node --version

# Étape 3 : Préparation du répertoire de migration
mkdir -p ~/pi_migration
chmod 700 ~/pi_migration
cd ~/pi_migration

# Fonction de recherche et d'extraction des identifiants
extraire_identifiants() {
    local fichiers=(
        "./mainnet.env"
        "./stellar-core.cfg"
        "./docker-compose.yml"
        "./config.json"
    )

    local node_seed=""
    local postgres_password=""
    local docker_volumes=""

    for fichier in "${fichiers[@]}"; do
        if [[ -f "$fichier" ]]; then
            # Extraction des identifiants
            node_seed=$(grep -E '^(NODE_SEED|NODE_PRIVATE_KEY)=' "$fichier" | cut -d'=' -f2 | tr -d ' ')
            postgres_password=$(grep -E '^POSTGRES_PASSWORD=' "$fichier" | cut -d'=' -f2 | tr -d ' ')
            docker_volumes=$(grep -E 'volumes:' "$fichier" | cut -d':' -f2 | tr -d ' ')

            # Arrêter si les identifiants sont trouvés
            [[ -n "$node_seed" && -n "$postgres_password" ]] && break
        fi
    done

    # Validation et utilisation des identifiants
    if [[ -n "$node_seed" && -n "$postgres_password" ]]; then
        log "Identifiants trouvés. Initialisation du node..."
        pi-node initialize \
            --pi-folder "$HOME/pi-node" \
            --docker-volumes "${docker_volumes:-./docker_volumes/mainnet}" \
            --node-seed "$node_seed" \
            --postgres-password "$postgres_password" \
            --start-node
    else
        log "ERREUR : Impossible de trouver les identifiants complets du node"
        return 1
    fi
}

# Exécution principale
log "Début de la préparation de migration du node Pi"
extraire_identifiants

# Nettoyage final
log "Nettoyage des fichiers temporaires"
rm -rf ~/pi_migration/*

log "Migration du node Pi terminée avec succès"
"@

    # Chemin du script sur le système local
    $cheminScriptLocal = Join-Path $dossierMigration "preparation_node_pi.sh"
    
    # Enregistrer le script
    $scriptContenu | Out-File -FilePath $cheminScriptLocal -Encoding UTF8

    # Rendre le script exécutable
    & chmod +x $cheminScriptLocal

    # Transférer le script via SCP
    try {
        scp $cheminScriptLocal "$Utilisateur@$AdresseIP:~/preparation_node_pi.sh"
        Afficher-Message "Script transféré avec succès sur l'hôte Debian" -Couleur Green
    } catch {
        Afficher-Message "Échec du transfert du script" -Couleur Red
    }
}

# Fonction principale d'exécution
function Executer-MigrationNodePi {
    # Demander les informations de l'hôte
    if (Demander-InformationsHote) {
        # Rechercher les fichiers de configuration
        $fichiersConfiguration = Rechercher-FichierConfiguration

        # Générer et transférer le script de préparation
        Generer-ScriptPreparationDebian -AdresseIP $global:hoteDebian.AdresseIP -Utilisateur $global:hoteDebian.Utilisateur

        # Afficher un résumé
        Afficher-Message "`nRésumé de la migration :" -Couleur Cyan
        Afficher-Message "Adresse IP du node Debian : $($global:hoteDebian.AdresseIP)" -Couleur White
        Afficher-Message "Utilisateur SSH : $($global:hoteDebian.Utilisateur)" -Couleur White
        Afficher-Message "Fichiers de configuration trouvés : $($fichiersConfiguration.Count)" -Couleur White

        # Demander confirmation avant l'exécution finale
        $confirmation = Read-Host "Voulez-vous exécuter le script de migration sur le node Debian ? (O/N)"
        
        if ($confirmation -eq 'O' -or $confirmation -eq 'o') {
            try {
                # Exécution du script sur l'hôte distant
                $resultat = ssh "$($global:hoteDebian.Utilisateur)@$($global:hoteDebian.AdresseIP)" "bash ~/preparation_node_pi.sh"
                
                Afficher-Message "Migration du node Pi terminée avec succès" -Couleur Green
                Afficher-Message "Détails de l'exécution :" -Couleur White
                Afficher-Message $resultat -Couleur Cyan
            } catch {
                Afficher-Message "Erreur lors de l'exécution du script de migration : $_" -Couleur Red
            }
        } else {
            Afficher-Message "Migration annulée par l'utilisateur" -Couleur Yellow
        }
    } else {
        Afficher-Message "La connexion à l'hôte Debian a échoué. Veuillez vérifier les paramètres." -Couleur Red
    }
}

function Test-PiNode {
    Write-Host "=== Tests post-migration ==="

    $allOk = $true

    # Vérifier que pi-node est accessible
    & ssh "$sshUser@$sshTarget" "pi-node --help" | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "pi-node est installé et accessible."
    } else {
        Write-Warning "pi-node n'est pas disponible."
	$allOk = $false
    }

    # Vérifier l'état du conteneur mainnet
    $dockerStatus = & ssh "$sshUser@$sshTarget" "docker ps --filter 'name=mainnet' --format '{{.Status}}'"
    if ($dockerStatus) {
        Write-Host "Conteneur mainnet trouvé : $dockerStatus"
    } else {
        Write-Warning "Conteneur mainnet introuvable ou arrêté."
	$allOk = $false
    }

    # Afficher quelques lignes de logs
    $logs = & ssh "$sshUser@$sshTarget" "docker logs --tail 5 mainnet 2>&1"
    Write-Host "Extrait des logs du conteneur mainnet :"
    Write-Host $logs

    Write-Host "=== Fin des tests ==="
    return $allOk
}

# Point d'entrée du script
try {
    Afficher-Message "Script de Migration de node Pi Network" -Couleur Magenta
    Afficher-Message "Version 1.0 - © drehuwann - https://github.com/drehuwann" -Couleur DarkGray
    Afficher-Message "Contact : mailto:drehuwann@gmail.com" -Couleur DarkGray
    Executer-MigrationNodePi
} catch {
    Afficher-Message "Une erreur inattendue s'est produite : $_" -Couleur Red
} finally {
    Afficher-Message "`nFin du processus de migration" -Couleur White
    $testResult = Test-PiNode
    if ($testResult) {
        exit 0   # succès
    } else {
        exit 1   # erreur
    }
}

