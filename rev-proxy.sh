#!/bin/bash
# A script to set up an Nginx reverse proxy for Odoo.
# Option 3 now automatically detects the local IP address.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Color Definitions ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- 1. User Choice Menu ---
echo -e "${YELLOW}Please choose the type of reverse proxy setup:${NC}"
echo ""
echo "  1) Secure (Let's Encrypt): Requires a public domain name. (RECOMMENDED)"
echo "  2) Self-Signed (Public IP): For testing with a public IP. (Causes browser warnings)"
echo "  3) Self-Signed (Local Network): For LAN access only. Auto-detects IP. (Causes browser warnings)"
echo ""
read -p "$(echo -e "${YELLOW}Enter your choice [1, 2, or 3]: ${NC}")" SETUP_CHOICE

# --- 2. Install Common Dependencies & Configure Firewall ---
echo -e "\n${BLUE}--- Installing Nginx and configuring firewall ---${NC}"
sudo apt-get update > /dev/null
sudo apt-get install -y nginx
sudo ufw allow 'Nginx Full' > /dev/null
sudo ufw allow ssh > /dev/null
sudo ufw --force enable > /dev/null

# --- 3. Execute Based on Choice ---
if [ "$SETUP_CHOICE" == "1" ]; then
    # --- SECURE LET'S ENCRYPT PATH ---
    echo -e "\n${BLUE}--- Proceeding with Secure (Let's Encrypt) setup ---${NC}"
    read -p "$(echo -e "${YELLOW}Enter your domain name (e.g., odoo.yourcompany.com): ${NC}")" DOMAIN
    read -p "$(echo -e "${YELLOW}Enter your email address (for Let's Encrypt notifications): ${NC}")" EMAIL
    if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then echo -e "${RED}Error: Domain name and email are required.${NC}"; exit 1; fi
    echo -e "${BLUE}Installing Certbot...${NC}"
    sudo apt-get install -y certbot python3-certbot-nginx > /dev/null
    echo -e "${BLUE}Creating Nginx configuration for $DOMAIN...${NC}"
    NGINX_CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN"
    sudo bash -c "cat > $NGINX_CONFIG_FILE" << EOF
server {
    listen 80; server_name $DOMAIN;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    location /longpolling { proxy_pass http://127.0.0.1:8069; }
    location / { proxy_pass http://127.0.0.1:8069; }
}
EOF
    echo -e "${BLUE}Enabling Nginx site...${NC}"
    sudo ln -s -f $NGINX_CONFIG_FILE /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo nginx -t && sudo systemctl restart nginx
    echo -e "${BLUE}🔒 Obtaining SSL certificate from Let's Encrypt...${NC}"
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL --redirect
    echo -e "\n--------------------------------------------------"
    echo -e "${GREEN}✅ Phase 2 Complete!${NC}"
    echo -e "Your Odoo instance is now secure and accessible at: ${GREEN}https://$DOMAIN${NC}"
    echo -e "--------------------------------------------------"

elif [ "$SETUP_CHOICE" == "2" ] || [ "$SETUP_CHOICE" == "3" ]; then
    # --- SELF-SIGNED PATHS (Public IP or Local Network) ---
    IDENTIFIER=""
    if [ "$SETUP_CHOICE" == "2" ]; then
        echo -e "\n${BLUE}--- Proceeding with Self-Signed (Public IP) setup ---${NC}"
        echo -e "${BLUE}🔎 Detecting public IP address...${NC}"
        IDENTIFIER=$(curl -s ifconfig.me)
        if [ -z "$IDENTIFIER" ]; then echo -e "${RED}Error: Could not determine public IP.${NC}"; exit 1; fi
        echo -e "Server's Public IP is: ${YELLOW}$IDENTIFIER${NC}"
    else # This is the updated, fully automatic logic for option 3
        echo -e "\n${BLUE}--- Proceeding with Self-Signed (Local Network) setup ---${NC}"
        echo -e "${BLUE}🔎 Detecting local network IP address...${NC}"
        IDENTIFIER=$(hostname -I | awk '{print $1}')
        if [ -z "$IDENTIFIER" ]; then echo -e "${RED}Error: Could not determine local IP address.${NC}"; exit 1; fi
        echo -e "Server's Local IP is: ${YELLOW}$IDENTIFIER${NC}"
    fi

    echo -e "${BLUE}🔑 Generating self-signed SSL certificate...${NC}"
    CERT_DIR="/etc/ssl/private"
    sudo mkdir -p $CERT_DIR
    KEY_PATH="$CERT_DIR/nginx-selfsigned.key"
    CERT_PATH="$CERT_DIR/nginx-selfsigned.crt"
    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$KEY_PATH" -out "$CERT_PATH" -subj "/C=NL/ST=North Holland/L=Amsterdam/O=Odoo Test/CN=$IDENTIFIER" > /dev/null

    echo -e "${BLUE}📝 Creating Nginx configuration...${NC}"
    NGINX_CONFIG_FILE="/etc/nginx/sites-available/odoo-self-signed"
    sudo bash -c "cat > $NGINX_CONFIG_FILE" << EOF
server {
    listen 80; server_name $IDENTIFIER; return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl; server_name $IDENTIFIER;
    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    location /longpolling { proxy_pass http://127.0.0.1:8069; }
    location / { proxy_pass http://127.0.0.1:8069; }
}
EOF
    echo -e "${BLUE}Enabling Nginx site...${NC}"
    sudo ln -s -f $NGINX_CONFIG_FILE /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo nginx -t && sudo systemctl restart nginx
    echo -e "\n--------------------------------------------------"
    echo -e "${GREEN}✅ Setup Complete${NC}"
    echo -e ""
    echo -e "${RED}⚠️  WARNING: You will see a browser security warning. This is expected.${NC}"
    echo -e ""
    echo -e "Access Odoo at: ${YELLOW}https://$IDENTIFIER${NC}"
    echo -e "--------------------------------------------------"
else
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
fi
