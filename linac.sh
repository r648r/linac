#!/usr/bin/env bash

# Vérification des commandes nécessaires
_linac_check_commands() {
	if ! command -v ldapsearch &> /dev/null; then
		printf '❌ Erreur: La commande '\''ldapsearch'\'' n'\''est pas installée.\n' >&2
		printf 'Pour l'\''installer sur macOS, utilisez:\n' >&2
		printf 'brew install openldap\n' >&2
		printf 'apt update && apt install openldap\n' >&2
		printf 'sudo apt update && sudo apt install openldap\n' >&2
		return 1
	fi

	if ! command -v pbcopy &> /dev/null; then
		printf '❌ Erreur: La commande '\''pbcopy'\'' n'\''est pas disponible.\n' >&2
		printf 'Cette commande est normalement disponible sur macOS par défaut.\n' >&2
		printf 'Si elle n'\''est pas disponible, installez les outils de développement Xcode:\n' >&2
		printf 'xcode-select --install\n' >&2
		return 1
	fi

	if ! command -v bc &> /dev/null; then
		printf '❌ Erreur: La commande '\''bc'\'' n'\''est pas installée.\n' >&2
		printf 'Pour l'\''installer sur macOS, utilisez:\n' >&2
		printf 'brew install bc\n' >&2
		printf 'apt update && apt install bc\n' >&2
		return 1
	fi

	return 0
}

# Comptage du nombre total d'utilisateurs actifs
_linac_count_users() {
	printf '🔍 Exécution de la commande ldapsearch pour compter les utilisateurs:\n' >&2
	printf 'ldapsearch -x -H "ldap://%s" -D "%s" -w "%s" -b "%s" '\''(&(objectCategory=person)(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))'\'' sAMAccountName | grep -c "^sAMAccountName:"\n' \
		"${config[dc_ip]}" "${config[user_dn]}" "${config[password]}" "${config[base_dn]}" >&2
	printf '\n' >&2

	ldapsearch -x -H "ldap://${config[dc_ip]}" \
		-D "${config[user_dn]}" \
		-w "${config[password]}" \
		-b "${config[base_dn]}" \
		'(&(objectCategory=person)(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))' \
		sAMAccountName | grep -c '^sAMAccountName:'
}

# Génération des données LDAP avec traitement AWK
_linac_generate_data() {
	local local_threshold_days="$1"

	printf '🔍 Exécution de la commande ldapsearch pour générer les données:\n' >&2
	printf 'ldapsearch -x -H "ldap://%s" -D "%s" -w "%s" -b "%s" '\''(&(objectCategory=person)(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))'\'' sAMAccountName description lastLogon lastLogonTimestamp physicalDeliveryOfficeName manager typeContrat division badPwdCount badPasswordTime logonCount displayName department\n' \
		"${config[dc_ip]}" "${config[user_dn]}" "${config[password]}" "${config[base_dn]}" >&2
	printf '\n' >&2

	ldapsearch -x -H "ldap://${config[dc_ip]}" \
		-D "${config[user_dn]}" \
		-w "${config[password]}" \
		-b "${config[base_dn]}" \
		'(&(objectCategory=person)(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))' \
		sAMAccountName description lastLogon lastLogonTimestamp \
		physicalDeliveryOfficeName manager typeContrat division \
		badPwdCount badPasswordTime logonCount displayName department | \
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
			# Calcul des jours depuis dernière connexion avec logique améliorée
			epoch_ll = int(ll / 10000000 - 11644473600)
			epoch_llt = int(llt / 10000000 - 11644473600)

			# Calcul des jours pour chaque timestamp
			days_ll = (epoch_ll > 0) ? int((now - epoch_ll) / 86400) : -1
			days_llt = (epoch_llt > 0) ? int((now - epoch_llt) / 86400) : -1

			# Sélection du meilleur timestamp selon la logique demandée
			if (days_ll >= 0 && days_llt >= 0) {
				# Les deux sont valides, prendre le plus récent (plus petit nombre de jours)
				days = (days_ll < days_llt) ? days_ll : days_llt
			} else if (days_ll >= 0) {
				# Seul lastLogon est valide
				days = days_ll
			} else if (days_llt >= 0) {
				# Seul lastLogonTimestamp est valide
				days = days_llt
			} else {
				# Aucun timestamp valide
				days = -1
			}

			if (days > threshold) {
				# Extraction du nom du manager depuis le CN
				managerName = "N/A"
				if (manager && match(manager, /CN=([^,]+)/)) {
					managerName = substr(manager, RSTART+3, RLENGTH-3)
				}

				# Traitement de badPasswordTime (conversion depuis timestamp Windows)
				badPasswordTimeDays = 0
				if (badPasswordTime > 0) {
					epoch_bpt = int(badPasswordTime / 10000000 - 11644473600)
					if (epoch_bpt > 0) {
						badPasswordTimeDays = int((now - epoch_bpt) / 86400)
					}
				}

				# Utilisation de N/A pour les champs vides
				final_siteGeo = (siteGeo ? siteGeo : "N/A")
				final_typeContrat = (typeContrat ? typeContrat : "N/A")
				final_division = (division ? division : "N/A")
				final_logonCount = (logonCount ? logonCount : "N/A")
				final_displayName = (displayName ? displayName : "N/A")
				final_department = (department ? department : "N/A")

				# Ordre: sAMAccountName, NombreDeJoursDerniereCon, badPwdCount, badPasswordTime, displayName, ManagerName, TypeContrat, Description, SiteGeo, Division, logonCount, department
				print user, \
					  days, \
					  badPwdCount, \
					  badPasswordTimeDays, \
					  final_displayName, \
					  managerName, \
					  final_typeContrat, \
					  (desc ? desc : "N/A"), \
					  final_siteGeo, \
					  final_division, \
					  final_logonCount, \
					  final_department
			}

			# Reset des variables
			user = ""; desc = ""; ll = 0; llt = 0
			siteGeo = ""; manager = ""; typeContrat = ""; division = ""
			badPwdCount = 0; badPasswordTime = 0; logonCount = ""
			displayName = ""; department = ""
		}
	' | sort -t $'\t' -k2 -nr
}

