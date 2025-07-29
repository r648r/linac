#!/usr/bin/env bash

# linac.sh - List inactive LDAP/AD user accounts
RESET='\033[0m'                # Text Reset
BLACK='\033[0;30m'             # Black
RED='\033[0;31m'               # Red
GREEN='\033[0;32m'             # Green
YELLOW='\033[0;33m'            # Yellow
BLUE='\033[0;34m'              # Blue
PINK='\033[0;35m'              # Pink
CYAN='\033[0;36m'              # Cyan
WHITE='\033[0;37m'             # White

# OS detection
_linac_detect_os() {
	if [[ "$OSTYPE" == "darwin"* ]]; then
		echo "macos"
	elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
		echo "linux"
	else
		echo "unknown"
	fi
}

# Check required commands per OS
_linac_check_commands() {
	local os="$1"
	
	if ! command -v ldapsearch &> /dev/null; then
		printf '❌ Error: '\''ldapsearch'\'' is not installed.\n' >&2
		if [[ "$os" == "macos" ]]; then
			printf 'To install on macOS, run:\n' >&2
			printf 'brew install openldap\n' >&2
		else
			printf 'To install on Linux, run:\n' >&2
			printf 'apt update && apt install ldap-utils\n' >&2
			printf 'or on RedHat/CentOS:\n' >&2
			printf 'yum install openldap-clients\n' >&2
		fi
		return 1
	fi

	if [[ "$os" == "macos" ]] && ! command -v pbcopy &> /dev/null; then
		printf '❌ Error: '\''pbcopy'\'' is not available.\n' >&2
		printf 'This command is normally available on macOS by default.\n' >&2
		printf 'If missing, install the Xcode developer tools:\n' >&2
		printf 'xcode-select --install\n' >&2
		return 1
	fi

	if ! command -v bc &> /dev/null; then
		printf '❌ Error: '\''bc'\'' is not installed.\n' >&2
		if [[ "$os" == "macos" ]]; then
			printf 'To install on macOS, run:\n' >&2
			printf 'brew install bc\n' >&2
		else
			printf 'To install on Linux, run:\n' >&2
			printf 'apt update && apt install bc\n' >&2
			printf 'or on RedHat/CentOS:\n' >&2
			printf 'yum install bc\n' >&2
		fi
		return 1
	fi

	return 0
}

