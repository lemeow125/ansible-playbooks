## Usage

### Setup

1. Run `setup.yml` using a non-sudo user, providing regular and sudo credentials.

```bash
ansible-playbook roles/tasks/debian/setup.yml -u keannu125 -k --ask-become-pass
```

This will elevate to `root` user via `sudo` and set up root SSH access through the provided `id_rsa.pub` file in the control node's own `.ssh` directory

2. Set up the necessary template scripts provided at `/root/scripts`

- Rename `.env.sample` to `.env.` (via `mv .env.sample .env`)
- Provide your ACME SSL access tokens in the `.env` for `renew_ssl.sh` to parse
- Provide project directories to spin up on boot through `start_services.sh`
- Provide the same project directories to back up via Borg in `backup.sh`

3. Update the Samba credentials file located at `/root/.samba`

```
# credentials
user=USERNAME
password=PASSWORD
```

4. Update the CIFS/Samba mount for backups located in `crontab` (via `crontab -e`)

```
# crontab entry
* * * * * mount.cifs "//255.255.255.0/SAMBA-MOUNT" "/mnt/backups" -o credentials="/root/.samba/credentials"
```

If you'd need to run the `setup.yml` playbook again for any reason. You can omit specifying user or sudo credentials and simply run

```bash
ansible-playbook roles/tasks/debian/setup.yml
```

Any existing or additional scripts that have already been modified will not be overwritten (See `force: false` directives in [`setup.yml`](./setup.yml))
