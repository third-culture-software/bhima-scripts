#!/usr/bin/env bash

# The BHIMA installation script.

# Global Variables
BHIMA_INSTALL_DIR="/opt/bhima"
BHIMA_VERSION="1.35.0"
BHIMA_HOST=""   # e.g. vanga.thirdculturesoftware.com
BHIMA_PORT=8080 # e.g.8080

MYSQL_ROOT_PASSWORD="$(openssl rand -hex 64)"

TS_AUTH_KEY=""

# Checks if the script is running with root privileges (sudo).
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (sudo)."
  exit 1
fi

echo "Welcome! This script will help install the BHIMA software."

cat header.txt

# Function to install dependencies
function install_dependencies() {
  echo "Updating BHIMA OS dependencies..."

  # Refresh the package lists, and download the OS libraries
  sudo apt-get update && sudo apt-get upgrade -y
  sudo apt-get install -y wget lsb-release ca-certificates curl gnupg software-properties-common apt-transport-https tar screen

  printf '\342\234\224 dependencies updated!\n'

  # Get the LTS NodeJS from NodeSource
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo bash -
  sudo apt-get install -y nodejs

  # Install the redis.io APT repository
  curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
  sudo chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
  sudo apt-get update
  sudo apt-get install -y redis

  printf '\342\234\224 installed redis!\n'
}

# Function to install and configure MySQL
function install_mysql() {
  wget -c https://dev.mysql.com/get/mysql-apt-config_0.8.33-1_all.deb

  sudo debconf-set-selections <<<"mysql-apt-config mysql-apt-config/select-server select mysql-8.4"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ./mysql-apt-config_0.8.24-1_all.deb

  sudo apt-get update -y

  sudo debconf-set-selections <<<"mysql-server mysql-server/root_password password $MYSQL_PASSWORD"
  sudo debconf-set-selections <<<"mysql-server mysql-server/root_password_again password $MYSQL_PASSWORD"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server

  # create the ~/my.cnf file with the mysql credentials
  cat <<EOF >"$HOME/.my.cnf"
[mysql]
user=root
password=$MYSQL_PASSWORD
host=127.0.0.1

[mysqldump]
user=root
password=$MYSQL_PASSWORD
host=127.0.0.1
EOF
}

# Function to install and configure NGINX
install_nginx() {
  sudo apt-get install nginx -y
  mkdir -p /etc/nginx/includes/

  wget -O /etc/nginx/includes/gzip.conf \
    https://raw.githubusercontent.com/Third-Culture-Software/bhima-scripts/refs/heads/main/install/nginx/gzip.conf

  wget -O /etc/nginx/sites-available/bhima \
    https://raw.githubusercontent.com/Third-Culture-Software/bhima-scripts/refs/heads/main/install/nginx/bhima.site

  sed -i "s/BHIMA_HOST/$BHIMA_HOST/g" /etc/nginx/sites-available/bhima
  sed -i "s/BHIMA_PORT/$BHIMA_PORT/g" /etc/nginx/sites-available/bhima

  ln -s /etc/nginx/sites-available/bhima /etc/nginx/sites-enabled/bhima

  sudo systemctl enable nginx
  sudo systemctl start nginx
}

# Function to install and configure syncthing (optional)
install_syncthing() {
  sudo mkdir -p /etc/apt/keyrings
  sudo curl -L -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
  echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | sudo tee /etc/apt/sources.list.d/syncthing.list
  sudo apt-get update && sudo apt-get install -y syncthing

  sed -i 's/127.0.0.1/0.0.0.0/g' "$HOME/.config/syncthing/config.xml"

  systemctl --user enable syncthing.service
  systemctl --user start syncthing.service
}

# Function to install and configure BHIMA
install_bhima() {
  local REPO="Third-Culture-Software/bhima"

  mkdir -p "$BHIMA_INSTALL_DIR"

  local LATEST_RELEASE=$(curl -s https://api.github.com/repos/$REPO/releases/latest)

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
  echo "Download and extraction complete!"

  cd "$BHIMA_INSTALL_DIR/"

  cp ./bin/* .

  sed -i "s/DB_NAME/$BHIMA_INSTALL_DIR/g" .env
  sed '/DB_NAME/d' .env
  sed '/SESS_SECRET/d' .env
  sed '/DB_PASS/d' .env
  sed '/PORT/d' .env

  echo "DB_NAME=bhima" >>.env
  echo "PORT=$BHIMA_PORT" >>.env
  echo "DB_PASS=$MYSQL_ROOT_PASSWORD" >>.env
  echo "SESS_SECRET=$(openssl rand -hex 64)" >>.env

  npm ci

  wget -O /etc/systemd/system/bhima.service \
    https://raw.githubusercontent.com/Third-Culture-Software/bhima-scripts/refs/heads/main/install/systemd/bhima.service

  sed -i "s/BHIMA_INSTALL_DIR/$BHIMA_INSTALL_DIR/g" /etc/systemd/system/bhima.service

  systemctl daemon-reload
  systemctl start bhima
  systemctl enable bhima
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
  sudo apt-get install -y unattended-upgrade fail2ban
}

# Execute the functions
install_dependencies
install_mysql
install_nginx
install_syncthing
install_bhima
install_tailscale
harden_server

echo "BHIMA installation complete!"