# Count total enabled users
_linac_count_users() {
	printf '🔍 Running ldapsearch to count users:\n' >&2
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

# Generate LDAP data (AWK processing)
_linac_generate_data() {
	local local_threshold_days="$1"

	printf '🔍 Running ldapsearch to fetch user data:\n' >&2
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
			# Compute days since last logon (improved logic)
			epoch_ll = int(ll / 10000000 - 11644473600)
			epoch_llt = int(llt / 10000000 - 11644473600)

			# Days for each timestamp
			days_ll = (epoch_ll > 0) ? int((now - epoch_ll) / 86400) : -1
			days_llt = (epoch_llt > 0) ? int((now - epoch_llt) / 86400) : -1

			# Pick the most recent valid timestamp
			if (days_ll >= 0 && days_llt >= 0) {
				# Both valid: take the most recent (smallest day count)
				days = (days_ll < days_llt) ? days_ll : days_llt
			} else if (days_ll >= 0) {
				# Only lastLogon is valid
				days = days_ll
			} else if (days_llt >= 0) {
				# Only lastLogonTimestamp is valid
				days = days_llt
			} else {
				# No valid timestamp
				days = -1
			}

			if (days > threshold) {
				# Extract manager name from CN
				managerName = "N/A"
				if (manager && match(manager, /CN=([^,]+)/)) {
					managerName = substr(manager, RSTART+3, RLENGTH-3)
				}

				# Convert badPasswordTime (Windows timestamp)
				badPasswordTimeDays = 0
				if (badPasswordTime > 0) {
					epoch_bpt = int(badPasswordTime / 10000000 - 11644473600)
					if (epoch_bpt > 0) {
						badPasswordTimeDays = int((now - epoch_bpt) / 86400)
					}
				}

				# Use N/A for empty fields
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

			# Reset variables
			user = ""; desc = ""; ll = 0; llt = 0
			siteGeo = ""; manager = ""; typeContrat = ""; division = ""
			badPwdCount = 0; badPasswordTime = 0; logonCount = ""
			displayName = ""; department = ""
		}
	' | sort -t $'\t' -k2 -nr
}

# Pretty-print results to the terminal
_linac_display_results() {
	local local_threshold_days="$1"
	local local_temp_results="$2"

	printf '\n📊 INACTIVE ENABLED USERS (> %s days)\n' "$local_threshold_days" >&2
	printf '=======================================================\n' >&2

	if [[ -n $local_temp_results ]]; then
		# Terminal table header
		printf '\n' >&2
		printf '%-20s %-6s %-4s %-8s %-25s %-20s %-12s %-15s %-10s %-15s %-6s %-15s\n' \
			'USER' 'DAYS' 'PWD' 'FAILS' 'FULL NAME' 'MANAGER' 'CONTRACT' 'DESCRIPTION' 'SITE' 'DIVISION' 'LOGON' 'DEPT' >&2
		printf '%.0s-' {1..200} >&2
		printf '\n' >&2

		# Formatted rows for the terminal
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
		printf '✅ No inactive enabled users found above %s days\n' "$local_threshold_days" >&2
	fi
}

# Copy to clipboard (macOS, no file) or save to file, then print stats
_linac_copy_and_stats() {
	local local_os="$1"
	local local_threshold_days="$2"
	local local_temp_results="$3"
	local local_total_enabled_users="$4"
	local local_output_file="$5"

	if [[ -n $local_temp_results ]]; then
		local local_user_count
		local_user_count=$(printf '%s\n' "$local_temp_results" | wc -l | tr -d ' ')

		# Percentage
		local local_percentage=0
		if ((local_total_enabled_users > 0)); then
			local_percentage=$(printf 'scale=2; (%s * 100) / %s\n' "$local_user_count" "$local_total_enabled_users" | bc -l 2>/dev/null || printf '0')
		fi

		# Build TSV with header
		local tsv_content
		tsv_content=$(printf 'sAMAccountName\tNombreDeJoursDerniereCon\tbadPwdCount\tbadPasswordTime\tdisplayName\tManagerName\tTypeContrat\tDescription\tSiteGeo\tDivision\tlogonCount\tdepartment\n%s\n' "$local_temp_results")

		if [[ -n "$local_output_file" ]]; then
			# Save to file (macOS w/ 2 args, or Linux)
			printf '%s' "$tsv_content" > "$local_output_file"
			printf '\n✅ Results saved to file: %s (TSV)\n' "$local_output_file" >&2
		elif [[ "$local_os" == "macos" ]]; then
			# Copy to clipboard on macOS (1 arg)
			printf '%s' "$tsv_content" | pbcopy
			printf '\n✅ Results copied to macOS clipboard (TSV)\n' >&2
		fi

		printf '📊 Statistics:\n' >&2
		printf '==========================================================\n' >&2
		printf '%-40s | %-10s\n' 'Statistic' 'Value' >&2
		printf -- '----------------------------------------------------------\n' >&2
		printf '%-40s | %-10s\n' "Inactive enabled users (> $local_threshold_days d)" "$local_user_count" >&2
		printf '%-40s | %-10s\n' 'Total enabled users' "$local_total_enabled_users" >&2
		printf '%-40s | %-10s\n' "Inactive percentage (> $local_threshold_days d)" "${local_percentage}%" >&2
		printf '==========================================================\n' >&2
	fi
}

_linac_show_usage() {
	local os="$1"
	
	printf 'Usage: linac <threshold_days> [output.tsv] | linac env\n' >&2
	printf '\n' >&2
	printf 'Exemples:\n' >&2
	if [[ "$os" == "macos" ]]; then
		printf '  linac 90                     - Find users inactive for 90+ days (copy to clipboard)\n' >&2
		printf '  linac 90 /tmp/inactifs.tsv  - Find users inactive for 90+ days (save to file)\n' >&2
	else
		printf '  linac 90 /tmp/inactifs.tsv  - Find users inactive for 90+ days (save to file)\n' >&2
	fi
	printf '  linac env                    - Edit the configuration file\n' >&2
}

_linac_show_env() {
	printf '=== LDAP Configuration ===\n' >&2
	printf '%-25s: %s\n' 'OS detected' "$detected_os" >&2
	printf '%-25s: %s\n' 'DC IP' "${config[dc_ip]}" >&2
	printf '%-25s: %s\n' 'Base DN' "${config[base_dn]}" >&2
	printf '%-25s: %s\n' 'User DN' "${config[user_dn]}" >&2
	printf '%-25s: %s days\n' 'Threshold' "$threshold_days" >&2
	printf '%-25s: %s\n' 'Current date' "$(date)" >&2
	printf '=========================\n' >&2
}

# Edit the environment config file
_linac_edit_env() {
	local env_file="$1"
	
	# Create the file with a template if missing/empty
	if [[ ! -f "$env_file" || ! -s "$env_file" ]]; then
		cat > "$env_file" <<EOF
# LDAP configuration for linac
export DOMAIN='corp.example.com'
export USER='svc.linac'
export BASE_DN='DC=corp,DC=example,DC=com'
export DN="OU=Service Accounts,\${BASE_DN}"
export PASSWORD='<redacted>'
export DC_IP='198.51.100.10'

# To load: source "$env_file"
EOF
		chmod 600 "$env_file"
		printf 'File created: %s\n' "$env_file" >&2
	fi
	
	# Pick an editor
	local editor="$EDITOR"
	[[ -z "$editor" ]] && command -v code &>/dev/null && editor='code'
	[[ -z "$editor" ]] && command -v nano &>/dev/null && editor='nano'
	[[ -z "$editor" ]] && editor='vi'
	
	"$editor" "$env_file"
}

# Spreadsheet import instructions
_linac_show_instructions() {
	local os="$1"
	local output_file="$2"
	
	printf '\n📋 Spreadsheet import:\n' >&2
	
	if [[ -n "$output_file" ]]; then
		# File mode
		if [[ "$os" == "macos" ]]; then
			printf '1. Open Excel and create a new document\n' >&2
			printf '2. Open the file: %s\n' "$output_file" >&2
		else
			printf '1. Open OnlyOffice Calc or Excel\n' >&2
			printf '2. Open the file: %s\n' "$output_file" >&2
		fi
		printf '3. Select all the data\n' >&2
		printf '4. Convert to a formatted table with filters\n' >&2
	elif [[ "$os" == "macos" ]]; then
		# Clipboard mode (macOS, 1 arg)
		printf '1. Open Excel and create a new document\n' >&2
		printf '2. Paste the data (Cmd+V)\n' >&2
		printf '3. Select all pasted data\n' >&2
		printf '4. Convert to a formatted table (Insert > Table)\n' >&2
		printf '5. The table is auto-formatted with filters\n' >&2
	fi
}

# Main function
linac() {
	local detected_os
	detected_os=$(_linac_detect_os)
	
	local config_dir="$HOME/.config/linac"
	local config_file="$config_dir/.linac.env"
	
	if [[ ! -d "$config_dir" ]]; then
		mkdir -p "$config_dir" || {
			printf 'Error: cannot create directory %s\n' "$config_dir" >&2
			return 1
		}
		printf 'Directory created: %s\n' "$config_dir" >&2
	fi

	# Handle the "env" argument (both platforms)
	if [[ $# -eq 1 && "$1" == "env" ]]; then
		_linac_edit_env "$config_file"
		_linac_show_usage "$detected_os"
		return 0
	fi

	# Validate arguments per OS
	if [[ "$detected_os" == "macos" ]]; then
		# macOS accepts 1 or 2 arguments
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
		# Linux: 2 mandatory arguments
		if [[ $# -ne 2 ]]; then
			_linac_show_usage "$detected_os"
			return 1
		fi
		local threshold_days="$1"
		local output_file="$2"
	fi

	# Validate threshold_days is numeric
	if ! [[ $threshold_days =~ ^[0-9]+$ ]]; then
		printf 'Error: threshold must be a positive integer\n' >&2
		_linac_show_usage "$detected_os"
		return 1
	fi

	# Validate output file if provided
	if [[ -n "$output_file" ]]; then
		local output_dir
		output_dir=$(dirname "$output_file")
		if [[ ! -d "$output_dir" ]]; then
			printf 'Error: directory %s does not exist\n' "$output_dir" >&2
			return 1
		fi
		if [[ ! "$output_file" =~ \.tsv$ ]]; then
			printf 'Warning: output file does not end with .tsv\n' >&2
		fi
	fi

	# LDAP configuration (global to avoid local -n)
	if [[ ! -f "$config_file" ]]; then
		printf 'Error: configuration file not found: %s\n' "$config_file" >&2
		printf 'Run: linac env to create the configuration file\n' >&2
		return 1
	fi
	
	source "$config_file"
	declare -A config
	config[dc_ip]="${DC_IP:-172.24.0.4}"
	config[password]="${PASSWORD:-changeme}"
	config[base_dn]="${BASE_DN:-DC=corp,DC=example,DC=com}"
	config[user_dn]="$DN"
	config[now]=$(date +%s)
	
	_linac_show_env

	# Check required commands
	_linac_check_commands "$detected_os" || return 1

	# Count enabled users
	local total_enabled_users
	total_enabled_users=$(_linac_count_users)

	# Update config display with user count
	printf '%-25s: %s\n' 'Enabled users' "$total_enabled_users" >&2

	# Generate data
	local temp_results
	temp_results=$(_linac_generate_data "$threshold_days")

	# Display results
	_linac_display_results "$threshold_days" "$temp_results"

	# Copy/save and statistics
	_linac_copy_and_stats "$detected_os" "$threshold_days" "$temp_results" "$total_enabled_users" "$output_file"

	# Spreadsheet instructions
	_linac_show_instructions "$detected_os" "$output_file"
}