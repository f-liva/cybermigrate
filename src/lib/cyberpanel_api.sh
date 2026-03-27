## CyberPanel API wrapper functions

# Direct API call (POST /api/<endpoint>)
# Usage: cp_api_direct <host> <port> <user> <pass> <endpoint> [extra_json_fields]
cp_api_direct() {
  local host="$1" port="$2" user="$3" pass="$4" endpoint="$5"
  shift 5
  local extra="$*"

  local payload
  payload=$(jq -n --arg u "$user" --arg p "$pass" \
    '{adminUser: $u, adminPass: $p}')

  if [[ -n "$extra" ]]; then
    payload=$(echo "$payload" | jq ". + $extra")
  fi

  curl -sk -X POST "https://${host}:${port}/api/${endpoint}" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null
}

# Cloud API call (POST /cloudAPI/)
# Usage: cp_api_cloud <host> <port> <user> <pass> <controller> [extra_json_fields]
cp_api_cloud() {
  local host="$1" port="$2" user="$3" pass="$4" controller="$5"
  shift 5
  local extra="$*"

  local token
  token=$(echo -n "${user}:${pass}" | sha256sum | awk '{print $1}')

  local payload
  payload=$(jq -n --arg u "$user" --arg c "$controller" \
    '{serverUserName: $u, controller: $c}')

  if [[ -n "$extra" ]]; then
    payload=$(echo "$payload" | jq ". + $extra")
  fi

  curl -sk -X POST "https://${host}:${port}/cloudAPI/" \
    -H "Content-Type: application/json" \
    -H "Authorization: Basic ${token}" \
    -d "$payload" 2>/dev/null
}

# Shorthand: source direct API
src_api() {
  local endpoint="$1"; shift
  cp_api_direct "$SOURCE_HOST" "$CYBERPANEL_PORT" "$SOURCE_ADMIN_USER" "$SOURCE_PASS" "$endpoint" "$@"
}

# Shorthand: source cloud API
src_cloud() {
  local controller="$1"; shift
  cp_api_cloud "$SOURCE_HOST" "$CYBERPANEL_PORT" "$SOURCE_ADMIN_USER" "$SOURCE_PASS" "$controller" "$@"
}

# Shorthand: dest direct API
dst_api() {
  local endpoint="$1"; shift
  cp_api_direct "$DEST_HOST" "$CYBERPANEL_PORT" "$DEST_ADMIN_USER" "$DEST_PASS" "$endpoint" "$@"
}

# Shorthand: dest cloud API
dst_cloud() {
  local controller="$1"; shift
  cp_api_cloud "$DEST_HOST" "$CYBERPANEL_PORT" "$DEST_ADMIN_USER" "$DEST_PASS" "$controller" "$@"
}

# Verify API connection
# Usage: cp_verify_api <label> <host> <port> <user> <pass>
cp_verify_api() {
  local label="$1" host="$2" port="$3" user="$4" pass="$5"
  local result
  result=$(cp_api_direct "$host" "$port" "$user" "$pass" "verifyConn")

  if echo "$result" | jq -e '.verifyConn == 1' >/dev/null 2>&1; then
    log_ok "API ${label}: connection successful"
    return 0
  else
    log_error "API ${label}: connection failed"
    echo "  Response: $result"
    return 1
  fi
}

# Fetch website list from source
cp_fetch_websites() {
  src_cloud "fetchWebsites" '{"page": 1}'
}

# Fetch website details
# Usage: cp_fetch_site_data <domain>
cp_fetch_site_data() {
  local domain="$1"
  src_cloud "fetchWebsiteDataJSON" "$(jq -n --arg d "$domain" '{domainName: $d}')"
}

# Fetch databases for a domain
cp_fetch_databases() {
  local domain="$1"
  src_cloud "fetchDatabases" "$(jq -n --arg d "$domain" '{databaseWebsite: $d}')"
}

# Fetch PHP version for a domain
cp_fetch_php() {
  local domain="$1"
  src_cloud "getCurrentPHPConfig" "$(jq -n --arg d "$domain" '{domainName: $d}')"
}

# Create website on destination
# Usage: cp_create_website <domain> <package> <owner> <php> <email>
# <owner> must be a NEW username (not "admin") so CyberPanel creates a dedicated user
cp_create_website() {
  local domain="$1" package="$2" owner="$3" php="$4" email="$5"
  local owner_pass
  owner_pass=$(openssl rand -base64 16 | tr -d '/+=' | head -c 16)
  dst_api "createWebsite" "$(jq -n \
    --arg d "$domain" \
    --arg p "$package" \
    --arg o "$owner" \
    --arg php "$php" \
    --arg e "$email" \
    --arg pw "$owner_pass" \
    '{
      domainName: $d,
      packageName: $p,
      websiteOwner: $o,
      phpSelection: $php,
      ownerEmail: $e,
      ownerPassword: $pw,
      ssl: 0
    }')"
}

# Create database on destination via SSH (more reliable than API)
# Usage: cp_create_database <domain> <dbname> <dbuser> <dbpass>
cp_create_database() {
  local domain="$1" dbname="$2" dbuser="$3" dbpass="$4"
  ssh_dest "mysql -e \"CREATE DATABASE IF NOT EXISTS \\\`${dbname}\\\`; \
    CREATE USER IF NOT EXISTS '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}'; \
    GRANT ALL PRIVILEGES ON \\\`${dbname}\\\`.* TO '${dbuser}'@'localhost'; \
    FLUSH PRIVILEGES;\""
}

# Issue SSL on destination
cp_issue_ssl() {
  local domain="$1"
  dst_cloud "issueSSL" "$(jq -n --arg d "$domain" '{domain: $d}')"
}

# Change PHP version on destination
cp_change_php() {
  local domain="$1" php_version="$2"
  dst_cloud "changePHP" "$(jq -n \
    --arg d "$domain" \
    --arg p "$php_version" \
    '{domainName: $d, phpSelection: $p}')"
}

# Delete website on destination (for rollback)
cp_delete_website() {
  local domain="$1"
  dst_api "deleteWebsite" "$(jq -n --arg d "$domain" '{domainName: $d}')"
}

# Fetch packages from destination
cp_fetch_packages() {
  dst_api "listPackage"
}

# List child domains
cp_fetch_child_domains() {
  local domain="$1"
  src_cloud "fetchDomains" "$(jq -n --arg d "$domain" '{masterDomain: $d}')"
}
