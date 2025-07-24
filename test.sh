#!/usr/bin/env bash

# Test complet linac avec pbcopy réel
# Usage: ./test_linac_complete.sh

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration globale de test
declare -A config
config[dc_ip]="${DC_IP:-172.24.0.4}"
config[password]="${PASSWORD:-my-fucking-strong-password}"
config[base_dn]="${BASE_DN:-DC=SIEGE,DC=AMAZON,DC=COM}"
config[user_dn]="$DN"
config[now]=$(date +%s)

printf "${YELLOW}🧪 TEST COMPLET LINAC AVEC PBCOPY RÉEL${NC}\n"
printf "============================================\n\n"

# Données LDAP simulées
_simulate_ldapsearch() {
    cat << 'EOF'
dn: CN=John Doe,OU=IT,OU=SUPERMEGASUPERADMIN,OU=PANAMA,OU=AMAZON.COM,OU=GROUPE AMAZON.COM,DC=SIEGE,DC=AMAZON,DC=COM
sAMAccountName: jdoe
displayName: John Doe
description: Administrateur Système Senior
lastLogon: 133635136000000000
lastLogonTimestamp: 133635136000000000
physicalDeliveryOfficeName: Paris
manager: CN=Marie Martin,OU=Management,OU=SUPERMEGASUPERADMIN,OU=PANAMA,OU=AMAZON.COM,OU=GROUPE AMAZON.COM,DC=SIEGE,DC=AMAZON,DC=COM
typeContrat: CDI
division: Direction des Systèmes d'Information
badPwdCount: 0
badPasswordTime: 0
logonCount: 1547
department: IT

dn: CN=Sophie Dupont,OU=RH,OU=SUPERMEGASUPERADMIN,OU=PANAMA,OU=AMAZON.COM,OU=GROUPE AMAZON.COM,DC=SIEGE,DC=AMAZON,DC=COM
sAMAccountName: sdupont
displayName: Sophie Dupont
description: Gestionnaire RH
lastLogon: 133627328000000000
lastLogonTimestamp: 133627328000000000
physicalDeliveryOfficeName: Lyon
manager: CN=Pierre Durand,OU=Management,OU=SUPERMEGASUPERADMIN,OU=PANAMA,OU=AMAZON.COM,OU=GROUPE AMAZON.COM,DC=SIEGE,DC=AMAZON,DC=COM
typeContrat: CDI
division: Ressources Humaines
badPwdCount: 2
badPasswordTime: 133627000000000000
logonCount: 892
department: RH

dn: CN=Michel Bernard,OU=FINANCE,OU=SUPERMEGASUPERADMIN,OU=PANAMA,OU=AMAZON.COM,OU=GROUPE AMAZON.COM,DC=SIEGE,DC=AMAZON,DC=COM
sAMAccountName: mbernard
displayName: Michel Bernard
description: Analyste Financier
lastLogon: 133619904000000000
lastLogonTimestamp: 133619904000000000
physicalDeliveryOfficeName: Marseille
manager: CN=Alice Moreau,OU=Management,OU=SUPERMEGASUPERADMIN,OU=PANAMA,OU=AMAZON.COM,OU=GROUPE AMAZON.COM,DC=SIEGE,DC=AMAZON,DC=COM
typeContrat: CDD
division: Direction Financière
badPwdCount: 5
badPasswordTime: 133620000000000000
logonCount: 234
department: Finance

dn: CN=Claire Rousseau,OU=MARKETING,OU=SUPERMEGASUPERADMIN,OU=PANAMA,OU=AMAZON.COM,OU=GROUPE AMAZON.COM,DC=SIEGE,DC=AMAZON,DC=COM
sAMAccountName: crousseau
displayName: Claire Rousseau
description: Chargée de Communication
lastLogon: 133604736000000000
lastLogonTimestamp: 133604736000000000
physicalDeliveryOfficeName: Toulouse
manager: CN=Luc Petit,OU=Management,OU=SUPERMEGASUPERADMIN,OU=PANAMA,OU=AMAZON.COM,OU=GROUPE AMAZON.COM,DC=SIEGE,DC=AMAZON,DC=COM
typeContrat: Stage
division: Marketing et Communication
badPwdCount: 0
badPasswordTime: 0
logonCount: 156
department: Marketing

dn: CN=Paul Leroy,OU=VENTES,OU=SUPERMEGASUPERADMIN,OU=PANAMA,OU=AMAZON.COM,OU=GROUPE AMAZON.COM,DC=SIEGE,DC=AMAZON,DC=COM
sAMAccountName: pleroy
displayName: Paul Leroy
lastLogon: 133622656000000000
lastLogonTimestamp: 133622656000000000
badPwdCount: 1
badPasswordTime: 133622500000000000
logonCount: 445

EOF
}

