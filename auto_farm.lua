local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local workspace = game:GetService("Workspace")

local autoLootEnabled = false
local autoPurchaseEnabled = false
local lootConn = nil
local purchaseThread = nil

-- =========================================================
-- REMOTES (dùng chung đường dẫn gốc)
-- =========================================================
local PackagesPath = ReplicatedStorage:WaitForChild("Packages")
    :WaitForChild("_Index")
    :WaitForChild("leifstout_networker@0.3.1")
    :WaitForChild("networker")
    :WaitForChild("_remotes")

local LootRemote = PackagesPath:WaitForChild("LootService"):WaitForChild("RemoteFunction")
local ZoneRemote = PackagesPath:WaitForChild("ZonesService"):WaitForChild("RemoteFunction")
local LootFolder = workspace:WaitForChild("Loot")
local ZonesFolder = workspace:WaitForChild("Zones")

-- =========================================================
-- HÀM ĐỌC SỐ TIỀN TỪ UI
-- =========================================================
-- Parse text dạng "15.907M", "1.5B", "500K", "1234" thành số thật
local function parseCoinText(text)
    if not text then return 0 end
    text = text:gsub(",", ""):gsub(" ", "")
    local num, suffix = text:match("^([%d%.]+)(%a*)$")
    if not num then return 0 end
    num = tonumber(num) or 0
    suffix = suffix:upper()
    if suffix == "K" then
        num = num * 1e3
    elseif suffix == "M" then
        num = num * 1e6
    elseif suffix == "B" then
        num = num * 1e9
    elseif suffix == "T" then
        num = num * 1e12
    end
    return num
end

local function getCoinAmount()
    local ok, result = pcall(function()
        return Players.LocalPlayer.PlayerGui.Root.LeftSideBar
            .CounterStack.CoinCounter.CounterRow.Amount.DropShadow.Text
    end)
    if ok and result then
        return parseCoinText(result)
    end
    return 0
end

-- =========================================================
-- HÀM CHỨC NĂNG
-- =========================================================
local function collectItem(item)
    if not item or not autoLootEnabled then return end
    pcall(function()
        LootRemote:InvokeServer("requestCollect", item.Name)
    end)
end

local function tryPurchaseZone()
    local ok, result = pcall(function()
        return ZoneRemote:InvokeServer("requestPurchaseZone")
    end)
    return ok
end

-- Bảng mapping tên zone → {số thứ tự workspace, giá tiền}
local ZONE_DATA = {
    ["Grasslands"]      = { num = 1,  price = 0 },
    ["Desert"]          = { num = 2,  price = 400 },
    ["Polar"]           = { num = 3,  price = 5000 },
    ["Volcano"]         = { num = 4,  price = 50000 },
    ["Islands"]         = { num = 5,  price = 400000 },
    ["Cave"]            = { num = 6,  price = 2000000 },
    ["Heaven"]          = { num = 7,  price = 12000000 },
    ["Jungle"]          = { num = 8,  price = 54000000 },
    ["Canyon"]          = { num = 9,  price = 216000000 },
    ["Mushroom Forest"] = { num = 10, price = 936000000 },
    ["Moon"]            = { num = 11, price = 3800000000 },
    ["Redwood Forest"]  = { num = 12, price = 15600000000 },
    ["Meteor"]          = { num = 13, price = 75000000000 },
    ["Candyland"]       = { num = 14, price = 250000000000 },
    ["Cherry Grove"]    = { num = 15, price = 1000000000000 },
    ["Crystal Cavern"]  = { num = 16, price = 3500000000000 },
    ["Pumpkin Patch"]   = { num = 17, price = 11000000000000 },
    ["Atlantis"]        = { num = 18, price = 31000000000000 },
    ["River"]           = { num = 19, price = 94000000000000 },
    ["Pyramids"]        = { num = 20, price = 282000000000000 },
    ["Graveyard"]       = { num = 21, price = 846000000000000 },
    ["Hot Springs"]     = { num = 22, price = 2500000000000000 },
    ["Tribe"]           = { num = 23, price = 8000000000000000 },
    ["Toxic Wasteland"] = { num = 24, price = 2.6e16 },
    ["Steampunk"]       = { num = 25, price = 8e16 },
}

