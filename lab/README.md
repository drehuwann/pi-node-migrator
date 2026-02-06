# 📘 README — Répertoire `lab/`

## 🎯 Objectif du répertoire

Le dossier **`lab/`** contient les scripts et ressources nécessaires au développement du pipeline d’installation et d’optimisation Windows 10 sous QEMU/KVM.  
Il s’agit d’un espace **WIP (Work In Progress)** destiné aux expérimentations, refactors et évolutions avant intégration dans la branche principale.

Ce répertoire ne contient **que les sources versionnées**.  
Les artefacts générés (ISO, QCOW2, fichiers temporaires…) ne sont **pas** stockés ici.

---

## 🧩 Contenu du répertoire

| Élément | Description |
|--------|-------------|
| **`win10-lab.sh`** | Script principal orchestrant la génération de l’ISO, l’installation Windows, l’optimisation et le shrink QCOW2 |
| `optimWin/` | Répertoire contenant les scripts PowerShell d’optimisation Windows **ainsi que les scripts OOBE (`fix-oobe.cmd`, `run-fix-oobe.cmd`)** |
| `build/` *(généré)* | Répertoire temporaire utilisé pour construire l’ISO (non versionné) |

### Détails du répertoire `optimWin/`

Ce répertoire contient :

- `optimize.ps1` — script principal d’optimisation Windows  
- `fix-oobe.cmd` *(ignoré par Git)* — correctif OOBE intégré dans l’ISO  
- `run-fix-oobe.cmd` *(ignoré par Git)* — lanceur automatique pour `fix-oobe.cmd`  

---

## 📦 Artefacts générés (non versionnés)

Les fichiers suivants **ne sont pas stockés dans le repo** et sont générés dans le répertoire depuis lequel `win10-lab.sh` est exécuté :

- `optimize.iso`
- `optimize.config.ps1`
- `win10.qcow2`
- `win10-old.qcow2`
- `win10-shrink.qcow2`
- fichiers temporaires dans `build/`

Ces fichiers sont exclus via `.gitignore`.

---

## ⚙️ Fonctionnement général

Le pipeline suit les étapes suivantes :

### **1. Construction de l’ISO d’optimisation**
- copie du script PowerShell source  
- ajout du BOM UTF‑8 si nécessaire  
- génération d’un fichier de configuration externe  
- création d’une ISO propre contenant :  
  - le script d’optimisation  
  - la configuration externe  
  - les scripts OOBE (`fix-oobe.cmd`, `run-fix-oobe.cmd`)  

### **2. Détection du disque Windows**
- installation si nécessaire  
- sinon reprise directe  

### **3. Optimisation Windows**
- lancement de la VM  
- exécution du script PowerShell (semi‑automatisée pour l’instant)  
- défragmentation automatique au reboot  

### **4. Shrink QCOW2**
- vérification du disque  
- conversion QCOW2 → QCOW2 compacté  
- remplacement du disque  

---

## 🚧 État actuel (WIP)

- Le pipeline fonctionne mais nécessite encore une intervention utilisateur dans PowerShell.  
- L’automatisation complète (exécution silencieuse, RunOnce, etc.) est prévue dans une prochaine itération.  
- Le passage à OVMF/UEFI est en cours d’étude pour fiabiliser le boot.  
- Le répertoire `lab/` évolue activement et peut changer rapidement.

---

## 🛠️ Améliorations prévues

- Exécution automatique du script PowerShell sans interaction  
- Nettoyage silencieux (remplacement de cleanmgr)  
- Passage complet à UEFI  
- Mode headless pour l’optimisation  
- Documentation complète du pipeline  
- Intégration d’un mécanisme de reprise automatique en cas d’erreur  

---

## 📌 Notes

- Les fichiers ignorés (`*.cmd`, artefacts générés…) sont copiés ou créés au runtime.  
- Le répertoire `lab/` ne contient que les **sources versionnées**.  
- Toute contribution doit passer par la branche `labsWIP`.
