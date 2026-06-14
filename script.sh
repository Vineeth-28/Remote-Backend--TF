#!/bin/bash

# Exit instantly if any structural installation commands fail
set -e

echo "================================================="
echo "⚙️ Starting Persistent Terraform Installer for AWS CloudShell"
echo "================================================="

# 1. Fetch latest version safely without crashing on API hiccups
echo "🔍 Fetching the latest stable Terraform version..."
LATEST_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform 2>/dev/null | jq -r '.current_version' 2>/dev/null || echo "fallback")

# Validate output or use hardcoded latest stable release fallback
if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" == "null" ] || [ "$LATEST_VERSION" == "fallback" ]; then
    echo "⚠️ Checkpoint API throttled or unavailable. Using stable release safety target..."
    LATEST_VERSION="1.10.5"
fi

echo "🚀 Target installation version: v${LATEST_VERSION}"

# 2. Setup the persistent path directory
echo "📁 Creating persistent binary folder ~/bin if needed..."
mkdir -p ~/bin

# 3. Download the AMD64 stable package ZIP file
ZIP_FILE="terraform_${LATEST_VERSION}_linux_amd64.zip"
DOWNLOAD_URL="https://releases.hashicorp.com/terraform/${LATEST_VERSION}/${ZIP_FILE}"

echo "📥 Downloading from: ${DOWNLOAD_URL}"
curl -sSL -O "$DOWNLOAD_URL"

# 4. Extract and safely move the binary executable
echo "📦 Extracting package contents..."
unzip -o "$ZIP_FILE"

echo "🚚 Deploying binary into persistent user space..."
mv terraform ~/bin/

# 5. Erase the downloaded archive cache
echo "🧹 Cleaning up remaining installation files..."
rm -f "$ZIP_FILE"

# 6. Ensure CloudShell path integration is active
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo "🔗 Exporting user workspace pathway into shell configurations..."
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/bin:$PATH"
fi

echo "================================================="
echo "✅ Installation successfully executed!"
echo "================================================="
echo "Installed Details:"
~/bin/terraform -v
echo "================================================="
echo "💡 IMPORTANT: Please execute: 'source ~/.bashrc' to activate the command line entry!"
