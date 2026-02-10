<details>
<summary>🇫🇷 Français</summary>

<!-- Ton contenu actuel en français -->

# Pi Node Migrator

## Description
Script de migration de node Pi Network pour les systèmes Debian/Linux

### Fonctionnalités
- Migration automatisée de node Pi
- Transfert sécurisé des configurations
- Support pour environnements Debian

## Prérequis

### Système Windows
- PowerShell 5.1 ou supérieur
- Connexion client SSH configurée
- Droits administrateur
- Pi-node installé et configuré

### Système Debian
- Debian 10/11 
- Accès client/serveur SSH pour utilisateur ayant les droits root

### Dépendances
- Normalement gérées par le script

## Utilisation

### Sur l'hôte Debian
Allumez votre machine Debian. Le script vous guidera pour effectuer les manipulations nécessaires sur cet hôte.

### Sur l'hôte Windows
⚠️ Important : le noeud Pi sur Windows doit être **arrêté** avant de lancer la migration.  
Cela évite tout conflit entre les deux environnements et garantit l’intégrité des données.

1. **Ouvrir PowerShell en tant qu’administrateur**  
   - Cliquez sur le menu Démarrer  
   - Tapez `PowerShell`  
   - Faites un clic droit sur **Windows PowerShell** → sélectionnez **Exécuter en tant qu’administrateur**

2. **Télécharger le script PowerShell**  
   - Accédez au dépôt GitHub :  
     [pi-node-migrator.ps1](https://github.com/drehuwann/pi-node-migrator/blob/main/pi-node-migrator.ps1)  
   - Cliquez sur **Raw**, puis faites un clic droit → **Enregistrer sous...**  
   - Sauvegardez le fichier dans un dossier facile d’accès, par exemple `C:\PiNodeMigrator`

3. **Naviguer jusqu’au dossier du script**  
   Dans PowerShell, tapez :
   ```powershell
   cd "C:\PiNodeMigrator"
   ```

4. **Vérifier et modifier la stratégie d’exécution**  
   PowerShell peut empêcher l’exécution de scripts pour des raisons de sécurité. Pour vérifier la stratégie actuelle :
   ```powershell
   Get-ExecutionPolicy
   ```
   Si la réponse est `Restricted`, cela signifie que **aucun script ne peut être exécuté**, même local.

   👉 Dans ce cas, vous devez temporairement autoriser l’exécution des scripts signés ou locaux. Voici comment faire :
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope Process
   ```
   - `RemoteSigned` : autorise les scripts locaux non signés, mais exige une signature pour les scripts téléchargés.
   - `-Scope Process` : applique ce changement **uniquement à la session PowerShell en cours** (aucun impact permanent sur le système).

   💡 Exemple complet :
   ```powershell
   Get-ExecutionPolicy
   # Résultat : Restricted

   Set-ExecutionPolicy RemoteSigned -Scope Process
   # Confirmez avec "Y" si demandé

   .\pi-node-migrator.ps1
   ```

5. **Exécuter le script**  
   Lancez le script avec :
   ```powershell
   .\pi-node-migrator.ps1
   ```

### 📌 Remarques
- Le script s'assure que votre hôte Debian est accessible via SSH.
- Le script gère automatiquement les dépendances nécessaires.
- Suivez les instructions affichées dans PowerShell pour compléter la migration.

## Référence Officielle
[Pi Network Node Documentation](https://minepi.com/pi-blockchain/pi-node/linux/) a servi a réaliser ce script.

## Licence
GNU General Public License v3.0

Copyright © 2025 drehuwann drehuwann@gmail.com

Ce programme est un logiciel libre ; vous pouvez le redistribuer et/ou le modifier selon les termes de la Licence Publique Générale GNU publiée par la Free Software Foundation.

## Vous êtes nouveau avec Pi Network ?
### Qu'est-ce qu'un node Pi ?
- Un ordinateur qui participe à la validation des transactions
- Contribue à la sécurité et à la décentralisation du réseau

### Prérequis Techniques Minimum
- Ordinateur sous Linux/Debian
- Connexion Internet stable
- 4 Go RAM recommandées
- 50 Go d'espace disque

### Sécurité
- Utilisez toujours des mots de passe robustes
- Mettez à jour régulièrement vos systèmes
- Configurez un pare-feu

### Confidentialité
- Ne partagez JAMAIS vos clés privées
- Utilisez des connexions sécurisées
- Vérifiez toujours les sources

## Contribution
Les contributions sont les bienvenues !
Merci de soumettre vos Pull Requests.

## Support
En cas de problème, ouvrez un ticket GitHub ou contactez support@pi-network.org
</details>

---

<details>
<summary>🇬🇧 English</summary>

<!-- Traduction anglaise du même contenu -->

</details>
