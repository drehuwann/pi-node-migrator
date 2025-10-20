# Pi Node Migrator

## Description
Script de migration de node Pi Network pour les syst�mes Debian/Linux

###Fonctionnalit�s
- Migration automatis�e de node Pi
- Transfert s�curis� des configurations
- Support pour environnements Debian/LXDE

## Pr�requis

### Syst�me Windows
- PowerShell 5.1 ou sup�rieur
- Connexion SSH configur�e
- Droits administrateur

### Syst�me Debian
- Debian 10/11 
- LXDE recommand�
- Docker install�
- Acc�s SSH

## Installation

### D�pendances
```bash
sudo apt-get update
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    docker.io \
    docker-compose
```
##Configuration
###Variables Requises

    $AdresseIP : IP du node Debian
    $Utilisateur : Utilisateur SSH
    $MotDePasse : Mot de passe SSH

##Utilisation

```powershell
.\pi-node-migrator.ps1
```
R�f�rence Officielle

    Pi Network Node Documentation

##Licence

GNU General Public License v3.0

Copyright � 2025 drehuwann drehuwann@gmail.com

Ce programme est un logiciel libre ; vous pouvez le redistribuer et/ou le modifier selon les termes de la Licence Publique G�n�rale GNU publi�e par la Free Software Foundation.
Avertissement pour D�butants

##Vous �tes nouveau avec Pi Network ?

    Qu'est-ce qu'un node Pi ?
        Un ordinateur qui participe � la validation des transactions
        Contribue � la s�curit� et � la d�centralisation du r�seau

    Pr�requis Techniques Minimum
        Ordinateur sous Linux/Debian
        Connexion Internet stable
        4 Go RAM recommand�es
        50 Go d'espace disque

    S�curit�
        Utilisez toujours des mots de passe robustes
        Mettez � jour r�guli�rement vos syst�mes
        Configurez un pare-feu

##Confidentialit�

    Ne partagez JAMAIS vos cl�s priv�es
    Utilisez des connexions s�curis�es
    V�rifiez toujours les sources

##Contribution

Les contributions sont les bienvenues !
Merci de soumettre vos Pull Requests.
Support

En cas de probl�me, ouvrez un ticket GitHub ou contactez support@pi-network.org
