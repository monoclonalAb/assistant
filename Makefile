.PHONY: setup chat tui status doctor update shell

setup:
	docker compose run --rm hermes setup

chat:
	docker compose run --rm hermes

tui:
	docker compose run --rm hermes --tui

status:
	docker compose run --rm hermes status

doctor:
	docker compose run --rm hermes doctor

update:
	docker compose pull

shell:
	docker compose run --rm hermes bash

