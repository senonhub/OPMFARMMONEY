-- =========================
-- Plants vs Brainrots – Auto (ALL-IN-ONE)
-- =========================

-- ===== PERSISTENCE (Cross-Session Save) =====
local FS = {
	isfile = isfile or function(_) return false end,
	readfile = readfile or function(_) return nil end,
	writefile = writefile or function(_,_) end,
	makefolder = makefolder or function(_) end
}
local SAVE_DIR  = "AutoPvB"
local SAVE_FILE = SAVE_DIR .. "/config.json"
local Http = game:GetService("HttpService")

local function loadConfig()
	local cfg = { MaxMoneySeen = 0 }
	pcall(function() FS.makefolder(SAVE_DIR) end)
	if FS.isfile(SAVE_FILE) then
		local ok, data = pcall(function() return FS.readfile(SAVE_FILE) end)
		if ok and data and #data > 0 then
			local ok2, tbl = pcall(function() return Http:JSONDecode(data) end)
			if ok2 and type(tbl) == "table" then
				for k, v in pairs(tbl) do cfg[k] = v end
			end
		end
	end
	getgenv().AutoPvBConfig = cfg
	return cfg
end
local function saveConfig()
	local cfg = getgenv().AutoPvBConfig or { MaxMoneySeen = 0 }
	local ok, data = pcall(function() return Http:JSONEncode(cfg) end)
	if ok and data then
		pcall(function()
			FS.makefolder(SAVE_DIR)
			FS.writefile(SAVE_FILE, data)
		end)
	end
end
local _cfg = loadConfig()
local _closing = false
local function shutdownSave()
	if _closing then return end
	_closing = true
	saveConfig()
end
pcall(function() game:BindToClose(shutdownSave) end)

_G.Enabled = true

-- ===== CONFIG =====
local PLANT_DELAY       = 1.2             -- ดีเลย์ระหว่างปลูกแต่ละต้น
local COLLECT_INTERVAL  = 60
local MAX_PLATFORM_IDX  = 80
local MAX_ROW_IDX       = 7
local WEBHOOK_URL       = "https://discord.com/api/webhooks/1392662642543427665/auxuNuldvu2l5GfGqCr4dpQCw_OdJCIFLaGhdTOn4Vq1ZMXixiGE6yMLCAAUW83GOXTi"

-- ===== SERVICES =====
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local VIM     = game:GetService("VirtualInputManager")
local HttpSvc = game:GetService("HttpService")
local plr     = Players.LocalPlayer
local Plots   = workspace:WaitForChild("Plots")

-- ===== WEBHOOK HELPERS =====
local function _postWebhook(payload)
    if not WEBHOOK_URL or WEBHOOK_URL=="" then return end
    local req = getgenv().http_request or request or (syn and syn.request) or http_request
    local body = HttpSvc:JSONEncode(payload)
    local headers = {["Content-Type"]="application/json"}
    if req then pcall(function() req({Url=WEBHOOK_URL, Method="POST", Headers=headers, Body=body}) end) end
end
local function sendText(msg)
    _postWebhook({content=msg, username="AutoPvB"})
end
local function sendEmbed(title, desc, color, fields)
    _postWebhook({
        username="AutoPvB",
        embeds={{title=title, description=desc, color=color or 0x57F287, fields=fields, timestamp=DateTime.now():ToIsoDate()}}
    })
end

-- ===== PRICE PARSER
local function parsePrice(txt)
    txt = tostring(txt or ""):lower():gsub("%$", ""):gsub(",", ""):gsub("%s+", "")
    local mult = 1
    if txt:find("k") then mult=1e3;  txt=txt:gsub("k","")
    elseif txt:find("m") then mult=1e6;  txt=txt:gsub("m","")
    elseif txt:find("b") then mult=1e9;  txt=txt:gsub("b","")
    elseif txt:find("t") then mult=1e12; txt=txt:gsub("t","")
    end
    local n = tonumber(txt) or 0
    return math.floor(n*mult+0.5)
end

-- ===== LOCATE MY PLOT =====
local currentPlot
local function Findplot()
    for _, plot in ipairs(Plots:GetChildren()) do
        local sign = plot:FindFirstChild("PlayerSign")
        local bb   = sign and sign:FindFirstChild("BillboardGui")
        local tl   = bb and bb:FindFirstChild("TextLabel")
        if tl and tl.Text == plr.Name then currentPlot = plot; return plot end
    end
end
while not Findplot() do task.wait(0.25) end

-- ===== TILE & PLANT HELPERS =====
local function getGrassTiles(plot)
    local tiles, rows = {}, plot and plot:FindFirstChild("Rows")
    if not rows then return tiles end
    for _, row in ipairs(rows:GetChildren()) do
        local g = row:FindFirstChild("Grass")
        if g then
            for _, inst in ipairs(g:GetChildren()) do
                if inst:IsA("BasePart") and inst:GetAttribute("CanPlace") then
                    table.insert(tiles, inst)
                end
            end
        end
    end
    return tiles
