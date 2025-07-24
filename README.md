# LINAC - LDAP Inactive Accounts

## Description
Outil en ligne de commande pour identifier les comptes utilisateurs inactifs dans un Active Directory via LDAP.

## Prérequis
- `ldapsearch` (OpenLDAP)
- `pbcopy` (macOS)
- `bc` (calculatrice)

```bash
# Installation macOS
brew install openldap bc
# ou
apt update && apt install openldap bc
# ou 
sudo apt update && sudo apt install openldap bc
```

## Installation

### 📦 Installation locale (macOS)

```bash
DIR=$(mktemp -d)
cd "$DIR"
git clone https://github.com/username/linac.git
cd linac
source linac.sh

# Ajouter à votre profil pour un chargement automatique
echo "source $DIR/linac/linac.sh" >> ~/.zshrc && source ~/.zshrc
# ou
echo "source $DIR/linac/linac.sh" >> ~/.bashrc && source ~/.bashrc
```

## Configuration
```bash
# Première utilisation : créer le fichier de configuration
linac env
```
Édite le fichier `~/.config/linac/.linac.env` avec vos paramètres LDAP :
- `DOMAIN` : Domaine (ex: siege.amazon.com)
- `USER` : Nom d'utilisateur (ex: p.nom)
- `BASE_DN` : Base DN de recherche
- `DN` : DN complet de l'utilisateur
- `PASSWORD` : Mot de passe de connexion
- `DC_IP` : Adresse IP du contrôleur de domaine

### Exemple de configuration
```bash
# Configuration LDAP pour linac
export DOMAIN='siege.amazon.com'
export USER='p.nom'
export BASE_DN='DC=SIEGE,DC=AMAZON,DC=COM'
export DN="OU=DSI,OU=SUPERMEGASUPERADMIN,OU=PANAMA,OU=AMAZON.COM,OU=GROUPE AMAZON.COM,${BASE_DN}"
export PASSWORD='aaaaaaas'
export DC_IP='172.131.0.99'
```

## Utilisation
```bash
# Rechercher les utilisateurs inactifs depuis 99 jours
linac 99
```

## Fonctionnalités
- ✅ Détection automatique des utilisateurs enabled/disabled
- ✅ Calcul intelligent de la dernière connexion (lastLogon & lastLogonTimestamp)
- ✅ Export TSV automatique vers le presse-papier (macOS only)
- ✅ Statistiques détaillées (nombre, pourcentage)
- ✅ Affichage formaté en tableau
- ✅ Compatible Excel (collage direct du presse papier)

## Données exportées
- sAMAccountName 
- description 
- lastLogon 
- lastLogonTimestamp
- physicalDeliveryOfficeName 
- manager 
- typeContrat 
- division
- badPwdCount 
- badPasswordTime 
- logonCount 
- displayName 
- department

---

## 🐳 Brouillon - Installation avec Docker
```bash
# Cloner le repository
git clone https://github.com/username/linac.git
cd linac

# Construire l'image Docker
docker build -t linac-image .

# Lancer le conteneur
docker run -d --name linac -it linac-image

# Accéder au conteneur
docker exec -it linac /bin/zsh

# Dans le conteneur, linac est déjà disponible
linac env  # Configuration
linac 90   # Utilisation
```