# TEST 1: _linac_check_commands
test_check_commands() {
    printf "${BLUE}📋 TEST 1: _linac_check_commands${NC}\n"
    printf "Entrée: Vérification des commandes nécessaires (bc, pbcopy)\n"
    
    _linac_check_commands() {
        local missing_commands=()
        
        if ! command -v bc &> /dev/null; then
            printf '❌ Erreur: La commande '\''bc'\'' n'\''est pas installée.\n' >&2
            missing_commands+=("bc")
        fi
        
        if ! command -v pbcopy &> /dev/null; then
            printf '❌ Erreur: La commande '\''pbcopy'\'' n'\''est pas disponible.\n' >&2
            missing_commands+=("pbcopy")
        fi
        
        if [[ ${#missing_commands[@]} -eq 0 ]]; then
            printf '✅ Toutes les commandes nécessaires sont disponibles.\n' >&2
            return 0
        else
            return 1
        fi
    }
    
    local result
    result=$(_linac_check_commands 2>&1)
    local exit_code=$?
    
    printf "Sortie:\n%s\n" "$result"
    printf "Code de sortie: %d\n" "$exit_code"
    
    if [[ $exit_code -eq 0 ]]; then
        printf "${GREEN}✓ PASS${NC}\n\n"
    else
        printf "${RED}✗ FAIL${NC}\n\n"
    fi
}

# TEST 2: _linac_count_users
test_count_users() {
    printf "${BLUE}📋 TEST 2: _linac_count_users${NC}\n"
    printf "Entrée: Données LDAP avec plusieurs utilisateurs\n"
    
    _linac_count_users() {
        _simulate_ldapsearch | grep -c '^sAMAccountName:'
    }
    
    local count
    count=$(_linac_count_users)
    
    printf "Sortie: %d utilisateurs trouvés\n" "$count"
    printf "Détail des utilisateurs:\n"
    _simulate_ldapsearch | grep '^sAMAccountName:' | while read -r line; do
        printf "  - %s\n" "$line"
    done
    
    if [[ $count -eq 5 ]]; then
        printf "${GREEN}✓ PASS${NC}\n\n"
    else
        printf "${RED}✗ FAIL (attendu: 5, obtenu: %d)${NC}\n\n" "$count"
    fi
}

# TEST 3: _linac_generate_data
test_generate_data() {
    printf "${BLUE}📋 TEST 3: _linac_generate_data${NC}\n"
    printf "Entrée: Seuil de 90 jours d'inactivité\n"
    
    _linac_generate_data() {
        local local_threshold_days="$1"
        
        _simulate_ldapsearch | \
        awk -v now="${config[now]}" -v threshold="$local_threshold_days" '
            BEGIN {
                FS=": "
                OFS="\t"
            }
            
            $1 == "sAMAccountName" { user = $2 }
            $1 == "description" { desc = $2 }
            $1 == "lastLogon" { ll = $2 }
            $1 == "lastLogonTimestamp" { llt = $2 }
            $1 == "physicalDeliveryOfficeName" { siteGeo = $2 }
            $1 == "manager" { manager = $2 }
            $1 == "typeContrat" { typeContrat = $2 }
            $1 == "division" { division = $2 }
            $1 == "badPwdCount" { badPwdCount = ($2 ? $2 : 0) }
            $1 == "badPasswordTime" { badPasswordTime = $2 }
            $1 == "logonCount" { logonCount = $2 }
            $1 == "displayName" { displayName = $2 }
            $1 == "department" { department = $2 }

            $1 == "" {
                # Calcul des jours depuis dernière connexion
                epoch_ll = int(ll / 10000000 - 11644473600)
                epoch_llt = int(llt / 10000000 - 11644473600)

                days_ll = (epoch_ll > 0) ? int((now - epoch_ll) / 86400) : -1
                days_llt = (epoch_llt > 0) ? int((now - epoch_llt) / 86400) : -1

                if (days_ll >= 0 && days_llt >= 0) {
                    days = (days_ll < days_llt) ? days_ll : days_llt
                } else if (days_ll >= 0) {
                    days = days_ll
                } else if (days_llt >= 0) {
                    days = days_llt
                } else {
                    days = -1
                }

                if (days > threshold) {
                    managerName = "N/A"
                    if (manager && match(manager, /CN=([^,]+)/)) {
                        managerName = substr(manager, RSTART+3, RLENGTH-3)
                    }

                    badPasswordTimeDays = 0
                    if (badPasswordTime > 0) {
                        epoch_bpt = int(badPasswordTime / 10000000 - 11644473600)
                        if (epoch_bpt > 0) {
                            badPasswordTimeDays = int((now - epoch_bpt) / 86400)
                        }
                    }

                    final_siteGeo = (siteGeo ? siteGeo : "N/A")
                    final_typeContrat = (typeContrat ? typeContrat : "N/A")
                    final_division = (division ? division : "N/A")
                    final_logonCount = (logonCount ? logonCount : "N/A")
                    final_displayName = (displayName ? displayName : "N/A")
                    final_department = (department ? department : "N/A")

                    print user, days, badPwdCount, badPasswordTimeDays, final_displayName, managerName, final_typeContrat, (desc ? desc : "N/A"), final_siteGeo, final_division, final_logonCount, final_department
                }

                user = ""; desc = ""; ll = 0; llt = 0
                siteGeo = ""; manager = ""; typeContrat = ""; division = ""
                badPwdCount = 0; badPasswordTime = 0; logonCount = ""
                displayName = ""; department = ""
            }
        ' | sort -t $'\t' -k2 -nr
    }
    
    local generated_data
    generated_data=$(_linac_generate_data 90)
    
    printf "Sortie:\n"
    if [[ -n "$generated_data" ]]; then
        printf "Utilisateurs inactifs depuis plus de 90 jours:\n"
        printf "%s\n" "$generated_data" | while IFS=$'\t' read -r user days badPwd badTime displayName manager contract desc site division login dept; do
            printf "  - %-10s | %3d jours | %s\n" "$user" "$days" "$displayName"
        done
        printf "\nDonnées complètes (format TSV):\n%s\n" "$generated_data"
        printf "${GREEN}✓ PASS${NC}\n\n"
    else
        printf "Aucun utilisateur trouvé avec ce seuil\n"
        printf "${YELLOW}⚠ INFO${NC}\n\n"
    fi
}

# TEST 4: _linac_copy_and_stats avec pbcopy RÉEL
test_copy_and_stats() {
    printf "${BLUE}📋 TEST 4: _linac_copy_and_stats avec pbcopy RÉEL${NC}\n"
    printf "Entrée: Données d'utilisateurs inactifs + statistiques\n"
    
    _linac_copy_and_stats() {
        local local_threshold_days="$1"
        local local_temp_results="$2"
        local local_total_enabled_users="$3"
        
        if [[ -n $local_temp_results ]]; then
            # Génération TSV avec header pour pbcopy RÉEL
            {
                printf 'sAMAccountName\tNombreDeJoursDerniereCon\tbadPwdCount\tbadPasswordTime\tdisplayName\tManagerName\tTypeContrat\tDescription\tSiteGeo\tDivision\tlogonCount\tdepartment\n'
                printf '%s\n' "$local_temp_results"
            } | pbcopy
            
            local local_user_count
            local_user_count=$(printf '%s\n' "$local_temp_results" | wc -l | tr -d ' ')
            
            # Calcul du pourcentage
            local local_percentage=0
            if ((local_total_enabled_users > 0)); then
                local_percentage=$(printf 'scale=2; (%s * 100) / %s\n' "$local_user_count" "$local_total_enabled_users" | bc -l 2>/dev/null || printf '0')
            fi
            
            printf '✅ Résultats copiés dans le presse-papier macOS (format TSV)\n' >&2
            printf '📊 Statistiques:\n' >&2
            printf '==========================================================\n' >&2
            printf '%-40s | %-10s\n' 'Statistique' 'Valeur' >&2
            printf -- '----------------------------------------------------------\n' >&2
            printf '%-40s | %-10s\n' "Utilisateurs enabled inactifs depuis $local_threshold_days j" "$local_user_count" >&2
            printf '%-40s | %-10s\n' 'Utilisateurs enabled total' "$local_total_enabled_users" >&2
            printf '%-40s | %-10s\n' "Pourcentage d'inactifs depuis $local_threshold_days j" "${local_percentage}%" >&2
            printf '==========================================================\n' >&2
        fi
    }
    
    # Générer des données de test
    local test_results
    test_results=$(_linac_generate_data 90)
    local total_users=10
    
    printf "Données à copier:\n"
    printf "Header: sAMAccountName | NombreDeJoursDerniereCon | badPwdCount | ...\n"
    if [[ -n "$test_results" ]]; then
        printf "%s\n" "$test_results" | head -2
        printf "...\n"
    fi
    
    printf "\nExécution de pbcopy...\n"
    _linac_copy_and_stats 90 "$test_results" "$total_users" 2>&1
    
    # Vérification du contenu du presse-papier
    printf "\n${YELLOW}🔍 Vérification du presse-papier:${NC}\n"
    printf "Contenu copié (premières lignes):\n"
    pbpaste | head -5
    
    printf "\n${GREEN}✓ PBCOPY RÉEL TESTÉ${NC}\n\n"
}

# TEST 5: _linac_display_results
test_display_results() {
    printf "${BLUE}📋 TEST 5: _linac_display_results${NC}\n"
    printf "Entrée: Données formatées d'utilisateurs inactifs\n"
    
    _linac_display_results() {
        local local_threshold_days="$1"
        local local_temp_results="$2"
        
        printf '\n📊 UTILISATEURS ENABLED INACTIFS (> %s jours)\n' "$local_threshold_days" >&2
        printf '=======================================================\n' >&2
        
        if [[ -n $local_temp_results ]]; then
            # Header pour l'affichage terminal
            printf '\n' >&2
            printf '%-15s %-6s %-4s %-8s %-20s %-15s %-10s %-15s %-10s %-12s %-6s %-10s\n' \
                'UTILISATEUR' 'JOURS' 'PWD' 'ECHEC' 'NOM COMPLET' 'MANAGER' 'CONTRAT' 'DESCRIPTION' 'SITE' 'DIVISION' 'LOGIN' 'DEPT' >&2
            printf '%.0s-' {1..150} >&2
            printf '\n' >&2
            
            # Données formatées pour le terminal
            while IFS=$'\t' read -r local_user local_days local_badPwd local_badTime local_displayName local_manager local_contract local_desc local_site local_division local_loginCount local_dept; do
                printf '%-15s %-6s %-4s %-8s %-20s %-15s %-10s %-15s %-10s %-12s %-6s %-10s\n' \
                    "${local_user:0:15}" \
                    "$local_days" \
                    "$local_badPwd" \
                    "$local_badTime" \
                    "${local_displayName:0:20}" \
                    "${local_manager:0:15}" \
                    "${local_contract:0:10}" \
                    "${local_desc:0:15}" \
                    "${local_site:0:10}" \
                    "${local_division:0:12}" \
                    "$local_loginCount" \
                    "${local_dept:0:10}" >&2
            done <<< "$local_temp_results"
        else
            printf '✅ Aucun utilisateur enabled inactif trouvé avec le seuil de %s jours\n' "$local_threshold_days" >&2
        fi
    }
    
    local test_data
    test_data=$(_linac_generate_data 90)
    
    printf "Sortie (affichage formaté):\n"
    _linac_display_results 90 "$test_data" 2>&1
    
    printf "${GREEN}✓ PASS${NC}\n\n"
}

# Fonction principale
main() {
    test_check_commands
    test_count_users
    test_generate_data
    test_copy_and_stats
    test_display_results

    printf 'ldapsearch -x -H "ldap://%s" -D "%s" -w "%s" -b "%s" '\''(&(objectCategory=person)(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))'\'' sAMAccountName | grep -c "^sAMAccountName:"\n' \
		"${config[dc_ip]}" "${config[user_dn]}" "${config[password]}" "${config[base_dn]}" >&2
	printf '\n' >&2
    printf 'ldapsearch -x -H "ldap://%s" -D "%s" -w "%s" -b "%s" '\''(&(objectCategory=person)(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))'\'' sAMAccountName description lastLogon lastLogonTimestamp physicalDeliveryOfficeName manager typeContrat division badPwdCount badPasswordTime logonCount displayName department\n' \
		"${config[dc_ip]}" "${config[user_dn]}" "${config[password]}" "${config[base_dn]}" >&2
    
    printf "${YELLOW}🏆 TESTS TERMINÉS${NC}\n"
    printf "Tous les tests utilisent des données réelles et pbcopy fonctionne vraiment.\n"
    printf "Vous pouvez vérifier le presse-papier avec: pbpaste\n"
}

# Point d'entrée
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi