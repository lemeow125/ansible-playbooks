#!/bin/bash

# Read CF_Token and ACME_Email from .env
source ".env"

/root/.acme.sh/acme.sh --upgrade --auto-upgrade
/root/.acme.sh/acme.sh --register-account -m noehbernasol0@gmail.com

# Array of domains
domains=("*.06222001.xyz" "06222001.xyz")
legacy_domains=()
all_domains=("${domains[@]}" "${legacy_domains[@]}")

# Whether to force update or not
force_update=false
echo "===== Force update domains: " $force_update " ====="

# Loop through the domains and execute the commands for each one
for domain in "${all_domains[@]}"
do

    # Issue the certificate using acme.sh
	echo "====== Registering domain:" $domain " ======"
	if $force_update ; then
		/root/.acme.sh/acme.sh --force --issue --dns dns_cf --keylength 4096 -d "$domain" --server letsencrypt
	else
		/root/.acme.sh/acme.sh --issue --dns dns_cf --keylength 4096 -d "$domain" --server letsencrypt
	fi

done

echo "===== Reloading firewall ====="
service nginx reload 
echo "===== Done ====="