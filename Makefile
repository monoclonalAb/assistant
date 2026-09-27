.PHONY: setup gateway-up gateway-down gateway-restart chat tui status doctor update shell logs logs-follow

setup:
	docker compose stop gateway
	docker compose run --rm gateway setup
	docker compose up -d gateway

gateway-up:
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

update:
	docker compose pull gateway
	docker compose up -d gateway

shell: gateway-up
	docker compose exec gateway bash

logs: gateway-up
	docker compose exec -T gateway tail -n 100 /opt/data/logs/gateways/default/current

logs-follow: gateway-up
	docker compose exec gateway tail -F /opt/data/logs/gateways/default/current
