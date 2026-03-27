## Migrate a website from source server to destination server

domain="${args[domain]}"
package="${args[--package]}"
owner="${args[--owner]}"
php_override="${args[--php]}"
skip_files="${args[--skip-files]}"
skip_db="${args[--skip-db]}"
skip_ssl="${args[--skip-ssl]}"
dry_run="${args[--dry-run]}"
git_repo="${args[--git-repo]}"
git_branch="${args[--git-branch]}"
deploy_script="${args[--deploy-script]}"

separator
echo -e "${BOLD}Migration: ${domain}${NC}"
separator

# ─── Step 0: Preflight checks ───────────────────────────────────────

log_step "0/8 Preflight checks"

# Verify API connectivity
cp_verify_api "source" "$SOURCE_HOST" "$CYBERPANEL_PORT" "$SOURCE_ADMIN_USER" "$SOURCE_PASS" || exit 1
cp_verify_api "destination" "$DEST_HOST" "$CYBERPANEL_PORT" "$DEST_ADMIN_USER" "$DEST_PASS" || exit 1

# Check direct SSH between servers
DIRECT_SSH=false
if ssh_source "ssh $SSH_OPTS -p $DEST_SSH_PORT ${DEST_SSH_USER}@${DEST_HOST} 'echo ok'" >/dev/null 2>&1; then
  DIRECT_SSH=true
  log_ok "Transfer: direct server-to-server"
else
  log_info "Transfer: two-hop via local machine"
fi

# Check deploy script exists locally
if [[ -n "$deploy_script" ]] && [[ ! -f "$deploy_script" ]]; then
  log_error "Deploy script not found: ${deploy_script}"
  exit 1
fi

# ─── Step 1: Gather source site info ────────────────────────────────

log_step "1/8 Gathering source site information"

# DocRoot - read from source vhost config
doc_root="public_html"
raw_docroot=$(ssh_source "grep -oP 'docRoot\s+\K\S+' /usr/local/lsws/conf/vhosts/${domain}/vhost.conf 2>/dev/null" | tr -d '\r' || true)
if [[ -n "$raw_docroot" ]]; then
  # Remove $VH_ROOT/ to get the relative path (e.g. "public_html/public")
  doc_root=$(echo "$raw_docroot" | sed 's|\$VH_ROOT/||')
  log_info "DocRoot detected: ${doc_root}"
else
  log_info "DocRoot: default (public_html)"
fi

# PHP version - read from CyberPanel database via SSH
php_version=""

# Method 1: CyberPanel database (most reliable)
db_php=$(ssh_source "mysql -N cyberpanel -e \"SELECT phpSelection FROM websiteFunctions_websites WHERE domain='${domain}'\" 2>/dev/null" | tr -d '\r' || true)
if [[ -n "$db_php" ]] && [[ "$db_php" != "NULL" ]]; then
  php_version="$db_php"
fi

# Method 2: CyberPanel API
if [[ -z "$php_version" ]]; then
  site_data=$(cp_fetch_site_data "$domain" 2>/dev/null || true)
  if [[ -n "$site_data" ]]; then
    detected_php=$(echo "$site_data" | jq -r '.phpSelection // .php // empty' 2>/dev/null || true)
    if [[ -n "$detected_php" ]]; then
      php_version=$(normalize_php_version "$detected_php")
    fi
  fi
fi

# Method 3: vhost config
if [[ -z "$php_version" ]]; then
  raw_php=$(ssh_source "grep -oP 'lsphp\d+' /usr/local/lsws/conf/vhosts/${domain}/*.conf 2>/dev/null | head -1" || true)
  if [[ -n "$raw_php" ]]; then
    php_version=$(normalize_php_version "$raw_php")
  fi
fi

# Default
if [[ -z "$php_version" ]]; then
  php_version="PHP 8.1"
  log_warn "PHP not detected, using default: ${php_version}"
fi

# Override if specified
if [[ -n "$php_override" ]]; then
  php_version="$php_override"
fi

# Disk size
disk_size=$(ssh_site_size "$domain" 2>/dev/null || echo "?")

# Databases
db_list=""
if [[ -z "$skip_db" ]]; then
  db_list=$(db_list_from_mysql "$domain" 2>/dev/null || true)
fi

# Summary
echo ""
table_row "Domain:" "$domain"
table_row "DocRoot:" "$doc_root"
table_row "PHP:" "$php_version"
table_row "Space:" "$disk_size"
table_row "Dest. package:" "$package"
table_row "Dest. owner:" "$owner"
if [[ -n "$db_list" ]]; then
  table_row "Database:" "$(echo "$db_list" | wc -l | tr -d ' ') found"
  while IFS= read -r db; do
    table_row "  -" "$db"
  done <<< "$db_list"
else
  table_row "Database:" "(none or skipped)"
fi
if [[ -n "$git_repo" ]]; then
  table_row "Git repo:" "$git_repo"
  table_row "Git branch:" "$git_branch"
fi
if [[ -n "$deploy_script" ]]; then
  table_row "Deploy script:" "$deploy_script"
