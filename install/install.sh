#!/usr/bin/env bash

# The BHIMA installation script.
set -e # Exit immediately if a command exits with a non-zero status

# Global Variables
BHIMA_INSTALL_DIR="/opt/bhima"
BHIMA_VERSION="1.36.0"
BHIMA_HOST=""   # e.g. vanga.thirdculturesoftware.com
BHIMA_PORT=8080 # e.g.8080

MYSQL_PASSWORD="$(openssl rand -hex 26)"

TS_AUTH_KEY=""

# Checks if the script is running with root privileges (sudo).
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (sudo)."
  exit 1
fi

# Print welcome message
echo "Welcome! This script will help install the BHIMA software version $BHIMA_VERSION."
echo "=============================================================================="

# Function to install dependencies
function install_dependencies() {
  echo "Updating BHIMA OS dependencies..."

  # Refresh the package lists, and download the OS libraries
  sudo apt-get -qq update && sudo apt-get -qq upgrade -y
  sudo apt-get -qq install -y wget lsb-release ca-certificates curl gnupg software-properties-common apt-transport-https tar screen

  echo "✓ dependencies updated"

  # show the banner image
  echo ""
  echo "Welcome!  You are now installing..."
  curl https://raw.githubusercontent.com/Third-Culture-Software/bhima-scripts/refs/heads/main/install/header.txt
  echo "BHIMA is free and open source software (FOSS) licensed under GPLv2.  By continuing you agree to the terms of the license."
  echo ""

  # Get the LTS NodeJS from NodeSource
  echo "Installing NodeJS LTS..."
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo bash -
  sudo apt-get -qq install -y nodejs
  echo "✓ NodeJS installed."
  
  echo "Installing redis ..."

  # Install the redis.io APT repository
  if [ -f /usr/share/keyrings/redis-archive-keyring.gpg ]; then
    rm /usr/share/keyrings/redis-archive-keyring.gpg
  fi

  curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
  sudo chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
  sudo apt-get -qq update
  sudo apt-get -qq install -y redis

  echo "✓ redis installed."
}

# Function to install and configure MySQL
function install_mysql() {
  local RELEASE_REPO="mysql-8.4"
  # local RELEASE_AUTH="caching_sha2_password" 

  echo "Configuring mysql APT repository... (using $RELEASE_REPO)"
  if [ -f /usr/share/keyrings/mysql.gpg ]; then
    rm /usr/share/keyrings/mysql.gpg
  fi

  # Add MySQL APT repository (non-interactive)
  wget https://dev.mysql.com/get/mysql-apt-config_0.8.34-1_all.deb
  sudo DEBIAN_FRONTEND=noninteractive \
    dpkg -i mysql-apt-config_0.8.34-1_all.deb <<EOF
1
EOF

  echo "✓ mysql repository configured."

  # Update package info
  apt-get -qq update

  # Preseed MySQL root password and install MySQL Server non-interactively
  debconf-set-selections <<< "mysql-community-server mysql-community-server/root-pass password $MYSQL_PASSWORD"
  debconf-set-selections <<< "mysql-community-server mysql-community-server/re-root-pass password $MYSQL_PASSWORD"
  debconf-set-selections <<< "mysql-apt-config mysql-apt-config/select-server select $RELEASE_REPO" 
  DEBIAN_FRONTEND=noninteractive apt-get -qq install -y mysql-community-server

  echo "✓ mysql installed."
  echo "Configuring mysql server..."
  
  # Start and enable MySQL
  systemctl enable mysql
  systemctl start mysql
  
  # create the ~/my.cnf file with the mysql credentials
  cat <<EOF >"/root/.my.cnf"
[mysql]
user=root
password=$MYSQL_PASSWORD
host=127.0.0.1

[mysqldump]
user=root
password=$MYSQL_PASSWORD
host=127.0.0.1
EOF

  echo "✓ mysql server configured."

  # clean up previous mysql files
  rm mysql-apt-config_0.8.34-1_all.deb

  systemctl enable -q --now mysql
}

# Function to install and configure NGINX
install_nginx() {
  sudo apt-get install nginx -y
  mkdir -p /etc/nginx/includes/

  echo "✓ nginx installed."

  wget -O /etc/nginx/includes/gzip.conf \
    https://raw.githubusercontent.com/Third-Culture-Software/bhima-scripts/refs/heads/main/install/nginx/gzip.conf

  wget -O /etc/nginx/sites-available/bhima \
    https://raw.githubusercontent.com/Third-Culture-Software/bhima-scripts/refs/heads/main/install/nginx/bhima.site

  sed -i "s/BHIMA_HOST/$BHIMA_HOST/g" /etc/nginx/sites-available/bhima
  sed -i "s/BHIMA_PORT/$BHIMA_PORT/g" /etc/nginx/sites-available/bhima

  ln -s /etc/nginx/sites-available/bhima /etc/nginx/sites-enabled/bhima

  # Remove default site if it exists
  if [ -f /etc/nginx/sites-enabled/default ]; then
    rm /etc/nginx/sites-enabled/default
  fi

  # Create symlink if it doesn't exist already
  if [ ! -f /etc/nginx/sites-enabled/bhima ]; then
    ln -s /etc/nginx/sites-available/bhima /etc/nginx/sites-enabled/bhima
  fi

  echo "✓ nginx configured."
  sudo systemctl enable nginx
  sudo systemctl start nginx
}

