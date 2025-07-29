#!/usr/bin/env bash

# linac.sh - Script pour l'analyse des utilisateurs LDAP inactifs
RESET='\033[0m'                # Text Reset
BLACK='\033[0;30m'             # Black
RED='\033[0;31m'               # Red
GREEN='\033[0;32m'             # Green
YELLOW='\033[0;33m'            # Yellow
BLUE='\033[0;34m'              # Blue
PINK='\033[0;35m'              # Pink
CYAN='\033[0;36m'              # Cyan
WHITE='\033[0;37m'             # White

# Détection de l'OS
_linac_detect_os() {
	if [[ "$OSTYPE" == "darwin"* ]]; then
		echo "macos"
	elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
		echo "linux"
	else
		echo "unknown"
	fi
}

# Vérification des commandes nécessaires selon l'OS
_linac_check_commands() {
	local os="$1"
	
	if ! command -v ldapsearch &> /dev/null; then
		printf '❌ Erreur: La commande '\''ldapsearch'\'' n'\''est pas installée.\n' >&2
		if [[ "$os" == "macos" ]]; then
			printf 'Pour l'\''installer sur macOS, utilisez:\n' >&2
			printf 'brew install openldap\n' >&2
		else
			printf 'Pour l'\''installer sur Linux, utilisez:\n' >&2
			printf 'apt update && apt install ldap-utils\n' >&2
			printf 'ou sur RedHat/CentOS:\n' >&2
			printf 'yum install openldap-clients\n' >&2
		fi
		return 1
	fi

	if [[ "$os" == "macos" ]] && ! command -v pbcopy &> /dev/null; then
		printf '❌ Erreur: La commande '\''pbcopy'\'' n'\''est pas disponible.\n' >&2
		printf 'Cette commande est normalement disponible sur macOS par défaut.\n' >&2
		printf 'Si elle n'\''est pas disponible, installez les outils de développement Xcode:\n' >&2
		printf 'xcode-select --install\n' >&2
		return 1
	fi

	if ! command -v bc &> /dev/null; then
		printf '❌ Erreur: La commande '\''bc'\'' n'\''est pas installée.\n' >&2
		if [[ "$os" == "macos" ]]; then
			printf 'Pour l'\''installer sur macOS, utilisez:\n' >&2
			printf 'brew install bc\n' >&2
		else
			printf 'Pour l'\''installer sur Linux, utilisez:\n' >&2
			printf 'apt update && apt install bc\n' >&2
			printf 'ou sur RedHat/CentOS:\n' >&2
			printf 'yum install bc\n' >&2
		fi
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

# Copie vers le presse-papier (macOS sans fichier) ou sauvegarde fichier et affichage des statistiques
_linac_copy_and_stats() {
	local local_os="$1"
	local local_threshold_days="$2"
	local local_temp_results="$3"
	local local_total_enabled_users="$4"
	local local_output_file="$5"

	if [[ -n $local_temp_results ]]; then
		local local_user_count
		local_user_count=$(printf '%s\n' "$local_temp_results" | wc -l | tr -d ' ')

		# Calcul du pourcentage
		local local_percentage=0
		if ((local_total_enabled_users > 0)); then
			local_percentage=$(printf 'scale=2; (%s * 100) / %s\n' "$local_user_count" "$local_total_enabled_users" | bc -l 2>/dev/null || printf '0')
		fi

		# Génération TSV avec header
		local tsv_content
		tsv_content=$(printf 'sAMAccountName\tNombreDeJoursDerniereCon\tbadPwdCount\tbadPasswordTime\tdisplayName\tManagerName\tTypeContrat\tDescription\tSiteGeo\tDivision\tlogonCount\tdepartment\n%s\n' "$local_temp_results")

		if [[ -n "$local_output_file" ]]; then
			# Sauvegarde dans un fichier (macOS avec 2 args ou Linux)
			printf '%s' "$tsv_content" > "$local_output_file"
			printf '\n✅ Résultats sauvegardés dans le fichier: %s (format TSV)\n' "$local_output_file" >&2
		elif [[ "$local_os" == "macos" ]]; then
			# Copie vers le presse-papier sur macOS (1 arg seulement)
			printf '%s' "$tsv_content" | pbcopy
			printf '\n✅ Résultats copiés dans le presse-papier macOS (format TSV)\n' >&2
		fi

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
	local os="$1"
	
	printf 'Usage: linac <jours_seuil> [fichier_sortie.tsv] | linac env\n' >&2
	printf '\n' >&2
	printf 'Exemples:\n' >&2
	if [[ "$os" == "macos" ]]; then
		printf '  linac 90                     - Rechercher les utilisateurs inactifs depuis 90 jours (copie vers presse-papier)\n' >&2
		printf '  linac 90 /tmp/inactifs.tsv  - Rechercher les utilisateurs inactifs depuis 90 jours (sauvegarde fichier)\n' >&2
	else
		printf '  linac 90 /tmp/inactifs.tsv  - Rechercher les utilisateurs inactifs depuis 90 jours (sauvegarde fichier)\n' >&2
	fi
	printf '  linac env                    - Éditer le fichier de configuration\n' >&2
}

_linac_show_env() {
	printf '=== Configuration LDAP ===\n' >&2
	printf '%-25s: %s\n' 'OS détecté' "$detected_os" >&2
	printf '%-25s: %s\n' 'DC IP' "${config[dc_ip]}" >&2
	printf '%-25s: %s\n' 'Base DN' "${config[base_dn]}" >&2
	printf '%-25s: %s\n' 'User DN' "${config[user_dn]}" >&2
	printf '%-25s: %s jours\n' 'Seuil' "$threshold_days" >&2
	printf '%-25s: %s\n' 'Date actuelle' "$(date)" >&2
	printf '=========================\n' >&2
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

# Affichage des instructions pour Excel/OnlyOffice
_linac_show_instructions() {
	local os="$1"
	local output_file="$2"
	
	printf '\n📋 Instructions pour tableur:\n' >&2
	
	if [[ -n "$output_file" ]]; then
		# Mode fichier (macOS avec 2 args ou Linux)
		if [[ "$os" == "macos" ]]; then
			printf '1. Ouvrez Excel et créez un nouveau document\n' >&2
			printf '2. Ouvrez le fichier: %s\n' "$output_file" >&2
		else
			printf '1. Ouvrez OnlyOffice Calc ou Excel\n' >&2
			printf '2. Ouvrez le fichier: %s\n' "$output_file" >&2
		fi
		printf '3. Sélectionnez toutes les données\n' >&2
		printf '4. Convertir en tableau formaté avec des filtres\n' >&2
	elif [[ "$os" == "macos" ]]; then
		# Mode presse-papier (macOS avec 1 arg)
		printf '1. Ouvrez Excel et créez un nouveau document\n' >&2
		printf '2. Collez les données (Cmd+V)\n' >&2
		printf '3. Sélectionnez toutes les données collées\n' >&2
		printf '4. Convertir en tableau formaté (Insertion > Tableau)\n' >&2
		printf '5. Le tableau sera automatiquement formaté avec des filtres\n' >&2
	fi
}

# Fonction principale refactorisée
linac() {
	local detected_os
	detected_os=$(_linac_detect_os)
	
	local config_dir="$HOME/.config/linac"
	local config_file="$config_dir/.linac.env"
	
	if [[ ! -d "$config_dir" ]]; then
		mkdir -p "$config_dir" || {
			printf 'Erreur: Impossible de créer le répertoire %s\n' "$config_dir" >&2
			return 1
		}
		printf 'Répertoire créé : %s\n' "$config_dir" >&2
	fi

	# Gestion de l'argument "env" (sur les deux plateformes)
	if [[ $# -eq 1 && "$1" == "env" ]]; then
		_linac_edit_env "$config_file"
		_linac_show_usage "$detected_os"
		return 0
	fi

	# Validation des arguments selon l'OS
	if [[ "$detected_os" == "macos" ]]; then
		# macOS accepte 1 ou 2 arguments
		if [[ $# -eq 1 ]]; then
			local threshold_days="$1"
			local output_file=""
		elif [[ $# -eq 2 ]]; then
			local threshold_days="$1"
			local output_file="$2"
		else
			_linac_show_usage "$detected_os"
			return 1
		fi
	else
		# Linux - besoin de 2 arguments obligatoires
		if [[ $# -ne 2 ]]; then
			_linac_show_usage "$detected_os"
			return 1
		fi
		local threshold_days="$1"
		local output_file="$2"
	fi

	# Validation que l'argument threshold_days est un nombre
	if ! [[ $threshold_days =~ ^[0-9]+$ ]]; then
		printf 'Erreur: Le seuil doit être un nombre entier positif\n' >&2
		_linac_show_usage "$detected_os"
		return 1
	fi

	# Validation du fichier de sortie si spécifié
	if [[ -n "$output_file" ]]; then
		local output_dir
		output_dir=$(dirname "$output_file")
		if [[ ! -d "$output_dir" ]]; then
			printf 'Erreur: Le répertoire %s n'\''existe pas\n' "$output_dir" >&2
			return 1
		fi
		if [[ ! "$output_file" =~ \.tsv$ ]]; then
			printf 'Avertissement: Le fichier de sortie ne se termine pas par .tsv\n' >&2
		fi
	fi

	# Configuration LDAP (maintenant globale pour éviter local -n)
	if [[ ! -f "$config_file" ]]; then
		printf 'Erreur: Fichier de configuration non trouvé: %s\n' "$config_file" >&2
		printf 'Utilisez: linac env pour créer le fichier de configuration\n' >&2
		return 1
	fi
	
	source "$config_file"
	declare -A config
	config[dc_ip]="${DC_IP:-172.24.0.4}"
	config[password]="${PASSWORD:-my-fucking-strong-password}"
	config[base_dn]="${BASE_DN:-DC=SIEGE,DC=AMAZON,DC=COM}"
	config[user_dn]="$DN"
	config[now]=$(date +%s)
	
	_linac_show_env

	# Vérification des commandes nécessaires
	_linac_check_commands "$detected_os" || return 1

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

	# Copie/sauvegarde et statistiques
	_linac_copy_and_stats "$detected_os" "$threshold_days" "$temp_results" "$total_enabled_users" "$output_file"

	# Instructions tableur
	_linac_show_instructions "$detected_os" "$output_file"
}