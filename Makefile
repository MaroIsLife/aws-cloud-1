PLAYBOOK = cloud-one-playbook.yml

# --- Remote (Ansible -> servers in inventories/hosts.yml)
ping:           ## Check Ansible can reach every server
	ansible all -m ping

deploy:         ## Deploy or update every server
	ansible-playbook $(PLAYBOOK)

check:          ## Dry run: show what deploy WOULD change
	ansible-playbook $(PLAYBOOK) --check --diff

syntax:         ## Check the playbook for YAML/syntax errors
	ansible-playbook $(PLAYBOOK) --syntax-check

# --- Secrets (inventories/group_vars/all/vault.yml, unlocked by .vault_pass)
vault-init:     ## First thing on a new machine or setup: creates or unlocks the vault
	@./scripts/vault-init.sh

vault-view:     ## Show the decrypted secrets
	ansible-vault view inventories/group_vars/all/vault.yml

vault-edit:     ## Edit the secrets (decrypts, opens your editor, re-encrypts)
	ansible-vault edit inventories/group_vars/all/vault.yml

# --- Local (Docker on your Mac, from srcs/)
local-up:       ## Start the stack locally and install WordPress if needed
	cd srcs && docker compose up -d && docker compose run --rm -T wpcli

local-down:     ## Stop the local stack (data is kept)
	cd srcs && docker compose down

help:           ## List the commands
	@grep -E '^[a-z-]+:.*##' Makefile | sed 's/:.*##/ -/'

.PHONY: ping deploy check syntax vault-init vault-view vault-edit local-up local-down help
