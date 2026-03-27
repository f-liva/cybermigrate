## Load config from .env if present
CONFIG_FILE="${CYBERMIGRATE_CONFIG:-.env}"
if [[ -f "$CONFIG_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  set +a
fi
