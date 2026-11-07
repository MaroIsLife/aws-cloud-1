# Cloud-1

Automated deployment of a WordPress site on one or more cloud servers, with **Ansible** and **Docker Compose**.
A fresh Ubuntu server with only SSH and Python becomes, in one command, a secured server running
WordPress, MariaDB and phpMyAdmin behind nginx, over HTTPS.

Project of the [42](https://42.fr) curriculum (Cloud-1).

## Authors

| Login | Profile |
|---|---|
| **mougnou** | [profile.intra.42.fr/users/mougnou](https://profile.intra.42.fr/users/mougnou) |
| **omanar** | [profile.intra.42.fr/users/omanar](https://profile.intra.42.fr/users/omanar) |

## Features

- **One command deploys everything**: `make deploy` installs, configures and starts the whole stack.
- **Idempotent**: running it again changes nothing (`changed=0`) and the site keeps working.
- **Several servers in parallel**: add a line to the inventory, Ansible deploys them all at once.
- **One container per service**, all from official images: nginx, WordPress (php-fpm), MariaDB, phpMyAdmin.
- **HTTPS** with a free Let's Encrypt certificate, renewed automatically. HTTP redirects to HTTPS.
- **Stable domain name** with DuckDNS, updated on every deploy (the cloud IP changes on each restart).
- **Secured server**: firewall (only 22, 80, 443 open), key-only SSH, no root login, database never exposed.
- **No secrets in the code**: passwords and tokens are encrypted with Ansible Vault.
- **Persistent data** in Docker volumes; containers restart on crash and after a reboot.

## Architecture

```
                        Internet
                           │  80: Let's Encrypt + redirect to HTTPS     443: HTTPS
┌──────────────────────────▼───────────────────────────────────────────────────────┐
│ Ubuntu server                       firewall: ufw + cloud security group         │
│                                                                                  │
│  ┌─────────┐  wp.<name>.duckdns.org   ┌────────────┐                             │
│  │  nginx  │ ──── FastCGI :9000 ─────►│ wordpress  │───┐                         │
│  │ (TLS)   │                          │ (php-fpm)  │   │ :3306   ┌──────────┐    │
│  │         │  pma.<name>.duckdns.org  ├────────────┤   ├────────►│ mariadb  │    │
│  │         │ ──── HTTP :80 ──────────►│ phpmyadmin │───┘         └──────────┘    │
│  └─────────┘                          └────────────┘                             │
│  └──────────── web network ────────────────┘└──── db network (internal) ────┘    │
│                                                                                  │
│  volumes: db_data (database files), wp_files (WordPress files and uploads)       │
└──────────────────────────────────────────────────────────────────────────────────┘
```

- **nginx** is the only container with published ports. It terminates TLS, routes by hostname
  (`server_name`) and serves WordPress's static files directly.
- **WordPress** runs as php-fpm and speaks FastCGI, not HTTP. **phpMyAdmin** is reverse-proxied over HTTP.
- **MariaDB** publishes no port and sits on an `internal` network: unreachable from outside,
  and without internet access itself.
- Two one-shot jobs run only when needed: **wp-cli** (installs WordPress once) and **certbot**
  (gets or renews the certificate).

## Requirements

**On your machine** (the Ansible control node)
- Ansible ≥ 2.15 (the full `ansible` package includes the `community.docker` and `community.general` collections)
- An SSH key pair (e.g. `ssh-keygen -t ed25519`)
- `make`

**For each server**
- Ubuntu 22.04 or later, with SSH and Python 3, and your public key in `authorized_keys`
  (on AWS: import it as a key pair and launch the instance with it)
- At least **20 GB of disk** (the Docker images don't fit on 8 GB)
- Inbound ports **22, 80 and 443** open in the cloud provider's security group
- A free [DuckDNS](https://www.duckdns.org) subdomain

## Quick start

```bash
git clone <this repo> && cd cloud-1
```

**1. Secrets.** Create a subdomain on duckdns.org and copy your token, then:

```bash
make vault-init
```

| Situation | What `vault-init` does |
|---|---|
| No `vault.yml` yet (new setup) | Generates random passwords, asks for the DuckDNS token, writes `vault.yml` encrypted and a random vault password in `.vault_pass` |
| `vault.yml` exists, no `.vault_pass` (new machine) | Asks for the existing vault password and checks it |
| Both exist | Nothing: it never overwrites secrets |

> Back up the vault password (`cat .vault_pass`): without it the vault can never be opened.

**2. Servers.** Edit `inventories/hosts.yml`:

```yaml
all:
  children:
    webservers:
      hosts:
        server-1:
          ansible_host: 203.0.113.10      # the server's public IP
          duckdns_subdomain: mysubdomain  # → wp.mysubdomain.duckdns.org
```

The SSH user and key are set in `ansible.cfg` (`remote_user`, `private_key_file`).

**3. Deploy.**

```bash
make ping      # every server answers "pong"
make deploy    # installs everything
make deploy    # again: the recap must show changed=0
```

**4. Open the site.**

| | URL | Login |
|---|---|---|
| WordPress | `https://wp.<subdomain>.duckdns.org` (admin: `/wp-admin`) | `wp_admin_user` + `vault_wp_admin_password` |
| WordPress (2nd admin) | same | `wp_admin2_user` + `vault_wp_admin2_password` |
| phpMyAdmin | `https://pma.<subdomain>.duckdns.org` | `db_user` + `vault_db_password` |

Usernames are in `inventories/group_vars/all/main.yml`; `make vault-view` shows the passwords.

## Commands

| Command | Description |
|---|---|
| `make ping` | Check Ansible can reach every server |
| `make deploy` | Deploy or update every server |
| `make check` | Dry run: show what `deploy` would change |
| `make syntax` | Check the playbook for syntax errors |
| `make vault-init` | Create or unlock the vault (first thing on a new machine or setup) |
| `make vault-view` | Show the decrypted secrets |
| `make vault-edit` | Edit the secrets (decrypts, opens your editor, re-encrypts) |
| `make local-up` | Run the stack locally with Docker and install WordPress |
| `make local-down` | Stop the local stack (data is kept) |
| `make help` | List the commands |

## Project structure

```
cloud-1/
├── Makefile                      # shortcuts (see Commands)
├── ansible.cfg                   # inventory, SSH user and key, vault password file, SSH options
├── cloud-one-playbook.yml        # the roles, in the order they run
├── inventories/
│   ├── hosts.yml                 # the servers: IP + DuckDNS subdomain of each
│   └── group_vars/all/
│       ├── main.yml              # all settings: domains, ports, users, database name
│       └── vault.yml             # secrets, encrypted with Ansible Vault
├── roles/
│   ├── common/                   # apt updates, basic tools, swap file
│   ├── firewall/                 # ufw: deny incoming except 22, 80, 443
│   ├── ssh/                      # key-only SSH, no root login (validated before applying)
│   ├── dns/                      # point the DuckDNS subdomain at the server
│   ├── docker/                   # Docker Engine + Compose plugin from Docker's apt repository
│   ├── setup/                    # copy docker-compose.yml, write the server's .env
│   ├── database/                 # start MariaDB, wait until healthy
│   ├── phpmyadmin/               # start phpMyAdmin
│   ├── wordpress/                # start WordPress, install it once with wp-cli
│   ├── nginx/                    # copy the nginx config, start nginx
│   └── tls/                      # Let's Encrypt certificate, switch to HTTPS, nightly renewal
├── scripts/
│   └── vault-init.sh             # used by make vault-init
└── srcs/                         # the application itself, also runnable locally
    ├── docker-compose.yml        # services, networks, volumes
    ├── .env.example              # variables needed to run locally
    └── nginx/
        ├── http/                 # HTTP only: local use, and before the first certificate
        └── https/                # port 80 → redirect, port 443 → TLS 1.2/1.3
```

## How a deployment works

The playbook runs these roles on every server, in parallel:

1. **Prepare and secure**: `common` → `firewall` → `ssh` → `dns` → `docker`
2. **Ship the project**: `setup` copies `docker-compose.yml` and generates `.env` (mode `0600`)
   from the settings and the vault.
3. **Start the services in dependency order**: `database` → `phpmyadmin` → `wordpress` → `nginx`
4. **HTTPS**: `tls`

**Getting the certificate.** nginx refuses to start with a certificate that doesn't exist yet, so
on the first deploy it starts in HTTP mode. certbot then proves domain ownership with the
HTTP-01 challenge (Let's Encrypt downloads a token from `/.well-known/acme-challenge/` on port 80),
and nginx switches to its HTTPS config. Later deploys reuse the certificate
(`--keep-until-expiring`); it's renewed when less than 30 days are left, by a deploy or by a
nightly cron job.

**After a server restart** (new public IP): update `ansible_host` in `hosts.yml` and run
`make deploy`. The DuckDNS record follows; the certificate stays valid (it certifies the name, not the IP).

## Security

| Measure | Where |
|---|---|
| Only ports 22, 80, 443 reachable | `roles/firewall` (ufw) + the cloud security group |
| Database unreachable from outside | MariaDB publishes no port; the `db` network is `internal` |
| HTTPS only, TLS 1.2/1.3 | `roles/tls`, `srcs/nginx/https/` |
| Key-only SSH, no root login | `roles/ssh` (config tested with `sshd -t` before it's applied) |
| New hosts trusted on first use, changed host keys refused | `ansible.cfg` (`StrictHostKeyChecking=accept-new`) |
| Secrets encrypted in the repo | Ansible Vault (`vault.yml`); its key `.vault_pass` is git-ignored |
| `.env` readable by root only | `roles/setup` (mode `0600`) |

Never committed (see `.gitignore`): `.vault_pass`, `.env`, `*.pem`, `srcs/certbot/`.

## Run locally

The same `docker-compose.yml` runs on your machine, in HTTP mode, without Ansible:

```bash
cp srcs/.env.example srcs/.env   # replace every change_me (e.g. openssl rand -base64 24)
make local-up
```

- WordPress: http://wp.localhost:8080 (admin: `/wp-admin`, `WP_ADMIN_USER` / `WP_ADMIN_PASSWORD`)
- phpMyAdmin: http://pma.localhost:8080 (`DB_USER` / `DB_PASSWORD`)

`*.localhost` always points to your own machine, so no DNS setup is needed.

## Verification

After `make deploy`, on the server (`cd /opt/cloud1`) unless noted:

| Check | Command | Expected |
|---|---|---|
| Idempotency | `make deploy` (your machine) | `changed=0` |
| Containers | `sudo docker compose ps` | 4 services up, mariadb `healthy` |
| Only nginx exposed | `sudo docker compose ps --format '{{.Name}} {{.Ports}}'` | only nginx has `0.0.0.0:80` / `:443` |
| Firewall | `sudo ufw status verbose` | active, only 22/80/443 allowed |
| Database not reachable | `nc -zv -w3 <ip> 3306` (your machine) | timeout / refused |
| Password SSH refused | `ssh -o PubkeyAuthentication=no ubuntu@<ip>` (your machine) | `Permission denied (publickey)` |
| HTTP → HTTPS | `curl -sI http://wp.<subdomain>.duckdns.org` | `301`, `Location: https://…` |
| Volumes | `sudo docker volume ls` | `cloud1_db_data`, `cloud1_wp_files` |
| Persistence | write a post, `sudo docker compose down && sudo docker compose up -d` | post still there |
| Restart one service | `sudo docker compose restart nginx` | others untouched |
| Crash recovery | `sudo docker compose exec wordpress sh -c 'kill 1'` | container comes back up |
| Reboot | `sudo reboot`, wait a minute | site back on its own |
| Certificate renewal | `sudo docker compose run --rm certbot renew --dry-run` | simulated renewal succeeded |

## Troubleshooting

| Error | Cause / fix |
|---|---|
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | The IP was used by another server before: `ssh-keygen -R <ip>`, then deploy again |
| `Permission denied (publickey)` | Wrong key or user: check `private_key_file` / `remote_user` in `ansible.cfg` |
| `no space left on device` | Disk too small for the images: grow it to 20 GB |
| certbot: `Timeout during connect` | Port 80 blocked: open it in the cloud security group |
| certbot: `DNS problem` | DuckDNS not pointing at the server: check the token (`make vault-edit`) |
| `Decryption failed` | Wrong vault password in `.vault_pass` |
| `Error establishing a database connection` | Database passwords changed after the first install: MariaDB keeps the original ones |
