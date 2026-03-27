<p align="center">
  <img src="cybermigrate.png" alt="CyberMigrate" width="200">
</p>

<h1 align="center">CyberMigrate</h1>

<p align="center">
  <strong>Migrate websites between CyberPanel servers with a single command.</strong>
</p>

<p align="center">
  <a href="#installation">Installation</a> &bull;
  <a href="#quick-start">Quick Start</a> &bull;
  <a href="#commands">Commands</a> &bull;
  <a href="#how-it-works">How It Works</a> &bull;
  <a href="#contributing">Contributing</a>
</p>

---

CyberMigrate is a CLI tool that automates the full migration of websites between CyberPanel servers. It handles file transfer, database migration, PHP configuration, SSL certificates, OpenLiteSpeed vhost config, and optional Git + deploy script setup.

Built with [Bashly](https://bashly.dev/).

## Features

- **Full site migration** in a single command (files, databases, PHP, SSL, vhost)
- **Automatic PHP detection** from CyberPanel database
- **Smart file transfer** with progress indicator (direct server-to-server or two-hop)
- **Database password auto-detection** for WordPress, Laravel, Joomla, and Drupal
- **Vhost config replication** for non-standard document roots (e.g., Laravel's `public_html/public`)
- **Automatic rollback** if migration fails after site creation
- **Git + deploy script** setup on the destination server
- **Dry-run mode** to preview changes before executing

## Prerequisites

- **bash** 4.2+
- **curl**, **jq**, **ssh**, **rsync** on the machine running the script
- **SSH access** to both source and destination servers
- **CyberPanel API enabled** on both servers

### Enabling CyberPanel API

1. Log in to `https://<server>:<port>`
2. Go to **Users > API Access**
3. Select the admin user and click **Enable**

## Installation

```bash
git clone https://github.com/f-liva/cybermigrate.git
cd cybermigrate
cp .env.example .env
```

Edit `.env` with your server credentials:

```bash
# SOURCE server (migrate FROM)
SOURCE_HOST=203.0.113.10
SOURCE_PASS=your-admin-password
SOURCE_SSH_USER=root

# DESTINATION server (migrate TO)
DEST_HOST=203.0.113.20
DEST_PASS=your-admin-password
DEST_SSH_USER=root

# CyberPanel port (default: 8090)
CYBERPANEL_PORT=8090
```

<details>
<summary>All configuration variables</summary>

| Variable | Required | Default | Description |
|----------|:---:|---------|-------------|
| `SOURCE_HOST` | yes | - | Source server hostname/IP |
| `SOURCE_PASS` | yes | - | Source CyberPanel admin password |
| `DEST_HOST` | yes | - | Destination server hostname/IP |
| `DEST_PASS` | yes | - | Destination CyberPanel admin password |
| `SOURCE_ADMIN_USER` | no | `admin` | Source admin username |
| `DEST_ADMIN_USER` | no | `admin` | Destination admin username |
| `SOURCE_SSH_USER` | no | `root` | Source SSH user |
| `DEST_SSH_USER` | no | `root` | Destination SSH user |
| `SOURCE_SSH_PORT` | no | `22` | Source SSH port |
| `DEST_SSH_PORT` | no | `22` | Destination SSH port |
| `CYBERPANEL_PORT` | no | `8090` | CyberPanel HTTPS port |

</details>

## Quick Start

```bash
# 1. Verify connectivity
./cybermigrate verify

# 2. List sites on the source server
./cybermigrate list

# 3. Preview the migration
./cybermigrate migrate example.com --dry-run

# 4. Run the migration
./cybermigrate migrate example.com
```

## Commands

### `verify`

Test API and SSH connectivity to both servers. Detects if direct server-to-server transfer is available.

```bash
./cybermigrate verify
```

### `list`

List all websites on the source CyberPanel with PHP version and status.

```bash
./cybermigrate list
```

### `info <domain>`

Show detailed site information: PHP version, disk usage, databases, detected CMS, and subdomains.

```bash
./cybermigrate info example.com
```

### `packages`

List available hosting packages on the destination server.

```bash
./cybermigrate packages
```

### `migrate <domain>`

Migrate a website from source to destination.

```bash
# Basic migration
./cybermigrate migrate example.com

# Force a specific PHP version
./cybermigrate migrate example.com --php "PHP 8.2"

# With Git and deploy script
./cybermigrate migrate example.com \
  --git-repo git@gitlab.com:team/project.git \
  --git-branch main \
  --deploy-script ./scripts/deploy.sh

# Skip specific steps
./cybermigrate migrate example.com --skip-db --skip-ssl

# Re-issue SSL after DNS change
./cybermigrate migrate example.com --skip-files --skip-db
```

| Flag | Short | Description |
|------|:-----:|-------------|
| `--package` | `-p` | Hosting package on destination (default: `Default`) |
| `--owner` | `-o` | Website owner on destination (default: `admin`) |
| `--php` | | Force PHP version (e.g., `PHP 8.1`) |
| `--skip-files` | | Skip file transfer |
| `--skip-db` | | Skip database migration |
| `--skip-ssl` | | Skip SSL certificate issuance |
| `--dry-run` | | Preview without executing |
| `--git-repo` | `-g` | Git repository URL to set up |
| `--git-branch` | | Git branch (default: `main`) |
| `--deploy-script` | `-d` | Path to deploy script to install |

## How It Works

### Migration steps

When you run `./cybermigrate migrate example.com`, the tool executes 8 steps:

| Step | What it does |
|:---:|---|
| 0 | **Preflight** - Verify API/SSH connectivity, detect transfer mode |
| 1 | **Gather info** - Read PHP version, document root, databases from source |
| 2 | **Create site** - Create the website on destination via CyberPanel API |
| 3 | **Transfer files** - rsync with progress (direct or two-hop) |
| 4 | **Fix permissions** - Set correct ownership using CyberPanel's site user |
| 5 | **Migrate databases** - Create DBs via API, dump from source, import on destination |
| 6 | **Configure PHP + vhost** - Set PHP version, copy vhost.conf for custom docRoots |
| 7 | **SSL** - Issue Let's Encrypt certificate |
| 8 | **Git + Deploy** - Clone repo and install deploy script |

If any step fails after site creation, the site is **automatically rolled back** (deleted from destination).

### Transfer modes

The tool detects the best transfer method:

- **Direct** (server-to-server): rsync and MySQL pipes go directly between servers. Requires SSH key from source to destination.
- **Two-hop** (via local machine): Data passes through your machine as a bridge. No extra setup needed.

To enable direct transfer:

```bash
# On the source server
ssh-keygen -t ed25519
ssh-copy-id root@<destination-host>
```

### Database password detection

Passwords are automatically detected from common config files:

| CMS/Framework | Config file |
|---------------|-------------|
| WordPress | `wp-config.php` |
| Laravel | `.env` |
| Joomla | `configuration.php` |
| Drupal | `sites/default/settings.php` |

If detection fails, a random password is generated and displayed.

### Vhost replication

For sites with non-standard document roots (e.g., Laravel's `public_html/public`), the source `vhost.conf` is copied to the destination and adapted:

- Site user references updated to destination user
- PHP binary path updated to destination version
- OpenLiteSpeed restarted to apply

## Project structure

```
cybermigrate/
├── cybermigrate             # Generated CLI (executable)
├── .env.example             # Config template
├── settings.yml             # Bashly config
└── src/
    ├── bashly.yml           # CLI definition
    ├── initialize.sh        # .env loader
    ├── verify_command.sh
    ├── list_command.sh
    ├── info_command.sh
    ├── migrate_command.sh
    ├── packages_command.sh
    └── lib/
        ├── colors.sh        # Terminal colors
        ├── cyberpanel_api.sh# API wrapper
        ├── ssh_utils.sh     # SSH/rsync
        ├── db_utils.sh      # Database ops
        └── helpers.sh       # Utilities
```

## Development

Edit files in `src/` and regenerate:

```bash
# Requires Ruby + bashly gem
gem install bashly
bashly generate

# Watch mode
bashly generate --watch
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push and open a Pull Request

## License

MIT