# Function to install and configure syncthing (optional)
install_syncthing() {
  echo "Installing Syncthing..."

  sudo mkdir -p /etc/apt/keyrings
  sudo curl -L -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
  echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | sudo tee /etc/apt/sources.list.d/syncthing.list
  sudo apt-get -qq update && sudo apt-get -qq  install -y syncthing

  echo "✓ syncthing installed."

  systemctl --user enable syncthing.service
  systemctl --user start syncthing.service

  # wait for syncthing to generate config files
  sleep 3

  sed -i 's/127.0.0.1/0.0.0.0/g' "$HOME/.config/syncthing/config.xml"

  echo "✓ syncthing configured."
}

# Function to install and configure BHIMA
install_bhima() {
  local REPO="Third-Culture-Software/bhima"
  local LATEST_RELEASE
  local DOWNLOAD_URL

  echo "Installing BHIMA..."

  mkdir -p "$BHIMA_INSTALL_DIR"

  echo "Fetching the latest release information..."

  LATEST_RELEASE=$(curl -s https://api.github.com/repos/$REPO/releases/latest)
  DOWNLOAD_URL=$(echo "$LATEST_RELEASE" | grep -o 'https://.*\.tar\.gz')

  if [ -z "$DOWNLOAD_URL" ]; then
    echo "Error: Could not find a .tar.gz release asset"
    exit 1
  fi

  echo "Downloading latest release..."
  wget -O "$BHIMA_INSTALL_DIR/bhima-latest.tar.gz" "$DOWNLOAD_URL"

  echo "Extracting release..."
  tar -xzf "$BHIMA_INSTALL_DIR/bhima-latest.tar.gz" -C "$BHIMA_INSTALL_DIR"
  rm "$BHIMA_INSTALL_DIR/bhima-latest.tar.gz"
  echo "✓ download and extraction complete."

  local RELEASE_DIR
  RELEASE_DIR="$BHIMA_INSTALL_DIR/bhima-$BHIMA_VERSION"
  echo "BHIMA installed to $RELEASE_DIR."

  # make a symbolic link to the bin directory
  ln -s "$RELEASE_DIR/" "$BHIMA_INSTALL_DIR/bhima"

  # jump into installed directory
  mkdir -p "$BHIMA_INSTALL_DIR"
  cd "$BHIMA_INSTALL_DIR/bhima"

  cp ./bin/* .

  sed -i '/DB_NAME/d' .env
  sed -i '/DB_PASS/d' .env
  sed -i '/DB_USER/d' .env
  sed -i '/PORT/d' .env
  sed -i '/SESS_SECRET/d' .env

  # write to .env file
  {
    echo "DB_NAME=bhima" &
    echo "DB_PASS=$MYSQL_PASSWORD" &
    echo "DB_USER=root" &

    echo "NODE_ENV=production" &

    echo "PORT=$BHIMA_PORT" &
    echo "SESS_SECRET=$(openssl rand -hex 65)" &
  } >>.env

  echo "✓ updated .env file."

  NODE_ENV=production npm ci

  echo "✓ installing npm dependencies."

  echo "Setting bhima to automatically startup..."
  wget -O /etc/systemd/system/bhima.service \
    https://raw.githubusercontent.com/Third-Culture-Software/bhima-scripts/refs/heads/main/install/systemd/bhima.service

  sed -i "s/BHIMA_INSTALL_DIR/$BHIMA_INSTALL_DIR/g" /etc/systemd/system/bhima.service

  # now we need to set up the BHIMA database
  systemctl daemon-reload
  systemctl start bhima
  systemctl enable bhima

  echo "✓ BHIMA installed and configured."
}

# Function to install and configure Tailscale
install_tailscale() {
  if [ -z "${TS_AUTH_KEY}" ]; then
    echo "TS_AUTH_KEY is not set. Exiting..."
    exit 1
  fi

  echo "Installing Tailscale!"
  curl -fsSL https://tailscale.com/install.sh | sh
  sudo tailscale up --auth-key="$TS_AUTH_KEY"
  echo "Tailscale installed."
}

# Function to harden the server against attacks
harden_server() {
  echo "Hardening server security..."

  sudo apt-get install -y unattended-upgrade fail2ban

  # Configure unattended-upgrades
  cat >/etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
}

# Function to perform final checks
function perform_final_checks() {
  echo "Performing final checks..."

  # Check if BHIMA service is running
  if systemctl is-active --quiet bhima; then
    echo "✓ BHIMA service is running"
  else
    echo "✗ BHIMA service is not running"
    systemctl status bhima --no-pager
  fi

  # Check if NGINX is running
  if systemctl is-active --quiet nginx; then
    echo "✓ NGINX service is running"
  else
    echo "✗ NGINX service is not running"
    systemctl status nginx --no-pager
  fi

  # Check if MySQL is running
  if systemctl is-active --quiet mysql; then
    echo "✓ MySQL service is running"
  else
    echo "✗ MySQL service is not running"
    systemctl status mysql --no-pager
  fi

  # Print installation summary
  echo ""
  echo "Installation Summary:"
  echo "====================="
  echo "BHIMA installed at: $BHIMA_INSTALL_DIR"
  echo "BHIMA hostname: $BHIMA_HOST"
  echo "BHIMA port: $BHIMA_PORT"
  echo "MySQL password: $MYSQL_PASSWORD (saved in /root/.my.cnf)"
  echo ""
  echo "Access your BHIMA installation at: http://$BHIMA_HOST"
  echo ""
  echo "Important: Please write down the MySQL password and keep it in a secure location."
}

# Execute the functions
install_dependencies
install_mysql
install_nginx
install_bhima
#install_syncthing # only enable on production environments
#install_tailscale # only enable on production environments
harden_server
perform_final_checks

echo "BHIMA installation complete!"