fi
echo ""

# Dry run: stop here
if [[ -n "$dry_run" ]]; then
  log_dry "Simulation completed. No changes were made."
  exit 0
fi

# Confirm
if ! confirm "Proceed with the migration?"; then
  log_info "Migration cancelled."
  exit 0
fi

echo ""
TMP_DIR=$(create_tmp_dir)
SITE_CREATED=false

# Rollback: delete the site from destination if migration fails
rollback_site() {
  local d="$1"
  if $SITE_CREATED; then
    log_warn "Rollback: deleting ${d} from destination..."
    local del_result
    del_result=$(cp_delete_website "$d")
    if echo "$del_result" | tr -d '\r' | jq -e '.websiteDeleteStatus == 1' >/dev/null 2>&1; then
      log_ok "Rollback: ${d} deleted from destination"
    else
      log_error "Rollback failed: manually delete ${d} from destination"
    fi
  fi
  cleanup_tmp "$TMP_DIR"
}

trap "rollback_site '$domain'" ERR
trap "cleanup_tmp '$TMP_DIR'" EXIT

# ─── Step 2: Create website on destination ──────────────────────────

log_step "2/8 Creating website on destination"

create_result=$(cp_create_website "$domain" "$package" "$owner" "$php_version" "admin@${domain}")

if json_success "$create_result"; then
  SITE_CREATED=true
  log_ok "Website ${domain} created"
else
  error_msg=$(json_error "$create_result")
  if echo "$error_msg" | grep -qi "already exist"; then
    log_warn "Website ${domain} already exists on destination"
    if ! confirm "Continue anyway (files will be overwritten)?"; then
      exit 1
    fi
  else
    log_error "Website creation failed: ${error_msg}"
    log_info "Full response:"
    echo "$create_result" | pp_json
    exit 1
  fi
fi

# Detect the user that CyberPanel created for the site
SITE_OWNER=$(ssh_dest "stat -c '%U' /home/${domain}/" 2>/dev/null | tr -d '\r' | grep -v '^\*\*' | grep -v '^Warning' | grep -v '^$' | tail -1 || true)
if [[ -z "$SITE_OWNER" ]] || [[ "$SITE_OWNER" == "UNKNOWN" ]] || [[ "$SITE_OWNER" == "root" ]]; then
  # Fallback: search in /etc/passwd by home dir
  SITE_OWNER=$(ssh_dest "awk -F: -v h='/home/${domain}' '\$6==h {print \$1}' /etc/passwd" 2>/dev/null | tr -d '\r' | grep -v '^\*\*' | grep -v '^Warning' | grep -v '^$' | tail -1 || true)
fi
if [[ -n "$SITE_OWNER" ]] && [[ "$SITE_OWNER" != "UNKNOWN" ]]; then
  log_ok "CyberPanel owner detected: ${SITE_OWNER}"
else
  log_error "Unable to detect website owner on destination"
  rollback_site "$domain"
  exit 1
fi

# Clean up CyberPanel default files
ssh_dest "rm -f /home/${domain}/public_html/index.html" 2>/dev/null
log_info "Removed default index.html from public_html"

# ─── Step 3: Transfer files ─────────────────────────────────────────

if [[ -z "$skip_files" ]]; then
  log_step "3/8 Transferring files"

  if $DIRECT_SSH; then
    rsync_site_direct "$domain"
  else
    rsync_site_twohop "$domain" "$TMP_DIR"
  fi

  log_ok "Files transferred"
else
  log_step "3/8 File transfer (SKIPPED)"
fi

# ─── Step 4: Fix permissions ────────────────────────────────────────

log_step "4/8 Fixing file permissions"
ssh_fix_permissions "$domain" "$SITE_OWNER"

# ─── Step 5: Migrate databases ──────────────────────────────────────

if [[ -z "$skip_db" ]] && [[ -n "$db_list" ]]; then
  log_step "5/8 Migrating databases"

  while IFS= read -r dbname; do
    [[ -z "$dbname" ]] && continue

    log_info "Database: ${dbname}"

    # Get DB user
    dbuser=$(db_get_user "$dbname" 2>/dev/null || echo "")
    if [[ -z "$dbuser" ]]; then
      dbuser="${dbname}_user"
      log_warn "User not found for ${dbname}, using: ${dbuser}"
    fi

    # Detect or generate password
    dbpass=$(db_detect_password "$domain" "$dbname" 2>/dev/null || true)
    if [[ -n "$dbpass" ]]; then
      log_ok "DB password detected automatically"
    else
      dbpass=$(db_random_password)
      log_warn "Password not detectable, generated: ${dbpass}"
      log_warn "Manually update the site configuration!"
    fi

    # Create DB on destination
    create_db_result=$(cp_create_database "$domain" "$dbname" "$dbuser" "$dbpass")
    if json_success "$create_db_result"; then
      log_ok "Database ${dbname} created on destination"
    else
      db_error=$(json_error "$create_db_result")
      if echo "$db_error" | grep -qi "already exist"; then
        log_warn "Database ${dbname} already exists"
      else
        log_error "DB creation failed: ${db_error}"
        log_warn "Trying to continue with dump/import..."
      fi
    fi

    # Dump and import
    if $DIRECT_SSH; then
      db_migrate_direct "$dbname"
    else
      db_migrate_twohop "$dbname" "$TMP_DIR"
    fi

    log_ok "Database ${dbname} migrated"
    echo ""
  done <<< "$db_list"
