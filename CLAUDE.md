# CLAUDE.md

## Project overview

CyberMigrate is a CLI tool for migrating websites between CyberPanel servers. It handles files (rsync), databases (mysqldump), PHP config, SSL, OpenLiteSpeed vhost config, and optional Git + deploy script setup.

Built with [Bashly](https://bashly.dev/) — a Ruby-based bash CLI generator. The final executable `./cybermigrate` is generated from source files in `src/`.

## Tech stack

- **Language**: Bash 4.2+
- **CLI framework**: Bashly 1.3.6 (requires Ruby to regenerate)
- **Dependencies**: curl, jq, ssh, rsync (runtime)
- **CyberPanel API**: Direct API (`/api/`) and Cloud API (`/cloudAPI/`) — both use HTTPS
- **Database ops**: Done via SSH + MySQL directly (not via API, which is unreliable for DB creation)

## Repository structure

```
src/
├── bashly.yml              # CLI definition: commands, flags, args, env vars
├── initialize.sh           # Loads .env file
├── before.sh               # Validates required env vars (skipped for setup command)
├── setup_command.sh         # Interactive setup wizard + SSH key exchange
├── verify_command.sh        # Tests API + SSH connectivity
├── list_command.sh          # Lists sites from source CyberPanel
├── info_command.sh          # Shows site details (PHP, DBs, CMS, disk)
├── migrate_command.sh       # Main migration logic (8 steps)
├── packages_command.sh      # Lists packages on destination
└── lib/
    ├── colors.sh            # Terminal colors and log_* functions
    ├── cyberpanel_api.sh    # API wrappers: cp_api_direct, cp_api_cloud, shorthand helpers
    ├── ssh_utils.sh         # ssh_source, ssh_dest, rsync_site_direct/twohop, ssh_fix_permissions
    ├── db_utils.sh          # db_list_from_mysql, db_migrate_direct/twohop, db_detect_password
    └── helpers.sh           # confirm, json_success, json_error, normalize_php_version, table_row
```

## Development workflow

1. Edit files in `src/`
2. Run `bashly generate` to regenerate `./cybermigrate`
3. Test with `./cybermigrate <command>`
4. **Never edit `./cybermigrate` directly** — it gets overwritten on regenerate

## Key design decisions

### CyberPanel API limitations
- The Cloud API (`/cloudAPI/`) requires `Authorization: Basic <sha256(user:pass)>` header
- Cloud API is admin-only (hardcoded check)
- **Database creation via API is broken** (`webUserName` error) — we create DBs directly via MySQL over SSH
- The API `fetchWebsites` often fails — fallback reads from CyberPanel's MySQL database (`cyberpanel` DB)
- Website list, PHP version, and database associations are read from CyberPanel's internal MySQL tables

### SSH considerations
- SSH warnings (post-quantum algorithm) pollute stdout — `SSH_OPTS` includes `-o LogLevel=ERROR`
- All SSH output is filtered with `tr -d '\r'` to remove carriage returns
- Two transfer modes: direct (source->dest) or two-hop (source->local->dest)
- rsync uses `--no-owner --no-group --no-inc-recursive --info=progress2`

### Site ownership
- CyberPanel creates a random username per site (e.g., `stori4643` for storivox.com)
- After site creation, we detect the owner with `stat -c '%U'` on the destination
- File permissions are fixed using this detected owner, not the domain name

### Vhost config
- Source vhost.conf is read to detect non-standard docRoots (e.g., Laravel's `public_html/public`)
- When docRoot differs from default, vhost.conf is copied to destination with sed replacements for user, socket path, and PHP binary path
- OpenLiteSpeed is restarted after vhost changes

### Rollback
- If migration fails after site creation, the site is automatically deleted from destination via API
- Rollback is disabled once migration completes successfully

## Configuration

The `.env` file contains server credentials. Created by `./cybermigrate setup` or manually from `.env.example`. Key variables:

- `SOURCE_HOST`, `SOURCE_PASS` — source CyberPanel
- `DEST_HOST`, `DEST_PASS` — destination CyberPanel
- `CYBERPANEL_PORT` — default 8090 but often customized (e.g., 8443)
- SSH users default to `root`, ports to `22`

## Testing

No automated tests. Manual testing workflow:
1. `./cybermigrate setup` — configure and test connectivity
2. `./cybermigrate list` — verify site listing works
3. `./cybermigrate migrate <domain> --dry-run` — preview migration
4. `./cybermigrate migrate <domain>` — full migration

## Publishing

```bash
bashly generate
git add -A && git commit -m "description"
git push
gh release create v<version> --title "v<version> - Title" --notes "changelog"
```

## Common issues

- **API connection fails**: Check `CYBERPANEL_PORT` — often changed from 8090 for security
- **DB migration skipped**: Databases are read from `databases_databases` table in CyberPanel's MySQL — if site has no DBs there, nothing to migrate
- **Owner shows as numeric ID**: The CyberPanel user wasn't created properly — delete and recreate the site
- **rsync percentage goes backwards**: Fixed with `--no-inc-recursive` which scans all files before transfer
- **vhost not applied**: Ensure OpenLiteSpeed restarted after vhost.conf copy