# Affichage formaté des résultats dans le terminal
_linac_display_results() {
	local local_threshold_days="$1"
	local local_temp_results="$2"

	printf '\n📊 UTILISATEURS ENABLED INACTIFS (> %s jours)\n' "$local_threshold_days" >&2
	printf '=======================================================\n' >&2

	if [[ -n $local_temp_results ]]; then
		# Header pour l'affichage terminal
		printf '\n' >&2
		printf '%-20s %-6s %-4s %-8s %-25s %-20s %-12s %-15s %-10s %-15s %-6s %-15s\n' \
			'UTILISATEUR' 'JOURS' 'PWD' 'ECHEC' 'NOM COMPLET' 'MANAGER' 'CONTRAT' 'DESCRIPTION' 'SITE' 'DIVISION' 'LOGIN' 'DEPT' >&2
		printf '%.0s-' {1..200} >&2
		printf '\n' >&2

		# Données formatées pour le terminal
		while IFS=$'\t' read -r local_user local_days local_badPwd local_badTime local_displayName local_manager local_contract local_desc local_site local_division local_loginCount local_dept; do
			printf '%-20s %-6s %-4s %-8s %-35s %-20s %-12s %-25s %-10s %-25s %-6s %-25s\n' \
				"${local_user:0:20}" \
				"$local_days" \
				"$local_badPwd" \
				"$local_badTime" \
				"${local_displayName:0:35}" \
				"${local_manager:0:20}" \
				"${local_contract:0:12}" \
				"${local_desc:0:25}" \
				"${local_site:0:10}" \
				"${local_division:0:25}" \
				"$local_loginCount" \
				"${local_dept:0:25}" >&2
		done <<< "$local_temp_results"
	else
		printf '✅ Aucun utilisateur enabled inactif trouvé avec le seuil de %s jours\n' "$local_threshold_days" >&2
	fi
}

