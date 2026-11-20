# Makefile for LUNA. Run it in nyx/luna. The flake is the nyx flake, one level up.
SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:

ORG       := LUNA.org
# An absolute path, so that a recipe can change directory.
FLAKE     := $(abspath ..)
HOST      ?= luna
OWNER     ?= coops
# The public IP address of the Vultr instance. Only the install uses it.
VPS_IP    ?= 108.160.135.211
SSH_KEY   ?= $(HOME)/.ssh/luna_ed25519
# Keep the host key outside the flake source. Nix copies the source to the store.
BOOTSTRAP := $(HOME)/.local/state/luna/bootstrap
DEV       := nix develop $(FLAKE) --command

.PHONY: help tangle check build install deploy host-key forget-host-key secrets matrix-users money-upload logs web-logs web-lock web-vm-test egress-vm-test sentry-vm-test integrity-vm-test verify deps-audit audit

help:
	@echo "tangle           Make the build files from $(ORG)."
	@echo "check            Run the tests of luna-core, luna-web and luna-core-ex. Evaluate the luna host."
	@echo "build            Build the full luna system on this laptop."
	@echo "host-key         Make the SSH host key for the install."
	@echo "forget-host-key  Delete the local copy of the host key."
	@echo "secrets          Edit secrets/luna.yaml with sops."
	@echo "install          Install NixOS on the VPS. Set VPS_IP. ERASES THE VPS DISK."
	@echo "matrix-users     Make the Matrix accounts for $(OWNER) and luna."
	@echo "deploy           Deploy the configuration over the tailnet."
	@echo "money-upload     Send bank exports to the luna inbox. Set FILES."
	@echo "logs             Show the luna-core log."
	@echo "web-logs         Show the luna-web log."
	@echo "web-lock         Write pkgs/luna-web/mix.lock again with mix deps.get."
	@echo "web-vm-test      Run the luna-web VM test. The test needs KVM."
	@echo "egress-vm-test   Run the VM test of the outbound allowlist. The test needs KVM."
	@echo "sentry-vm-test   Run the VM test of the alerts. The test needs KVM."
	@echo "integrity-vm-test Run the VM test of the integrity check and the brief."
	@echo "verify           Make sure that luna runs the system that this tree builds."
	@echo "deps-audit       Show retired Hex packages and security advisories."
	@echo "audit            Show the end of the audit log."

tangle:
	emacs --batch --eval "(progn (require 'org) (require 'ob-tangle) \
	  (setq org-src-preserve-indentation t) \
	  (org-babel-tangle-file \"$(ORG)\"))"

check:
	nix build $(FLAKE)#luna-core --no-link --print-build-logs
	nix build $(FLAKE)#luna-web --no-link --print-build-logs
	nix build $(FLAKE)#luna-core-ex --no-link --print-build-logs
	nix eval --raw $(FLAKE)#nixosConfigurations.$(HOST).config.system.build.toplevel.drvPath
	echo

build:
	nix build $(FLAKE)#nixosConfigurations.$(HOST).config.system.build.toplevel --print-build-logs

host-key:
	mkdir -p -m 700 $(BOOTSTRAP)/etc/ssh
	test -f $(BOOTSTRAP)/etc/ssh/ssh_host_ed25519_key || \
	  ssh-keygen -q -t ed25519 -N "" -C "root@$(HOST)" -f $(BOOTSTRAP)/etc/ssh/ssh_host_ed25519_key
	chmod 600 $(BOOTSTRAP)/etc/ssh/ssh_host_ed25519_key
	echo "Host public key (write it as &luna in nyx/.sops.yaml):"
	$(DEV) ssh-to-age < $(BOOTSTRAP)/etc/ssh/ssh_host_ed25519_key.pub

forget-host-key:
	rm -rf $(BOOTSTRAP)

secrets:
	if grep -q REPLACEWITH $(FLAKE)/.sops.yaml; then
	  echo "Write the luna host key in nyx/.sops.yaml first."
	  exit 1
	fi
	cd $(FLAKE)
	$(DEV) sops secrets/luna.yaml

