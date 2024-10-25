# Ansible Playbook Repository

This repository contains my Ansible playbook configuration and scripts.

## Installation

To install the Ansible playbook, follow these steps:

1. Clone this repository
2. Install Ansible on your system if you haven't already: `sudo apt-get install ansible`
3. Move into the repository directory: `cd /path/to/ansible-playbooks`

## Usage

To run an Ansible playbook, navigate to the desired playbook directory and execute:

```bash
ansible-playbook -i inventory playbook.yml
```

Don't forget to update hosts in `inventory`!
