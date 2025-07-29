# LINAC — LDAP Inactive Accounts

**English** · [Français](README.fr.md)

> CLI to flag inactive Active Directory accounts over LDAP — account hygiene
> and attack-surface reduction. Pure Bash, no dependency beyond `ldapsearch`.

Stale AD accounts are dead weight **and** an attack surface: orphaned service
accounts, departed employees, forgotten admins. `linac` lists them in one
command, computes a real last-logon (reconciling `lastLogon` and
`lastLogonTimestamp`), shows attack-surface stats, and exports a clean TSV.

## Demo

```console
$ linac env          # one-time: creates/edits ~/.config/linac/.linac.env
$ linac 90           # accounts inactive for 90+ days

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
   … (the exported TSV contains 12 columns: account, days, badPwdCount,
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

> Data above is **synthetic**. `linac` only reads from the AD you configure.

## What it does
- Binds to AD over LDAP and lists **enabled** accounts inactive past a threshold
- Reconciles `lastLogon` **and** `lastLogonTimestamp` for a reliable last-logon
- Surfaces risk signals: `badPwdCount`, failed-auth age, logon count, manager
- Exports an Excel-ready **TSV** (clipboard on macOS, file anywhere)
- Inactivity stats: count and percentage of the enabled population

## Requirements
- `ldapsearch` (OpenLDAP) · `bc` · `pbcopy` (clipboard export, macOS only)

```bash
# macOS
brew install openldap bc
# Debian / Ubuntu
sudo apt update && sudo apt install ldap-utils bc
```

## Install
```bash
git clone https://github.com/r648r/linac.git && cd linac
source linac.sh
```

## Configure
```bash
linac env        # creates ~/.config/linac/.linac.env, then opens your $EDITOR
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

## Usage
```bash
linac 90                  # inactive 90+ days → clipboard (macOS)
linac 90 /tmp/stale.tsv   # save to a TSV file (required on Linux)
linac env                 # edit configuration
```

## Exported fields
`sAMAccountName`, `NombreDeJoursDerniereCon`, `badPwdCount`, `badPasswordTime`,
`displayName`, `ManagerName`, `TypeContrat`, `Description`, `SiteGeo`,
`Division`, `logonCount`, `department`
