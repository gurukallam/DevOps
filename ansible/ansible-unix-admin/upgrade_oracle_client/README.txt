USAGE:
1. CHECK PLAYBOOK SYNTAX AND LIST NUMBER OF HOSTS WHERE PLAYBOOK WILL BE EXECUTED.
ansible-playbook --extra-vars 'override_hosts=TIB-*' playbooks/upgrade_oracle_client.yml --list-hosts

2. ACTUAL EXECUTION
ansible-playbook --extra-vars 'override_hosts=TIB-*' playbooks/upgrade_oracle_client.yml -Kk
