## Database migration utility functions

# Dump database from source and import on destination (direct pipe)
# Usage: db_migrate_direct <dbname>
db_migrate_direct() {
  local dbname="$1"

  log_info "Direct dump + import: ${dbname}"
  ssh_source "mysqldump --single-transaction --routines --triggers --events '${dbname}'" | \
    ssh_dest "mysql '${dbname}'"
}

# Dump database from source to local file
# Usage: db_dump_local <dbname> <output_file>
db_dump_local() {
  local dbname="$1" output="$2"

  log_info "Dump database ${dbname} -> ${output}"
  ssh_source "mysqldump --single-transaction --routines --triggers --events '${dbname}'" > "$output"
}

# Import database on destination from local file
# Usage: db_import_local <dbname> <input_file>
db_import_local() {
  local dbname="$1" input="$2"

  log_info "Import database ${dbname} <- ${input}"
  ssh_dest "mysql '${dbname}'" < "$input"
}

# Dump + import via local temp file (two-hop)
# Usage: db_migrate_twohop <dbname> <tmp_dir>
db_migrate_twohop() {
  local dbname="$1" tmp_dir="$2"
  local dumpfile="${tmp_dir}/${dbname}.sql"

  db_dump_local "$dbname" "$dumpfile"
  db_import_local "$dbname" "$dumpfile"
  rm -f "$dumpfile"
}

# Try to detect DB password from common config files
# Usage: db_detect_password <domain> <dbname>
db_detect_password() {
  local domain="$1" dbname="$2"
  local webroot="/home/${domain}/public_html"

  # WordPress: wp-config.php
  local wp_pass
  wp_pass=$(ssh_source "grep -oP \"define\\s*\\(\\s*'DB_PASSWORD'\\s*,\\s*'\\K[^']+\" '${webroot}/wp-config.php' 2>/dev/null" || true)
  if [[ -n "$wp_pass" ]]; then
    echo "$wp_pass"
    return 0
  fi

  # Laravel / generic .env
  local env_pass
  env_pass=$(ssh_source "grep -oP '^DB_PASSWORD=\\K.+' '${webroot}/.env' 2>/dev/null" || true)
  if [[ -n "$env_pass" ]]; then
    echo "$env_pass"
    return 0
  fi

  # Joomla: configuration.php
  local joomla_pass
  joomla_pass=$(ssh_source "grep -oP \"\\\\$password\\s*=\\s*'\\K[^']+\" '${webroot}/configuration.php' 2>/dev/null" || true)
  if [[ -n "$joomla_pass" ]]; then
    echo "$joomla_pass"
    return 0
  fi

  # Drupal: sites/default/settings.php
  local drupal_pass
  drupal_pass=$(ssh_source "grep -oP \"'password'\\s*=>\\s*'\\K[^']+\" '${webroot}/sites/default/settings.php' 2>/dev/null" || true)
  if [[ -n "$drupal_pass" ]]; then
    echo "$drupal_pass"
    return 0
  fi

  return 1
}

# Generate random password
db_random_password() {
  openssl rand -base64 16 | tr -d '/+=' | head -c 16
}

# List databases for a domain from CyberPanel database
db_list_from_mysql() {
  local domain="$1"
  ssh_source "mysql -N cyberpanel -e \"SELECT d.dbName FROM databases_databases d JOIN websiteFunctions_websites w ON d.website_id = w.id WHERE w.domain='${domain}'\" 2>/dev/null" | tr -d '\r'
}

# Get DB user for a database from CyberPanel database
db_get_user() {
  local dbname="$1"
  ssh_source "mysql -N cyberpanel -e \"SELECT dbUser FROM databases_databases WHERE dbName='${dbname}' LIMIT 1\" 2>/dev/null" | tr -d '\r'
}
