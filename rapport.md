# Rapport : Audit Système et Déploiement Docker

## 1. Audit Système (Choix techniques)

Pour récupérer les informations du système, j'ai utilisé les commandes et fichiers standards de Linux pour que le script soit le plus compatible possible :

*   **Système et Distribution :** Au lieu d'utiliser des commandes externes qui peuvent manquer, le script lit directement dans `/etc/os-release` (pour le nom de la distribution) et utilise `uname -r` pour le noyau.
*   **Mémoire et Uptime :** Pour l'uptime et la charge, le script lit directement les fichiers `/proc/uptime` et `/proc/loadavg`. Pour la mémoire et le swap, la commande `free -b` donne des valeurs précises en octets.
*   **Processus et Disques :** J'ai utilisé `ps -eo pid,user,%cpu,command --sort=-%cpu` (et `%mem`) pour avoir un tri direct, ce qui évite de le faire dans le script Ruby. Pour les disques, `df -P` fait très bien l'affaire.
*   **Utilisateurs :** Pour ne cibler que les vrais humains, le script lit les valeurs `UID_MIN` et `UID_MAX` dans `/etc/login.defs`, puis filtre les utilisateurs de `/etc/passwd` selon ces bornes (en ignorant le compte nobody). Les utilisateurs connectés sont récupérés avec `who`.
*   **Réseau :** La commande `ip -j a` est très pratique car elle renvoie directement du JSON, ce qui facilite l'extraction des IP et adresses MAC en Ruby. Pour les connexions, `ss` remplace l'ancien `netstat`.
*   **Services :** J'utilise `systemctl is-active` et `is-enabled`. Pour respecter la consigne sur les distributions récentes (Ubuntu 22.10+), si le service `ssh` classique est inactif, le script vérifie automatiquement l'état de `ssh.socket`.

## 2. Déploiement Docker (Analyse des environnements)

### Exécution du conteneur isolé (`docker run`)
Quand on lance l'image construite avec le `Dockerfile` sans options, le script audite l'intérieur du conteneur.
*   **Constat :** Le script trouve bien un OS (Debian) et le noyau de l'hôte (car partagé), mais les services (ssh, cron) sont inactifs/en erreur, et le réseau ne montre qu'une interface locale. 
*   **Explication :** C'est normal. Par défaut, Docker isole le conteneur dans ses propres namespaces (réseau, processus, système de fichiers). Il ne voit pas la vraie machine.

### Exécution pour auditer l'hôte (`docker compose`)
Pour que le script puisse auditer la vraie machine depuis le conteneur, j'ai configuré le fichier `compose.yaml` avec plusieurs options pour casser cette isolation :
*   `pid: "host"` : Permet de voir les vrais processus de la machine (pour la commande `ps`).
*   `network_mode: "host"` : Permet d'accéder aux vraies interfaces réseau et connexions.
*   `volumes` : J'ai monté `/:/host:ro`. Le `:ro` (read-only) est important pour la sécurité, ça évite que le conteneur casse la machine hôte. Le script est lancé avec le paramètre `-r /host/` pour qu'il aille lire les fichiers `/etc/passwd` ou `/proc/uptime` de la vraie machine, et non ceux du conteneur. J'ai aussi monté `/run/systemd` pour pouvoir interroger l'état des services de l'hôte.