# Script de Pr�paration de Migration de Node Pi Network

# Fonction pour afficher un message en fran�ais avec mise en forme
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
    Afficher-Message "Guide de R�cup�ration des Informations R�seau sur Debian (LXDE)" -Couleur Green

    # Instructions pour l'utilisateur
    Afficher-Message "`n�tapes � suivre sur l'ordinateur Debian :" -Couleur Yellow
    Afficher-Message "1. Ouvrez le Terminal (Ctrl+Alt+T)" -Couleur White
    Afficher-Message "2. Tapez les commandes suivantes :" -Couleur White
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
            Afficher-Message "Format d'adresse IP invalide. R�essayez." -Couleur Red
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

    # V�rification de la connexion SSH
    return (Tester-ConnexionSSH)
}

function Tester-ConnexionSSH {
    try {
        $result = ssh -o ConnectTimeout=5 "$($global:hoteDebian.Utilisateur)@$($global:hoteDebian.AdresseIP)" "echo CONNEXION_REUSSIE"
        if ($result -eq "CONNEXION_REUSSIE") {
            Afficher-Message "Connexion SSH r�ussie !" -Couleur Green
            return $true
        } else {
            Afficher-Message "�chec de la connexion SSH. V�rifiez les identifiants et le r�seau." -Couleur Red
            return $false
        }
    } catch {
        Afficher-Message "Erreur de connexion SSH : $_" -Couleur Red
        return $false
    }
}
function Rechercher-FichierConfiguration {
    $dossierMigration = Join-Path $env:USERPROFILE "PiNodeMigration"

    # Cr�er le dossier de migration s'il n'existe pas
    if (-not (Test-Path -Path $dossierMigration)) {
        New-Item -ItemType Directory -Path $dossierMigration | Out-Null
    }

    # Mod�les de recherche des fichiers de configuration
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

    # Copier les fichiers trouv�s dans le dossier de migration
    foreach ($fichier in $fichiersTraouves) {
        $cheminDestination = Join-Path $dossierMigration $fichier.Name
        try {
            Copy-Item -Path $fichier.FullName -Destination $cheminDestination -Force
            Afficher-Message "Copi� : $($fichier.FullName) vers $cheminDestination" -Couleur Green
        } catch {
            Afficher-Message "�chec de la copie de $($fichier.FullName)" -Couleur Red
        }
    }

    return $fichiersTraouves
}

function Generer-ScriptPreparationDebian {
    param($AdresseIP, $Utilisateur)

    $scriptContenu = @"
#!/bin/bash

# Script de Pr�paration du node Pi Network
set -e

# Fonction de journalisation
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# �tape 1 : Mise � jour des packages et installation des pr�requis
log "Mise � jour des listes de packages APT"
sudo apt-get update 

log "Installation des packages pr�requis"
sudo apt-get install -y ca-certificates curl gnupg 
sudo apt-get install -y docker.io docker-compose

# �tape 2 : Ajout du d�p�t Pi Network
log "Ajout de la cl� GPG Pi Network"
sudo install -m 0755 -d /etc/apt/keyrings 
curl -fsSL https://apt.minepi.com/repository.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/pinetwork-archive-keyring.gpg 
sudo chmod a+r /etc/apt/keyrings/pinetwork-archive-keyring.gpg 

log "Ajout du d�p�t APT Pi Network"
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/pinetwork-archive-keyring.gpg] https://apt.minepi.com stable main' | sudo tee /etc/apt/sources.list.d/pinetwork.list > /dev/null

# Mise � jour de l'index des packages APT
sudo apt-get update

# �tape 2 : Installation du package Pi Node
log "Installation du package Pi Node"
sudo apt-get install -y pi-node 

# V�rification de l'installation
pi-node --version

# �tape 3 : Pr�paration du r�pertoire de migration
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

            # Arr�ter si les identifiants sont trouv�s
            [[ -n "$node_seed" && -n "$postgres_password" ]] && break
        fi
    done

    # Validation et utilisation des identifiants
    if [[ -n "$node_seed" && -n "$postgres_password" ]]; then
        log "Identifiants trouv�s. Initialisation du node..."
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

# Ex�cution principale
log "D�but de la pr�paration de migration du node Pi"
extraire_identifiants