else
  log_step "5/8 Database migration (SKIPPED)"
fi

# ─── Step 6: PHP + vhost config ──────────────────────────────────────

log_step "6/8 Configuring PHP and vhost"
change_php_result=$(cp_change_php "$domain" "$php_version" 2>/dev/null || true)
log_ok "PHP set to: ${php_version}"

# Copy vhost.conf from source to destination
# This replicates docRoot, rewrite rules, context, etc.
if [[ "$doc_root" != "public_html" ]]; then
  log_info "Non-standard docRoot (${doc_root}), copying vhost.conf from source"
  local_vhost="${TMP_DIR}/vhost.conf"
  ssh_source "cat /usr/local/lsws/conf/vhosts/${domain}/vhost.conf" > "$local_vhost" 2>/dev/null

  if [[ -s "$local_vhost" ]]; then
    # Update extprocessor and scripthandler with destination user
    sed -i "s|extprocessor [a-z]*[0-9]*|extprocessor ${SITE_OWNER}|g" "$local_vhost"
    sed -i "s|lsapi:[a-z]*[0-9]*|lsapi:${SITE_OWNER}|g" "$local_vhost"
    sed -i "s|UDS://tmp/lshttpd/[a-z]*[0-9]*\.sock|UDS://tmp/lshttpd/${SITE_OWNER}.sock|g" "$local_vhost"
    sed -i "s|extUser\s\+[a-z]*[0-9]*|extUser                 ${SITE_OWNER}|g" "$local_vhost"
    sed -i "s|extGroup\s\+[a-z]*[0-9]*|extGroup                ${SITE_OWNER}|g" "$local_vhost"

    # Update lsphp path with destination PHP version
    php_num=$(echo "$php_version" | grep -oP '\d+\.\d+' | tr -d '.')
    sed -i "s|lsphp[0-9]*/bin/lsphp|lsphp${php_num}/bin/lsphp|g" "$local_vhost"

    # Upload to destination
    rsync -az -e "ssh $SSH_OPTS -p $DEST_SSH_PORT" \
      "$local_vhost" \
      "${DEST_SSH_USER}@${DEST_HOST}:/usr/local/lsws/conf/vhosts/${domain}/vhost.conf"

    # Restart lsws to apply changes
    ssh_dest "systemctl restart lsws 2>/dev/null || /usr/local/lsws/bin/lswsctrl restart 2>/dev/null" || true
    log_ok "vhost.conf copied and adapted (docRoot: ${doc_root})"
  else
    log_warn "Source vhost.conf empty or not readable"
  fi
else
  log_info "Standard docRoot, no vhost changes needed"
fi

# ─── Step 7: SSL Certificate ────────────────────────────────────────

if [[ -z "$skip_ssl" ]]; then
  log_step "7/8 Issuing SSL certificate"
  ssl_result=$(cp_issue_ssl "$domain")
  if json_success "$ssl_result"; then
    log_ok "SSL certificate issued"
  else
    log_warn "SSL not issued (domain may not point to the new server yet)"
    log_info "Run after DNS change: cybermigrate migrate ${domain} --skip-files --skip-db"
  fi
else
  log_step "7/8 SSL (SKIPPED)"
fi

# ─── Step 8: Git + Deploy setup ─────────────────────────────────────

log_step "8/8 Git and Deploy setup"

if [[ -n "$git_repo" ]]; then
  ssh_setup_git "$domain" "$git_repo" "$git_branch"
  log_ok "Git repository configured"
else
  log_info "Git: not configured (use --git-repo to enable)"
fi

if [[ -n "$deploy_script" ]]; then
  ssh_install_deploy_script "$domain" "$deploy_script"
  log_ok "Deploy script installed: /home/${domain}/deploy.sh"
else
  log_info "Deploy script: not configured (use --deploy-script to enable)"
fi

# ─── Done ────────────────────────────────────────────────────────────

# Migration succeeded: disable rollback
trap "cleanup_tmp '$TMP_DIR'" ERR
echo ""
separator
echo -e "${GREEN}${BOLD}Migration completed: ${domain}${NC}"
separator
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo "  1. Verify the site at https://${domain} (after DNS change)"
echo "  2. Update DNS records to point to ${DEST_HOST}"
if [[ -z "$skip_ssl" ]]; then
  echo "  3. If SSL was not issued, re-run after DNS change"
fi
if [[ -n "$git_repo" ]]; then
  echo "  4. Verify git: ssh ${DEST_SSH_USER}@${DEST_HOST} 'cd /home/${domain}/public_html && git status'"
fi
echo ""