# Copie vers le presse-papier et affichage des statistiques
_linac_copy_and_stats() {
	local local_threshold_days="$1"
	local local_temp_results="$2"
	local local_total_enabled_users="$3"

	if [[ -n $local_temp_results ]]; then
		# Génération TSV avec header pour pbcopy
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

		printf '\n✅ Résultats copiés dans le presse-papier macOS (format TSV)\n' >&2
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

_linac_show_usage() {
    echo 'Usage: linac <jours_seuil|env>\n' >&2
    echo 'Exemples:\n' >&2
    echo '  linac 90   - Rechercher les utilisateurs inactifs depuis 90 jours\n' >&2
    echo '  linac env  - Éditer le fichier de configuration : nano ~/.config/.linac.env\n' >&2
}

_linac_show_env () {
	printf '=== Configuration LDAP ===\n' >&2
	printf '%-25s: %s\n' 'DC IP' "${config[dc_ip]}" >&2
	printf '%-25s: %s\n' 'Base DN' "${config[base_dn]}" >&2
	printf '%-25s: %s\n' 'User DN' "${config[user_dn]}" >&2
	printf '%-25s: %s jours\n' 'Seuil' "$threshold_days" >&2
	printf '%-25s: %s\n' 'Date actuelle' "$(date)" >&2
	printf '=========================\n' >&2
}

# Affichage des instructions pour Excel
_linac_show_instructions() {
	printf '\n📋 Instructions pour Excel:\n' >&2
	printf '1. Ouvrez Excel et créez un nouveau document\n' >&2
	printf '2. Collez les données (Cmd+V)\n' >&2
	printf '3. Sélectionnez toutes les données collées\n' >&2
	printf '4. Convertir en tableau formaté (Insertion > Tableau)\n' >&2
	printf '5. Le tableau sera automatiquement formaté avec des filtres\n' >&2
}

# Édition du fichier de configuration environnement
_linac_edit_env() {
    local env_file="$1"
    
    # Créer le fichier s'il n'existe pas ou est vide avec un template
    if [[ ! -f "$env_file" || ! -s "$env_file" ]]; then
        cat > "$env_file" <<EOF
# Configuration LDAP pour linac
export DOMAIN='siege.amazon.com'
export USER='p.nom'
export BASE_DN='DC=SIEGE,DC=AMAZON,DC=COM'
export DN="OU=DSI,OU=SUPERMEGASUPERADMIN,OU=PANAMA,OU=AMAZON.COM,OU=GROUPE AMAZON.COM,\${BASE_DN}"
export PASSWORD='aaaaaaas'
export DC_IP='172.131.0.99'

# Pour charger: source "$env_file"
EOF
        chmod 600 "$env_file"
        printf 'Fichier créé : %s\n' "$env_file" >&2
    fi
    
    # Choisir l'éditeur
    local editor="$EDITOR"
    [[ -z "$editor" ]] && command -v code &>/dev/null && editor='code'
    [[ -z "$editor" ]] && command -v nano &>/dev/null && editor='nano'
    [[ -z "$editor" ]] && editor='vi'
    
    "$editor" "$env_file"
}

# Fonction principale refactorisée
linac() {
	local threshold_days="$1"
    local config_dir="$HOME/.config/linac"
    local config_file="$HOME/.config/linac/.linac.env"
    if [[ ! -d "$config_dir" ]]; then
		mkdir -p "$config_dir" || {
			printf 'Erreur: Impossible de créer le répertoire %s\n' "$config_dir" >&2
			return 1
		}
		printf 'Répertoire créé : %s\n' "$config_dir" >&2
	fi

	# Validation des arguments
	if [[ $# -ne 1 ]]; then
        _linac_show_usage
		return 1
	fi

	# Gestion de l'argument "env"
	if [[ $threshold_days == 'env' ]]; then
		_linac_edit_env $config_file
        _linac_show_usage
		return 0
	fi

	# Validation que l'argument est un nombre
	if ! [[ $threshold_days =~ ^[0-9]+$ ]]; then
		printf 'Erreur: Le seuil doit être un nombre entier positif\n' >&2
		_linac_show_usage
		return 1
	fi

	# Configuration LDAP (maintenant globale pour éviter local -n)
    source $config_file
	declare -A config
	config[dc_ip]="${DC_IP:-172.24.0.4}"
	config[password]="${PASSWORD:-my-fucking-strong-password}"
	config[base_dn]="${BASE_DN:-DC=SIEGE,DC=AMAZON,DC=COM}"
	config[user_dn]="$DN"
	config[now]=$(date +%s)
    _linac_show_env

	# Vérification des commandes nécessaires
	_linac_check_commands || return 1

	# Comptage des utilisateurs actifs
	local total_enabled_users
	total_enabled_users=$(_linac_count_users)

	# Mise à jour de l'affichage config avec le nombre d'utilisateurs
	printf '%-25s: %s\n' 'Utilisateurs actifs' "$total_enabled_users" >&2

	# Génération des données
	local temp_results
	temp_results=$(_linac_generate_data "$threshold_days")

	# Affichage des résultats
	_linac_display_results "$threshold_days" "$temp_results"

	# Copie et statistiques
	_linac_copy_and_stats "$threshold_days" "$temp_results" "$total_enabled_users"

	# Instructions Excel
	_linac_show_instructions
}