-- Đọc tên zone đang được offer mua từ UI ZonePurchase
local function getNextZoneName()
    local ok, name = pcall(function()
        return Players.LocalPlayer.PlayerGui.ZonePurchase.Frame
            .ZoneName.TextLabel.Text
    end)
    if ok and name then return name end
    return nil
end

-- Đọc giá zone trực tiếp từ UI (ZonePurchase.Frame.ZoneName.DropShadow.Text)
local function getZonePrice()
    local ok, priceText = pcall(function()
        return Players.LocalPlayer.PlayerGui.ZonePurchase.Frame
            .ZoneName.DropShadow.Text
    end)
    if ok and priceText then
        return parseCoinText(priceText)
    end
    return nil
end

-- Teleport tới zone theo số thứ tự
local function teleportToZone(zoneNumber)
    local character = Players.LocalPlayer.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local targetZone = ZonesFolder:FindFirstChild(tostring(zoneNumber))
    if not targetZone then return end

    -- Teleport tới POI > Hitbox của zone đó
    local poi = targetZone:FindFirstChild("POI")
    if not poi then return end
    local hitbox = poi:FindFirstChild("Hitbox")
    if not hitbox then return end

    if hitbox:IsA("BasePart") then
        hrp.CFrame = hitbox.CFrame + Vector3.new(0, 5, 0)
    elseif hitbox:IsA("Model") and hitbox.PrimaryPart then
        hrp.CFrame = hitbox.PrimaryPart.CFrame + Vector3.new(0, 5, 0)
    else
        local part = hitbox:FindFirstChildWhichIsA("BasePart", true)
        if part then
            hrp.CFrame = part.CFrame + Vector3.new(0, 5, 0)
        end
    end
end

-- =========================================================
-- TẠO UI
-- =========================================================
local uiName = "AutoFarmPanel"
if CoreGui:FindFirstChild(uiName) then CoreGui[uiName]:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = uiName
gui.ResetOnSpawn = false
gui.Parent = RunService:IsStudio() and Players.LocalPlayer:WaitForChild("PlayerGui") or CoreGui

-- Khung chính (kéo thả được)
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 230, 0, 200)
frame.Position = UDim2.new(0.5, -115, 0.12, 0)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

-- Viền phát sáng
local uiStroke = Instance.new("UIStroke")
uiStroke.Color = Color3.fromRGB(80, 80, 80)
uiStroke.Thickness = 1
uiStroke.Parent = frame

-- Tiêu đề
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 32)
title.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Text = "⚡ Auto Farm Panel"
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.BorderSizePixel = 0
title.Parent = frame
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 10)

-- Label hiển thị số tiền hiện tại
local coinLabel = Instance.new("TextLabel")
coinLabel.Size = UDim2.new(1, -20, 0, 22)
coinLabel.Position = UDim2.new(0, 10, 0, 36)
coinLabel.BackgroundTransparency = 1
coinLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
coinLabel.Text = "💰 Coins: ---"
coinLabel.Font = Enum.Font.GothamBold
coinLabel.TextSize = 13
coinLabel.TextXAlignment = Enum.TextXAlignment.Left
coinLabel.Parent = frame

-- Hàm tạo nút toggle
local function createToggle(name, posY)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 200, 0, 42)
    btn.Position = UDim2.new(0.5, -100, 0, posY)
    btn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Text = name .. ": OFF"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 15
    btn.BorderSizePixel = 0
    btn.Parent = frame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    return btn
end

local lootBtn = createToggle("Auto Loot", 62)
local zoneBtn = createToggle("Auto Zone", 112)

-- Status label phía dưới
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 20)
statusLabel.Position = UDim2.new(0, 10, 0, 160)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
statusLabel.Text = "Trạng thái: Chờ..."
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 11
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = frame

