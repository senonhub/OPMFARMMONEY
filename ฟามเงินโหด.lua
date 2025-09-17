--// Auto Treasure Chest Farm + Hop Server + UI 🍍
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- =========================
-- CONFIG
local CHECK_INTERVAL = 0.5
local WAIT_BEFORE_FARM = 1
local SAFE_HOP_DELAY = 3
local HOP_PERCENT = 0.50
local autoEnabled = true

-- =========================
-- STATE
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local respawning = false
local firstRun = true
local foundChests = {}

-- =========================
-- UI (อยู่หน้าสุด)
local screenGui = Instance.new("ScreenGui", playerGui)
screenGui.Name = "TreasureFarmUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 9999  -- อยู่หน้าสุด

local bg = Instance.new("Frame", screenGui)
bg.Size = UDim2.new(0, 280, 0, 180)
bg.Position = UDim2.new(0, 20, 0, 200)
bg.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
bg.BackgroundTransparency = 0.2
bg.BorderSizePixel = 0
bg.Active = true
bg.Draggable = true

local corner = Instance.new("UICorner", bg)
corner.CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke", bg)
stroke.Thickness = 2
stroke.Color = Color3.fromRGB(255, 255, 255)
stroke.Transparency = 0.6

-- Title
local title = Instance.new("TextLabel", bg)
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "💎 Treasure Chest AutoFarm"
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(255, 255, 255)

-- Status
local statusLabel = Instance.new("TextLabel", bg)
statusLabel.Size = UDim2.new(1, -10, 0, 25)
statusLabel.Position = UDim2.new(0, 5, 0, 40)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "⏳ รอเริ่มทำงาน..."
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 14
statusLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Chest Count
local chestLabel = Instance.new("TextLabel", bg)
chestLabel.Size = UDim2.new(1, -10, 0, 25)
chestLabel.Position = UDim2.new(0, 5, 0, 70)
chestLabel.BackgroundTransparency = 1
chestLabel.Text = "📦 หีบในแมพ: 0"
chestLabel.Font = Enum.Font.Gotham
chestLabel.TextSize = 14
chestLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
chestLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Beri
local beriLabel = Instance.new("TextLabel", bg)
beriLabel.Size = UDim2.new(1, -10, 0, 25)
beriLabel.Position = UDim2.new(0, 5, 0, 100)
beriLabel.BackgroundTransparency = 1
beriLabel.Text = "💰 Beri: 0"
beriLabel.Font = Enum.Font.Gotham
beriLabel.TextSize = 14
beriLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
beriLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Hop Button
local hopBtn = Instance.new("TextButton", bg)
hopBtn.Size = UDim2.new(0, 120, 0, 30)
hopBtn.Position = UDim2.new(0, 80, 0, 140)
hopBtn.BackgroundColor3 = Color3.fromRGB(50, 150, 250)
hopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
hopBtn.Font = Enum.Font.GothamBold
hopBtn.TextSize = 14
hopBtn.Text = "🌍 Hop 50% ทันที"
hopBtn.AutoButtonColor = true

local btnCorner = Instance.new("UICorner", hopBtn)
btnCorner.CornerRadius = UDim.new(0, 8)

local btnStroke = Instance.new("UIStroke", hopBtn)
btnStroke.Thickness = 2
btnStroke.Color = Color3.fromRGB(255, 255, 255)
btnStroke.Transparency = 0.4

-- =========================
-- Helpers
local function setStatus(text) statusLabel.Text = "⚙ สถานะ: "..text end
local function updateChestCount() chestLabel.Text = "📦 หีบในแมพ: "..#foundChests end
local function updateBeri()
    local stats = player:FindFirstChild("leaderstats")
    if stats then
        local beri = stats:FindFirstChild("Beri")
        if beri then beriLabel.Text = "💰 Beri: "..beri.Value end
    end
end

local function tweenTo(part)
    if hrp then
        hrp.CFrame = CFrame.new(part.Position + Vector3.new(0,7,0))
    end
end

