## List packages on the destination server

log_info "Fetching packages from ${DEST_HOST}..."
echo ""

response=$(cp_fetch_packages)

if ! echo "$response" | jq -e '.' >/dev/null 2>&1; then
  log_error "Invalid API response"
  exit 1
fi

separator
printf "  ${BOLD}%-25s %-10s %-10s %-10s %-10s${NC}\n" "NAME" "DISK" "BANDWIDTH" "DB" "EMAIL"
separator

echo "$response" | jq -r '
  to_entries[] |
  select(.key != "listPackage") |
  .value |
  [.packageName // .name, .diskSpace // "N/A", .bandwidth // "N/A", .dataBases // "N/A", .emailAccounts // "N/A"] |
  @tsv
' 2>/dev/null | while IFS=$'\t' read -r name disk bw db email; do
  printf "  %-25s %-10s %-10s %-10s %-10s\n" "$name" "$disk" "$bw" "$db" "$email"
done

separator