-- =========================================================
-- LOGIC AUTO LOOT
-- =========================================================
lootBtn.MouseButton1Click:Connect(function()
    autoLootEnabled = not autoLootEnabled
    if autoLootEnabled then
        lootBtn.Text = "Auto Loot: ON"
        lootBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 40)

        -- Nhặt đồ đang có sẵn
        for _, item in ipairs(LootFolder:GetChildren()) do
            task.spawn(collectItem, item)
        end

        -- Lắng nghe đồ mới
        lootConn = LootFolder.ChildAdded:Connect(function(item)
            task.spawn(collectItem, item)
        end)
    else
        lootBtn.Text = "Auto Loot: OFF"
        lootBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
        if lootConn then
            lootConn:Disconnect()
            lootConn = nil
        end
    end
end)

-- =========================================================
-- LOGIC AUTO PURCHASE ZONE (SMART - CHECK TIỀN TRƯỚC)
-- =========================================================
zoneBtn.MouseButton1Click:Connect(function()
    autoPurchaseEnabled = not autoPurchaseEnabled
    if autoPurchaseEnabled then
        zoneBtn.Text = "Auto Zone: ON"
        zoneBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 40)

        purchaseThread = task.spawn(function()
            -- Khi vừa bật: TP ngay đến zone cao nhất đã unlock
            local initZoneName = getNextZoneName()
            local initData = initZoneName and ZONE_DATA[initZoneName]
            if initData and initData.num > 1 then
                local currentZoneNum = initData.num - 1
                statusLabel.Text = "TP tới zone " .. currentZoneNum .. "..."
                teleportToZone(currentZoneNum)
                statusLabel.Text = "✅ Đã TP tới zone " .. currentZoneNum .. "!"
                task.wait(1)
            end

            while autoPurchaseEnabled do
                local coins = getCoinAmount()

                -- Đọc zone đang được offer và giá từ UI
                local nextZoneName = getNextZoneName()
                local zoneData = nextZoneName and ZONE_DATA[nextZoneName]
                local zonePrice = getZonePrice() -- Đọc giá trực tiếp từ UI

                if not nextZoneName or not zonePrice then
                    coinLabel.Text = "💰 Coins: " .. tostring(coins)
                    statusLabel.Text = "Trạng thái: Đã mua hết zone / Không tìm thấy zone"
                    task.wait(3)
                else
                    local zoneNum = zoneData and zoneData.num

                    -- Cập nhật hiển thị
                    coinLabel.Text = "💰 Coins: " .. Players.LocalPlayer.PlayerGui.Root.LeftSideBar
                        .CounterStack.CoinCounter.CounterRow.Amount.DropShadow.Text
                    statusLabel.Text = "Chờ mua: " .. nextZoneName .. " (cần " .. tostring(zonePrice) .. ")"

                    -- Chỉ mua khi ĐỦ TIỀN (so với giá từ UI)
                    if coins >= zonePrice then
                        statusLabel.Text = "Đang mua " .. nextZoneName .. "..."

                        tryPurchaseZone()
                        task.wait(1)

                        local coinsAfter = getCoinAmount()

                        if coinsAfter < coins then
                            -- Mua thành công! TP tới zone vừa mua
                            if zoneNum then
                                statusLabel.Text = "✅ Đã mua " .. nextZoneName .. "! Đang TP..."
                                task.wait(1)
                                teleportToZone(zoneNum)
                                statusLabel.Text = "✅ Đã TP tới " .. nextZoneName .. "!"
                            else
                                statusLabel.Text = "✅ Mua thành công! (zone chưa có trong ZONE_DATA)"
                            end
                        else
                            statusLabel.Text = "❌ Mua thất bại (server từ chối?)"
                        end
                    end
                end

                task.wait(2) -- Check mỗi 2 giây để tránh lag
            end
        end)
    else
        zoneBtn.Text = "Auto Zone: OFF"
        zoneBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
        autoPurchaseEnabled = false
        statusLabel.Text = "Trạng thái: Đã tắt"
        coinLabel.Text = "💰 Coins: ---"

        if purchaseThread then
            task.cancel(purchaseThread)
            purchaseThread = nil
        end
    end
end)

print("⚡ Auto Farm Panel đã sẵn sàng!")