end
local function randomPointOnTile(tile, margin)
    margin = margin or 0.15
    local hx, hz = tile.Size.X*(0.5-margin), tile.Size.Z*(0.5-margin)
    local ox = (math.random()*2-1)*hx
    local oz = (math.random()*2-1)*hz
    return (tile.CFrame * CFrame.new(ox, tile.Size.Y/2, oz)).Position
end
local function getExistingPlants(plot)
    local folder, res = plot:FindFirstChild("Plants"), {}
    if not folder then return res end
    for _, p in ipairs(folder:GetChildren()) do
        if p:GetAttribute("Owner") == plr.Name then
            local pos = p:GetAttribute("Position")
            local sz  = p:GetAttribute("Size")
            if typeof(pos)=="Vector3" then table.insert(res, {position=pos, size=sz}) end
        end
    end
    return res
end
local function isSpotFree(point, plants, minGap)
    minGap = minGap or 0.6
    for _, plinfo in ipairs(plants) do
        local need = math.max(minGap, (plinfo.size or 1)*0.5)
        if (point - plinfo.position).Magnitude <= need then return false end
    end
    return true
end
local function pickRandomFreePoint(tile, plants, tries, margin, minGap)
    tries = tries or 12
    for _=1,tries do
        local pt = randomPointOnTile(tile, margin)
        if isSpotFree(pt, plants, minGap) then return pt end
    end
    return nil
end
local function isTileEmpty(tile)
    local occ = tile:GetAttribute("Occupied")
    if occ ~= nil then return not occ end
    for _, c in ipairs(tile:GetChildren()) do
        if c:IsA("Model") or c:IsA("BasePart") then return false end
    end
    return true
