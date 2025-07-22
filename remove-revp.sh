#!/bin/bash
# This script reverts the Nginx reverse proxy setup for Odoo.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Color Definitions ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- 1. User Confirmation ---
echo -e "${YELLOW}This script will STOP and REMOVE Nginx and its configurations, and DISABLE the firewall.${NC}"
read -p "$(echo -e "${YELLOW}Are you absolutely sure you want to continue? [y/N]: ${NC}")" CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Revert cancelled."
    exit 0
fi

# --- 2. User Choice Menu ---
echo -e "\n${YELLOW}Which setup are you reverting?${NC}"
echo "  1) The Secure (Let's Encrypt with Domain) setup"
echo "  2) The Self-Signed (Public IP) setup"
echo "  3) The Self-Signed (Local Network) setup"
read -p "$(echo -e "${YELLOW}Enter your choice [1, 2, or 3]: ${NC}")" SETUP_CHOICE

# --- 3. Stop Nginx Service ---
echo -e "\n${YELLOW}Stopping and disabling Nginx service...${NC}"
sudo systemctl stop nginx
sudo systemctl disable nginx

# --- 4. Execute Revert Logic ---
if [ "$SETUP_CHOICE" == "1" ]; then
    # --- REVERT SECURE LET'S ENCRYPT PATH ---
    read -p "$(echo -e "${YELLOW}Enter the domain name you used (e.g., odoo.yourcompany.com): ${NC}")" DOMAIN
    if [ -z "$DOMAIN" ]; then echo -e "${RED}Error: Domain name is required.${NC}"; exit 1; fi
    echo "Deleting Let's Encrypt certificate for $DOMAIN..."
    sudo certbot delete --cert-name "$DOMAIN" --non-interactive || true
    echo "Purging Nginx and Certbot packages..."
    sudo apt-get purge --auto-remove -y nginx nginx-common certbot python3-certbot-nginx

elif [ "$SETUP_CHOICE" == "2" ] || [ "$SETUP_CHOICE" == "3" ]; then
    # --- REVERT SELF-SIGNED PATHS ---
    echo "Removing self-signed certificate files and Nginx config..."
    sudo rm -f /etc/ssl/private/nginx-selfsigned.key
    sudo rm -f /etc/ssl/certs/nginx-selfsigned.crt
    sudo rm -f /etc/nginx/sites-available/odoo-self-signed
    sudo rm -f /etc/nginx/sites-enabled/odoo-self-signed
    echo "Purging Nginx and related packages..."
    sudo apt-get purge --auto-remove -y nginx nginx-common

else
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
fi

# --- 5. Revert Firewall ---
echo "Disabling firewall..."
sudo ufw disable

echo -e "\n${GREEN}✅ Revert complete. Nginx has been removed and the firewall is disabled.${NC}"
