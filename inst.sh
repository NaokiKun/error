#!/bin/bash

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Outline VPN Panel Installer (Fixed CORS/SSL/Auto-Restart) ===${NC}"

# 1. Check Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit
fi

# 2. Update System & Install Dependencies
echo -e "${YELLOW}Updating System...${NC}"
apt update && apt upgrade -y
apt install -y curl wget gnupg2 ca-certificates lsb-release nginx git

# 3. Install Node.js 18
echo -e "${YELLOW}Installing Node.js...${NC}"
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# 4. Setup Directory Structure
echo -e "${YELLOW}Setting up directories...${NC}"
mkdir -p /root/outline-bot
rm -rf /var/www/html/*

# 5. Create backend files (bot.js) - FIXED VERSION
echo -e "${YELLOW}Creating Backend Files (With CORS Proxy Fix)...${NC}"
cat << 'EOF' > /root/outline-bot/bot.js
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const TelegramBot = require('node-telegram-bot-api');
const axios = require('axios');
const https = require('https');
const fs = require('fs');
const moment = require('moment-timezone');
const { exec } = require('child_process');

const app = express();
app.use(cors());
app.use(bodyParser.json({ limit: '10mb' }));

const CONFIG_FILE = 'config.json';
const CLAIM_FILE = 'claimed_users.json';
const BLOCKED_FILE = 'blocked_registry.json';
const RESELLER_FILE = 'resellers.json';

let config = {};
let bot = null;
let claimedUsers = [];
let blockedRegistry = {}; 
let userStates = {};
let resellers = [];
let resellerSessions = {}; 

// --- CRITICAL FIX: SSL AGENT ---
// This allows the backend to talk to Outline API even with self-signed certs
const agent = new https.Agent({ rejectUnauthorized: false });
const axiosClient = axios.create({ 
    httpsAgent: agent, 
    timeout: 15000, 
    headers: { 'Content-Type': 'application/json' } 
});

// --- ANTI-CRASH HANDLERS ---
process.on('uncaughtException', (err) => {
    console.error('CRITICAL ERROR (Prevents Crash):', err);
});
process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection:', reason);
});

function loadConfig() {
    try { if(fs.existsSync(CONFIG_FILE)) config = JSON.parse(fs.readFileSync(CONFIG_FILE)); } catch (e) {}
    try { if(fs.existsSync(CLAIM_FILE)) claimedUsers = JSON.parse(fs.readFileSync(CLAIM_FILE)); } catch(e) {}
    try { if(fs.existsSync(BLOCKED_FILE)) blockedRegistry = JSON.parse(fs.readFileSync(BLOCKED_FILE)); } catch(e) {}
    try { if(fs.existsSync(RESELLER_FILE)) resellers = JSON.parse(fs.readFileSync(RESELLER_FILE)); } catch(e) {}
}
loadConfig();

// --- PROXY ROUTE (Fixes CORS & SSL for Frontend) ---
app.post('/api/proxy', async (req, res) => {
    const { url, method = 'GET', data = {} } = req.body;
    
    if (!url) return res.status(400).json({ error: "URL required" });

    try {
        // console.log(`[PROXY] ${method} -> ${url}`);
        const response = await axiosClient({
            method: method,
            url: url,
            data: data
        });
        res.json(response.data || {});
    } catch (error) {
        console.error(`[PROXY ERROR] ${error.message}`);
        res.status(500).json({ error: error.message, details: error.response?.data });
    }
});

// --- SERVER HELPER FUNCTIONS ---
function getServers() {
    if (!config.api_urls) return [];
    return config.api_urls.map(s => {
        if (typeof s === 'string') return { name: "Server", url: s };
        return s;
    });
}

function getServerKeyboard(callbackPrefix) {
    const servers = getServers();
    let keyboard = [];
    let row = [];
    servers.forEach((srv, index) => {
        let sName = srv.name || `Server ${index + 1}`;
        row.push({ text: `🖥️ ${sName}`, callback_data: `${callbackPrefix}_${index}` });
        if (row.length === 2) {
            keyboard.push(row);
            row = [];
        }
    });
    if (row.length > 0) keyboard.push(row);
    return keyboard;
}

async function findKeyInAllServers(keyIdOrName, isName = false) {
    const servers = getServers();
    for (const srv of servers) {
        try {
            const serverUrl = srv.url;
            const [kRes, mRes] = await Promise.all([
                axiosClient.get(`${serverUrl}/access-keys`),
                axiosClient.get(`${serverUrl}/metrics/transfer`)
            ]);
            let key;
            if (isName) {
                // Loose match for name
                key = kRes.data.accessKeys.find(k => k.name.toLowerCase().includes(keyIdOrName.toLowerCase()));
            } else {
                key = kRes.data.accessKeys.find(k => String(k.id) === String(keyIdOrName));
            }
            if (key) {
                return { key, metrics: mRes.data, serverUrl, serverName: srv.name };
            }
        } catch (e) { console.error(`Error checking server ${srv.url}:`, e.message); }
    }
    return null;
}

async function getAllKeysFromAllServers(filter = null) {
    const servers = getServers();
    let allKeys = [];
    for (const srv of servers) {
        try {
            const res = await axiosClient.get(`${srv.url}/access-keys`);
            let keys = res.data.accessKeys;
            if(filter) keys = keys.filter(filter);
            keys = keys.map(k => ({ ...k, _serverUrl: srv.url, _serverName: srv.name }));
            allKeys = allKeys.concat(keys);
        } catch (e) {}
    }
    return allKeys;
}

async function createKeyOnServer(serverIndex, name, limitBytes) {
    const servers = getServers();
    if (!servers[serverIndex]) throw new Error("Invalid Server Index");
    const targetServer = servers[serverIndex];
    const res = await axiosClient.post(`${targetServer.url}/access-keys`);
    await axiosClient.put(`${targetServer.url}/access-keys/${res.data.id}/name`, { name: name });
    if(limitBytes > 0) {
        await axiosClient.put(`${targetServer.url}/access-keys/${res.data.id}/data-limit`, { limit: { bytes: limitBytes } });
    }
    return { ...res.data, _serverUrl: targetServer.url, _serverName: targetServer.name };
}

// --- API ROUTES ---
app.get('/api/config', (req, res) => { loadConfig(); res.json({ ...config, resellers }); });

app.post('/api/update-config', (req, res) => {
    try {
        const { resellers: newResellers, ...newConfig } = req.body;
        config = { ...config, ...newConfig };
        fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 4));
        if(newResellers) { resellers = newResellers; fs.writeFileSync(RESELLER_FILE, JSON.stringify(resellers, null, 4)); }
        res.json({ success: true, config: config });
        // Restart bot to apply changes
        setTimeout(() => { loadConfig(); startBot(); }, 1000);
    } catch (error) { res.status(500).json({ success: false }); }
});

app.post('/api/change-port', (req, res) => {
    const newPort = req.body.port;
    if(!newPort || isNaN(newPort)) return res.status(400).json({error: "Invalid Port"});
    const nginxConfig = `server { listen ${newPort}; server_name _; root /var/www/html; index index.html; location / { try_files $uri $uri/ =404; } }`;
    try { 
        fs.writeFileSync('/etc/nginx/sites-available/default', nginxConfig); 
        config.panel_port = parseInt(newPort); 
        fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 4)); 
        exec('systemctl reload nginx', (error) => { 
            if (error) { return res.status(500).json({error: "Failed to reload Nginx"}); } 
            res.json({ success: true, message: `Port changed to ${newPort}` }); 
        }); 
    } catch (err) { res.status(500).json({ error: "Failed to write config" }); }
});

app.listen(3000, () => console.log('✅ Sync Server running on Port 3000'));

// Initialize Bot if token exists
if (config.bot_token) startBot();

function startBot() {
    if(bot) { try { bot.stopPolling(); } catch(e){} }
    if(!config.bot_token) return;

    console.log("🚀 Starting Bot...");
    bot = new TelegramBot(config.bot_token, { polling: true });
    
    const ADMIN_IDS = config.admin_id ? config.admin_id.split(',').map(id => id.trim()) : [];
    const WELCOME_MSG = config.welcome_msg || "👋 Welcome to VPN Shop!\nမင်္ဂလာပါ VPN Shop မှ ကြိုဆိုပါတယ်။";
    const TRIAL_ENABLED = config.trial_enabled !== false;
    
    // Default Buttons
    const BTN = {
        trial: "🆓 Free Trial (အစမ်းသုံးရန်)",
        buy: "🛒 Buy Key (ဝယ်ယူရန်)",
        mykey: "🔑 My Key (မိမိ Key ရယူရန်)",
        info: "👤 Account Info (အကောင့်စစ်ရန်)",
        support: "🆘 Support (ဆက်သွယ်ရန်)",
        reseller: "🤝 Reseller Login",
        resell_buy: "🛒 Buy Stock",
        resell_create: "📦 Create User Key",
        resell_users: "👥 My Users",
        resell_extend: "⏳ Extend User",
        resell_logout: "🔙 Logout Reseller"
    };

    function formatAccessUrl(url, serverUrl) {
        if (!url) return url;
        try {
            const urlObj = new URL(url);
            const originalIp = urlObj.hostname;
            // Check domain map
            if (config.domain_map && config.domain_map.length > 0) {
                const mapping = config.domain_map.find(m => m.ip === originalIp);
                if (mapping && mapping.domain) return url.replace(originalIp, mapping.domain);
            }
            // Fallback global domain
            if (config.domain) return url.replace(originalIp, config.domain);
            return url;
        } catch (e) { return url; }
    }
    
    function isAdmin(chatId) { return ADMIN_IDS.includes(String(chatId)); }
    function formatBytes(bytes) { if (!bytes || bytes === 0) return '0 B'; const i = Math.floor(Math.log(bytes) / Math.log(1024)); return (bytes / Math.pow(1024, i)).toFixed(2) + ' ' + ['B', 'KB', 'MB', 'GB', 'TB'][i]; }
    function getMyanmarDate(offsetDays = 0) { return moment().tz("Asia/Yangon").add(offsetDays, 'days').format('YYYY-MM-DD'); }
    function isExpired(dateString) { if (!/^\d{4}-\d{2}-\d{2}$/.test(dateString)) return false; const today = moment().tz("Asia/Yangon").startOf('day'); const expire = moment.tz(dateString, "YYYY-MM-DD", "Asia/Yangon").startOf('day'); return expire.isBefore(today); }
    
    function getMainMenu(userId) {
        let kb = []; let row1 = [];
        if (TRIAL_ENABLED) row1.push({ text: BTN.trial });
        row1.push({ text: BTN.buy }); kb.push(row1);
        kb.push([{ text: BTN.mykey }, { text: BTN.info }]); 
        kb.push([{ text: BTN.reseller }, { text: BTN.support }]);
        if (isAdmin(userId)) kb.unshift([{ text: "👮‍♂️ Admin Panel" }]);
        return kb;
    }

    function getResellerMenu(username, balance) {
        return [
            [{ text: `${BTN.resell_buy} (${balance} Ks)` }],
            [{ text: BTN.resell_create }, { text: BTN.resell_extend }],
            [{ text: BTN.resell_users }, { text: BTN.resell_logout }]
        ];
    }

    // --- COMMAND LISTENERS ---

    bot.onText(/\/start/, (msg) => { 
        const userId = msg.chat.id; 
        delete userStates[userId];
        delete resellerSessions[userId];
        bot.sendMessage(userId, WELCOME_MSG, { reply_markup: { keyboard: getMainMenu(userId), resize_keyboard: true } }); 
    });

    bot.onText(/\/id/, (msg) => {
        bot.sendMessage(msg.chat.id, `🆔 Your ID: \`${msg.chat.id}\``, { parse_mode: 'Markdown' });
    });

    // --- MESSAGE HANDLER ---
    bot.on('message', async (msg) => {
        const chatId = msg.chat.id;
        const text = msg.text;
        
        if (!text) return; 

        // 1. STATE HANDLING (Reseller Login, Key Creation, etc.)
        if (userStates[chatId]) {
            const state = userStates[chatId];
            
            // Login: Username
            if (state.status === 'RESELLER_LOGIN_USER') {
                userStates[chatId].username = text.trim();
                userStates[chatId].status = 'RESELLER_LOGIN_PASS';
                return bot.sendMessage(chatId, "🔑 Enter **Password**:", { parse_mode: 'Markdown' });
            }
            
            // Login: Password
            if (state.status === 'RESELLER_LOGIN_PASS') {
                const username = userStates[chatId].username;
                const password = text.trim();
                const reseller = resellers.find(r => r.username === username && r.password === password);
                if(reseller) {
                    resellerSessions[chatId] = reseller.username;
                    delete userStates[chatId];
                    bot.sendMessage(chatId, `✅ **Login Success!**\n👤 Owner: ${reseller.username}\n💰 Balance: ${reseller.balance} Ks`, { parse_mode: 'Markdown', reply_markup: { keyboard: getResellerMenu(reseller.username, reseller.balance), resize_keyboard: true } });
                } else {
                    delete userStates[chatId];
                    bot.sendMessage(chatId, "❌ **Login Failed!**", { reply_markup: { keyboard: getMainMenu(chatId), resize_keyboard: true } });
                }
                return;
            }
            
            // Create Key: Name
            if (state.status === 'RESELLER_ENTER_NAME') {
                 const { plan, reseller: rUsername, serverIndex } = userStates[chatId];
                 const customerName = text.trim().replace(/\|/g, ''); // Remove pipes
                 
                 bot.sendMessage(chatId, "⏳ Generating Key...");
                 try {
                    const rIndex = resellers.findIndex(r => r.username === rUsername);
                    if(rIndex === -1 || resellers[rIndex].balance < plan.price) {
                         bot.sendMessage(chatId, "❌ Insufficient Balance or Error.", { reply_markup: { keyboard: getResellerMenu(rUsername, resellers[rIndex] ? resellers[rIndex].balance : 0), resize_keyboard: true } });
                    } else {
                        // Deduct Balance
                        resellers[rIndex].balance -= parseInt(plan.price);
                        fs.writeFileSync(RESELLER_FILE, JSON.stringify(resellers, null, 4));
                        
                        const expireDate = getMyanmarDate(plan.days);
                        const limitBytes = Math.floor(plan.gb * 1024 * 1024 * 1024);
                        const finalName = `${customerName} (R-${rUsername}) | ${expireDate}`;
                        
                        const data = await createKeyOnServer(serverIndex, finalName, limitBytes);
                        
                        let finalUrl = formatAccessUrl(data.accessUrl, data._serverUrl); 
                        finalUrl += `#${encodeURIComponent(customerName)}`;
                        
                        bot.sendMessage(chatId, `✅ **Key Created!**\n\n👤 Customer: ${customerName}\n🖥️ Server: ${data._serverName}\n💰 Cost: ${plan.price} Ks\n💰 Remaining: ${resellers[rIndex].balance} Ks\n\n🔗 **Key:**\n<code>${finalUrl}</code>`, { 
                            parse_mode: 'HTML',
                            reply_markup: { keyboard: getResellerMenu(rUsername, resellers[rIndex].balance), resize_keyboard: true }
                        });
                    }
                 } catch(e) { 
                     bot.sendMessage(chatId, "❌ Error connecting to servers.", { reply_markup: { keyboard: getResellerMenu(rUsername, resellers.find(r=>r.username===rUsername).balance), resize_keyboard: true } }); 
                 }
                 
                 delete userStates[chatId];
                 return;
            }

            // Admin Topup
            if (state.status === 'ADMIN_TOPUP_AMOUNT') {
                if(!isAdmin(chatId)) return;
                const amount = parseInt(text.trim());
                if(isNaN(amount)) return bot.sendMessage(chatId, "❌ Invalid Amount. Enter number only.");
                
                const targetReseller = state.targetReseller;
                const rIndex = resellers.findIndex(r => r.username === targetReseller);
                
                if(rIndex !== -1) {
                    resellers[rIndex].balance = parseInt(resellers[rIndex].balance) + amount;
                    fs.writeFileSync(RESELLER_FILE, JSON.stringify(resellers, null, 4));
                    bot.sendMessage(chatId, `✅ **Topup Success!**\n👤 Reseller: ${targetReseller}\n💰 Added: ${amount} Ks\n💰 New Balance: ${resellers[rIndex].balance} Ks`, { 
                        parse_mode: 'Markdown',
                        reply_markup: { keyboard: getMainMenu(chatId), resize_keyboard: true }
                    });
                } else {
                    bot.sendMessage(chatId, "❌ Reseller not found.", { reply_markup: { keyboard: getMainMenu(chatId), resize_keyboard: true } });
                }
                delete userStates[chatId];
                return;
            }

            return; 
        }

        // 2. MAIN MENU HANDLERS
        
        // --- Admin Panel ---
        if (text === "👮‍♂️ Admin Panel" && isAdmin(chatId)) {
            bot.sendMessage(chatId, "👮‍♂️ **Admin Controls**", {
                parse_mode: 'Markdown',
                reply_markup: {
                    inline_keyboard: [
                        [{ text: "📊 Stats", callback_data: "admin_db" }, { text: "💰 Topup Reseller", callback_data: "admin_topup" }]
                    ]
                }
            });
            return;
        }

        // --- Support ---
        if (text === BTN.support) {
            bot.sendMessage(chatId, `🆘 **Support**\n\nContact Admin: ${config.admin_username || 'Not set'}`);
            return;
        }

        // --- Free Trial ---
        if (text === BTN.trial) {
            if(claimedUsers.includes(chatId)) return bot.sendMessage(chatId, "❌ You already claimed a free trial!");
            
            // Show servers to pick
            const servers = getServers();
            if(servers.length === 0) return bot.sendMessage(chatId, "⚠️ No servers available.");
            
            bot.sendMessage(chatId, "🖥️ Select Server for Trial:", {
                reply_markup: { inline_keyboard: getServerKeyboard('trial_srv') }
            });
            return;
        }

        // --- Buy Key ---
        if (text === BTN.buy) {
            bot.sendMessage(chatId, "🛒 **Payment Methods:**\n\n" + (config.payment_methods || "KPay: 09123456789\nWave: 09123456789") + "\n\nSend screenshot to Admin.");
            return;
        }

        // --- My Key ---
        if (text === BTN.mykey) {
            const userFullName = `${msg.from.first_name}`.trim(); 
            bot.sendMessage(chatId, "🔎 Searching all servers..."); 
            try { 
                const result = await findKeyInAllServers(userFullName, true);
                if (!result) return bot.sendMessage(chatId, "❌ **Key Not Found!**\nTry contacting admin if you purchased one."); 
                
                const { key, serverUrl, serverName } = result;
                let cleanName = key.name.split('|')[0].trim();
                let finalUrl = formatAccessUrl(key.accessUrl, serverUrl);
                finalUrl += `#${encodeURIComponent(cleanName)}`;
                
                bot.sendMessage(chatId, `🔑 <b>My Key (${serverName}):</b>\n<code>${finalUrl}</code>`, { parse_mode: 'HTML' }); 
            } catch (e) { bot.sendMessage(chatId, "⚠️ Server Error"); }
            return;
        }

        // --- Reseller: Login ---
        if (text === BTN.reseller) {
            if(resellerSessions[chatId]) {
                 // Already logged in
                 const r = resellers.find(x => x.username === resellerSessions[chatId]);
                 bot.sendMessage(chatId, `👤 Logged in as: ${r.username}`, { reply_markup: { keyboard: getResellerMenu(r.username, r.balance), resize_keyboard: true }});
            } else {
                userStates[chatId] = { status: 'RESELLER_LOGIN_USER' };
                bot.sendMessage(chatId, "👤 Enter **Reseller Username**:", { parse_mode: 'Markdown', reply_markup: { remove_keyboard: true } });
            }
            return;
        }

        // --- Reseller Actions ---
        const loggedInReseller = resellerSessions[chatId];
        if (loggedInReseller) {
            if (text === BTN.resell_logout) {
                delete resellerSessions[chatId];
                bot.sendMessage(chatId, "👋 Logged Out", { reply_markup: { keyboard: getMainMenu(chatId), resize_keyboard: true } });
                return;
            }
            
            if (text === BTN.resell_create) {
                const servers = getServers();
                if(servers.length === 0) return bot.sendMessage(chatId, "No servers configured.");
                bot.sendMessage(chatId, "🖥️ Select Server:", { reply_markup: { inline_keyboard: getServerKeyboard('r_create_srv') } });
                return;
            }

            if (text === BTN.resell_users) {
                bot.sendMessage(chatId, "🔎 Fetching your users...");
                try {
                    const keys = await getAllKeysFromAllServers(k => k.name.includes(`(R-${loggedInReseller})`));
                    if(keys.length === 0) return bot.sendMessage(chatId, "No users found.");
                    
                    let msg = `👥 **Your Users (${keys.length})**\n\n`;
                    keys.forEach(k => {
                        const nameParts = k.name.split('|');
                        const simpleName = nameParts[0].replace(`(R-${loggedInReseller})`, '').trim();
                        const expire = nameParts.length > 1 ? nameParts[nameParts.length-1].trim() : 'N/A';
                        msg += `▪️ ${simpleName} (${expire})\n`;
                    });
                    
                    // Split message if too long
                    if(msg.length > 4000) msg = msg.substring(0, 4000) + "...";
                    bot.sendMessage(chatId, msg, { parse_mode: 'Markdown' });
                } catch(e) { bot.sendMessage(chatId, "Error fetching data."); }
                return;
            }
        }
    });

    // --- CALLBACK QUERIES ---
    bot.on('callback_query', async (q) => {
         const chatId = q.message.chat.id; 
         const data = q.data;
         
         // 1. Admin DB Stats
         if (data === 'admin_db' && isAdmin(chatId)) {
                bot.answerCallbackQuery(q.id, { text: "Calculating..." });
                const servers = getServers();
                let totalKeys = 0;
                let totalBytes = 0;
                try {
                    const promises = servers.map(async (srv) => {
                        try {
                            const [kRes, mRes] = await Promise.all([
                                axiosClient.get(`${srv.url}/access-keys`),
                                axiosClient.get(`${srv.url}/metrics/transfer`)
                            ]);
                            return { keys: kRes.data.accessKeys.length, metrics: mRes.data.bytesTransferredByUserId };
                        } catch(e) { return { keys: 0, metrics: {} }; }
                    });
                    const results = await Promise.all(promises);
                    results.forEach(res => {
                        totalKeys += res.keys;
                        Object.values(res.metrics).forEach(bytes => totalBytes += bytes);
                    });
                    bot.sendMessage(chatId, `📊 **DATABASE STATISTICS**\n\n💾 **Total Servers:** ${servers.length}\n🔑 **Total Keys:** ${totalKeys}\n📡 **Total Traffic:** ${formatBytes(totalBytes)}`, { parse_mode: 'Markdown' });
                } catch(e) { bot.sendMessage(chatId, "❌ Error fetching stats."); }
         }

         // 2. Admin Topup
         if (data === 'admin_topup' && isAdmin(chatId)) {
             const rList = resellers.map(r => [{ text: `${r.username} (${r.balance})`, callback_data: `admin_topup_${r.username}` }]);
             bot.sendMessage(chatId, "Select Reseller to Topup:", { reply_markup: { inline_keyboard: rList } });
         }
         
         if (data.startsWith('admin_topup_')) {
             const target = data.replace('admin_topup_', '');
             userStates[chatId] = { status: 'ADMIN_TOPUP_AMOUNT', targetReseller: target };
             bot.sendMessage(chatId, `💰 Enter amount to add for **${target}**:`, { parse_mode: 'Markdown' });
         }

         // 3. Trial Server Selection
         if (data.startsWith('trial_srv_')) {
             if(claimedUsers.includes(chatId)) return;
             const sIndex = parseInt(data.split('_')[2]);
             
             bot.answerCallbackQuery(q.id, { text: "Creating Trial..." });
             
             try {
                const days = config.trial_days || 1;
                const gb = config.trial_gb || 1;
                const limit = Math.floor(gb * 1024 * 1024 * 1024);
                const name = `TEST_${q.from.first_name}_${chatId} | ${getMyanmarDate(days)}`;
                
                const newKey = await createKeyOnServer(sIndex, name, limit);
                
                claimedUsers.push(chatId);
                fs.writeFileSync(CLAIM_FILE, JSON.stringify(claimedUsers));
                
                let finalUrl = formatAccessUrl(newKey.accessUrl, newKey._serverUrl); 
                finalUrl += `#Outline_Trial`;
                
                bot.sendMessage(chatId, `✅ **Trial Created!**\n\n⏳ Valid: ${days} Days\n📦 Limit: ${gb} GB\n\n<code>${finalUrl}</code>`, { parse_mode: 'HTML' });
             } catch(e) {
                 bot.sendMessage(chatId, "❌ Failed to create key. Try again later.");
             }
         }

         // 4. Reseller Server Selection
         if (data.startsWith('r_create_srv_')) {
            const sIndex = parseInt(data.split('_')[3]);
            const rUser = resellerSessions[chatId];
            if(!rUser) return;
            
            // Load Plans from Config or Default
            const plans = config.reseller_plans || [
                { name: "1 Month (Unlimited)", days: 30, gb: 0, price: 1500 },
                { name: "1 Month (100GB)", days: 30, gb: 100, price: 1000 }
            ];
            
            const keyboard = plans.map((p, i) => [{ text: `${p.name} - ${p.price}Ks`, callback_data: `r_plan_${sIndex}_${i}` }]);
            bot.editMessageText("📅 Select Plan:", { chat_id: chatId, message_id: q.message.message_id, reply_markup: { inline_keyboard: keyboard } });
         }

         // 5. Reseller Plan Selection
         if (data.startsWith('r_plan_')) {
             const parts = data.split('_');
             const sIndex = parseInt(parts[2]);
             const pIndex = parseInt(parts[3]);
             const rUser = resellerSessions[chatId];
             
             const plans = config.reseller_plans || [
                { name: "1 Month (Unlimited)", days: 30, gb: 0, price: 1500 },
                { name: "1 Month (100GB)", days: 30, gb: 100, price: 1000 }
            ];
            const plan = plans[pIndex];
            
            userStates[chatId] = { status: 'RESELLER_ENTER_NAME', plan: plan, reseller: rUser, serverIndex: sIndex };
            bot.sendMessage(chatId, `📝 Enter **Customer Name**:`, { parse_mode: 'Markdown' });
         }
    });

    // --- AUTO GUARDIAN (Expiry & Limit Checker) ---
    async function runGuardian() { 
        try { 
            const keys = await getAllKeysFromAllServers();
            const today = moment().tz("Asia/Yangon").startOf('day');

            for (const key of keys) { 
                const serverUrl = key._serverUrl; 
                let usage = 0;
                try {
                    const mRes = await axiosClient.get(`${serverUrl}/metrics/transfer`);
                    usage = mRes.data.bytesTransferredByUserId[key.id] || 0; 
                } catch(e) {}

                const limit = key.dataLimit ? key.dataLimit.bytes : 0; 
                let expireDateStr = null; 
                
                // Extract date from name (Name | YYYY-MM-DD)
                if (key.name.includes('|')) expireDateStr = key.name.split('|').pop().trim(); 
                
                const isTrial = key.name.startsWith("TEST_"); 
                const expiredStatus = isExpired(expireDateStr); 
                
                // 1. If already blocked but limit is not 0 (User re-enabled manually), ignore
                if (key.name.startsWith("🔴") && limit !== 0) {
                     // Auto re-block if expire date is still past? 
                     // For now, let's assume manual intervention wins, unless we force block
                     if(expiredStatus) await axiosClient.put(`${serverUrl}/access-keys/${key.id}/data-limit`, { limit: { bytes: 0 } });
                     continue; 
                }
                
                // 2. If blocked and limit 0, skip
                if (key.name.startsWith("🔴") && limit === 0) continue; 

                // 3. Trial Logic
                if (isTrial && (expiredStatus || (limit > 0 && usage >= limit))) { 
                    await axiosClient.delete(`${serverUrl}/access-keys/${key.id}`); 
                    continue; 
                } 

                // 4. Normal User Logic
                if (!isTrial) {
                    // Expired?
                    if (expiredStatus) {
                        const expireMoment = moment.tz(expireDateStr, "YYYY-MM-DD", "Asia/Yangon").startOf('day');
                        const daysPast = today.diff(expireMoment, 'days');
                        
                        // Delete after 20 days
                        if (daysPast >= 20) {
                            await axiosClient.delete(`${serverUrl}/access-keys/${key.id}`);
                            continue;
                        } 
                        
                        // Just Block
                        if (!key.name.startsWith("🔴")) {
                            const newName = `🔴 [BLOCKED] ${key.name}`;
                            await axiosClient.put(`${serverUrl}/access-keys/${key.id}/name`, { name: newName });
                            await axiosClient.put(`${serverUrl}/access-keys/${key.id}/data-limit`, { limit: { bytes: 0 } });
                        }
                        continue;
                    }
                    
                    // Quota Exceeded? (Only if limit > 5MB to avoid accidental locks on small limits)
                    if (limit > 5000000 && usage >= limit) { 
                        if (!key.name.startsWith("🔴")) {
                            const newName = `🔴 [BLOCKED] ${key.name}`;
                            await axiosClient.put(`${serverUrl}/access-keys/${key.id}/name`, { name: newName });
                            await axiosClient.put(`${serverUrl}/access-keys/${key.id}/data-limit`, { limit: { bytes: 0 } });
                        }
                    } 
                }
            } 
        } catch (e) { console.log("Guardian Error", e.message); } 
    }
    
    // Run every 10 minutes
    setInterval(runGuardian, 1000 * 60 * 10); 
}
EOF

# 6. Create frontend files (index.html) - FIXED CORS/SSL via Proxy
echo -e "${YELLOW}Creating Frontend Files (Proxied Mode)...${NC}"
cat << 'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Outline Manager Pro</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://unpkg.com/lucide@latest"></script>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&display=swap');
        body { font-family: 'Inter', sans-serif; }
        .modal { transition: opacity 0.25s ease; }
        ::-webkit-scrollbar { width: 6px; height: 6px; }
        ::-webkit-scrollbar-track { background: #f1f5f9; }
        ::-webkit-scrollbar-thumb { background: #cbd5e1; border-radius: 3px; }
        .tab-btn.active { background-color: #4f46e5; color: white; box-shadow: 0 4px 6px -1px rgba(79, 70, 229, 0.2); }
        .tab-btn:not(.active) { color: #64748b; background-color: transparent; }
        .tab-btn:not(.active):hover { color: #334155; background-color: #f1f5f9; }
    </style>
</head>
<body class="bg-slate-100 min-h-screen text-slate-800">

    <nav class="bg-slate-900 text-white shadow-lg sticky top-0 z-40">
        <div class="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
            <div class="flex items-center space-x-3">
                <div class="bg-indigo-600 p-2 rounded-lg shadow-lg shadow-indigo-900/50">
                    <i data-lucide="shield-check" class="w-6 h-6 text-white"></i>
                </div>
                <div>
                    <h1 class="text-xl font-bold tracking-tight">Outline Manager</h1>
                    <p class="text-[10px] text-slate-400 uppercase tracking-widest font-semibold">Proxy Mode (Stable)</p>
                </div>
            </div>
            <div id="nav-status" class="hidden flex items-center space-x-3">
                <button onclick="openSettingsModal()" class="p-2 text-slate-300 hover:text-white hover:bg-slate-800 rounded-lg transition border border-slate-700" title="Settings">
                    <i data-lucide="settings" class="w-5 h-5"></i>
                </button>
                <button onclick="disconnect()" class="p-2 text-red-400 hover:text-red-300 hover:bg-red-900/30 rounded-lg transition border border-slate-700" title="Logout">
                    <i data-lucide="log-out" class="w-5 h-5"></i>
                </button>
            </div>
        </div>
    </nav>

    <main class="max-w-7xl mx-auto px-4 py-8">
        <div id="login-section" class="max-w-lg mx-auto mt-16">
            <div class="bg-white rounded-2xl shadow-xl p-8 border border-slate-200">
                <div class="text-center mb-8">
                    <div class="w-16 h-16 bg-slate-50 rounded-full flex items-center justify-center mx-auto mb-4 border border-slate-100">
                        <i data-lucide="server" class="w-8 h-8 text-indigo-600"></i>
                    </div>
                    <h2 class="text-2xl font-bold text-slate-800">Panel Login</h2>
                    <p class="text-slate-500 mt-2 text-sm">Enter ANY API URL (Connects via Proxy)</p>
                </div>
                <form onsubmit="connectServer(event)" class="space-y-4">
                    <div>
                        <label class="block text-xs font-bold text-slate-500 uppercase mb-1 ml-1">Any API URL</label>
                        <input type="password" id="login-api-url" class="w-full p-3 border border-slate-300 rounded-xl focus:ring-2 focus:ring-indigo-500 outline-none transition font-mono text-sm" placeholder="https://1.2.3.4:xxxxx/SecretKey..." required>
                    </div>
                    <button type="submit" id="connect-btn" class="w-full bg-indigo-600 hover:bg-indigo-700 text-white py-3.5 rounded-xl font-bold shadow-lg shadow-indigo-200 transition flex justify-center items-center">
                        Connect
                    </button>
                </form>
            </div>
        </div>

        <div id="dashboard" class="hidden space-y-8">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div class="bg-white p-5 rounded-2xl shadow-sm border border-slate-200">
                    <div class="flex items-center justify-between mb-2">
                        <div><p class="text-slate-500 text-xs font-bold uppercase tracking-wider">Total Keys</p><h3 class="text-3xl font-bold text-slate-800 mt-1" id="total-keys">0</h3></div>
                        <div class="p-3 bg-indigo-50 text-indigo-600 rounded-xl"><i data-lucide="users" class="w-6 h-6"></i></div>
                    </div>
                    <div id="server-breakdown" class="pt-3 border-t border-slate-100 space-y-1">
                        <div class="text-center text-xs text-slate-400">Loading Stats...</div>
                    </div>
                </div>
                
                <div class="bg-white p-6 rounded-2xl shadow-sm border border-slate-200 flex items-center justify-between">
                    <div><p class="text-slate-500 text-xs font-bold uppercase tracking-wider">Total Traffic</p><h3 class="text-3xl font-bold text-slate-800 mt-1" id="total-usage">0 GB</h3></div>
                    <div class="p-3 bg-emerald-50 text-emerald-600 rounded-xl"><i data-lucide="activity" class="w-6 h-6"></i></div>
                </div>
                <button onclick="openCreateModal()" class="bg-slate-900 p-6 rounded-2xl shadow-lg shadow-slate-300 flex items-center justify-center space-x-3 hover:bg-indigo-700 transition transform hover:-translate-y-1">
                    <div class="p-2 bg-white/10 rounded-lg"><i data-lucide="plus" class="w-6 h-6 text-white"></i></div>
                    <span class="text-white font-bold text-lg">Create New Key</span>
                </button>
            </div>

            <div>
                <div class="flex items-center justify-between mb-6">
                    <div class="flex items-center gap-4">
                        <h3 class="text-lg font-bold text-slate-800 flex items-center"><i data-lucide="list-filter" class="w-5 h-5 mr-2 text-slate-400"></i> Active Keys</h3>
                        <select id="server-filter" onchange="applyFilter()" class="bg-white border border-slate-300 text-slate-700 text-sm rounded-lg focus:ring-indigo-500 focus:border-indigo-500 block p-2 outline-none">
                            <option value="all">All Servers</option>
                        </select>
                    </div>
                    <span id="server-count-badge" class="text-xs bg-slate-200 px-2 py-1 rounded text-slate-600 font-bold">0 Servers</span>
                </div>
                <div id="keys-list" class="grid grid-cols-1 lg:grid-cols-2 gap-6"></div>
            </div>
        </div>
    </main>

    <div id="settings-overlay" class="fixed inset-0 bg-slate-900/60 hidden z-[60] flex items-center justify-center backdrop-blur-sm opacity-0 modal">
        <div class="bg-white rounded-2xl shadow-2xl w-full max-w-2xl transform transition-all scale-95 flex flex-col max-h-[90vh]" id="settings-content">
            <div class="p-5 border-b border-slate-100 flex justify-between items-center bg-slate-50 rounded-t-2xl">
                <h3 class="text-lg font-bold text-slate-800 flex items-center"><i data-lucide="sliders" class="w-5 h-5 mr-2 text-indigo-600"></i> System Settings</h3>
                <button onclick="closeSettingsModal()" class="p-1 text-slate-400 hover:text-slate-600 hover:bg-slate-200 rounded-lg transition"><i data-lucide="x" class="w-5 h-5"></i></button>
            </div>
            <div class="p-6 overflow-y-auto bg-slate-50/30 flex-1">
                <div id="settings-loader" class="text-center py-10 hidden"><span class="animate-pulse font-bold text-indigo-600">Loading Config from VPS...</span></div>
                
                <div id="settings-body" class="hidden">
                    <div class="flex space-x-1 mb-6 bg-slate-100 p-1 rounded-xl overflow-x-auto shadow-inner">
                        <button onclick="switchTab('server')" id="tab-btn-server" class="tab-btn flex-1 py-2 px-3 rounded-lg text-sm font-bold transition flex items-center justify-center whitespace-nowrap"><i data-lucide="server" class="w-4 h-4 mr-2"></i> Server</button>
                        <button onclick="switchTab('bot')" id="tab-btn-bot" class="tab-btn flex-1 py-2 px-3 rounded-lg text-sm font-bold transition flex items-center justify-center whitespace-nowrap"><i data-lucide="message-circle" class="w-4 h-4 mr-2"></i> Bot Config</button>
                    </div>

                    <div id="tab-content-server" class="tab-content space-y-6">
                        <div class="bg-white p-5 rounded-xl border border-slate-200 shadow-sm space-y-4">
                            <h4 class="text-xs font-bold text-indigo-600 uppercase tracking-wider flex items-center"><i data-lucide="network" class="w-4 h-4 mr-2"></i> Outline API Configuration</h4>
                            <div class="flex flex-col gap-3 mb-3 bg-indigo-50/50 p-3 rounded-lg border border-indigo-100">
                                <input type="text" id="new-server-name" class="w-full p-2 border border-indigo-200 rounded-lg text-sm outline-none" placeholder="Server Name (e.g. SG1)">
                                <input type="password" id="new-server-url" class="w-full p-2 border border-indigo-200 rounded-lg text-sm outline-none font-mono" placeholder="API URL (https://...)">
                                <button onclick="addServer()" class="w-full bg-indigo-600 text-white px-3 py-2 rounded-lg text-sm font-bold shadow-md hover:bg-indigo-700">Add Server</button>
                            </div>
                            <div id="server-list-container" class="space-y-2"></div>
                             <div class="mt-4 bg-yellow-50 p-3 rounded-lg border border-yellow-200">
                                <label class="block text-xs font-bold text-yellow-700 uppercase mb-1">Web Panel Port</label>
                                <input type="number" id="conf-panel-port" class="w-full p-2 border border-yellow-300 rounded-lg text-sm font-mono" placeholder="80">
                            </div>
                        </div>
                    </div>

                    <div id="tab-content-bot" class="tab-content hidden space-y-6">
                         <div class="bg-white p-5 rounded-xl border border-slate-200 shadow-sm space-y-4">
                            <h4 class="text-xs font-bold text-indigo-600 uppercase tracking-wider"><i data-lucide="settings" class="w-4 h-4 mr-2 inline"></i> Core Settings</h4>
                            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                                <div><label class="block text-xs font-bold text-slate-500 uppercase mb-1">Bot Token</label><input type="text" id="conf-bot-token" class="w-full p-2 border border-slate-300 rounded-lg text-sm font-mono"></div>
                                <div><label class="block text-xs font-bold text-slate-500 uppercase mb-1">Admin ID</label><input type="text" id="conf-tg-id" class="w-full p-2 border border-slate-300 rounded-lg text-sm font-mono"></div>
                                <div class="md:col-span-2"><label class="block text-xs font-bold text-slate-500 uppercase mb-1">Admin Usernames</label><input type="text" id="conf-admin-user" class="w-full p-2 border border-slate-300 rounded-lg text-sm font-mono" placeholder="user1, user2"></div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            <div class="p-5 border-t border-slate-100 bg-slate-50 rounded-b-2xl flex justify-between items-center">
                 <button class="flex items-center text-sm font-bold text-slate-600 opacity-50 cursor-not-allowed"><i data-lucide="info" class="w-4 h-4 mr-2"></i> Auto Save</button>
                <button onclick="saveGlobalSettings()" class="bg-slate-900 hover:bg-slate-800 text-white px-6 py-2.5 rounded-xl font-bold shadow-lg transition">Save & Restart</button>
            </div>
        </div>
    </div>

    <div id="modal-overlay" class="fixed inset-0 bg-slate-900/60 hidden z-50 flex items-center justify-center backdrop-blur-sm opacity-0 modal">
        <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md transform transition-all scale-95" id="modal-content">
            <div class="p-6 border-b border-slate-100 flex justify-between items-center bg-slate-50/50 rounded-t-2xl">
                <h3 class="text-lg font-bold text-slate-800 flex items-center"><i data-lucide="key" class="w-5 h-5 mr-2 text-indigo-600"></i> Manage Key</h3>
                <button onclick="closeModal()" class="p-1 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-lg transition"><i data-lucide="x" class="w-5 h-5"></i></button>
            </div>
            <form id="key-form" class="p-6 space-y-5">
                <input type="hidden" id="key-id">
                <input type="hidden" id="key-server-url"> 
                <div>
                     <label class="block text-xs font-bold text-slate-500 uppercase mb-1 ml-1">Server</label>
                     <select id="server-select" class="w-full p-3 border border-slate-300 rounded-xl outline-none text-sm bg-slate-50">
                         </select>
                </div>
                <div><label class="block text-xs font-bold text-slate-500 uppercase mb-1 ml-1">Name</label><input type="text" id="key-name" class="w-full p-3 border border-slate-300 rounded-xl focus:ring-2 focus:ring-indigo-500 outline-none transition" placeholder="Username" required></div>
                <div class="grid grid-cols-2 gap-4">
                    <div>
                        <label class="block text-xs font-bold text-slate-500 uppercase mb-1">Limit</label>
                        <div class="flex shadow-sm rounded-xl overflow-hidden border border-slate-300 focus-within:ring-2 focus-within:ring-indigo-500">
                            <input type="number" id="key-limit" class="w-full p-3 outline-none" placeholder="Unl" min="0.1" step="0.1">
                            <select id="key-unit" class="bg-slate-50 border-l border-slate-300 px-3 text-sm font-bold text-slate-600 outline-none"><option value="GB">GB</option><option value="MB">MB</option></select>
                        </div>
                    </div>
                    <div><label class="block text-xs font-bold text-slate-500 uppercase mb-1 ml-1">Expiry Date</label><input type="date" id="key-expire" class="w-full p-3 border border-slate-300 rounded-xl focus:ring-2 focus:ring-indigo-500 outline-none text-sm text-slate-600"></div>
                </div>
                <div class="pt-2"><button type="submit" id="save-btn" class="w-full bg-slate-900 hover:bg-indigo-700 text-white py-3.5 rounded-xl font-bold shadow-lg transition flex justify-center items-center">Save Key</button></div>
            </form>
        </div>
    </div>

    <div id="toast" class="fixed bottom-5 right-5 bg-slate-800 text-white px-6 py-4 rounded-xl shadow-2xl transform translate-y-24 transition-transform duration-300 flex items-center z-[70] max-w-sm border border-slate-700/50">
        <div id="toast-icon" class="mr-3 text-emerald-400"></div>
        <div><h4 class="font-bold text-sm" id="toast-title">Success</h4><p class="text-xs text-slate-300 mt-0.5" id="toast-msg">Completed.</p></div>
    </div>

    <script>
        let serverList = []; 
        let globalAllKeys = []; 
        let globalUsageMap = {};
        let refreshInterval;
        let payments = [], plans = [], resellerPlans = [], resellers = [], domainMap = [];
        let botToken = '', currentPort = 80;

        // DYNAMIC BACKEND API DISCOVERY
        const nodeApi = `${window.location.protocol}//${window.location.hostname}:3000/api`;

        // --- KEY FIX: PROXY FETCH WRAPPER ---
        // This function routes all calls through your Node.js server to avoid CORS/SSL issues
        async function outlineFetch(targetUrl, method = 'GET', bodyData = null) {
            try {
                const res = await fetch(`${nodeApi}/proxy`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ url: targetUrl, method: method, data: bodyData })
                });
                
                if(!res.ok) {
                    const errJson = await res.json();
                    throw new Error(errJson.error || "Proxy Error");
                }
                return await res.json();
            } catch (error) {
                console.error("Proxy Fetch Failed:", error);
                throw error;
            }
        }

        document.addEventListener('DOMContentLoaded', () => {
            lucide.createIcons();
            if(localStorage.getItem('outline_connected') === 'true') {
                 document.getElementById('login-section').classList.add('hidden'); 
                 document.getElementById('dashboard').classList.remove('hidden'); 
                 document.getElementById('nav-status').classList.remove('hidden'); document.getElementById('nav-status').classList.add('flex');
                 fetchServerConfig().then(() => { startAutoRefresh(); });
            }
        });

        function switchTab(tabId) {
            document.querySelectorAll('.tab-content').forEach(el => el.classList.add('hidden'));
            document.querySelectorAll('.tab-btn.active').forEach(el => el.classList.remove('active'));
            document.getElementById('tab-content-' + tabId).classList.remove('hidden');
            document.getElementById('tab-btn-' + tabId).classList.add('active');
        }

        function showToast(title, msg, type = 'success') {
            const toast = document.getElementById('toast');
            const iconDiv = document.getElementById('toast-icon');
            document.getElementById('toast-title').textContent = title;
            document.getElementById('toast-msg').textContent = msg;
            let icon = 'check-circle'; let color = 'text-emerald-400';
            if(type === 'error') { icon = 'alert-circle'; color = 'text-red-400'; }
            iconDiv.innerHTML = `<i data-lucide="${icon}" class="w-5 h-5"></i>`;
            iconDiv.className = `mr-3 ${color}`;
            lucide.createIcons();
            toast.classList.remove('translate-y-24');
            setTimeout(() => toast.classList.add('translate-y-24'), 3000);
        }

        function formatAccessUrl(url, serverUrl) {
            if (!url) return url;
            try {
                const urlObj = new URL(url);
                const originalIp = urlObj.hostname;
                if (domainMap && domainMap.length > 0) {
                    const mapping = domainMap.find(m => m.ip === originalIp);
                    if (mapping && mapping.domain) return url.replace(originalIp, mapping.domain);
                }
                return url;
            } catch(e) { return url; }
        }

        async function fetchServerConfig() {
            try {
                const res = await fetch(`${nodeApi}/config`);
                if(!res.ok) throw new Error("Failed");
                const config = await res.json();
                
                let rawUrls = config.api_urls || [];
                serverList = [];
                rawUrls.forEach(item => {
                    if(typeof item === 'string') {
                        serverList.push({ name: "Server", url: item });
                    } else {
                        serverList.push(item);
                    }
                });
                renderServerList();
                updateFilterOptions(); 

                botToken = config.bot_token || '';
                currentPort = config.panel_port || 80;
                document.getElementById('conf-bot-token').value = config.bot_token || '';
                document.getElementById('conf-tg-id').value = config.admin_id || '';
                document.getElementById('conf-admin-user').value = config.admin_username || '';
                document.getElementById('conf-panel-port').value = currentPort;
                document.getElementById('server-count-badge').innerText = `${serverList.length} Servers`;
                return true;
            } catch(e) { return false; }
        }

        function updateFilterOptions() {
            const select = document.getElementById('server-filter');
            select.innerHTML = '<option value="all">All Servers</option>';
            serverList.forEach(s => {
                const opt = document.createElement('option');
                opt.value = s.url;
                opt.text = s.name || "Server";
                select.appendChild(opt);
            });
        }

        function applyFilter() {
            const filterVal = document.getElementById('server-filter').value;
            let filteredKeys = [];
            let totalBytes = 0;

            if (filterVal === 'all') {
                filteredKeys = globalAllKeys;
            } else {
                filteredKeys = globalAllKeys.filter(k => k._serverUrl === filterVal);
            }

            filteredKeys.forEach(k => {
                const used = globalUsageMap[k.id] || 0; 
                totalBytes += used;
            });

            document.getElementById('total-keys').textContent = filteredKeys.length;
            document.getElementById('total-usage').textContent = formatBytes(totalBytes);
            
            renderDashboard(filteredKeys, globalUsageMap);
        }

        function disconnect() { localStorage.removeItem('outline_connected'); if(refreshInterval) clearInterval(refreshInterval); location.reload(); }
        
        async function connectServer(e) { 
            e.preventDefault(); 
            const inputUrl = document.getElementById('login-api-url').value.trim();
            const btn = document.getElementById('connect-btn'); 
            const originalContent = btn.innerHTML; 
            btn.innerHTML = `Connecting via Proxy...`; btn.disabled = true;
            try {
                // FIXED: Use outlineFetch (Proxy) instead of direct fetch
                // We try to fetch the server info
                await outlineFetch(`${inputUrl}/server`, 'GET');
                
                // If successful, save config locally first if needed, but really we rely on server config
                // For the "First Login" we just need to verify it works.
                // NOTE: In this full panel version, we actually use the /api/config from Node.
                // But this login form acts as a "Verify I can access" step.
                
                // If it's the very first setup, we might want to PUSH this URL to config.
                // Let's do that for user convenience.
                if(serverList.length === 0) {
                     await fetch(`${nodeApi}/update-config`, {
                         method: 'POST',
                         headers: {'Content-Type': 'application/json'},
                         body: JSON.stringify({ api_urls: [inputUrl] })
                     });
                }

                localStorage.setItem('outline_connected', 'true');
                document.getElementById('login-section').classList.add('hidden'); 
                document.getElementById('dashboard').classList.remove('hidden'); 
                document.getElementById('nav-status').classList.remove('hidden'); document.getElementById('nav-status').classList.add('flex');
                
                await fetchServerConfig();
                startAutoRefresh();
            } catch (error) { 
                showToast("Connection Failed", "Backend cannot reach this Outline Server. Check URL.", "error"); 
                console.error(error);
                btn.innerHTML = originalContent; btn.disabled = false; 
            }
        }
        
        function startAutoRefresh() { refreshData(); refreshInterval = setInterval(refreshData, 5000); }

        async function refreshData() {
            if(serverList.length === 0) return;
            let allKeys = [];
            
            const promises = serverList.map(async (srv) => {
                 try {
                     const url = srv.url;
                     // FIXED: Use Proxy
                     const [keysData, metricsData] = await Promise.all([ 
                         outlineFetch(`${url}/access-keys`, 'GET'),
                         outlineFetch(`${url}/metrics/transfer`, 'GET')
                     ]);
                     
                     const keys = keysData.accessKeys.map(k => ({ ...k, _serverUrl: url }));
                     return { keys, metrics: metricsData.bytesTransferredByUserId };
                 } catch(e) { return null; }
            });

            const results = await Promise.all(promises);
            globalUsageMap = {}; 
            
            const breakdown = document.getElementById('server-breakdown');
            breakdown.innerHTML = '';

            results.forEach((res, idx) => {
                const srvName = serverList[idx].name || "Server " + (idx+1);
                
                if(res) {
                    allKeys = allKeys.concat(res.keys);
                    Object.entries(res.metrics).forEach(([k, v]) => { globalUsageMap[k] = v; });
                    
                    const count = res.keys.length;
                    breakdown.innerHTML += `<div class="flex justify-between items-center text-xs"><span class="font-medium text-slate-600 truncate max-w-[120px]">${srvName}</span><span class="font-bold bg-slate-100 px-2 py-0.5 rounded text-slate-700">${count}</span></div>`;
                } else {
                    breakdown.innerHTML += `<div class="flex justify-between items-center text-xs"><span class="font-medium text-red-400 truncate max-w-[120px]">${srvName}</span><span class="font-bold bg-red-50 text-red-400 px-2 py-0.5 rounded">OFF</span></div>`;
                }
            });
            
            globalAllKeys = allKeys; 
            applyFilter(); 
        }

        function formatBytes(bytes) { if (!bytes || bytes === 0) return '0 B'; const i = parseInt(Math.floor(Math.log(bytes) / Math.log(1024))); return (bytes / Math.pow(1024, i)).toFixed(2) + ' ' + ['B', 'KB', 'MB', 'GB', 'TB'][i]; }

        async function renderDashboard(keys, usageMap) {
            const list = document.getElementById('keys-list'); list.innerHTML = '';
            keys.sort((a,b) => parseInt(a.id) - parseInt(b.id));
            const today = new Date().toISOString().split('T')[0];

            for (const key of keys) {
                const serverUrl = key._serverUrl; 
                const rawLimit = key.dataLimit ? key.dataLimit.bytes : 0; 
                const rawUsage = usageMap[key.id] || 0;
                
                let displayUsed = rawUsage; let displayLimit = rawLimit;
                let displayName = key.name || 'No Name'; let rawName = displayName; let expireDate = null;
                if (displayName.includes('|')) { const parts = displayName.split('|'); rawName = parts[0].trim(); const potentialDate = parts[parts.length - 1].trim(); if (/^\d{4}-\d{2}-\d{2}$/.test(potentialDate)) expireDate = potentialDate; }
                const isBlocked = rawLimit > 0 && rawLimit <= 5000; let isExpired = expireDate && expireDate < today;
                
                let statusBadge, cardClass, progressBarColor, percentage = 0, switchState = true;
                if (isBlocked) { switchState = false; percentage = 100; progressBarColor = 'bg-slate-300'; cardClass = 'border-slate-200 bg-slate-50 opacity-90'; statusBadge = isExpired ? `<span class="text-xs font-bold text-slate-500">Expired</span>` : `<span class="text-xs font-bold text-slate-500">Disabled</span>`; }
                else { cardClass = 'border-slate-200 bg-white'; percentage = displayLimit > 0 ? Math.min((displayUsed / displayLimit) * 100, 100) : 5; progressBarColor = percentage > 90 ? 'bg-orange-500' : (displayLimit > 0 ? 'bg-indigo-500' : 'bg-emerald-500'); statusBadge = `<span class="text-xs font-bold text-emerald-600">Active</span>`; }

                let finalAccessUrl = formatAccessUrl(key.accessUrl, serverUrl); 
                if(key.name) finalAccessUrl = `${finalAccessUrl.split('#')[0]}#${encodeURIComponent(displayName)}`;
                let limitText = displayLimit > 0 ? formatBytes(displayLimit) : 'Unlimited';
                const serverUrlEnc = encodeURIComponent(serverUrl);

                const card = document.createElement('div');
                card.className = `rounded-2xl shadow-sm border p-5 hover:shadow-md transition-all ${cardClass}`;
                card.innerHTML = `
                    <div class="flex justify-between items-start mb-4">
                        <div class="flex items-center">
                            <div class="w-12 h-12 rounded-2xl ${isBlocked ? 'bg-slate-200 text-slate-500' : 'bg-indigo-50 text-indigo-600'} font-bold flex items-center justify-center mr-4 text-sm border border-black/5">${key.id}</div>
                            <div><h4 class="font-bold text-slate-800 text-lg leading-tight line-clamp-1">${rawName}</h4><div class="flex items-center gap-3 mt-1">${statusBadge} ${expireDate ? `<span class="text-xs text-slate-400 font-medium">${expireDate}</span>` : ''}</div></div>
                        </div>
                        <button onclick="toggleKey('${key.id}', ${isBlocked}, '${serverUrlEnc}')" class="relative w-12 h-7 rounded-full transition-colors focus:outline-none ${switchState ? 'bg-emerald-500' : 'bg-slate-300'}"><span class="inline-block w-5 h-5 transform rounded-full bg-white shadow transition-transform mt-1 ${switchState ? 'translate-x-6' : 'translate-x-1'}"></span></button>
                    </div>
                    <div class="mb-5"><div class="flex justify-between text-xs mb-1.5 font-bold text-slate-500 uppercase tracking-wider"><span>${formatBytes(displayUsed)}</span><span>${limitText}</span></div><div class="w-full bg-slate-100 rounded-full h-3 overflow-hidden"><div class="${progressBarColor} h-3 rounded-full transition-all duration-700" style="width: ${percentage}%"></div></div></div>
                    <div class="flex justify-between items-center pt-4 border-t border-slate-100">
                        <div class="flex space-x-2">
                            <button onclick="editKey('${key.id}', '${rawName.replace(/'/g, "\\'")}', '${expireDate || ''}', ${displayLimit}, '${serverUrlEnc}')" class="p-2 text-slate-400 hover:text-indigo-600 hover:bg-indigo-50 rounded-lg transition"><i data-lucide="settings-2" class="w-4 h-4"></i></button>
                            <button onclick="deleteKey('${key.id}', '${serverUrlEnc}')" class="p-2 text-slate-400 hover:text-red-600 hover:bg-red-50 rounded-lg transition"><i data-lucide="trash-2" class="w-4 h-4"></i></button>
                        </div>
                        <div class="flex space-x-2">
                             <button onclick="copyKey('${finalAccessUrl}')" class="flex items-center px-4 py-2 bg-slate-50 hover:bg-indigo-50 text-slate-600 hover:text-indigo-700 rounded-lg text-xs font-bold transition"><i data-lucide="copy" class="w-3 h-3 mr-2"></i> Copy</button>
                        </div>
                    </div>`;
                list.appendChild(card);
            }
            lucide.createIcons();
        }

        async function toggleKey(id, isBlocked, serverUrlEnc) { 
            const url = decodeURIComponent(serverUrlEnc); 
            try { 
                if(isBlocked) await outlineFetch(`${url}/access-keys/${id}/data-limit`, 'DELETE'); 
                else await outlineFetch(`${url}/access-keys/${id}/data-limit`, 'PUT', { limit: { bytes: 1 } }); 
                showToast(isBlocked ? "Enabled" : "Disabled", isBlocked ? "Key activated" : "Key blocked"); refreshData(); 
            } catch(e) { showToast("Error", "Action failed", 'error'); } 
        }
        
        async function deleteKey(id, serverUrlEnc) { 
            const url = decodeURIComponent(serverUrlEnc); 
            if(!confirm("Delete this key?")) return; 
            try { await outlineFetch(`${url}/access-keys/${id}`, 'DELETE'); showToast("Deleted", "Key removed"); refreshData(); } 
            catch(e) { showToast("Error", "Delete failed", 'error'); } 
        }

        function addServer() {
            const name = document.getElementById('new-server-name').value.trim();
            const url = document.getElementById('new-server-url').value.trim();
            if(!url) return showToast("Missing", "API URL is required", "warn");
            serverList.push({ name: name || "Server", url: url });
            renderServerList();
            document.getElementById('new-server-name').value = '';
            document.getElementById('new-server-url').value = '';
        }
        function removeServer(index) { serverList.splice(index, 1); renderServerList(); }
        function renderServerList() {
            const list = document.getElementById('server-list-container'); list.innerHTML = '';
            if(serverList.length === 0) list.innerHTML = '<div class="text-center text-slate-400 text-xs py-2">No servers configured.</div>';
            serverList.forEach((s, idx) => {
                const item = document.createElement('div');
                item.className = 'flex justify-between items-center bg-white p-2 rounded-lg border border-slate-200 text-sm';
                let displayName = s.name || "Server";
                let displayUrl = s.url.substring(0, 25) + "...";
                item.innerHTML = `<div class="flex items-center gap-2 overflow-hidden"><span class="bg-indigo-100 text-indigo-700 px-2 py-0.5 rounded text-xs font-bold whitespace-nowrap">${displayName}</span><span class="font-mono text-slate-500 text-xs truncate" title="${s.url}">${displayUrl}</span></div><button onclick="removeServer(${idx})" class="text-red-400 hover:text-red-600 ml-2"><i data-lucide="trash" class="w-4 h-4"></i></button>`;
                list.appendChild(item);
            });
            lucide.createIcons();
        }

        const settingsOverlay = document.getElementById('settings-overlay'); const settingsContent = document.getElementById('settings-content');
        
        async function openSettingsModal() { 
            settingsOverlay.classList.remove('hidden'); 
            setTimeout(() => { settingsOverlay.classList.remove('opacity-0'); settingsContent.classList.remove('scale-95'); }, 10);
            document.getElementById('settings-loader').classList.remove('hidden');
            document.getElementById('settings-body').classList.add('hidden');
            await fetchServerConfig();
            document.getElementById('settings-loader').classList.add('hidden');
            document.getElementById('settings-body').classList.remove('hidden');
            switchTab('server');
        }
        function closeSettingsModal() { settingsOverlay.classList.add('opacity-0'); settingsContent.classList.add('scale-95'); setTimeout(() => settingsOverlay.classList.add('hidden'), 200); }
        
        async function saveGlobalSettings() {
            const btn = document.querySelector('button[onclick="saveGlobalSettings()"]'); const originalText = btn.innerText; btn.innerText = "Saving to VPS..."; btn.disabled = true;

            const newPort = document.getElementById('conf-panel-port').value;
            if(newPort && newPort != currentPort) {
                try { await fetch(`${nodeApi}/change-port`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ port: newPort }) }); showToast("Port Changed", `Server moved to port ${newPort}. Reloading...`); } catch(e) { showToast("Error", "Failed to change port", "error"); btn.innerText = originalText; btn.disabled = false; return; }
            }

            const payload = {
                api_urls: serverList, 
                bot_token: document.getElementById('conf-bot-token').value,
                admin_id: document.getElementById('conf-tg-id').value,
                admin_username: document.getElementById('conf-admin-user').value
            };

            try {
                const res = await fetch(`${nodeApi}/update-config`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
                if(res.ok) { 
                    showToast("Success", "Settings Saved"); 
                    if(newPort && newPort != currentPort) { setTimeout(() => { window.location.port = newPort; }, 2000); } 
                    else { 
                        setTimeout(() => {
                             fetchServerConfig(); 
                             closeSettingsModal();
                             btn.innerText = originalText; btn.disabled = false;
                        }, 2000); 
                    } 
                } else { throw new Error("API Error"); }
            } catch (error) { 
                showToast("Error", "Could not connect to VPS Backend", "error"); 
                btn.innerText = originalText; btn.disabled = false;
            }
        }

        const modal = document.getElementById('modal-overlay'); const modalContent = document.getElementById('modal-content');
        
        function openCreateModal() { 
            document.getElementById('key-form').reset(); document.getElementById('key-id').value = ''; document.getElementById('key-unit').value = 'GB';
            const d = new Date(); d.setDate(d.getDate() + 30); document.getElementById('key-expire').value = d.toISOString().split('T')[0]; 
            document.getElementById('key-server-url').value = ''; 
            
            const sel = document.getElementById('server-select');
            sel.innerHTML = '';
            if(serverList.length === 0) sel.innerHTML = '<option>No Servers Configured</option>';
            else {
                serverList.forEach(s => {
                    const opt = document.createElement('option');
                    opt.value = s.url;
                    opt.text = s.name || s.url; 
                    sel.appendChild(opt);
                });
            }
            sel.parentElement.classList.remove('hidden');

            modal.classList.remove('hidden'); setTimeout(() => { modal.classList.remove('opacity-0'); modalContent.classList.remove('scale-95'); }, 10); lucide.createIcons(); 
        }
        function closeModal() { modal.classList.add('opacity-0'); modalContent.classList.add('scale-95'); setTimeout(() => modal.classList.add('hidden'), 200); }
        
        function editKey(id, name, date, displayBytes, serverUrlEnc) { 
            const url = decodeURIComponent(serverUrlEnc);
            document.getElementById('key-id').value = id; 
            document.getElementById('key-server-url').value = url; 
            document.getElementById('server-select').parentElement.classList.add('hidden');
            
            document.getElementById('key-name').value = name; document.getElementById('key-expire').value = date; if(displayBytes > 0) { if (displayBytes >= 1073741824) { document.getElementById('key-limit').value = (displayBytes / 1073741824).toFixed(2); document.getElementById('key-unit').value = 'GB'; } else { document.getElementById('key-limit').value = (displayBytes / 1048576).toFixed(2); document.getElementById('key-unit').value = 'MB'; } } else { document.getElementById('key-limit').value = ''; } modal.classList.remove('hidden'); setTimeout(() => { modal.classList.remove('opacity-0'); modalContent.classList.remove('scale-95'); }, 10); lucide.createIcons(); 
        }
        
        document.getElementById('key-form').addEventListener('submit', async (e) => { 
            e.preventDefault(); 
            const btn = document.getElementById('save-btn'); btn.innerHTML = 'Saving...'; btn.disabled = true; 
            const id = document.getElementById('key-id').value; 
            let name = document.getElementById('key-name').value.trim(); 
            const date = document.getElementById('key-expire').value; 
            const inputVal = parseFloat(document.getElementById('key-limit').value); 
            const unit = document.getElementById('key-unit').value; 
            
            let targetUrl = document.getElementById('key-server-url').value;
            if(!targetUrl && !id) {
                targetUrl = document.getElementById('server-select').value;
            }
            if(!targetUrl) { showToast("Error", "No server selected", 'error'); btn.innerHTML = 'Save Key'; btn.disabled = false; return; }

            if (date) name = `${name} | ${date}`; 
            try { 
                let targetId = id; 
                if(!targetId) { 
                    const res = await outlineFetch(`${targetUrl}/access-keys`, 'POST'); 
                    targetId = res.id; 
                } 
                await outlineFetch(`${targetUrl}/access-keys/${targetId}/name`, 'PUT', { name: name }); 
                if(inputVal > 0) { 
                    let newQuota = (unit === 'GB') ? Math.floor(inputVal * 1024 * 1024 * 1024) : Math.floor(inputVal * 1024 * 1024); 
                    await outlineFetch(`${targetUrl}/access-keys/${targetId}/data-limit`, 'PUT', { limit: { bytes: newQuota } }); 
                } else { 
                    await outlineFetch(`${targetUrl}/access-keys/${targetId}/data-limit`, 'DELETE'); 
                } 
                closeModal(); refreshData(); showToast("Saved", "Success"); 
            } catch(e) { showToast("Error", "Failed", 'error'); console.error(e); } finally { btn.innerHTML = 'Save Key'; btn.disabled = false; } 
        });
        function copyKey(text) { const temp = document.createElement('textarea'); temp.value = text; document.body.appendChild(temp); temp.select(); document.execCommand('copy'); document.body.removeChild(temp); showToast("Copied", "Link copied"); }
    </script>
</body>
</html>
EOF

# 7. Install Node Modules
echo -e "${YELLOW}Installing Node Modules...${NC}"
cd /root/outline-bot
# Create package.json
cat << 'PKG' > package.json
{
  "name": "outline-bot",
  "version": "1.0.0",
  "description": "Outline Telegram Bot & Panel",
  "main": "bot.js",
  "scripts": {
    "start": "node bot.js"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "body-parser": "^1.20.2",
    "cors": "^2.8.5",
    "express": "^4.18.2",
    "moment-timezone": "^0.5.43",
    "node-telegram-bot-api": "^0.63.0"
  }
}
PKG
npm install

# 8. Setup Nginx
echo -e "${YELLOW}Configuring Nginx...${NC}"
cat << 'NGINX' > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
NGINX
systemctl reload nginx

# 9. Setup Firewall (UFW) if active
if ufw status | grep -q "Status: active"; then
    echo -e "${YELLOW}Configuring Firewall...${NC}"
    ufw allow 80/tcp
    ufw allow 3000/tcp
fi

# 10. Start Bot with PM2 (Auto Restart Enabled)
echo -e "${YELLOW}Starting Bot Process with Auto-Restart...${NC}"
npm install -g pm2
pm2 stop outline-bot 2>/dev/null
pm2 start bot.js --name "outline-bot" --restart-delay=3000
pm2 startup
pm2 save

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN} FIXED INSTALLATION COMPLETE! ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "Web Panel URL: ${YELLOW}http://$(curl -s ifconfig.me)${NC}"
echo -e "Backend Port: ${YELLOW}3000 (Internal)${NC}"
echo -e "\n${YELLOW}✅ CORS / SSL Fixed:${NC} Backend Proxy is active."
echo -e "Login using your normal API URL. No additional setup needed."