end
local function pickEmptyThenAny(tiles)
    local empty = {}
    for _, t in ipairs(tiles) do if isTileEmpty(t) then table.insert(empty, t) end end
    local list = (#empty>0) and empty or tiles
    return (#list>0) and list[math.random(1, #list)] or nil
end

-- ===== TOOLS / SEEDS =====
local function EquipTool(toolItemName)
    local char = plr.Character or plr.CharacterAdded:Wait()
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool:GetAttribute("ItemName")==toolItemName then return tool end
    end
    local bag = plr:FindFirstChild("Backpack")
    if bag then
        for _, tool in ipairs(bag:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("ItemName")==toolItemName then
                tool.Parent = char
                for _=1,15 do if char:FindFirstChild(tool.Name) then break end; task.wait(0.05) end
                return tool
            end
        end
    end
    return nil
end
local function findLatestSeedId(seedName)
    local containers = {plr.Character, plr.Backpack}
    for _, bag in ipairs(containers) do
        if bag then
            for _, tool in ipairs(bag:GetChildren()) do
                if tool:IsA("Tool") and tool:GetAttribute("ItemName")==seedName then
                    local id = tool:GetAttribute("ID"); if id then return id end
                end
            end
        end
    end
    return nil
end
local function BuySeed(seedName)
    if not seedName or seedName=="" then return false end
    local ok, err = pcall(function() RS.Remotes.BuyItem:FireServer(seedName) end)
    if ok then
        sendEmbed("🛒 ซื้อเมล็ด", ("ซื้อ **%s** สำเร็จ"):format(seedName), 0x5865F2)
    else
        sendEmbed("🛒 ซื้อเมล็ดล้มเหลว", ("**%s**\n```%s```"):format(seedName, tostring(err)), 0xED4245)
    end
    return ok
end
local function plant(tile, seedName)
    if not tile then return end
    local id = findLatestSeedId(seedName)
    if not id then
        sendEmbed("🌱 ปลูกล้มเหลว", "หา **ID** ของ seed ไม่เจอ: `".. tostring(seedName) .."`", 0xED4245)
        return
    end
    if not EquipTool(seedName) then
        sendEmbed("🌱 ปลูกล้มเหลว", "ไม่มี/ถือ **Tool** ไม่ได้: `".. tostring(seedName) .."`", 0xED4245)
        return
    end
    local planted = getExistingPlants(currentPlot)
    local spot = pickRandomFreePoint(tile, planted, 12, 0.15, 0.6)
    if not spot then
        sendEmbed("🌱 ปลูกล้มเหลว", "ไม่พบตำแหน่งว่างบน tile", 0xED4245)
        return
    end
    local item = seedName:match("^(%S+)") -- "Cactus Seed" -> "Cactus"
    local ok, err = pcall(function()
        RS.Remotes.PlaceItem:FireServer({
            ID = id, CFrame = CFrame.new(spot), Item = item, Floor = tile
        })
    end)
    if ok then
        sendEmbed("🌱 ปลูกสำเร็จ",
            ("ปลูก **%s** บน `%s`\nตำแหน่ง `(%.1f, %.1f, %.1f)`"):format(item, tile:GetFullName(), spot.X, spot.Y, spot.Z),
            0x57F287, {{name="SeedID", value="`"..tostring(id).."`", inline=true}})
    else
        sendEmbed("🌱 ปลูกล้มเหลว", "PlaceItem error:\n```"..tostring(err).."```", 0xED4245)
    end
end

-- ===== OWNED SEEDS & CAPACITY =====
local function getOwnedSeeds()
    local res, containers = {}, {plr.Backpack, plr.Character}
    for _, bag in ipairs(containers) do
        if bag then
            for _, tool in ipairs(bag:GetChildren()) do
                if tool:IsA("Tool") and tool:GetAttribute("Seed") then
                    local name = tool:GetAttribute("ItemName") or tool.Name
                    local uses = tonumber(tool:GetAttribute("Uses")) or 1
                    table.insert(res, {Name=name, Uses=uses})
                end
            end
        end
    end
    return res
end
local function getPlantCapacity()
    if not currentPlot then return 0 end
    local rows = currentPlot:FindFirstChild("Rows")
    if not rows then return 0 end
    local enabled = 0
    for _, rf in ipairs(rows:GetChildren()) do
        if rf:IsA("Folder") then
            local en = rf:GetAttribute("Enabled")
            if en == true or (en == nil and rf.Name == "1") then
                enabled = enabled + 1
            end
        end
    end
    return enabled * 5
end
local function getMyPlantCount()
    if not currentPlot then return 0 end
    local folder = currentPlot:FindFirstChild("Plants")
    if not folder then return 0 end
    local n = 0
    for _, p in ipairs(folder:GetChildren()) do
        if p:GetAttribute("Owner") == plr.Name then n = n + 1 end
    end
    return n
end
local function getFreePlantSlots()
    local cap = getPlantCapacity()
    local used = getMyPlantCount()
    return math.max(0, cap - used), used, cap
end

-- ===== SHOP READER (ราคา/stock/rarity) =====
local function getAvailableSeeds()
    local main = plr.PlayerGui:FindFirstChild("Main")
    local seedsUI = main and main:FindFirstChild("Seeds")
    local frame   = seedsUI and seedsUI:FindFirstChild("Frame")
    local scrolling = frame and frame:FindFirstChild("ScrollingFrame")
    if not scrolling then return {} end
    local list = {}
    for _, seedFrame in ipairs(scrolling:GetChildren()) do
        if seedFrame:IsA("Frame") and seedFrame:FindFirstChild("Buttons") then
            local name = seedFrame.Name
            local buy  = seedFrame.Buttons:FindFirstChild("Buy")
            local priceLabel = buy and buy:FindFirstChild("TextLabel")
            local stockLabel = seedFrame:FindFirstChild("Stock")
            local rarityLabel = seedFrame:FindFirstChild("Rarity")
            if priceLabel and stockLabel then
                local price  = parsePrice(priceLabel.Text)
                local stock  = tonumber((stockLabel.Text or ""):match("x(%d+)")) or 0
                local rarity = rarityLabel and rarityLabel.Text or ""
                if stock > 0 then
                    table.insert(list, {Name=name, Price=price, Stock=stock, Rarity=rarity})
                end
            end
        end
    end
    table.sort(list, function(a,b) return a.Price > b.Price end) -- แพง -> ถูก
    return list
end

-- ===== CPS / WAIT-FOR-AFFORD =====
local function getCashPerSecond()
    local main = plr.PlayerGui:FindFirstChild("Main")
    local cpsLabel = main and main:FindFirstChild("CashPerSecond")
        and main.CashPerSecond:FindFirstChild("Money")
    if not cpsLabel or type(cpsLabel.Text) ~= "string" then return 0 end
    local n = cpsLabel.Text:lower():gsub("/s","")
    return parsePrice(n)
end
local function waitUntilAffordable(price, limitSec)
    limitSec = limitSec or 300 -- 5 นาที
    local t0 = tick()
    while tick() - t0 <= limitSec do
        local money = (plr.leaderstats and plr.leaderstats.Money and plr.leaderstats.Money.Value) or 0
        if money >= price then return true end
        task.wait(0.5)
    end
    return false
end
local function shouldWaitFor(price, horizonSec)
    horizonSec = horizonSec or 300
    local money = (plr.leaderstats and plr.leaderstats.Money and plr.leaderstats.Money.Value) or 0
    if money >= price then return false, 0 end
    local cps = getCashPerSecond()
    if cps <= 0 then return false, math.huge end
    local need = price - money
    local eta = need / cps
    return eta <= horizonSec, eta
end

-- ===== RARITY HELPERS =====
local RANK = {
    ["common"]=0, ["uncommon"]=0.5,
    ["rare"]=1, ["epic"]=2, ["legendary"]=3,
    ["mythic"]=4, ["godly"]=5, ["secret"]=6
}
local function normalizeRarity(s)
    if not s or s=="" then return "", -1 end
    s = string.lower(s)
    return s, (RANK[s] or -1)
end
local function getSeedToolRarity(tool)
    local r = tool:GetAttribute("Rarity")
    if type(r)=="string" then
        local key, rank = normalizeRarity(r)
        return r, rank
    end
    return "Rare", RANK["rare"]
end
local function getOwnedSeedsWithRarity()
    local res, containers = {}, {plr.Backpack, plr.Character}
    for _, bag in ipairs(containers) do
        if bag then
            for _, tool in ipairs(bag:GetChildren()) do
                if tool:IsA("Tool") and tool:GetAttribute("Seed") then
                    local name  = tool:GetAttribute("ItemName") or tool.Name
                    local uses  = tonumber(tool:GetAttribute("Uses")) or 1
                    local rTxt, rRank = getSeedToolRarity(tool)
                    table.insert(res, {Name=name, Uses=uses, Rarity=rTxt, Rank=rRank, _tool=tool})
                end
            end
        end
    end
    return res
end
local function getMyPlantsByWeakness()
    local res = {}
    local folder = currentPlot and currentPlot:FindFirstChild("Plants")
    if not folder then return res end
    for _, p in ipairs(folder:GetChildren()) do
        if p:GetAttribute("Owner") == plr.Name then
            local dmg  = tonumber(p:GetAttribute("Damage")) or 0
            local rid  = p:GetAttribute("ID")
            local rTxt = p:GetAttribute("Rarity")
            local key, rRank = normalizeRarity(rTxt)
            if rRank < 0 then rRank = 0 end
            table.insert(res, {inst=p, id=rid, dmg=dmg, Rarity=rTxt or "Unknown", Rank=rRank})
        end
    end
    table.sort(res, function(a,b)
        if a.Rank ~= b.Rank then return a.Rank < b.Rank end
        return a.dmg < b.dmg
    end)
    return res
end

-- ===== NOTIFICATION CHECK =====
local function isTooManyPlants()
    local gui = plr:FindFirstChild("PlayerGui")
    local notifRoot = gui and gui:FindFirstChild("Notifications")
    notifRoot = notifRoot and notifRoot:FindFirstChild("Notifications")
    if not notifRoot then return false end
    for _, lbl in ipairs(notifRoot:GetChildren()) do
        if lbl:IsA("TextLabel") then
          print(lbl.Text)
            return true
        end
    end
    return false
end

-- ===== PRICE-AWARE WEAKNESS & REPLACEMENT =====
local function getPlantShopPrice(plantName, shopList)
    local seedName = tostring(plantName) .. " Seed"
    for _, it in ipairs(shopList or {}) do
        if it.Name == seedName then
            return tonumber(it.Price) or 0, (it.Rarity or "")
        end
    end
    return 0, ""
end
local function getMyPlantsByWeakness_WithPrice()
    local list = getMyPlantsByWeakness()
    local shop = getAvailableSeeds()
    for _, p in ipairs(list) do
        local price = getPlantShopPrice(p.inst.Name, shop)
        p.ShopPrice = price
    end
    table.sort(list, function(a,b)
        if a.Rank ~= b.Rank then return a.Rank < b.Rank end
        if a.dmg  ~= b.dmg  then return a.dmg  < b.dmg  end
        return (a.ShopPrice or 0) < (b.ShopPrice or 0)
    end)
    return list
end
local function sellWeakestPlantsByCount_WithPrice(n)
    if n <= 0 then return 0 end
    local list = getMyPlantsByWeakness_WithPrice()
    local sold = 0
    local sellRemote = RS.Remotes:WaitForChild("RemoveItem")
    for i = 1, math.min(n, #list) do
        local id = list[i].id
        if id then
            local ok = pcall(function() sellRemote:FireServer(id) end)
            if ok then
                sold += 1
                sendEmbed("🪓 ขายพืช (แทนที่)",
                    ("%s | Rank %s | DMG %d | Shop $%s"):format(
                        list[i].inst.Name, tostring(list[i].Rarity), list[i].dmg, tostring(list[i].ShopPrice or 0)),
                    0xED4245)
                task.wait(0.1)
            end
        end
    end
    return sold
end
local function makeRoomIfBetter_RankAndPrice(seedRank, seedBasePrice)
    local free = select(1, getFreePlantSlots())
    if free > 0 then return true end
    local mine = getMyPlantsByWeakness_WithPrice()
    local weakest = mine[1]
    if not weakest then return false end
    if seedRank > weakest.Rank then
        return sellWeakestPlantsByCount_WithPrice(1) == 1
    elseif seedRank == weakest.Rank then
        local wPrice = tonumber(weakest.ShopPrice or 0) or 0
        if (tonumber(seedBasePrice or 0) or 0) > wPrice then
            return sellWeakestPlantsByCount_WithPrice(1) == 1
        end
    end
    return false
end

-- ===== PLANT OWNED SEEDS (PRICE-AWARE) =====
local function plantOwnedSeeds_PriceAware()
    local seeds = getOwnedSeedsWithRarity()
    if #seeds == 0 then return end
    table.sort(seeds, function(a,b)
        if a.Rank ~= b.Rank then return a.Rank > b.Rank end
        return (a.Uses or 1) > (b.Uses or 1)
    end)
    local shop = getAvailableSeeds()
    for _, s in ipairs(seeds) do
        local seedPrice = 0
        for _, it in ipairs(shop) do
            if it.Name == s.Name then seedPrice = tonumber(it.Price) or 0; break end
        end
        if EquipTool(s.Name) then
            local char = plr.Character or plr.CharacterAdded:Wait()
            for _=1,15 do if char:FindFirstChild(s.Name) then break end; task.wait(0.05) end
            for _ = 1, (s.Uses or 1) do
                if isTooManyPlants() then
                    if not makeRoomIfBetter_RankAndPrice(s.Rank, seedPrice) then
                        break
                    end
                end
                local tiles = getGrassTiles(currentPlot)
                if #tiles == 0 then return end
                local t = pickEmptyThenAny(tiles)
                if t and t:GetAttribute("CanPlace") then
                    plant(t, s.Name)
                    task.wait(PLANT_DELAY + 0.1)
                end
            end
        end
    end
end

-- ===== PRIORITY RARITY BUY =====
local function updateMaxMoneySeen(current)
	local cfg = getgenv().AutoPvBConfig or _cfg
	local old = tonumber(cfg.MaxMoneySeen or 0) or 0
	local now = tonumber(current or 0) or 0
	if now > old then
		cfg.MaxMoneySeen = now
		saveConfig()
	end
end
local function pickSeedByPolicy(money, items)
    updateMaxMoneySeen(money)
    local function firstAffordable(list)
        for _, it in ipairs(list) do if it.Price > 0 and money >= it.Price then return it end end
        return nil
    end
    local function between(min,max) return money > min and money <= max end

    if money > 5_000_000 then
        local pri = {}
        for _, it in ipairs(items) do
            local r = (it.Rarity or ""):lower()
            if r=="godly" or r=="secret" then table.insert(pri, it) end
        end
        table.sort(pri, function(a,b) return a.Price > b.Price end)
        local pick = firstAffordable(pri); if pick then return pick end
    end
    if between(1_000_000, 5_000_000) then
        local mythics = {}
        for _, it in ipairs(items) do if (it.Rarity or ""):lower()=="mythic" then table.insert(mythics, it) end end
        table.sort(mythics, function(a,b) return a.Price > b.Price end)
        local pick = firstAffordable(mythics); if pick then return pick end
    end
    if between(100_000, 1_000_000) then
        local leg = {}
        for _, it in ipairs(items) do if (it.Rarity or ""):lower()=="legendary" then table.insert(leg, it) end end
        table.sort(leg, function(a,b) return a.Price > b.Price end)
        if (getgenv().AutoPvBConfig and getgenv().AutoPvBConfig.MaxMoneySeen or 0) >= 250_000 then
            for _, it in ipairs(leg) do if it.Price >= 250_000 and it.Price <= money then return it end end
            local pick = firstAffordable(leg); if pick then return pick end
        else
            local pick = firstAffordable(leg); if pick then return pick end
        end
    end
    if between(5_000, 100_000) then
        local ep = {}
        for _, it in ipairs(items) do if (it.Rarity or ""):lower()=="epic" then table.insert(ep, it) end end
        table.sort(ep, function(a,b) return a.Price > b.Price end)
        if (getgenv().AutoPvBConfig and getgenv().AutoPvBConfig.MaxMoneySeen or 0) >= 25_000 then
            for _, it in ipairs(ep) do if it.Price >= 25_000 and it.Price <= money then return it end end
            local pick = firstAffordable(ep); if pick then return pick end
        else
            local pick = firstAffordable(ep); if pick then return pick end
        end
    end
    if money <= 5_000 then
        local rares = {}
        for _, it in ipairs(items) do if (it.Rarity or ""):lower()=="rare" then table.insert(rares, it) end end
        table.sort(rares, function(a,b) return a.Price > b.Price end)
        if (getgenv().AutoPvBConfig and getgenv().AutoPvBConfig.MaxMoneySeen or 0) >= 1_000 then
            for _, it in ipairs(rares) do if it.Price >= 1_000 and it.Price <= money then return it end end
            local pick = firstAffordable(rares); if pick then return pick end
        else
            local pick = firstAffordable(rares); if pick then return pick end
        end
    end
    local all = {}
    for _, it in ipairs(items) do table.insert(all, it) end
    table.sort(all, function(a,b) return a.Price > b.Price end)
    for _, it in ipairs(all) do if money >= it.Price then return it end end
    return nil
end
local function buyPriorityRaritySeeds()
    local seeds = getAvailableSeeds()
    if #seeds == 0 then return false end
    local boughtAny = false
    local money = (plr.leaderstats and plr.leaderstats.Money and plr.leaderstats.Money.Value) or 0
    updateMaxMoneySeen(money)
    for _, it in ipairs(seeds) do
        local r = (it.Rarity or ""):lower()
        if r=="mythic" or r=="godly" or r=="secret" then
            if money >= it.Price then
                BuySeed(it.Name); boughtAny = true; task.wait(0.2)
                money = (plr.leaderstats and plr.leaderstats.Money and plr.leaderstats.Money.Value) or money
            else
                local okWait = select(1, shouldWaitFor(it.Price, 300))
                if okWait and waitUntilAffordable(it.Price, 300) then
                    BuySeed(it.Name); boughtAny = true; task.wait(0.2)
                    money = (plr.leaderstats and plr.leaderstats.Money and plr.leaderstats.Money.Value) or money
                end
            end
        end
    end
    return boughtAny
end

-- ===== BRAINROT PLATFORM (BuyPlatform) =====
local function getPlatformPrice(slot)
    local priceObj = slot:FindFirstChild("PlatformPrice")
    if not priceObj then return 0 end
    if priceObj:IsA("NumberValue") or priceObj:IsA("IntValue") then
        return tonumber(priceObj.Value) or 0
    end
    local moneyLabel
    for _, d in ipairs(priceObj:GetDescendants()) do
        if d:IsA("TextLabel") and d.Name=="Money" then moneyLabel = d; break end
    end
    if moneyLabel and typeof(moneyLabel.Text)=="string" then
        return parsePrice(moneyLabel.Text)
    end
    return 0
end
local function findNextPlatformToBuy_NoRebirth()
    local plants = currentPlot and currentPlot:FindFirstChild("Plants")
    if not plants then return nil end
    for i=2, MAX_PLATFORM_IDX do
        local slot = plants:FindFirstChild(tostring(i))
        if not slot then break end
        local reb = slot:GetAttribute("Rebirth")
        if reb and tonumber(reb) and tonumber(reb) > 0 then
            -- skip rebirth
        else
            local price = getPlatformPrice(slot)
            if price and price > 0 then return i, price end
        end
    end
    return nil
end
local function tryBuyNextPlatform_NoWalk()
    local idx, price = findNextPlatformToBuy_NoRebirth()
    if not idx then return false end
    local money = (plr.leaderstats and plr.leaderstats.Money and plr.leaderstats.Money.Value) or 0
    if money < price then
        sendEmbed("🧱 ซื้อแพลตฟอร์ม", ("ยังซื้อ **#%d** ไม่ได้ (ต้องการ $%s)"):format(idx, tostring(price)), 0xFAA61A)
        return false
    end
    pcall(function() RS.Remotes.EquipBestBrainrots:FireServer() end)
    local ok, err = pcall(function() RS.Remotes.BuyPlatform:FireServer(tostring(idx)) end)
    if ok then
        sendEmbed("🧱 ซื้อแพลตฟอร์มสำเร็จ", ("ซื้อช่อง **#%d** ราคา **$%s**"):format(idx, tostring(price)), 0x57F287)
    else
        sendEmbed("🧱 ซื้อแพลตฟอร์มล้มเหลว", "```"..tostring(err).."```", 0xED4245)
    end
    return ok
end

-- ===== BUY ROW (แถวปลูกพืช) =====
local function getRowPrice(rowFolder)
    local button = rowFolder:FindFirstChild("Button")
    local main = button and button:FindFirstChild("Main")
    local sg = main and main:FindFirstChild("SurfaceGui")
    local label = sg and sg:FindFirstChild("TextLabel")
    if label and typeof(label.Text)=="string" then return parsePrice(label.Text) end
    return 0
end
local function findNextRowToBuy()
    if not currentPlot then return nil end
    local rows = currentPlot:FindFirstChild("Rows"); if not rows then return nil end
    for i = 2, MAX_ROW_IDX do
        local rf = rows:FindFirstChild(tostring(i))
        if not rf then break end
        local enabled = rf:GetAttribute("Enabled")
        if enabled == true then
            -- bought
        else
            local price = getRowPrice(rf)
            if price and price > 0 then return i, price end
        end
    end
    return nil
end
local function tryBuyNextRow_NoWalk()
    local idx, price = findNextRowToBuy()
    if not idx then return false end
    local money = (plr.leaderstats and plr.leaderstats.Money and plr.leaderstats.Money.Value) or 0
    if money < price then
        sendEmbed("🌿 ซื้อแถวปลูกพืช", ("เงินไม่พอซื้อ **Row #%d** (ต้องการ $%s)"):format(idx, tostring(price)), 0xFAA61A)
        return false
    end
    local ok, err = pcall(function() RS.Remotes.BuyRow:FireServer(idx) end)
    if ok then
        sendEmbed("🌿 ซื้อแถวปลูกพืชสำเร็จ", ("ซื้อ **Row #%d** ราคา **$%s** (+5 slot)"):format(idx, tostring(price)), 0x57F287)
    else
        sendEmbed("🌿 ซื้อแถวล้มเหลว", "```"..tostring(err).."```", 0xED4245)
    end
    return ok
end

-- ===== COLLECT MONEY (เดินเหยียบ Center ทุกแพลตฟอร์มที่เป็นของเรา) =====
local function isPlatformOwned(slot)
    local priceObj = slot:FindFirstChild("PlatformPrice")
    local price = getPlatformPrice(slot)
    local rebirthAttr = slot:GetAttribute("Rebirth")
    if rebirthAttr and tonumber(rebirthAttr) and tonumber(rebirthAttr) > 0 then
        return false, "rebirth"
    end
    return (not priceObj) or (price <= 0), nil
end
local function collectMoneyOnAllCenters(options)
    options = options or {}
    local dwell  = options.dwell or 0.35
    local doJump = (options.jump == nil) and true or options.jump
    local maxIdx = options.maxIdx or MAX_PLATFORM_IDX

    local plants = currentPlot and currentPlot:FindFirstChild("Plants"); if not plants then return end
    local character = plr.Character or plr.CharacterAdded:Wait()
    local humanoid  = character:FindFirstChildOfClass("Humanoid"); if not humanoid then return end

    local moneyBefore = (plr.leaderstats and plr.leaderstats.Money and plr.leaderstats.Money.Value) or 0
    local visited, skippedRebirth = 0, 0

    for i = 1, maxIdx do
        local slot = plants:FindFirstChild(tostring(i))
        if not slot then break end
        local owned, reason = isPlatformOwned(slot)
        if owned then
            local center = slot:FindFirstChild("Center")
            if center and center:IsA("BasePart") then
                humanoid:MoveTo(center.Position)
                humanoid.MoveToFinished:Wait()
                if doJump then
                    VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                    task.wait(0.05)
                    VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                end
                visited = visited + 1
                task.wait(dwell)
            end
        elseif reason == "rebirth" then
            skippedRebirth = skippedRebirth + 1
        end
    end

    local moneyAfter = (plr.leaderstats and plr.leaderstats.Money and plr.leaderstats.Money.Value) or moneyBefore
    local gain = moneyAfter - moneyBefore
    sendEmbed("💰 เก็บเงินจาก Brainrot",
        ("เดินเก็บครบ **%d จุด**, ข้าม Rebirth **%d**\nได้เงินเพิ่ม **$%s** (รวมปัจจุบัน $%s)")
            :format(visited, skippedRebirth, tostring(gain), tostring(moneyAfter)),
        0xFEE75C
    )
end

-- ===== BRAINROT INVENTORY / EQUIP CHECK =====
local function hasBrainrotInInventory()
    local containers = {plr.Backpack, plr.Character}
    for _, bag in ipairs(containers) do
        if bag then
            for _, tool in ipairs(bag:GetChildren()) do
                if tool:IsA("Tool") then
                    local attrName = tool:GetAttribute("Brainrot")
                    local itemName = tool:GetAttribute("ItemName") or tool.Name
                    if attrName == true or (type(attrName)=="string" and attrName~="") then
                        return true, itemName
                    end
                end
            end
        end
    end
    return false, nil
end
local function waitForBrainrot(timeoutSec, interval)
    timeoutSec = timeoutSec or 120
    interval   = interval   or 1.0
    local t0 = tick()
    while tick() - t0 <= timeoutSec do
        local ok, name = hasBrainrotInInventory()
        if ok then return true, name end
        task.wait(interval)
    end
    return false, nil
end
local function ensureEquipBestBrainrots()
    local ok, _ = hasBrainrotInInventory()
    if not ok then return false end
    local succeeded, err = pcall(function()
        RS.Remotes.EquipBestBrainrots:FireServer()
    end)
    if succeeded then
        sendEmbed("🧠 Equip Brainrot", "เรียกใช้ **EquipBestBrainrots** (มี Brainrot อยู่แล้ว)", 0x57F287)
    else
        sendEmbed("🧠 Equip Brainrot ล้มเหลว", "```"..tostring(err).."```", 0xED4245)
    end
    return succeeded
end

-- ===== TUTORIAL HELPERS =====
local function getHumanoid()
    local char = plr.Character or plr.CharacterAdded:Wait()
    return char:FindFirstChildOfClass("Humanoid")
end
local function Walk(targetPosition, timeout)
    timeout = timeout or 8
    local hum = getHumanoid(); if not hum then return end
    hum:MoveTo(targetPosition)
    local t0 = tick()
    while tick() - t0 < timeout do
        if hum.RootPart and (hum.RootPart.Position - targetPosition).Magnitude < 3 then break end
        if hum.MoveToFinished:Wait(0.25) then break end
        hum:MoveTo(targetPosition)
    end
end
local function getGeorgePos()
    if not currentPlot then return nil end
    local root = currentPlot:FindFirstChild("NPCs")
                    and currentPlot.NPCs:FindFirstChild("George")
                    and currentPlot.NPCs.George:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    return root.Position + Vector3.new(4, 0, 0)
end
local function needsTutorial()
    local hud = plr.PlayerGui:FindFirstChild("HUD")
    local tut = hud and hud:FindFirstChild("Tutorial")
    if tut and tut.Visible then return true end
    local plants = currentPlot and currentPlot:FindFirstChild("Plants")
    if plants and #plants:GetChildren() == 0 then return true end
    return false
end
local function buyAnySeedOnce()
    local shop = getAvailableSeeds()
    if #shop == 0 then return false end
    table.sort(shop, function(a,b) return a.Price < b.Price end)
    local money = (plr.leaderstats and plr.leaderstats.Money and plr.leaderstats.Money.Value) or 0
    for _, s in ipairs(shop) do
        if s.Stock > 0 and s.Price > 0 then
            if money >= s.Price then
                return BuySeed(s.Name)
            else
                local okWait = select(1, shouldWaitFor(s.Price, 300))
                if okWait and waitUntilAffordable(s.Price, 300) then
                    return BuySeed(s.Name)
                end
            end
        end
    end
    return false
end
local function plantOneIfPossible()
    local seeds = getOwnedSeeds(); if #seeds == 0 then return false end
    local tiles = getGrassTiles(currentPlot); if #tiles == 0 then return false end
    local free = select(1, getFreePlantSlots()); if free <= 0 then return false end
    local s = seeds[1]
    if not EquipTool(s.Name) then return false end
    local t = pickEmptyThenAny(tiles); if not (t and t:GetAttribute("CanPlace")) then return false end
    plant(t, s.Name)
    task.wait(PLANT_DELAY + 0.1)
    return true
end
local function runTutorialOnce()
    sendEmbed("📘 เริ่ม Tutorial", "1) ไปหา George → 2) ซื้อเมล็ด → 3) ปลูก → 4) EquipBestBrainrots", 0x5865F2)
    local gpos = getGeorgePos()
    if gpos then
        Walk(gpos, 10)
        task.wait(0.2)
        VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.15)
        VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        task.wait(0.5)
    end
    buyAnySeedOnce()
    plantOneIfPossible()
    local gotBR = select(1, waitForBrainrot(180, 1.0))
    if gotBR then
        ensureEquipBestBrainrots()
    else
        sendEmbed("⏳ ยังไม่มี Brainrot", "ข้ามการ Equip ใน Tutorial (จะไปลอง Equip ในลูปหลักแทน)", 0xFAA61A)
    end
    sendEmbed("✅ จบ Tutorial", "เสร็จสิ้น 4 ขั้นตอน พร้อมเข้าระบบอัตโนมัติหลัก", 0x57F287)
end

-- ===== MAIN LOOP =====
if needsTutorial() then
    task.wait(1)
    pcall(runTutorialOnce)
end

local lastCollect = tick()
local lastCap = getPlantCapacity()
local lastEquipCheck = 0
sendText("🔁 เริ่ม Auto PvB")

while _G.Enabled do
    -- 1) ซื้อเมล็ด: กวาดหายากก่อน (Mythic/Godly/Secret)
    local shop  = getAvailableSeeds()
    local money = (plr.leaderstats and plr.leaderstats.Money and plr.leaderstats.Money.Value) or 0
    updateMaxMoneySeen(money)

    local boughtPriority = buyPriorityRaritySeeds()
    if not boughtPriority then
        local pick = pickSeedByPolicy(money, shop)
        if pick then
            if money >= pick.Price then
                BuySeed(pick.Name)
            else
                local okWait = select(1, shouldWaitFor(pick.Price, 300))
                if okWait and waitUntilAffordable(pick.Price, 300) then
                    BuySeed(pick.Name)
                end
            end
        end
    end

    -- 2) ปลูกแบบฉลาด (แทนที่ “กาก” ด้วยกฎ Rank + ราคา)
    plantOwnedSeeds_PriceAware()

    -- 3) เดินเก็บเงินเป็นรอบ ๆ
    if tick() - lastCollect >= COLLECT_INTERVAL then
        collectMoneyOnAllCenters({dwell = 0.35, jump = true, maxIdx = MAX_PLATFORM_IDX})
        lastCollect = tick()
    end

    -- 4) ซื้อแพลตฟอร์ม Brainrot ถัดไป (ข้าม Rebirth)
    tryBuyNextPlatform_NoWalk()

    -- 5) ซื้อ Row ปลูกพืชถัดไป (เพิ่มความจุ +5)
    tryBuyNextRow_NoWalk()

    -- 6) แจ้งเมื่อความจุปลูกเพิ่มขึ้น
    local cap = getPlantCapacity()
    if cap > lastCap then
        sendEmbed("📈 เพิ่มความจุปลูก", ("จาก **%d** → **%d** ต้น"):format(lastCap, cap), 0x00FFFF)
        lastCap = cap
    end

    -- 7) ลอง Equip Brainrot เป็นช่วง ๆ เมื่อมีของ
    if tick() - lastEquipCheck > 5 then
        ensureEquipBestBrainrots()
        lastEquipCheck = tick()
    end

    task.wait(1)
end

sendText("⏹ หยุด Auto PvB")
shutdownSave()
