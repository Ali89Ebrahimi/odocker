#!/bin/bash
# A modern, production-ready script to install Odoo 18 in Docker Compose.
# This version handles all installation scenarios robustly.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- 1. Password Generation & Setup ---
echo "🔐 Generating secure random passwords..."
DB_PASSWORD=$(openssl rand -base64 12)
ADMIN_PASSWORD=$(openssl rand -base64 12)
PROJECT_DIR="/srv/odoo-production"


# --- 2. System Preparation & Docker Installation ---
echo "🚀 Starting Odoo 18 installation..."
echo "Updating system packages..."
sudo apt-get update && sudo apt-get upgrade -y

# Ensure Docker's official repository is configured
if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    echo "Docker repository not found. Adding Docker's official GPG key and repository..."
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    echo "Updating package list with new Docker repo..."
    sudo apt-get update
fi

# Install Docker Engine if not present
if ! command -v docker &> /dev/null; then
    echo "Installing Docker Engine..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    sudo usermod -aG docker ${SUDO_USER:-$(whoami)}
    echo "Docker installed. You must log out and back in for Docker commands to work without sudo."
else
    echo "Docker Engine is already installed."
fi

# Install Docker Compose plugin if not present
if ! docker compose version &> /dev/null; then
    echo "Docker Compose v2 not found. Installing docker-compose-plugin..."
    sudo apt-get install -y docker-compose-plugin
else
    echo "Docker Compose v2 is already installed."
fi


# --- 3. Create Odoo Project Structure & Files ---
echo "Setting up Odoo project directory in ${PROJECT_DIR}..."
sudo mkdir -p ${PROJECT_DIR}/{config,postgresql-data}

echo "Creating compose.yml with secure passwords..."
sudo bash -c "cat > ${PROJECT_DIR}/compose.yml" << EOF
services:
  db:
    image: postgres:17
    container_name: odoo_db_prod
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    volumes:
      - ./postgresql-data:/var/lib/postgresql/data
    restart: always

  odoo:
    image: odoo:18.0
    container_name: odoo_app_prod
    depends_on:
      - db
    ports:
      - "127.0.0.1:8069:8069"
    volumes:
      - ./config:/etc/odoo
    restart: always
    command: --
EOF

echo "Creating odoo.conf with secure passwords..."
sudo bash -c "cat > ${PROJECT_DIR}/config/odoo.conf" << EOF
[options]
admin_passwd = ${ADMIN_PASSWORD}
db_host = db
db_port = 5432
db_user = odoo
db_password = ${DB_PASSWORD}
workers = 4
limit_time_real = 120
limit_time_cpu = 60
EOF


# --- 4. Set Permissions and Launch ---
echo "Assigning ownership to user ${SUDO_USER:-$(whoami)}..."
sudo chown -R ${SUDO_USER:-$(whoami)}:${SUDO_USER:-$(whoami)} ${PROJECT_DIR}

cd ${PROJECT_DIR}

echo "Pulling Docker images and starting Odoo..."
docker compose pull
docker compose up -d


# --- 5. Display Final Information ---
echo ""
echo "--------------------------------------------------"
echo "✅ Phase 1 Complete: Odoo is installed!"
echo ""
echo "⚠️  IMPORTANT: Please save this master password! ⚠️"
echo ""
echo "    Odoo Master Password: ${ADMIN_PASSWORD}"
echo ""
echo "Your project files are in: ${PROJECT_DIR}"
echo "Odoo is running but is NOT yet accessible from the internet."
echo "Next, proceed to Phase 2: Point your domain and set up a reverse proxy."
echo "--------------------------------------------------"