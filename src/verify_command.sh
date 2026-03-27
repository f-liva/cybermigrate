## Verify API and SSH connectivity

separator
echo -e "${BOLD}Connectivity check${NC}"
separator

errors=0

# API checks
cp_verify_api "source" "$SOURCE_HOST" "$CYBERPANEL_PORT" "$SOURCE_ADMIN_USER" "$SOURCE_PASS" || ((errors++))
cp_verify_api "destination" "$DEST_HOST" "$CYBERPANEL_PORT" "$DEST_ADMIN_USER" "$DEST_PASS" || ((errors++))

echo ""

# SSH checks
ssh_verify "source" "$SOURCE_HOST" "$SOURCE_SSH_PORT" "$SOURCE_SSH_USER" || ((errors++))
ssh_verify "destination" "$DEST_HOST" "$DEST_SSH_PORT" "$DEST_SSH_USER" || ((errors++))

echo ""

# Direct connectivity check (source -> dest)
DIRECT_SSH=false
if ssh_verify_source_to_dest; then
  DIRECT_SSH=true
fi

separator

if [[ $errors -gt 0 ]]; then
  log_error "${errors} checks failed. Verify your configuration."
  exit 1
else
  log_ok "All checks passed!"
  if $DIRECT_SSH; then
    log_info "Transfer mode: direct server-to-server"
  else
    log_info "Transfer mode: two-hop (via local machine)"
  fi
fi
