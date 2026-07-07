DEV_RUN_CONTEXT ?= docker compose exec dev
MOCK_RUN_CONTEXT ?= docker compose exec mock

ANSIBLE_USER=tech

default: check

############################################
# container
############################################
build:
	docker compose build

up:
	docker compose up -d

down:
	docker compose down --remove-orphans

clean:
	docker compose down --rmi all --volumes --remove-orphans

ps:
	docker compose ps -a

logs:
	docker compose logs

logs/%:
	docker compose logs $(@F)

restart: down up

rebuild: clean up

reset:
	docker compose up -d --force-recreate mock

############################################
# ansible
############################################
install:
	$(DEV_RUN_CONTEXT) ansible-galaxy collection install -r ./ansible/requirements.yaml

check: lint yamllint shellcheck

fmt:
	$(DEV_RUN_CONTEXT) ansible-lint --config-file "ansible/.ansible-lint" --fix

lint:
	$(DEV_RUN_CONTEXT) ansible-lint --config-file "ansible/.ansible-lint"

yamllint:
	$(DEV_RUN_CONTEXT) yamllint .

shellcheck:
	$(DEV_RUN_CONTEXT) shellcheck init.sh

play:
	$(MOCK_RUN_CONTEXT) \
		sudo -u "$(ANSIBLE_USER)" \
		bash -c "ansible-playbook -i inventories/hosts.yaml playbook.yaml --extra-vars '@/etc/ansible/extra_vars.yaml' --extra-vars 'ansible_user=$(ANSIBLE_USER)'"

play-wsl:
	$(MOCK_RUN_CONTEXT) \
		sudo -u "$(ANSIBLE_USER)" \
		bash -c "ansible-playbook -i inventories/hosts.yaml playbook.yaml --extra-vars '@/etc/ansible/extra_vars.yaml' --extra-vars 'ansible_user=$(ANSIBLE_USER)' --extra-vars '{\"is_wsl\": true}'"

play/%:
	$(MOCK_RUN_CONTEXT) \
		sudo -u "$(ANSIBLE_USER)" \
		bash -c "ansible-playbook -i inventories/hosts.yaml playbook.yaml --extra-vars '@/etc/ansible/extra_vars.yaml' --extra-vars 'ansible_user=$(ANSIBLE_USER)' --tags $(@F)"
