## Interactive setup wizard

separator
echo -e "${BOLD}CyberMigrate Setup Wizard${NC}"
separator
echo ""
echo "This wizard will:"
echo "  1. Configure your .env file with server credentials"
echo "  2. Test connectivity to both servers"
echo "  3. Exchange SSH keys between servers for direct transfer"
echo ""

ENV_FILE=".env"

# ─── Step 1: Source server ───────────────────────────────────────────

echo -e "${BOLD}Source Server${NC} (CyberPanel to migrate FROM)"
separator

echo -n "  Hostname/IP: "
read -r src_host
[[ -z "$src_host" ]] && { log_error "Hostname is required"; exit 1; }

echo -n "  CyberPanel admin username [admin]: "
read -r src_admin_user
src_admin_user="${src_admin_user:-admin}"

echo -n "  CyberPanel admin password: "
read -rs src_pass
echo ""
[[ -z "$src_pass" ]] && { log_error "Password is required"; exit 1; }

echo -n "  SSH user [root]: "
read -r src_ssh_user
src_ssh_user="${src_ssh_user:-root}"

echo -n "  SSH port [22]: "
read -r src_ssh_port
src_ssh_port="${src_ssh_port:-22}"

echo ""

# ─── Step 2: Destination server ──────────────────────────────────────

echo -e "${BOLD}Destination Server${NC} (CyberPanel to migrate TO)"
separator

echo -n "  Hostname/IP: "
read -r dst_host
[[ -z "$dst_host" ]] && { log_error "Hostname is required"; exit 1; }

echo -n "  CyberPanel admin username [admin]: "
read -r dst_admin_user
dst_admin_user="${dst_admin_user:-admin}"

echo -n "  CyberPanel admin password: "
read -rs dst_pass
echo ""
[[ -z "$dst_pass" ]] && { log_error "Password is required"; exit 1; }

echo -n "  SSH user [root]: "
read -r dst_ssh_user
dst_ssh_user="${dst_ssh_user:-root}"

echo -n "  SSH port [22]: "
read -r dst_ssh_port
dst_ssh_port="${dst_ssh_port:-22}"

echo ""

# ─── Step 3: CyberPanel port ────────────────────────────────────────

echo -n "CyberPanel HTTPS port [8090]: "
read -r cp_port
cp_port="${cp_port:-8090}"

echo ""

# ─── Step 4: Write .env ─────────────────────────────────────────────

log_step "Writing ${ENV_FILE}"

cat > "$ENV_FILE" <<ENVEOF
# SOURCE server (CyberPanel to migrate FROM)
SOURCE_HOST=${src_host}
SOURCE_PASS=${src_pass}
SOURCE_ADMIN_USER=${src_admin_user}
SOURCE_SSH_USER=${src_ssh_user}
SOURCE_SSH_PORT=${src_ssh_port}

# DESTINATION server (CyberPanel to migrate TO)
DEST_HOST=${dst_host}
DEST_PASS=${dst_pass}
DEST_ADMIN_USER=${dst_admin_user}
DEST_SSH_USER=${dst_ssh_user}
DEST_SSH_PORT=${dst_ssh_port}

# CyberPanel
CYBERPANEL_PORT=${cp_port}
ENVEOF

chmod 600 "$ENV_FILE"
log_ok ".env created (permissions: 600)"

# Reload env
set -a
source "$ENV_FILE"
set +a

echo ""

# ─── Step 5: Test connectivity ───────────────────────────────────────

log_step "Testing connectivity"
echo ""

ssh_ok=true

# Test SSH to source
echo -n "  SSH to source (${src_ssh_user}@${src_host}:${src_ssh_port})... "
if ssh $SSH_OPTS -p "$src_ssh_port" "${src_ssh_user}@${src_host}" "echo ok" >/dev/null 2>&1; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}FAILED${NC}"
  ssh_ok=false
fi

# Test SSH to destination
echo -n "  SSH to destination (${dst_ssh_user}@${dst_host}:${dst_ssh_port})... "
if ssh $SSH_OPTS -p "$dst_ssh_port" "${dst_ssh_user}@${dst_host}" "echo ok" >/dev/null 2>&1; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}FAILED${NC}"
  ssh_ok=false
fi

# Test API source
echo -n "  API source (${src_host}:${cp_port})... "
api_result=$(cp_api_direct "$src_host" "$cp_port" "$src_admin_user" "$src_pass" "verifyConn" 2>/dev/null || true)
if echo "$api_result" | jq -e '.verifyConn == 1' >/dev/null 2>&1; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}FAILED${NC}"
  echo "    Ensure API is enabled: CyberPanel > Users > API Access"
