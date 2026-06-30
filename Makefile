ANSIBLE_PLAYBOOK ?= ansible-playbook
ANSIBLE_GALAXY ?= ansible-galaxy
ANSIBLE_DIR ?= ansible
INVENTORY ?= $(ANSIBLE_DIR)/inventory.ini
PLAYBOOK ?= $(ANSIBLE_DIR)/site.yml

.PHONY: syntax-check install-collections run

syntax-check:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(PLAYBOOK) --syntax-check

install-collections:
	$(ANSIBLE_GALAXY) collection install ansible.posix

run:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(PLAYBOOK)