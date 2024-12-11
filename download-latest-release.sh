#!/bin/bash

# Set the GitHub repository details
REPO="Third-Culture-Software/bhima"

# Create the code directory if it doesn't exist
mkdir -p ~/code

# Fetch the latest release information from GitHub API
LATEST_RELEASE=$(curl -s https://api.github.com/repos/$REPO/releases/latest)

# Extract the download URL for the tar.gz asset
DOWNLOAD_URL=$(echo "$LATEST_RELEASE" | grep -o 'https://.*\.tar\.gz')

# Check if a download URL was found
if [ -z "$DOWNLOAD_URL" ]; then
  echo "Error: Could not find a .tar.gz release asset"
  exit 1
fi

# Download the latest release
echo "Downloading latest release..."
wget -O ~/code/bhima-latest.tar.gz "$DOWNLOAD_URL"

# Extract the downloaded file
echo "Extracting release..."
tar -xzf ~/code/bhima-latest.tar.gz -C ~/code

# Remove the downloaded archive after extraction
rm ~/code/bhima-latest.tar.gz

echo "Download and extraction complete!"