fi

# Test API destination
echo -n "  API destination (${dst_host}:${cp_port})... "
api_result=$(cp_api_direct "$dst_host" "$cp_port" "$dst_admin_user" "$dst_pass" "verifyConn" 2>/dev/null || true)
if echo "$api_result" | jq -e '.verifyConn == 1' >/dev/null 2>&1; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}FAILED${NC}"
  echo "    Ensure API is enabled: CyberPanel > Users > API Access"
fi

echo ""

# ─── Step 6: SSH key exchange ────────────────────────────────────────

if ! $ssh_ok; then
  log_warn "SSH connectivity failed, skipping key exchange"
  log_info "Fix SSH access and re-run './cybermigrate setup'"
  echo ""
  separator
  exit 0
fi

log_step "SSH key exchange (for direct server-to-server transfer)"
echo ""

# Check if source -> dest already works
direct_ok=false
if ssh $SSH_OPTS -p "$src_ssh_port" "${src_ssh_user}@${src_host}" \
  "ssh $SSH_OPTS -p $dst_ssh_port ${dst_ssh_user}@${dst_host} 'echo ok'" >/dev/null 2>&1; then
  log_ok "Source -> Destination: already connected"
  direct_ok=true
fi

# Check if dest -> source already works
reverse_ok=false
if ssh $SSH_OPTS -p "$dst_ssh_port" "${dst_ssh_user}@${dst_host}" \
  "ssh $SSH_OPTS -p $src_ssh_port ${src_ssh_user}@${src_host} 'echo ok'" >/dev/null 2>&1; then
  log_ok "Destination -> Source: already connected"
  reverse_ok=true
fi

if $direct_ok && $reverse_ok; then
  log_ok "Both servers can already reach each other"
else
  if confirm "Set up SSH keys between servers?"; then
    echo ""

    # Generate key on source if needed
    log_info "Generating SSH key on source server (if needed)..."
    src_key=$(ssh $SSH_OPTS -p "$src_ssh_port" "${src_ssh_user}@${src_host}" \
      "cat ~/.ssh/id_ed25519.pub 2>/dev/null || (ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -q && cat ~/.ssh/id_ed25519.pub)")

    # Generate key on destination if needed
    log_info "Generating SSH key on destination server (if needed)..."
    dst_key=$(ssh $SSH_OPTS -p "$dst_ssh_port" "${dst_ssh_user}@${dst_host}" \
      "cat ~/.ssh/id_ed25519.pub 2>/dev/null || (ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -q && cat ~/.ssh/id_ed25519.pub)")

    # Add source key to destination
    if ! $direct_ok; then
      log_info "Adding source key to destination..."
      ssh $SSH_OPTS -p "$dst_ssh_port" "${dst_ssh_user}@${dst_host}" \
        "grep -qF '${src_key}' ~/.ssh/authorized_keys 2>/dev/null || echo '${src_key}' >> ~/.ssh/authorized_keys"

      # Verify
      if ssh $SSH_OPTS -p "$src_ssh_port" "${src_ssh_user}@${src_host}" \
        "ssh $SSH_OPTS -p $dst_ssh_port ${dst_ssh_user}@${dst_host} 'echo ok'" >/dev/null 2>&1; then
        log_ok "Source -> Destination: connected"
      else
        log_warn "Source -> Destination: key added but connection failed"
      fi
    fi

    # Add destination key to source
    if ! $reverse_ok; then
      log_info "Adding destination key to source..."
      ssh $SSH_OPTS -p "$src_ssh_port" "${src_ssh_user}@${src_host}" \
        "grep -qF '${dst_key}' ~/.ssh/authorized_keys 2>/dev/null || echo '${dst_key}' >> ~/.ssh/authorized_keys"

      # Verify
      if ssh $SSH_OPTS -p "$dst_ssh_port" "${dst_ssh_user}@${dst_host}" \
        "ssh $SSH_OPTS -p $src_ssh_port ${src_ssh_user}@${src_host} 'echo ok'" >/dev/null 2>&1; then
        log_ok "Destination -> Source: connected"
      else
        log_warn "Destination -> Source: key added but connection failed"
      fi
    fi
  else
    log_info "Skipping SSH key exchange"
    log_info "Direct transfer won't be available; files will go through your local machine"
  fi
fi

# ─── Done ────────────────────────────────────────────────────────────

echo ""
separator
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
separator
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo "  1. Run './cybermigrate verify' to confirm everything works"
echo "  2. Run './cybermigrate list' to see available sites"
echo "  3. Run './cybermigrate migrate <domain>' to migrate a site"
echo ""
