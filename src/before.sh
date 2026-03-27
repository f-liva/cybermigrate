## Validate required env vars for all commands except setup
if [[ "${action}" != "setup" ]]; then
  missing=()
  [[ -z "$SOURCE_HOST" ]] && missing+=("SOURCE_HOST")
  [[ -z "$SOURCE_PASS" ]] && missing+=("SOURCE_PASS")
  [[ -z "$DEST_HOST" ]] && missing+=("DEST_HOST")
  [[ -z "$DEST_PASS" ]] && missing+=("DEST_PASS")

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required environment variables: ${missing[*]}"
    log_info "Run './cybermigrate setup' to configure, or create a .env file"
    exit 1
  fi
fi