# Nettoyage final
log "Nettoyage des fichiers temporaires"
rm -rf ~/pi_migration/*

log "Migration du node Pi termin�e avec succ�s"
"@

    # Chemin du script sur le syst�me local
    $cheminScriptLocal = Join-Path $dossierMigration "preparation_node_pi.sh"
    
    # Enregistrer le script
    $scriptContenu | Out-File -FilePath $cheminScriptLocal -Encoding UTF8

    # Rendre le script ex�cutable
    & chmod +x $cheminScriptLocal

    # Transf�rer le script via SCP
    try {
        scp $cheminScriptLocal "$Utilisateur@$AdresseIP:~/preparation_node_pi.sh"
        Afficher-Message "Script transf�r� avec succ�s sur l'h�te Debian" -Couleur Green
    } catch {
        Afficher-Message "�chec du transfert du script" -Couleur Red
    }
}

# Fonction principale d'ex�cution
function Executer-MigrationNodePi {
    # Demander les informations de l'h�te
    if (Demander-InformationsHote) {
        # Rechercher les fichiers de configuration
        $fichiersConfiguration = Rechercher-FichierConfiguration

        # G�n�rer et transf�rer le script de pr�paration
        Generer-ScriptPreparationDebian -AdresseIP $global:hoteDebian.AdresseIP -Utilisateur $global:hoteDebian.Utilisateur

        # Afficher un r�sum�
        Afficher-Message "`nR�sum� de la migration :" -Couleur Cyan
        Afficher-Message "Adresse IP du node Debian : $($global:hoteDebian.AdresseIP)" -Couleur White
        Afficher-Message "Utilisateur SSH : $($global:hoteDebian.Utilisateur)" -Couleur White
        Afficher-Message "Fichiers de configuration trouv�s : $($fichiersConfiguration.Count)" -Couleur White

        # Demander confirmation avant l'ex�cution finale
        $confirmation = Read-Host "Voulez-vous ex�cuter le script de migration sur le node Debian ? (O/N)"
        
        if ($confirmation -eq 'O' -or $confirmation -eq 'o') {
            try {
                # Ex�cution du script sur l'h�te distant
                $resultat = ssh "$($global:hoteDebian.Utilisateur)@$($global:hoteDebian.AdresseIP)" "bash ~/preparation_node_pi.sh"
                
                Afficher-Message "Migration du node Pi termin�e avec succ�s" -Couleur Green
                Afficher-Message "D�tails de l'ex�cution :" -Couleur White
                Afficher-Message $resultat -Couleur Cyan
            } catch {
                Afficher-Message "Erreur lors de l'ex�cution du script de migration : $_" -Couleur Red
            }
        } else {
            Afficher-Message "Migration annul�e par l'utilisateur" -Couleur Yellow
        }
    } else {
        Afficher-Message "La connexion � l'h�te Debian a �chou�. Veuillez v�rifier les param�tres." -Couleur Red
    }
}

function Test-PiNode {
    Write-Host "=== Tests post-migration ==="

    $allOk = $true

    # V�rifier que pi-node est accessible
    & ssh "$sshUser@$sshTarget" "pi-node --help" | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "pi-node est install� et accessible."
    } else {
        Write-Warning "pi-node n'est pas disponible."
	$allOk = $false
    }

    # V�rifier l'�tat du conteneur mainnet
    $dockerStatus = & ssh "$sshUser@$sshTarget" "docker ps --filter 'name=mainnet' --format '{{.Status}}'"
    if ($dockerStatus) {
        Write-Host "Conteneur mainnet trouv� : $dockerStatus"
    } else {
        Write-Warning "Conteneur mainnet introuvable ou arr�t�."
	$allOk = $false
    }

    # Afficher quelques lignes de logs
    $logs = & ssh "$sshUser@$sshTarget" "docker logs --tail 5 mainnet 2>&1"
    Write-Host "Extrait des logs du conteneur mainnet :"
    Write-Host $logs

    Write-Host "=== Fin des tests ==="
    return $allOk
}

# Point d'entr�e du script
try {
    Afficher-Message "Script de Migration de node Pi Network" -Couleur Magenta
    Afficher-Message "Version 1.0 - �drehuwann <https://mailto:drehuwann@gmail.com Octobre 2025" -Couleur DarkGray
    
    Executer-MigrationNodePi
} catch {
    Afficher-Message "Une erreur inattendue s'est produite : $_" -Couleur Red
} finally {
    Afficher-Message "`nFin du processus de migration" -Couleur White
    $testResult = Test-PiNode
    if ($testResult) {
        exit 0   # succ�s
    } else {
        exit 1   # erreur
    }
}

