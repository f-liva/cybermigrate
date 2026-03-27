## General helper functions

# Generate a CyberPanel-style username from domain
# e.g. storivox.com -> stori1234 (5 chars from domain + 4 random digits)
generate_site_username() {
  local domain="$1"
  local base
  base=$(echo "$domain" | sed 's/\..*//' | tr -cd 'a-z' | head -c 5)
  local rand
  rand=$(shuf -i 1000-9999 -n 1)
  echo "${base}${rand}"
}

# Get the system user that owns a site on destination
# CyberPanel assigns a user whose home is /home/<domain>
get_site_owner() {
  local domain="$1"
  local owner
  owner=$(ssh_dest "stat -c '%U' /home/${domain}/ 2>/dev/null" || true)
  if [[ -z "$owner" ]] || [[ "$owner" == "UNKNOWN" ]]; then
    # Fallback: look up in /etc/passwd by home dir
    owner=$(ssh_dest "grep ':/home/${domain}:' /etc/passwd 2>/dev/null | cut -d: -f1" || true)
  fi
  echo "$owner"
}

# Confirm action with user
confirm() {
  local prompt="${1:-Continue?}"
  echo -en "${YELLOW}${prompt} [y/N]: ${NC}"
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# Create temp directory for migration
create_tmp_dir() {
  local tmp
  tmp=$(mktemp -d "/tmp/cybermigrate.XXXXXX")
  echo "$tmp"
}

# Cleanup temp directory
cleanup_tmp() {
  local tmp_dir="$1"
  if [[ -d "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
    log_info "Cleanup: ${tmp_dir} removed"
  fi
}

# Detect PHP version from CyberPanel site data
# Normalizes to format "PHP X.Y"
normalize_php_version() {
  local raw="$1"
  # Handle formats: "PHP 8.1", "php81", "8.1", "lsphp81"
  local version
  version=$(echo "$raw" | grep -oP '\d+\.?\d+' | head -1)
  if [[ ${#version} -le 2 ]] && [[ ! "$version" == *.* ]]; then
    # e.g. "81" -> "8.1"
    version="${version:0:1}.${version:1}"
  fi
  echo "PHP ${version}"
}

# Pretty print JSON
pp_json() {
  jq '.' 2>/dev/null || cat
}

# Check if value is in json response
json_success() {
  local response="$1"
  # CyberPanel returns various success indicators
  if echo "$response" | jq -e '.status == 1 or .createWebSiteStatus == 1 or .verifyConn == 1 or .status == "success"' >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Extract error from CyberPanel response
json_error() {
  local response="$1"
  echo "$response" | jq -r '.error_message // .errorMessage // .statusmsg // "Unknown error"' 2>/dev/null
}

# Format table row
table_row() {
  printf "  %-30s %s\n" "$1" "$2"
}
