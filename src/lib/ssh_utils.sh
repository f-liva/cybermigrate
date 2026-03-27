## SSH and rsync utility functions

# SSH common options
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"

# Run command on source server
ssh_source() {
  ssh $SSH_OPTS -p "$SOURCE_SSH_PORT" "${SOURCE_SSH_USER}@${SOURCE_HOST}" "$@"
}

# Run command on destination server
ssh_dest() {
  ssh $SSH_OPTS -p "$DEST_SSH_PORT" "${DEST_SSH_USER}@${DEST_HOST}" "$@"
}

# Verify SSH connectivity
# Usage: ssh_verify <label> <host> <port> <user>
ssh_verify() {
  local label="$1" host="$2" port="$3" user="$4"
  if ssh $SSH_OPTS -p "$port" "${user}@${host}" "echo ok" >/dev/null 2>&1; then
    log_ok "SSH ${label}: connection successful (${user}@${host}:${port})"
    return 0
  else
    log_error "SSH ${label}: connection failed (${user}@${host}:${port})"
    return 1
  fi
}

# Verify source can reach destination via SSH (for direct rsync)
ssh_verify_source_to_dest() {
  if ssh_source "ssh $SSH_OPTS -p $DEST_SSH_PORT ${DEST_SSH_USER}@${DEST_HOST} 'echo ok'" >/dev/null 2>&1; then
    log_ok "SSH source -> destination: direct connection OK"
    return 0
  else
    log_warn "SSH source -> destination: direct connection not available"
    log_info "File transfer will go through the local machine"
    return 1
  fi
}

# Rsync files: source -> destination (direct server-to-server)
# Usage: rsync_site_direct <domain>
rsync_site_direct() {
  local domain="$1"
  local src_path="/home/${domain}"
  local dst_conn="${DEST_SSH_USER}@${DEST_HOST}"
  local dst_path="/home/${domain}/"

  log_info "Direct rsync: source -> destination"
  ssh_source "rsync -rlptz --delete --no-owner --no-group --no-inc-recursive --info=progress2 \
    --exclude='.well-known/acme-challenge' \
    -e 'ssh $SSH_OPTS -p $DEST_SSH_PORT' \
    '${src_path}/' '${dst_conn}:${dst_path}'"
}

# Rsync files: source -> local -> destination (two-hop)
# Usage: rsync_site_twohop <domain> <tmp_dir>
rsync_site_twohop() {
  local domain="$1"
  local tmp_dir="$2"
  local local_path="${tmp_dir}/${domain}"

  mkdir -p "$local_path"

  log_info "rsync: source -> local"
  rsync -rlptz --delete --no-inc-recursive --info=progress2 \
    --exclude='.well-known/acme-challenge' \
    -e "ssh $SSH_OPTS -p $SOURCE_SSH_PORT" \
    "${SOURCE_SSH_USER}@${SOURCE_HOST}:/home/${domain}/" \
    "${local_path}/"

  log_info "rsync: local -> destination"
  rsync -rlptz --delete --no-owner --no-group --no-inc-recursive --info=progress2 \
    --exclude='.well-known/acme-challenge' \
    -e "ssh $SSH_OPTS -p $DEST_SSH_PORT" \
    "${local_path}/" \
    "${DEST_SSH_USER}@${DEST_HOST}:/home/${domain}/"
}

# Get site disk usage on source
ssh_site_size() {
  local domain="$1"
  ssh_source "du -sh /home/${domain} 2>/dev/null | awk '{print \$1}'"
}

# Fix file ownership on destination
# Usage: ssh_fix_permissions <domain> <owner>
ssh_fix_permissions() {
  local domain="$1"
  local site_owner="$2"

  log_info "Fixing permissions: owner=${site_owner} on /home/${domain}"
  ssh_dest "chown -R ${site_owner}:${site_owner} /home/${domain}/ && \
            find /home/${domain}/public_html -type d -exec chmod 755 {} \; && \
            find /home/${domain}/public_html -type f -exec chmod 644 {} \;"

  # Verify
  local actual_owner
  actual_owner=$(ssh_dest "stat -c '%U' /home/${domain}/public_html/" | tr -d '\r')
  if [[ "$actual_owner" == "$site_owner" ]]; then
    log_ok "Owner verified: ${site_owner}:${site_owner}"
  else
    log_error "Expected owner: ${site_owner}, found: ${actual_owner}"
    log_warn "Retrying fix with numeric ID..."
    local uid
    uid=$(ssh_dest "id -u ${site_owner}" | tr -d '\r')
    ssh_dest "chown -R ${uid}:${uid} /home/${domain}/"
    actual_owner=$(ssh_dest "stat -c '%U' /home/${domain}/public_html/" | tr -d '\r')
    log_info "Owner after retry: ${actual_owner}"
  fi
}

# Setup git on destination site
# Usage: ssh_setup_git <domain> <repo_url> <branch>
ssh_setup_git() {
  local domain="$1" repo_url="$2" branch="$3"
  local webroot="/home/${domain}/public_html"

  log_step "Setup Git: ${repo_url} (branch: ${branch})"
  ssh_dest "cd '${webroot}' && \
    git init && \
    git remote add origin '${repo_url}' && \
    git fetch origin '${branch}' && \
    git checkout -f '${branch}'"
}

# Install deploy script on destination
# Usage: ssh_install_deploy_script <domain> <local_script_path>
ssh_install_deploy_script() {
  local domain="$1" local_script="$2"
  local remote_path="/home/${domain}/deploy.sh"

  log_step "Installing deploy script: ${remote_path}"
  rsync -avz \
    -e "ssh $SSH_OPTS -p $DEST_SSH_PORT" \
    "$local_script" \
    "${DEST_SSH_USER}@${DEST_HOST}:${remote_path}"

  ssh_dest "chmod +x '${remote_path}' && chown ${domain}:${domain} '${remote_path}'"
}
