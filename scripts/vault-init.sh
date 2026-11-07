#!/usr/bin/env bash
# make vault-init: prepares the vault for this machine. Never overwrites existing secrets.
#
#   vault.yml + .vault_pass exist   -> nothing to do
#   vault.yml exists, no .vault_pass -> new machine: asks for the EXISTING vault password
#   no vault.yml                    -> new setup: random vault password + random secrets,
#                                      asks for the DuckDNS token, writes vault.yml encrypted
set -euo pipefail
cd "$(dirname "$0")/.."

VAULT=inventories/group_vars/all/vault.yml
PASS=.vault_pass

# N random letters and digits. head stops reading after N characters, which makes tr exit
# with "broken pipe": normal here, so pipefail is turned off inside this function only.
random() ( set +o pipefail; LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${1:-32}" )

# 1. Everything is already there
if [ -f "$VAULT" ] && [ -f "$PASS" ]; then
    echo "Vault already set up ($VAULT + $PASS). Nothing to do."
    echo "Show the secrets: make vault-view    Change them: make vault-edit"
    exit 0
fi

# 2. New machine, existing vault: we need the password it was encrypted with
if [ -f "$VAULT" ]; then
    read -rsp "Vault password (the one saved when the vault was created): " pw; echo
    ( umask 077; printf '%s\n' "$pw" > "$PASS" )
    if ansible-vault view "$VAULT" > /dev/null 2>&1; then
        echo "OK: $PASS written, the vault opens. You can run make deploy."
    else
        rm -f "$PASS"
        echo "Wrong password: $VAULT can't be decrypted. Nothing written." >&2
        exit 1
    fi
    exit 0
fi

# 3. New setup: no vault yet
echo "No vault found: creating a new one with random passwords."
read -rsp "DuckDNS token (from duckdns.org, top of the page): " token; echo
if [ -z "$token" ]; then
    echo "The DuckDNS token can't be empty. Nothing written." >&2
    exit 1
fi

[ -f "$PASS" ] || ( umask 077; random 32 > "$PASS" )

# The plain text only goes through a pipe, it's never written to disk
cat <<EOF | ansible-vault encrypt --output "$VAULT" -
# Encrypted with ansible-vault. Show: make vault-view   Edit: make vault-edit
vault_db_password: $(random 32)
vault_db_root_password: $(random 32)
vault_wp_admin_password: $(random 24)
vault_wp_admin2_password: $(random 24)

# From https://www.duckdns.org (top of the page once signed in)
vault_duckdns_token: $token
EOF

echo
echo "Created $VAULT (encrypted) and $PASS."
echo "IMPORTANT: back up the vault password now, it is the only way to open the vault:"
echo "    cat $PASS"
