## List websites on the source CyberPanel server

log_info "Fetching website list from ${SOURCE_HOST}..."
echo ""

response=$(cp_fetch_websites)

if ! echo "$response" | jq -e '.data' >/dev/null 2>&1; then
  # Fallback: try fetching via SSH from the CyberPanel database
  log_warn "API fetchWebsites not available, trying via SSH..."
  sites=$(ssh_source "sqlite3 /usr/local/CyberCP/cyberpanel.db \
    \"SELECT domain, phpSelection, state FROM websiteFunctions_websites ORDER BY domain\" 2>/dev/null || \
    mysql -N cyberpanel -e \"SELECT domain, phpSelection, state FROM websiteFunctions_websites ORDER BY domain\" 2>/dev/null" || true)

  if [[ -z "$sites" ]]; then
    log_error "Unable to fetch website list"
    exit 1
  fi

  separator
  printf "  ${BOLD}%-35s %-15s %-10s${NC}\n" "DOMAIN" "PHP" "STATUS"
  separator
  while IFS=$'|\t' read -r domain php state; do
    # Trim whitespace
    domain=$(echo "$domain" | xargs)
    php=$(echo "$php" | xargs)
    state=$(echo "$state" | xargs)
    state_label="active"
    [[ "$state" == "0" ]] && state_label="suspended"
    printf "  %-35s %-15s %-10s\n" "$domain" "$php" "$state_label"
  done <<< "$sites"
  separator
  exit 0
fi

# Parse JSON response
sites_json=$(echo "$response" | jq -r '.data // .fetchWebsites // .websites // []')

if [[ "$sites_json" == "[]" ]] || [[ -z "$sites_json" ]]; then
  log_warn "No websites found"
  exit 0
fi

separator
printf "  ${BOLD}%-35s %-15s %-10s${NC}\n" "DOMAIN" "PHP" "STATUS"
separator

echo "$sites_json" | jq -r '.[] | [.domain // .domainName, .phpSelection // .php // "N/A", .state // "1"] | @tsv' 2>/dev/null | \
while IFS=$'\t' read -r domain php state; do
  state_label="active"
  [[ "$state" == "0" ]] && state_label="suspended"
  printf "  %-35s %-15s %-10s\n" "$domain" "${php:-N/A}" "$state_label"
done

separator
total=$(echo "$sites_json" | jq 'length' 2>/dev/null || echo "?")
log_info "Total: ${total} websites"
