#!/bin/bash

# =========================================================
#   VPN SHOP UNINSTALLER
# =========================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root (sudo su)${NC}"
  exit
fi

clear
echo -e "${RED}==============================================${NC}"
echo -e "${RED}   VPN SHOP REMOVAL TOOL                      ${NC}"
echo -e "${RED}==============================================${NC}"
echo -e ""
read -p "Are you sure you want to uninstall VPN Shop? (y/n): " confirm
if [[ $confirm != "y" && $confirm != "Y" ]]; then
    echo -e "${YELLOW}Uninstall cancelled.${NC}"
    exit
fi

echo -e "\n${YELLOW}[1/4] Stopping Bot Processes...${NC}"
if command -v pm2 &> /dev/null; then
    pm2 delete vpn-shop > /dev/null 2>&1
    pm2 save > /dev/null 2>&1
    echo -e "${GREEN}Bot process stopped.${NC}"
else
    echo -e "${YELLOW}PM2 not found or already removed.${NC}"
fi

echo -e "${YELLOW}[2/4] Removing System Files...${NC}"
# Remove Project Folder
if [ -d "/root/vpn-shop" ]; then
    rm -rf /root/vpn-shop
    echo -e "${GREEN}Removed /root/vpn-shop folder.${NC}"
fi

# Remove Web Panel
if [ -f "/var/www/html/index.html" ]; then
    rm /var/www/html/index.html
    echo -e "${GREEN}Removed Web Panel.${NC}"
    
    # Create a default placeholder
    echo "<h1>VPN Shop Uninstalled</h1>" > /var/www/html/index.html
fi

echo -e "${YELLOW}[3/4] Cleaning up Nginx...${NC}"
systemctl restart nginx

echo -e "${YELLOW}[4/4] Cleaning Cache...${NC}"
# Optional: Remove Node modules global if not needed (Skipped for safety)

echo -e "\n${GREEN}==============================================${NC}"
echo -e "${GREEN}   UNINSTALL COMPLETE!                        ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "Web Panel and Bot have been removed from this server."
echo -e "Note: Nginx and Node.js are kept installed."
