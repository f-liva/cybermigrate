## Show website details

domain="${args[domain]}"
log_info "Fetching information for: ${domain}"
echo ""

separator
echo -e "  ${BOLD}Website: ${domain}${NC}"
separator

# Fetch site data from API
site_data=$(cp_fetch_site_data "$domain" 2>/dev/null || true)

# PHP version
php_version="N/A"
if [[ -n "$site_data" ]]; then
  php_version=$(echo "$site_data" | jq -r '.phpSelection // .php // "N/A"' 2>/dev/null || echo "N/A")
fi
# Fallback: detect from vhost
if [[ "$php_version" == "N/A" ]] || [[ -z "$php_version" ]]; then
  php_version=$(ssh_source "ls -la /usr/local/lsws/conf/vhosts/${domain}/ 2>/dev/null | grep -oP 'lsphp\d+' | head -1" || echo "N/A")
  if [[ "$php_version" != "N/A" ]] && [[ -n "$php_version" ]]; then
    php_version=$(normalize_php_version "$php_version")
  fi
fi
table_row "PHP:" "$php_version"

# Disk usage
disk_size=$(ssh_site_size "$domain" 2>/dev/null || echo "N/A")
table_row "Disk space:" "$disk_size"

# Document root
table_row "Document root:" "/home/${domain}/public_html"

echo ""

# Databases
echo -e "  ${BOLD}Database:${NC}"
dbs=$(db_list_from_mysql "$domain" 2>/dev/null || true)
if [[ -n "$dbs" ]]; then
  while IFS= read -r db; do
    db_user=$(db_get_user "$db" 2>/dev/null || echo "N/A")
    db_size=$(ssh_source "mysql -N -e \"SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) FROM information_schema.tables WHERE table_schema='${db}'\"" 2>/dev/null || echo "?")
    table_row "  ${db}" "user: ${db_user}, size: ${db_size} MB"
  done <<< "$dbs"
else
  table_row "  (no databases found)" ""
fi

echo ""

# Detect CMS
echo -e "  ${BOLD}Detected CMS:${NC}"
cms="Unknown"
if ssh_source "test -f /home/${domain}/public_html/wp-config.php" 2>/dev/null; then
  wp_ver=$(ssh_source "grep -oP \"\\$wp_version\\s*=\\s*'\\K[^']+\" /home/${domain}/public_html/wp-includes/version.php 2>/dev/null" || echo "?")
  cms="WordPress ${wp_ver}"
elif ssh_source "test -f /home/${domain}/public_html/artisan" 2>/dev/null; then
  cms="Laravel"
elif ssh_source "test -f /home/${domain}/public_html/configuration.php" 2>/dev/null; then
  cms="Joomla"
elif ssh_source "test -f /home/${domain}/public_html/index.php" 2>/dev/null; then
  if ssh_source "grep -q 'Drupal' /home/${domain}/public_html/index.php 2>/dev/null"; then
    cms="Drupal"
  fi
fi
table_row "  Type:" "$cms"

# Child domains
echo ""
echo -e "  ${BOLD}Subdomains:${NC}"
subdomains=$(ssh_source "ls -1 /home/${domain}/public_html/ 2>/dev/null | head -20" || true)
child_domains=$(cp_fetch_child_domains "$domain" 2>/dev/null || true)
if [[ -n "$child_domains" ]] && echo "$child_domains" | jq -e '.data' >/dev/null 2>&1; then
  echo "$child_domains" | jq -r '.data[] | .domain // .domainName' 2>/dev/null | while read -r sub; do
    table_row "  ${sub}" ""
  done
else
  table_row "  (no subdomains)" ""
fi

separator
