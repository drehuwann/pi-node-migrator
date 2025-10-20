# Pi Node Migrator

## Description
Script de migration de node Pi Network pour les systèmes Debian/Linux

###Fonctionnalités
- Migration automatisée de node Pi
- Transfert sécurisé des configurations
- Support pour environnements Debian/LXDE

## Prérequis

### Système Windows
- PowerShell 5.1 ou supérieur
- Connexion SSH configurée
- Droits administrateur

### Système Debian
- Debian 10/11 
- LXDE recommandé
- Docker installé
- Accès SSH

## Installation

### Dépendances
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
Référence Officielle

    Pi Network Node Documentation

##Licence

GNU General Public License v3.0

Copyright © 2025 drehuwann drehuwann@gmail.com

Ce programme est un logiciel libre ; vous pouvez le redistribuer et/ou le modifier selon les termes de la Licence Publique Générale GNU publiée par la Free Software Foundation.
Avertissement pour Débutants

##Vous êtes nouveau avec Pi Network ?

    Qu'est-ce qu'un node Pi ?
        Un ordinateur qui participe à la validation des transactions
        Contribue à la sécurité et à la décentralisation du réseau

    Prérequis Techniques Minimum
        Ordinateur sous Linux/Debian
        Connexion Internet stable
        4 Go RAM recommandées
        50 Go d'espace disque

    Sécurité
        Utilisez toujours des mots de passe robustes
        Mettez à jour régulièrement vos systèmes
        Configurez un pare-feu

##Confidentialité

    Ne partagez JAMAIS vos clés privées
    Utilisez des connexions sécurisées
    Vérifiez toujours les sources

##Contribution

Les contributions sont les bienvenues !
Merci de soumettre vos Pull Requests.
Support

En cas de problème, ouvrez un ticket GitHub ou contactez support@pi-network.org
