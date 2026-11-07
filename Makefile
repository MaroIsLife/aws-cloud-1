PLAYBOOK = cloud-one-playbook.yml
# Optional: target one server, e.g. make deploy HOST=omanar (default: every server)
LIMIT = $(if $(HOST),--limit $(HOST))

# --- Remote (Ansible -> servers in inventories/hosts.yml)
ping:           ## Check Ansible can reach every server (or HOST=name)
	ansible $(or $(HOST),all) -m ping

deploy:         ## Deploy or update every server (or HOST=name)
	ansible-playbook $(PLAYBOOK) $(LIMIT)

check:          ## Dry run: show what deploy WOULD change
	ansible-playbook $(PLAYBOOK) --check --diff $(LIMIT)

syntax:         ## Check the playbook for YAML/syntax errors
	ansible-playbook $(PLAYBOOK) --syntax-check

# --- Secrets (inventories/group_vars/all/vault.yml, unlocked by .vault_pass)
# HOST=name works on that server's own vault instead: inventories/host_vars/<name>/vault.yml
VAULT_FILE = $(if $(HOST),inventories/host_vars/$(HOST)/vault.yml,inventories/group_vars/all/vault.yml)
vault-init:     ## First thing on a new machine or setup: creates or unlocks the vault (HOST=name: that server's own secrets)
	@./scripts/vault-init.sh $(HOST)

vault-view:     ## Show the decrypted secrets
	ansible-vault view $(VAULT_FILE)

vault-edit:     ## Edit the secrets (decrypts, opens your editor, re-encrypts)
	ansible-vault edit $(VAULT_FILE)

# --- Local (Docker on your Mac, from srcs/)
local-up:       ## Start the stack locally and install WordPress if needed
	cd srcs && docker compose up -d && docker compose run --rm -T wpcli

local-down:     ## Stop the local stack (data is kept)
	cd srcs && docker compose down

help:           ## List the commands
	@grep -E '^[a-z-]+:.*##' Makefile | sed 's/:.*##/ -/'

.PHONY: ping deploy check syntax vault-init vault-view vault-edit local-up local-down help