-- =========================
-- Hop Server (แก้ไขระบบ Hop)
local function hopServerSafe()
    if not hrp then return end
    setStatus("🌍 กำลังค้นหาเซิฟว่าง...")
    local pid = game.PlaceId
    local success = false
    local attempts = 0

    while not success and attempts < 3 do
        attempts += 1
        local ok, servers = pcall(function()
            return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..pid.."/servers/Public?sortOrder=Asc&limit=100")).data
        end)
        if ok and servers then
            for _, s in pairs(servers) do
                -- ตรวจ server ว่างจริง ๆ และไม่ใช่ server ปัจจุบัน
                if s.maxPlayers > 0 and s.playing/s.maxPlayers <= HOP_PERCENT and s.id ~= game.JobId then
                    setStatus("🌍 กำลัง Hop ไป server: "..s.id)
                    local teleOk, err = pcall(function()
                        TeleportService:TeleportToPlaceInstance(pid, s.id, player)
                    end)
                    if teleOk then
                        success = true
                        break
                    else
                        warn("Teleport failed: "..tostring(err))
                    end
                end
            end
        end
        task.wait(1) -- รอ 1 วิแล้วลอง server ถัดไป
    end
    if not success then
        setStatus("⚠ Hop server ล้มเหลว")
    end
end

-- =========================
-- Hop Button Event
hopBtn.MouseButton1Click:Connect(function()
    setStatus("🌍 กำลัง Hop เซิฟ 50% ทันที...")
    hopServerSafe()
end)

-- =========================
-- Respawn Handler
local function waitForRespawn()
    respawning = true
    local newChar = player.Character or player.CharacterAdded:Wait()
    local newHumanoid = newChar:WaitForChild("Humanoid")
    local newHRP = newChar:WaitForChild("HumanoidRootPart")
    task.wait(3)
    character = newChar
    humanoid = newHumanoid
    hrp = newHRP
    respawning = false
end

local function connectDeath(hum)
    hum.Died:Connect(function()
        if not respawning then waitForRespawn() end
    end)
end

connectDeath(humanoid)
player.CharacterAdded:Connect(function(char)
    character = char
    humanoid = char:WaitForChild("Humanoid")
    hrp = char:WaitForChild("HumanoidRootPart")
    connectDeath(humanoid)
end)

-- =========================
-- Main Loop
coroutine.wrap(function()
    setStatus("⏳ กำลังหาหีบ")
    local startWait = tick()
    while tick()-startWait < 15 do
        task.wait(0.1)
        updateBeri()
    end

    local noChestStart = nil
    while true do
        task.wait(CHECK_INTERVAL)
        if autoEnabled and not respawning then
            updateBeri()

            -- ตรวจหีบ
            local chests = {}
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj.Name == "TreasureChestPart" and obj:IsA("BasePart") then
                    table.insert(chests,obj)
                end
            end
            foundChests = chests
            updateChestCount()

            if #chests > 0 then
                noChestStart = nil
                if firstRun then
                    setStatus("⏳ เริ่มเก็บหีบใน: "..WAIT_BEFORE_FARM.." วิ")
                    for i = WAIT_BEFORE_FARM,1,-1 do
                        setStatus("⏳ เริ่มเก็บหีบใน: "..i.." วิ")
                        task.wait(1)
                        updateBeri()
                    end
                    firstRun = false
                end
                for _, chest in ipairs(chests) do
                    if chest and chest.Parent then
                        setStatus("🏃 กำลังเก็บหีบ...")
                        tweenTo(chest)
                        task.wait(0.1)
                        updateBeri()
                    end
                end
            else
                -- ไม่พบหีบ → รอ SAFE_HOP_DELAY ก่อน Hop
                if not noChestStart then
                    noChestStart = tick()
                    setStatus("🔍 ไม่พบหีบ, รอ "..SAFE_HOP_DELAY.." วิ ก่อน Hop เซิฟ...")
                elseif tick() - noChestStart >= SAFE_HOP_DELAY then
                    setStatus("🌍 กำลัง Hop เซิฟอัตโนมัติ...")
                    hopServerSafe()
                    noChestStart = nil
                end
            end
        end
    end
end)()