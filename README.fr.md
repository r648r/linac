# LINAC — Comptes Active Directory inactifs

[🇬🇧 English](README.md) · 🇫🇷 **Français**

> CLI pour repérer les comptes Active Directory inactifs via LDAP — hygiène des
> comptes et réduction de la surface d'attaque. Bash pur, aucune dépendance
> hormis `ldapsearch`.

Les comptes AD dormants sont du poids mort **et** une surface d'attaque : comptes
de service orphelins, ex-employés, admins oubliés. `linac` les liste en une seule
commande, calcule une vraie dernière connexion (en réconciliant `lastLogon` et
`lastLogonTimestamp`), affiche des statistiques de surface d'attaque, et exporte
un TSV propre.

## Démo

```console
$ linac env          # une fois : crée/édite ~/.config/linac/.linac.env
$ linac 90           # comptes inactifs depuis 90+ jours

=== LDAP Configuration ===
OS detected              : linux
DC IP                    : 198.51.100.10
Base DN                  : DC=corp,DC=example,DC=com
User DN                  : CN=svc.linac,OU=Service Accounts,DC=corp,DC=example,DC=com
Threshold                : 90 days
=========================
Enabled users            : 1428

📊 INACTIVE ENABLED USERS (> 90 days)
=======================================================
USER                 DAYS   PWD  FAILS  FULL NAME          SITE       DEPT
------------------------------------------------------------------------------
svc.backup-legacy    612    0    0      Service Backup     Paris      IT
old.admin            488    3    151    Legacy Admin       Lyon       IT
j.martin             274    0    0      Julien Martin      Nantes     Finance
intern-2024          203    1    44     Summer Intern 2024 Paris      Marketing
p.durand             142    0    0      Pauline Durand     Lyon       HR
   … (le TSV exporté contient 12 colonnes : account, days, badPwdCount,
      badPasswordTime, displayName, manager, contract, description, site,
      division, logonCount, department)

📊 Statistics:
==========================================================
Statistic                                | Value
----------------------------------------------------------
Inactive enabled users (> 90 d)          | 214
Total enabled users                      | 1428
Inactive percentage (> 90 d)             | 14.98%
==========================================================

✅ Results copied to clipboard (TSV) — ready for Excel
```

> Les données ci-dessus sont **synthétiques**. `linac` ne lit que l'AD que vous configurez.

## Ce qu'il fait
- Se connecte à l'AD en LDAP et liste les comptes **activés** inactifs au-delà d'un seuil
- Réconcilie `lastLogon` **et** `lastLogonTimestamp` pour une dernière connexion fiable
- Fait ressortir les signaux de risque : `badPwdCount`, ancienneté des échecs d'auth, nb de connexions, manager
- Exporte un **TSV** prêt pour Excel (presse-papier sur macOS, fichier ailleurs)
- Statistiques d'inactivité : nombre et pourcentage de la population activée

## Prérequis
- `ldapsearch` (OpenLDAP) · `bc` · `pbcopy` (export presse-papier, macOS uniquement)

```bash
# macOS
brew install openldap bc
# Debian / Ubuntu
sudo apt update && sudo apt install ldap-utils bc
```

## Installation
```bash
git clone https://github.com/r648r/linac.git && cd linac
source linac.sh
```

## Configuration
```bash
linac env        # crée ~/.config/linac/.linac.env, puis ouvre votre $EDITOR
```
```bash
# ~/.config/linac/.linac.env
export DOMAIN='corp.example.com'
export USER='svc.linac'
export BASE_DN='DC=corp,DC=example,DC=com'
export DN="CN=svc.linac,OU=Service Accounts,${BASE_DN}"
export PASSWORD='<redacted>'
export DC_IP='198.51.100.10'
```

## Utilisation
```bash
linac 90                  # inactifs 90+ jours → presse-papier (macOS)
linac 90 /tmp/stale.tsv   # sauvegarde dans un TSV (obligatoire sous Linux)
linac env                 # éditer la configuration
```

## Champs exportés
`sAMAccountName`, `NombreDeJoursDerniereCon`, `badPwdCount`, `badPasswordTime`,
`displayName`, `ManagerName`, `TypeContrat`, `Description`, `SiteGeo`,
`Division`, `logonCount`, `department`
