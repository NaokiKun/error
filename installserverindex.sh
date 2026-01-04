#!/bin/bash

# Color Codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== VPN Shop Frontend Installer (ID Collision Fixed) ===${NC}"

# 1. Check Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit
fi

# 2. Install Nginx if not exists
echo -e "${YELLOW}Checking Nginx...${NC}"
if ! command -v nginx &> /dev/null; then
    echo "Installing Nginx..."
    apt update && apt install -y nginx
fi

# 3. Clear old files
echo -e "${YELLOW}Clearing old frontend files...${NC}"
rm -rf /var/www/html/*

# 4. Create index.html with FIXES
echo -e "${YELLOW}Creating index.html with ID Collision Fixes...${NC}"
cat << 'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPN Shop Manager</title>
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
                    <h1 class="text-xl font-bold tracking-tight">VPN Shop</h1>
                    <p class="text-[10px] text-slate-400 uppercase tracking-widest font-semibold">Manager Panel</p>
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
                    <p class="text-slate-500 mt-2 text-sm">Enter one of your API URLs to authenticate</p>
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
                        <button onclick="switchTab('reseller')" id="tab-btn-reseller" class="tab-btn flex-1 py-2 px-3 rounded-lg text-sm font-bold transition flex items-center justify-center whitespace-nowrap"><i data-lucide="briefcase" class="w-4 h-4 mr-2"></i> Reseller</button>
                        <button onclick="switchTab('plans')" id="tab-btn-plans" class="tab-btn flex-1 py-2 px-3 rounded-lg text-sm font-bold transition flex items-center justify-center whitespace-nowrap"><i data-lucide="shopping-cart" class="w-4 h-4 mr-2"></i> Shop & Plans</button>
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

                        <div class="bg-white p-5 rounded-xl border border-slate-200 shadow-sm space-y-4">
                            <h4 class="text-xs font-bold text-slate-500 uppercase flex items-center"><i data-lucide="globe" class="w-4 h-4 mr-2"></i> Domain Mappings</h4>
                            <div class="flex flex-col md:flex-row gap-2 mb-3">
                                <input type="text" id="map-ip" class="flex-1 p-2 border border-slate-300 rounded-lg text-sm font-mono" placeholder="IP Address">
                                <input type="text" id="map-domain" class="flex-1 p-2 border border-slate-300 rounded-lg text-sm font-mono" placeholder="Domain">
                                <button onclick="addDomainMap()" class="bg-indigo-600 text-white px-4 py-2 rounded-lg text-sm font-bold">Add</button>
                            </div>
                            <div id="domain-map-list" class="space-y-2"></div>
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
                             <div>
                                <label class="block text-xs font-bold text-slate-500 uppercase mb-1">Welcome Message</label>
                                <textarea id="conf-welcome" class="w-full p-2 border border-slate-300 rounded-lg text-sm font-mono" rows="3"></textarea>
                            </div>
                        </div>
                        
                         <div class="bg-white p-5 rounded-xl border border-slate-200 shadow-sm space-y-4">
                             <h4 class="text-xs font-bold text-slate-500 uppercase mb-2">Bot Buttons</h4>
                             <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                                <input type="text" id="btn-trial" class="p-2 border border-slate-300 rounded-lg text-sm" placeholder="Trial Btn">
                                <input type="text" id="btn-buy" class="p-2 border border-slate-300 rounded-lg text-sm" placeholder="Buy Btn">
                                <input type="text" id="btn-mykey" class="p-2 border border-slate-300 rounded-lg text-sm" placeholder="My Key Btn">
                                <input type="text" id="btn-info" class="p-2 border border-slate-300 rounded-lg text-sm" placeholder="Info Btn">
                                <input type="text" id="btn-support" class="p-2 border border-slate-300 rounded-lg text-sm" placeholder="Support Btn">
                                <input type="text" id="btn-reseller" class="p-2 border border-slate-300 rounded-lg text-sm" placeholder="Reseller Btn">
                            </div>
                            <h5 class="text-xs font-bold text-purple-600 uppercase mt-4 mb-2">Reseller Buttons</h5>
                            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                                <input type="text" id="btn-resell-buy" class="p-2 border border-purple-200 rounded-lg text-sm bg-purple-50" placeholder="Buy Stock Btn">
                                <input type="text" id="btn-resell-create" class="p-2 border border-purple-200 rounded-lg text-sm bg-purple-50" placeholder="Create User Btn">
                                <input type="text" id="btn-resell-users" class="p-2 border border-purple-200 rounded-lg text-sm bg-purple-50" placeholder="My Users Btn">
                                <input type="text" id="btn-resell-extend" class="p-2 border border-purple-200 rounded-lg text-sm bg-purple-50" placeholder="Extend User Btn">
                                <input type="text" id="btn-resell-logout" class="p-2 border border-purple-200 rounded-lg text-sm bg-purple-50" placeholder="Logout Btn">
                            </div>
                         </div>
                    </div>

                    <div id="tab-content-reseller" class="tab-content hidden space-y-6">
                        <div class="bg-white p-5 rounded-xl border-l-4 border-purple-500 shadow-sm">
                            <div class="flex items-center justify-between mb-4">
                                 <h4 class="text-xs font-bold text-purple-600 uppercase tracking-wider flex items-center"><i data-lucide="users" class="w-4 h-4 mr-2"></i> Manage Resellers</h4>
                            </div>
                            <div class="flex flex-col md:flex-row gap-2 mb-4 bg-purple-50/50 p-3 rounded-lg border border-purple-100">
                                <input type="text" id="resell-user" class="flex-1 p-2 border border-purple-200 rounded-lg text-sm outline-none" placeholder="Username">
                                <input type="text" id="resell-pass" class="flex-1 p-2 border border-purple-200 rounded-lg text-sm outline-none" placeholder="Password">
                                <input type="number" id="resell-bal" class="flex-1 p-2 border border-purple-200 rounded-lg text-sm outline-none" placeholder="Balance (Ks)">
                                <button onclick="addReseller()" id="btn-add-reseller" class="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded-lg text-sm font-bold shadow-md transition w-24">Add</button>
                            </div>
                            <div id="reseller-list" class="space-y-2"></div>
                        </div>

                         <div class="bg-white p-5 rounded-xl border border-slate-200 shadow-sm">
                             <h4 class="text-xs font-bold text-purple-600 uppercase tracking-wider mb-4"><i data-lucide="tag" class="w-4 h-4 mr-2 inline"></i> Reseller Plans</h4>
                             <div class="flex gap-2 mb-4 bg-white p-2 rounded-lg border border-purple-200">
                                <div class="w-1/4"><input type="number" id="rplan-days" class="w-full p-2 border border-purple-100 rounded-lg text-sm text-center outline-none" placeholder="Days"></div>
                                <div class="w-1/4"><input type="text" id="rplan-gb" class="w-full p-2 border border-purple-100 rounded-lg text-sm text-center outline-none" placeholder="GB"></div>
                                <div class="flex-1"><input type="number" id="rplan-price" class="w-full p-2 border border-purple-100 rounded-lg text-sm text-center outline-none" placeholder="Reseller Price"></div>
                                <button onclick="addResellerPlan()" class="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded-lg text-sm font-bold shadow-md transition">Add</button>
                            </div>
                            <div id="rplan-list" class="grid grid-cols-1 gap-2"></div>
                        </div>
                    </div>

                    <div id="tab-content-plans" class="tab-content hidden space-y-6">
                        <div class="bg-white p-5 rounded-xl border border-slate-200 shadow-sm">
                            <h4 class="text-xs font-bold text-blue-600 uppercase tracking-wider mb-4 flex items-center"><i data-lucide="package" class="w-4 h-4 mr-2"></i> User VPN Plans</h4>
                            <div class="flex gap-2 mb-4 bg-blue-50/50 p-3 rounded-lg border border-blue-100">
                                <div class="w-1/4"><input type="number" id="plan-days" class="w-full p-2 border border-blue-200 rounded-lg text-sm text-center outline-none" placeholder="Days"></div>
                                <div class="w-1/4"><input type="text" id="plan-gb" class="w-full p-2 border border-blue-200 rounded-lg text-sm text-center outline-none" placeholder="GB"></div>
                                <div class="flex-1"><input type="number" id="plan-price" class="w-full p-2 border border-blue-200 rounded-lg text-sm text-center outline-none" placeholder="Price"></div>
                                <button onclick="addPlan()" class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-sm font-bold shadow-md transition">Add</button>
                            </div>
                            <div id="plan-list" class="grid grid-cols-1 gap-2"></div>
                        </div>

                         <div class="bg-white p-5 rounded-xl border border-slate-200 shadow-sm">
                            <h4 class="text-xs font-bold text-emerald-600 uppercase tracking-wider mb-4 flex items-center"><i data-lucide="credit-card" class="w-4 h-4 mr-2"></i> Payment Methods</h4>
                            <div class="flex flex-col md:flex-row gap-2 mb-4 bg-emerald-50/50 p-3 rounded-lg border border-emerald-100">
                                <input type="text" id="pay-name" class="flex-1 p-2 border border-emerald-200 rounded-lg text-sm outline-none" placeholder="Wallet">
                                <input type="text" id="pay-num" class="flex-1 p-2 border border-emerald-200 rounded-lg text-sm outline-none" placeholder="Number">
                                <input type="text" id="pay-owner" class="flex-1 p-2 border border-emerald-200 rounded-lg text-sm outline-none" placeholder="Owner">
                                <button onclick="addPayment()" class="bg-emerald-600 hover:bg-emerald-700 text-white px-4 py-2 rounded-lg text-sm font-bold shadow-md transition">Add</button>
                            </div>
                            <div id="payment-list" class="space-y-2"></div>
                        </div>

                        <div class="border border-slate-200 p-3 rounded-lg bg-indigo-50/50">
                            <div class="flex items-center justify-between mb-3">
                                <div class="flex items-center">
                                    <div class="bg-indigo-100 p-2 rounded-lg mr-3 text-indigo-600"><i data-lucide="gift" class="w-5 h-5"></i></div>
                                    <div><p class="text-sm font-bold text-slate-800">Free Trial Settings</p></div>
                                </div>
                                <input type="checkbox" id="conf-trial" class="w-5 h-5 text-indigo-600 rounded focus:ring-indigo-500 border-gray-300">
                            </div>
                            <div class="grid grid-cols-2 gap-4">
                                 <div><label class="block text-xs font-bold text-slate-500 uppercase mb-1">Trial Days</label><input type="number" id="conf-trial-days" class="w-full p-2 border border-slate-300 rounded-lg text-sm" placeholder="1"></div>
                                 <div><label class="block text-xs font-bold text-slate-500 uppercase mb-1">Trial GB</label><input type="number" id="conf-trial-gb" class="w-full p-2 border border-slate-300 rounded-lg text-sm" placeholder="1" step="0.1"></div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            <div class="p-5 border-t border-slate-100 bg-slate-50 rounded-b-2xl flex justify-between items-center">
                 <button onclick="copyPaymentInfo()" class="flex items-center text-sm font-bold text-slate-600 hover:text-indigo-600 px-3 py-2 rounded-lg hover:bg-indigo-50 transition"><i data-lucide="copy" class="w-4 h-4 mr-2"></i> Copy Info</button>
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
                     <label class="block text-xs font-bold text-slate-500 uppercase mb-1 ml-1">Server (Create Only)</label>
                     <select id="server-select" class="w-full p-3 border border-slate-300 rounded-xl outline-none text-sm bg-slate-50">
                         </select>
                </div>

                <div><label class="block text-xs font-bold text-slate-500 uppercase mb-1 ml-1">Name</label><input type="text" id="key-name" class="w-full p-3 border border-slate-300 rounded-xl focus:ring-2 focus:ring-indigo-500 outline-none transition" placeholder="Username" required></div>
                <div id="topup-container" class="hidden">
                    <div class="bg-indigo-50 p-3 rounded-xl border border-indigo-100 flex items-center">
                        <input type="checkbox" id="topup-mode" class="w-5 h-5 text-indigo-600 rounded focus:ring-indigo-500 border-gray-300">
                        <label for="topup-mode" class="ml-3 block text-sm font-bold text-indigo-900">Reset & Top Up</label>
                    </div>
                </div>
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
        let editingResellerIndex = -1;

        const nodeApi = `${window.location.protocol}//${window.location.hostname}:3000/api`;

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
            else if (type === 'warn') { icon = 'shield-alert'; color = 'text-orange-400'; }
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

                payments = config.payments || [];
                plans = config.plans || [];
                resellerPlans = config.reseller_plans || [];
                resellers = config.resellers || [];
                domainMap = config.domain_map || [];
                botToken = config.bot_token || '';
                currentPort = config.panel_port || 80;

                document.getElementById('conf-bot-token').value = config.bot_token || '';
                document.getElementById('conf-tg-id').value = config.admin_id || '';
                document.getElementById('conf-admin-user').value = config.admin_username || '';
                document.getElementById('conf-welcome').value = config.welcome_msg || '';
                document.getElementById('conf-panel-port').value = currentPort;
                document.getElementById('conf-trial').checked = config.trial_enabled !== false; 
                document.getElementById('conf-trial-days').value = config.trial_days || 1;
                document.getElementById('conf-trial-gb').value = config.trial_gb || 1;

                const btns = config.buttons || {};
                document.getElementById('btn-trial').value = btns.trial || "🆓 Free Trial (အစမ်းသုံးရန်)";
                document.getElementById('btn-buy').value = btns.buy || "🛒 Buy Key (ဝယ်ယူရန်)";
                document.getElementById('btn-mykey').value = btns.mykey || "🔑 My Key (မိမိ Key ရယူရန်)";
                document.getElementById('btn-info').value = btns.info || "👤 Account Info (အကောင့်စစ်ရန်)";
                document.getElementById('btn-support').value = btns.support || "🆘 Support (ဆက်သွယ်ရန်)";
                document.getElementById('btn-reseller').value = btns.reseller || "🤝 Reseller Login";
                
                document.getElementById('btn-resell-buy').value = btns.resell_buy || "🛒 Buy Stock";
                document.getElementById('btn-resell-create').value = btns.resell_create || "📦 Create User Key";
                document.getElementById('btn-resell-users').value = btns.resell_users || "👥 My Users";
                document.getElementById('btn-resell-extend').value = btns.resell_extend || "⏳ Extend User";
                document.getElementById('btn-resell-logout').value = btns.resell_logout || "🔙 Logout Reseller";
                
                renderPayments(); renderPlans(); renderResellerPlans(); renderResellers(); renderDomainMap();
                
                document.getElementById('server-count-badge').innerText = `${serverList.length} Servers`;
                return true;
            } catch(e) { 
                showToast("Error", "Could not load config from VPS", "error"); 
                return false;
            }
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
                // FIXED: Use composite ID for accurate usage sum
                const compositeId = `${k._serverUrl}::${k.id}`;
                const used = globalUsageMap[compositeId] || 0; 
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
            const btn = document.getElementById('connect-btn'); const originalContent = btn.innerHTML; btn.innerHTML = `Connecting...`; btn.disabled = true;
            try {
                await fetch(`${inputUrl}/server`, { method: 'GET' }); 
                localStorage.setItem('outline_connected', 'true');
                document.getElementById('login-section').classList.add('hidden'); document.getElementById('dashboard').classList.remove('hidden'); document.getElementById('nav-status').classList.remove('hidden'); document.getElementById('nav-status').classList.add('flex');
                await fetchServerConfig();
                startAutoRefresh();
            } catch (error) { 
                showToast("Connection Failed", "Check URL & SSL. Ensure CORS is enabled if testing locally.", "error"); 
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
                     const [keysRes, metricsRes] = await Promise.all([ fetch(`${url}/access-keys`), fetch(`${url}/metrics/transfer`) ]);
                     const keysData = await keysRes.json();
                     const metricsData = await metricsRes.json();
                     const keys = keysData.accessKeys.map(k => ({ ...k, _serverUrl: url }));
                     return { keys, metrics: metricsData.bytesTransferredByUserId, serverUrl: url };
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
                    
                    // FIXED: Key collision in globalUsageMap
                    // We now store usage as "ServerURL::ID" -> Bytes
                    Object.entries(res.metrics).forEach(([k, v]) => { 
                        globalUsageMap[`${res.serverUrl}::${k}`] = v; 
                    });
                    
                    const count = res.keys.length;
                    breakdown.innerHTML += `
                        <div class="flex justify-between items-center text-xs">
                            <span class="font-medium text-slate-600 truncate max-w-[120px]" title="${srvName}">${srvName}</span>
                            <span class="font-bold bg-slate-100 px-2 py-0.5 rounded text-slate-700">${count}</span>
                        </div>
                    `;
                } else {
                    breakdown.innerHTML += `
                        <div class="flex justify-between items-center text-xs">
                            <span class="font-medium text-red-400 truncate max-w-[120px]" title="${srvName}">${srvName}</span>
                            <span class="font-bold bg-red-50 text-red-400 px-2 py-0.5 rounded">OFF</span>
                        </div>
                    `;
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
                // FIXED: Use Composite ID for Offset storage
                const compositeId = `${serverUrl}::${key.id}`;
                
                const usageOffset = parseInt(localStorage.getItem(`offset_${compositeId}`) || '0');
                const rawLimit = key.dataLimit ? key.dataLimit.bytes : 0; 
                
                // FIXED: Retrieve usage using Composite ID
                const rawUsage = usageMap[compositeId] || 0;
                
                let displayUsed = Math.max(0, rawUsage - usageOffset); let displayLimit = 0; if (rawLimit > 0) displayLimit = Math.max(0, rawLimit - usageOffset);
                let displayName = key.name || 'No Name'; let rawName = displayName; let expireDate = null;
                if (displayName.includes('|')) { const parts = displayName.split('|'); rawName = parts[0].trim(); const potentialDate = parts[parts.length - 1].trim(); if (/^\d{4}-\d{2}-\d{2}$/.test(potentialDate)) expireDate = potentialDate; }
                const isBlocked = rawLimit > 0 && rawLimit <= 5000; let isExpired = expireDate && expireDate < today; let isDataExhausted = (rawLimit > 5000 && rawUsage >= rawLimit);
                
                let statusBadge, cardClass, progressBarColor, percentage = 0, switchState = true;
                if (isBlocked) { switchState = false; percentage = 100; progressBarColor = 'bg-slate-300'; cardClass = 'border-slate-200 bg-slate-50 opacity-90'; statusBadge = isExpired ? `<span class="text-xs font-bold text-slate-500">Expired</span>` : (isDataExhausted ? `<span class="text-xs font-bold text-red-500">Data Full</span>` : `<span class="text-xs font-bold text-slate-500">Disabled</span>`); }
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

        async function toggleKey(id, isBlocked, serverUrlEnc) { const url = decodeURIComponent(serverUrlEnc); try { if(isBlocked) await fetch(`${url}/access-keys/${id}/data-limit`, { method: 'DELETE' }); else await fetch(`${url}/access-keys/${id}/data-limit`, { method: 'PUT', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ limit: { bytes: 1 } }) }); showToast(isBlocked ? "Enabled" : "Disabled", isBlocked ? "Key activated" : "Key blocked"); refreshData(); } catch(e) { showToast("Error", "Action failed", 'error'); } }
        async function deleteKey(id, serverUrlEnc) { const url = decodeURIComponent(serverUrlEnc); if(!confirm("Delete this key?")) return; try { await fetch(`${url}/access-keys/${id}`, { method: 'DELETE' }); localStorage.removeItem(`offset_${id}`); showToast("Deleted", "Key removed"); refreshData(); } catch(e) { showToast("Error", "Delete failed", 'error'); } }

        function addPayment() { const name = document.getElementById('pay-name').value.trim(); const num = document.getElementById('pay-num').value.trim(); const owner = document.getElementById('pay-owner').value.trim(); if(!name || !num) return showToast("Info Missing", "Name and Number required", "warn"); payments.push({ name, num, owner }); renderPayments(); document.getElementById('pay-name').value = ''; document.getElementById('pay-num').value = ''; document.getElementById('pay-owner').value = ''; }
        function removePayment(index) { payments.splice(index, 1); renderPayments(); }
        function renderPayments() { const list = document.getElementById('payment-list'); list.innerHTML = ''; if(payments.length === 0) list.innerHTML = '<div class="text-center text-slate-400 text-xs py-2">No payment methods added.</div>'; payments.forEach((p, idx) => { const item = document.createElement('div'); item.className = 'flex justify-between items-center bg-white p-3 rounded-lg border border-slate-100 shadow-sm'; item.innerHTML = `<div class="flex items-center space-x-3"><div class="bg-emerald-100 text-emerald-600 p-2 rounded-full"><i data-lucide="wallet" class="w-4 h-4"></i></div><div><p class="text-sm font-bold text-slate-800">${p.name}</p><p class="text-xs text-slate-500 font-mono">${p.num} ${p.owner ? `(${p.owner})` : ''}</p></div></div><button onclick="removePayment(${idx})" class="text-slate-300 hover:text-red-500"><i data-lucide="trash" class="w-4 h-4"></i></button>`; list.appendChild(item); }); lucide.createIcons(); }
        
        function addPlan() { const days = document.getElementById('plan-days').value; const gb = document.getElementById('plan-gb').value; const price = document.getElementById('plan-price').value; if(!days || !gb || !price) return showToast("Info Missing", "Fill all plan details", "warn"); plans.push({ days, gb, price }); renderPlans(); document.getElementById('plan-days').value = ''; document.getElementById('plan-gb').value = ''; document.getElementById('plan-price').value = ''; }
        function removePlan(index) { plans.splice(index, 1); renderPlans(); }
        function renderPlans() { const list = document.getElementById('plan-list'); list.innerHTML = ''; if(plans.length === 0) list.innerHTML = '<div class="text-center text-slate-400 text-xs py-2">No plans added.</div>'; plans.forEach((p, idx) => { const item = document.createElement('div'); item.className = 'flex justify-between items-center bg-white p-3 rounded-lg border border-slate-100 shadow-sm'; item.innerHTML = `<div class="flex items-center space-x-3 w-full"><div class="bg-blue-100 text-blue-600 p-2 rounded-full flex-shrink-0"><i data-lucide="zap" class="w-4 h-4"></i></div><div class="flex justify-between w-full pr-4"><div class="text-sm font-bold text-slate-800 w-1/3">${p.days} Days</div><div class="text-sm font-bold text-slate-600 w-1/3 text-center">${p.gb}</div><div class="text-sm font-bold text-emerald-600 w-1/3 text-right">${p.price} Ks</div></div></div><button onclick="removePlan(${idx})" class="text-slate-300 hover:text-red-500 flex-shrink-0"><i data-lucide="trash" class="w-4 h-4"></i></button>`; list.appendChild(item); }); lucide.createIcons(); }
        
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

        function addDomainMap() {
            const ip = document.getElementById('map-ip').value.trim();
            const domain = document.getElementById('map-domain').value.trim();
            if(!ip || !domain) return showToast("Missing", "IP and Domain required", "warn");
            domainMap.push({ ip, domain });
            renderDomainMap();
            document.getElementById('map-ip').value = '';
            document.getElementById('map-domain').value = '';
        }
        function removeDomainMap(index) { domainMap.splice(index, 1); renderDomainMap(); }
        function renderDomainMap() {
             const list = document.getElementById('domain-map-list'); list.innerHTML = '';
             if(domainMap.length === 0) list.innerHTML = '<div class="text-center text-slate-400 text-xs py-2">No mappings added.</div>';
             domainMap.forEach((m, idx) => {
                 const item = document.createElement('div');
                 item.className = 'flex justify-between items-center bg-white p-2 rounded-lg border border-slate-200 text-sm';
                 item.innerHTML = `<div class="font-mono text-xs"><span class="text-indigo-600 font-bold">${m.ip}</span> <span class="text-slate-400">➜</span> <span class="font-bold text-slate-700">${m.domain}</span></div><button onclick="removeDomainMap(${idx})" class="text-red-400 hover:text-red-600"><i data-lucide="trash" class="w-4 h-4"></i></button>`;
                 list.appendChild(item);
             });
             lucide.createIcons();
        }

        function addResellerPlan() { const days = document.getElementById('rplan-days').value; const gb = document.getElementById('rplan-gb').value; const price = document.getElementById('rplan-price').value; if(!days || !gb || !price) return showToast("Info Missing", "Fill all plan details", "warn"); resellerPlans.push({ days, gb, price }); renderResellerPlans(); document.getElementById('rplan-days').value = ''; document.getElementById('rplan-gb').value = ''; document.getElementById('rplan-price').value = ''; }
        function removeResellerPlan(index) { resellerPlans.splice(index, 1); renderResellerPlans(); }
        function renderResellerPlans() { const list = document.getElementById('rplan-list'); list.innerHTML = ''; if(resellerPlans.length === 0) list.innerHTML = '<div class="text-center text-slate-400 text-xs py-2">No reseller plans added.</div>'; resellerPlans.forEach((p, idx) => { const item = document.createElement('div'); item.className = 'flex justify-between items-center bg-purple-50 p-3 rounded-lg border border-purple-100 shadow-sm'; item.innerHTML = `<div class="flex items-center space-x-3 w-full"><div class="bg-purple-100 text-purple-600 p-2 rounded-full flex-shrink-0"><i data-lucide="tag" class="w-4 h-4"></i></div><div class="flex justify-between w-full pr-4"><div class="text-sm font-bold text-slate-800 w-1/3">${p.days} Days</div><div class="text-sm font-bold text-slate-600 w-1/3 text-center">${p.gb}</div><div class="text-sm font-bold text-purple-600 w-1/3 text-right">${p.price} Ks</div></div></div><button onclick="removeResellerPlan(${idx})" class="text-slate-300 hover:text-red-500 flex-shrink-0"><i data-lucide="trash" class="w-4 h-4"></i></button>`; list.appendChild(item); }); lucide.createIcons(); }
        function addReseller() { const u = document.getElementById('resell-user').value.trim(); const p = document.getElementById('resell-pass').value.trim(); const b = document.getElementById('resell-bal').value.trim(); if(!u || !p || !b) return showToast("Missing", "All fields required", "warn"); if (editingResellerIndex > -1) { resellers[editingResellerIndex] = { username: u, password: p, balance: parseInt(b) }; editingResellerIndex = -1; document.getElementById('btn-add-reseller').innerText = "Add"; showToast("Updated", "Reseller updated successfully"); } else { resellers.push({ username: u, password: p, balance: parseInt(b) }); showToast("Added", "Reseller added"); } renderResellers(); document.getElementById('resell-user').value = ''; document.getElementById('resell-pass').value = ''; document.getElementById('resell-bal').value = ''; }
        function editReseller(index) { const r = resellers[index]; document.getElementById('resell-user').value = r.username; document.getElementById('resell-pass').value = r.password; document.getElementById('resell-bal').value = r.balance; editingResellerIndex = index; document.getElementById('btn-add-reseller').innerText = "Update"; }
        function removeReseller(index) { if(!confirm("Delete this reseller?")) return; resellers.splice(index, 1); renderResellers(); if(index === editingResellerIndex) { editingResellerIndex = -1; document.getElementById('btn-add-reseller').innerText = "Add"; document.getElementById('resell-user').value = ''; document.getElementById('resell-pass').value = ''; document.getElementById('resell-bal').value = ''; } }
        function renderResellers() { const list = document.getElementById('reseller-list'); list.innerHTML = ''; if(resellers.length === 0) list.innerHTML = '<div class="text-center text-slate-400 text-xs py-2">No resellers added.</div>'; resellers.forEach((r, idx) => { const item = document.createElement('div'); item.className = 'flex justify-between items-center bg-white p-3 rounded-lg border border-slate-100 shadow-sm'; item.innerHTML = `<div class="flex items-center space-x-3"><div class="bg-purple-100 text-purple-600 p-2 rounded-full"><i data-lucide="user-check" class="w-4 h-4"></i></div><div><p class="text-sm font-bold text-slate-800">${r.username}</p><p class="text-xs text-slate-500 font-mono">Pass: ${r.password} | Bal: <span class="text-emerald-600 font-bold">${r.balance} Ks</span></p></div></div><div class="flex space-x-1"><button onclick="editReseller(${idx})" class="p-2 text-slate-400 hover:text-indigo-600 hover:bg-indigo-50 rounded-lg transition" title="Edit/Topup"><i data-lucide="pencil" class="w-4 h-4"></i></button><button onclick="removeReseller(${idx})" class="p-2 text-slate-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition" title="Delete"><i data-lucide="trash" class="w-4 h-4"></i></button></div>`; list.appendChild(item); }); lucide.createIcons(); }

        const settingsOverlay = document.getElementById('settings-overlay'); const settingsContent = document.getElementById('settings-content');
        
        async function openSettingsModal() { 
            settingsOverlay.classList.remove('hidden'); 
            setTimeout(() => { settingsOverlay.classList.remove('opacity-0'); settingsContent.classList.remove('scale-95'); }, 10);
            document.getElementById('settings-loader').classList.remove('hidden');
            document.getElementById('settings-body').classList.add('hidden');
            await fetchServerConfig();
            document.getElementById('settings-loader').classList.add('hidden');
            document.getElementById('settings-body').classList.remove('hidden');
            switchTab('server'); // Default Tab
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
                admin_username: document.getElementById('conf-admin-user').value,
                domain_map: domainMap, 
                welcome_msg: document.getElementById('conf-welcome').value,
                trial_enabled: document.getElementById('conf-trial').checked,
                trial_days: parseInt(document.getElementById('conf-trial-days').value) || 1,
                trial_gb: parseFloat(document.getElementById('conf-trial-gb').value) || 1,
                buttons: {
                    trial: document.getElementById('btn-trial').value,
                    buy: document.getElementById('btn-buy').value,
                    mykey: document.getElementById('btn-mykey').value,
                    info: document.getElementById('btn-info').value,
                    support: document.getElementById('btn-support').value,
                    reseller: document.getElementById('btn-reseller').value,
                    
                    // --- SAVE NEW BUTTONS ---
                    resell_buy: document.getElementById('btn-resell-buy').value,
                    resell_create: document.getElementById('btn-resell-create').value,
                    resell_users: document.getElementById('btn-resell-users').value,
                    resell_extend: document.getElementById('btn-resell-extend').value,
                    resell_logout: document.getElementById('btn-resell-logout').value
                },
                payments: payments, plans: plans, reseller_plans: resellerPlans, resellers: resellers
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

        function copyPaymentInfo() { let text = "➖➖ Payment Methods ➖➖\n"; payments.forEach(p => { text += `✅ ${p.name}: ${p.num} ${p.owner ? '('+p.owner+')' : ''}\n`; }); text += "\n➖➖ Available Plans ➖➖\n"; plans.forEach(p => { text += `💎 ${p.days} Days - ${p.gb} - ${p.price} Ks\n`; }); const temp = document.createElement('textarea'); temp.value = text; document.body.appendChild(temp); temp.select(); document.execCommand('copy'); document.body.removeChild(temp); showToast("Copied", "Info copied"); }

        const modal = document.getElementById('modal-overlay'); const modalContent = document.getElementById('modal-content');
        
        function openCreateModal() { 
            document.getElementById('key-form').reset(); document.getElementById('key-id').value = ''; document.getElementById('key-unit').value = 'GB'; document.getElementById('topup-container').classList.add('hidden'); 
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
            
            document.getElementById('key-name').value = name; document.getElementById('key-expire').value = date; document.getElementById('topup-container').classList.remove('hidden'); document.getElementById('topup-mode').checked = false; if(displayBytes > 0) { if (displayBytes >= 1073741824) { document.getElementById('key-limit').value = (displayBytes / 1073741824).toFixed(2); document.getElementById('key-unit').value = 'GB'; } else { document.getElementById('key-limit').value = (displayBytes / 1048576).toFixed(2); document.getElementById('key-unit').value = 'MB'; } } else { document.getElementById('key-limit').value = ''; } modal.classList.remove('hidden'); setTimeout(() => { modal.classList.remove('opacity-0'); modalContent.classList.remove('scale-95'); }, 10); lucide.createIcons(); 
        }
        
        document.getElementById('key-form').addEventListener('submit', async (e) => { 
            e.preventDefault(); 
            const btn = document.getElementById('save-btn'); btn.innerHTML = 'Saving...'; btn.disabled = true; 
            const id = document.getElementById('key-id').value; 
            let name = document.getElementById('key-name').value.trim(); 
            const date = document.getElementById('key-expire').value; 
            const inputVal = parseFloat(document.getElementById('key-limit').value); 
            const unit = document.getElementById('key-unit').value; 
            const isTopUp = document.getElementById('topup-mode').checked; 
            
            let targetUrl = document.getElementById('key-server-url').value;
            if(!targetUrl && !id) {
                targetUrl = document.getElementById('server-select').value;
            }
            if(!targetUrl) { showToast("Error", "No server selected", 'error'); btn.innerHTML = 'Save Key'; btn.disabled = false; return; }

            if (date) name = `${name} | ${date}`; 
            try { 
                let targetId = id; 
                if(!targetId) { 
                    const res = await fetch(`${targetUrl}/access-keys`, { method: 'POST' }); 
                    const data = await res.json(); 
                    targetId = data.id; 
                    
                    // FIXED: Init composite offset
                    localStorage.setItem(`offset_${targetUrl}::${targetId}`, '0'); 
                } 
                await fetch(`${targetUrl}/access-keys/${targetId}/name`, { method: 'PUT', headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: `name=${encodeURIComponent(name)}` }); 
                if(inputVal > 0) { 
                    let newQuota = (unit === 'GB') ? Math.floor(inputVal * 1024 * 1024 * 1024) : Math.floor(inputVal * 1024 * 1024); 
                    let finalLimit = newQuota; 
                    
                    // FIXED: Composite ID for Offset logic
                    const compositeId = `${targetUrl}::${targetId}`;
                    
                    if (targetId && isTopUp) { 
                        const curRaw = globalUsageMap[compositeId] || 0; 
                        localStorage.setItem(`offset_${compositeId}`, curRaw); 
                        finalLimit = curRaw + newQuota; 
                    } else if (targetId) { 
                        const oldOff= parseInt(localStorage.getItem(`offset_${compositeId}`) || '0'); 
                        finalLimit = oldOff + newQuota; 
                    } 
                    await fetch(`${targetUrl}/access-keys/${targetId}/data-limit`, { method: 'PUT', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ limit: { bytes: finalLimit } }) }); 
                } else { 
                    await fetch(`${targetUrl}/access-keys/${targetId}/data-limit`, { method: 'DELETE' }); 
                } 
                closeModal(); refreshData(); showToast("Saved", "Success"); 
            } catch(e) { showToast("Error", "Failed", 'error'); } finally { btn.innerHTML = 'Save Key'; btn.disabled = false; } 
        });
        function copyKey(text) { const temp = document.createElement('textarea'); temp.value = text; document.body.appendChild(temp); temp.select(); document.execCommand('copy'); document.body.removeChild(temp); showToast("Copied", "Link copied"); }
    </script>
</body>
</html>
EOF

# 5. Restart Nginx
echo -e "${YELLOW}Restarting Nginx...${NC}"
systemctl restart nginx

echo -e "${GREEN}Frontend Installation Complete (With ID Fixes)!${NC}"
echo -e "Panel URL: http://$(curl -s ifconfig.me)"