# WARNING: install erases the disk of the VPS at VPS_IP.
install: check
	test -n "$(VPS_IP)" || { echo "Set VPS_IP. Example: make install VPS_IP=203.0.113.10"; exit 1; }
	test -f $(FLAKE)/secrets/luna.yaml || { echo "Run make secrets first."; exit 1; }
	test -f $(BOOTSTRAP)/etc/ssh/ssh_host_ed25519_key || { echo "Run make host-key first."; exit 1; }
	$(DEV) nixos-anywhere --flake $(FLAKE)#$(HOST) --extra-files $(BOOTSTRAP) -i $(SSH_KEY) --target-host root@$(VPS_IP)
	echo "The install is done. Delete the local host key: make forget-host-key"

matrix-users:
	echo "Write a password for the Matrix account $(OWNER). Keep it in your password manager."
	ssh -t root@$(HOST) luna-register-user -u $(OWNER) --admin
	ssh root@$(HOST) 'luna-register-user -u luna --no-admin -p "$$(cat /run/secrets/luna-matrix-password)"'
	ssh root@$(HOST) systemctl restart luna-core

deploy: check
	nixos-rebuild switch --flake $(FLAKE)#$(HOST) --target-host root@$(HOST)

# The inbox is outside git. The import deletes each file after the import.
money-upload:
	test -n "$(FILES)" || { echo "Set FILES. Example: make money-upload FILES='~/Downloads/*.csv'"; exit 1; }
	scp $(FILES) $(OWNER)@$(HOST):/var/lib/luna/inbox/
	echo "Uploaded. Delete the local copies when you no longer need them."

logs:
	ssh root@$(HOST) journalctl -u luna-core -n 200 --no-pager

web-logs:
	ssh root@$(HOST) journalctl -u luna-web -n 200 --no-pager

# Mix needs Hex. The nixpkgs Hex goes in MIX_PATH, so Mix does not download Hex.
web-lock:
	cd $(FLAKE)/pkgs/luna-web
	hex="$$(nix eval --raw --inputs-from $(FLAKE) nixpkgs#beamPackages.hex.outPath)"
	export MIX_PATH="$$(dirname "$$(find "$$hex" -name hex.app)")"
	nix shell --inputs-from $(FLAKE) nixpkgs#beamPackages.elixir --command mix deps.get

# The test file uses paths in this tree, so the build is impure.
web-vm-test:
	nix build --impure --no-link --print-build-logs --expr \
	  '(builtins.getFlake "$(FLAKE)").inputs.nixpkgs.legacyPackages.x86_64-linux.callPackage $(abspath tests/web-vm.nix) { }'

egress-vm-test:
	nix build --impure --no-link --print-build-logs --expr \
	  '(builtins.getFlake "$(FLAKE)").inputs.nixpkgs.legacyPackages.x86_64-linux.callPackage $(abspath tests/egress-vm.nix) { }'

sentry-vm-test:
	nix build --impure --no-link --print-build-logs --expr \
	  '(builtins.getFlake "$(FLAKE)").inputs.nixpkgs.legacyPackages.x86_64-linux.callPackage $(abspath tests/sentry-vm.nix) { }'

integrity-vm-test:
	nix build --impure --no-link --print-build-logs --expr \
	  '(builtins.getFlake "$(FLAKE)").inputs.nixpkgs.legacyPackages.x86_64-linux.callPackage $(abspath tests/integrity-vm.nix) { }'

# The check from the laptop (B3). A root attacker on luna can change the checks
# on luna, but not this build on the laptop. The tree must be the deployed commit.
verify:
	expected="$$(nix build $(FLAKE)#nixosConfigurations.$(HOST).config.system.build.toplevel --no-link --print-out-paths)"
	running="$$(ssh root@$(HOST) readlink -f /run/current-system)"
	if [ "$$expected" = "$$running" ]; then
	  echo "luna runs the expected system: $$running"
	else
	  echo "MISMATCH. Expected: $$expected"
	  echo "          Running:  $$running"
	  exit 1
	fi

# mix hex.audit reads the advisories from hex.pm, so it needs the network.
deps-audit:
	hex="$$(nix eval --raw --inputs-from $(FLAKE) nixpkgs#beamPackages.hex.outPath)"
	export MIX_PATH="$$(dirname "$$(find "$$hex" -name hex.app)")"
	for app in luna-web luna-core-ex; do
	  echo "== $$app"
	  (cd $(FLAKE)/pkgs/$$app && nix shell --inputs-from $(FLAKE) nixpkgs#beamPackages.elixir --command mix hex.audit)
	done

audit:
	ssh root@$(HOST) tail -n 50 /var/lib/luna/audit/audit.jsonl
