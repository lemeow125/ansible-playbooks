#!/bin/bash

# Read DuckDNS_Token and ACME_Email from .env
source ".env"

/root/.acme.sh/acme.sh --upgrade --auto-upgrade

# Array of main domains
domains=("*.keannu1.duckdns.org" "keannu1.duckdns.org")
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
		/root/.acme.sh/acme.sh --insecure --force --issue --dns dns_duckdns -d "$domain"
	else
		/root/.acme.sh/acme.sh --insecure --issue --dns dns_duckdns -d "$domain"
	fi

done

echo "===== Reloading firewall ====="
service nginx reload 
echo "===== Done ====="