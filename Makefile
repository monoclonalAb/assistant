-include .env
export

.PHONY: preflight setup gateway-up gateway-down gateway-restart chat tui status doctor update shell logs logs-follow \
	jarvis vault-init configure model host-setup check test imessage-check notify-test \
	dream-install dream-reinstall dream-run dream-status dream-remove \
	vault-backup-setup vault-backup vault-log

# Refuses to start Hermes unless HERMES_PROJECT_DIR is a Jarvis vault.
preflight:
	@scripts/preflight.sh

setup: preflight
	docker compose stop gateway
	docker compose run --rm gateway setup
	docker compose up -d gateway

gateway-up: preflight
	docker compose up -d gateway

gateway-down:
	docker compose stop gateway

gateway-restart:
	docker compose restart gateway

chat: gateway-up
	docker compose exec gateway hermes

tui: gateway-up
	docker compose exec gateway hermes --tui

status: gateway-up
	docker compose exec -T gateway hermes status

doctor: gateway-up
	docker compose exec -T gateway hermes doctor

update: preflight
	docker compose pull gateway
	docker compose up -d gateway

shell: gateway-up
	docker compose exec gateway bash

logs: gateway-up
	docker compose exec -T gateway tail -n 100 /opt/data/logs/gateways/default/current

logs-follow: gateway-up
	docker compose exec gateway tail -F /opt/data/logs/gateways/default/current

# --- Jarvis -------------------------------------------------------------

# One-shot: create the vault, configure Hermes, schedule the nightly dream.
jarvis: vault-init configure dream-install

vault-init:
	scripts/vault-init.sh "$(HERMES_PROJECT_DIR)"

configure: gateway-up
	scripts/configure.sh

# Switch the chat model / provider (interactive).
model: gateway-up
	docker compose exec gateway hermes model

# One-time macOS settings for the Jarvis Mac (sudo): no sleep on AC, manual OS updates.
host-setup:
	scripts/host-setup.sh

# Read-only health and safety audit.
check:
	@scripts/check.sh

# Throwaway end-to-end check of the whole setup (safe next to the real gateway).
test:
	tests/smoke.sh

# Is the BlueBubbles bridge connected and is the webhook registered?
imessage-check: gateway-up
	@docker compose exec -T gateway sh -c 'out=$$(grep -h "\[bluebubbles\]" /opt/data/logs/gateway.log | tail -n 15); \
		if [ -n "$$out" ]; then echo "$$out"; else echo "no BlueBubbles log lines yet; configure it with: make setup"; exit 1; fi'

# Send a test failure alert to JARVIS_NOTIFY.
notify-test: gateway-up
	@test -n "$(JARVIS_NOTIFY)" || { echo "set JARVIS_NOTIFY in .env first, e.g. bluebubbles:+64211234567"; exit 1; }
	scripts/notify.sh "Test from Jarvis: failure alerts reach you here."

dream-install: gateway-up
	scripts/dream.sh install

# Apply changed JARVIS_DREAM_* / JARVIS_NOTIFY settings.
dream-reinstall: gateway-up
	scripts/dream.sh reinstall

# Run the nightly consolidation now (starts on the next scheduler tick).
dream-run: gateway-up
	scripts/dream.sh run

dream-status: gateway-up
	scripts/dream.sh status

dream-remove: gateway-up
	scripts/dream.sh remove

# Create the private backup repo + deploy key, back up now, and schedule daily backups.
vault-backup-setup:
	scripts/vault-backup.sh setup
	scripts/vault-backup.sh install

vault-backup:
	scripts/vault-backup.sh run

# Read the vault's history safely (via the host-owned mirror, never git inside the vault).
vault-log:
	scripts/vault-backup.sh log --stat -n 20
