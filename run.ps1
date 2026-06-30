$ErrorActionPreference = "Stop"

$inventory = "ansible/inventory.ini"
$playbook = "ansible/site.yml"

ansible-playbook -i $inventory $playbook
