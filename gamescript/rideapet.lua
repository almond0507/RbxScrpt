if _G.AIO_Off then _G.AIO_Off() return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local LP = Players.LocalPlayer

-- anti-afk (always on while script runs)
pcall(function()
    LP.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

local ActiveEggs = (ReplicatedStorage:FindFirstChild("ServerData") or ReplicatedStorage):WaitForChild("ActiveEggs")
local RenderedEggs = Workspace:WaitForChild("RenderedEggs")
local Remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Game")
local EggPickup = Remotes:WaitForChild("EggPickup")
local EggPlacedR = Remotes:WaitForChild("EggPlaced")
local HatchR = Remotes:WaitForChild("Hatch")
local EggsData = require(ReplicatedStorage:WaitForChild("GameData"):WaitForChild("Eggs"))
local General2 = require(ReplicatedStorage:WaitForChild("GameData"):WaitForChild("General"))
local DayNight = require(ReplicatedStorage:WaitForChild("GameServices"):WaitForChild("DayNight"))

-- does this executor support Drawing? (some mobile executors do not)
local HAS_DRAWING = false
pcall(function()
    if Drawing then
        local d = Drawing.new("Text")
        d:Remove()
        HAS_DRAWING = true
    end
end)

-- CONFIG + JSON
local CONFIG_FILE = "allinone_config.json"
getgenv().AIO = getgenv().AIO or {}
local CFG = getgenv().AIO
pcall(function()
    if readfile and isfile and isfile(CONFIG_FILE) then
        local d = HttpService:JSONDecode(readfile(CONFIG_FILE))
        if type(d) == "table" then
            for k, v in pairs(d) do CFG[k] = v end
        end
    end
end)
CFG.MIN_KG = CFG.MIN_KG or 2
CFG.GO = CFG.GO or CFG.FLY or 170
CFG.BACK = CFG.BACK or 340
local ESP_ON = CFG.ESP == true
local AUTO_ON = CFG.AUTO == true
local PLACE_ON = CFG.PLACE == true
local HATCH_ON = CFG.HATCH == true

local Anchors = {
    {Real = 0.9, Shown = 1},
    {Real = 1.2, Shown = 15},
    {Real = 1.5, Shown = 73000},
    {Real = 2,   Shown = 240000},
    {Real = 3,   Shown = 1500000},
}
local function ShownKG(real)
    real = tonumber(real) or 1
    if real <= Anchors[1].Real then return Anchors[1].Shown end
    for i = 1, #Anchors - 1 do
        local a, b = Anchors[i], Anchors[i+1]
        if real <= b.Real then
            local t = (real - a.Real) / (b.Real - a.Real)
            return 10 ^ (math.log10(a.Shown) + (math.log10(b.Shown) - math.log10(a.Shown)) * t)
        end
    end
    return Anchors[#Anchors].Shown
end
local function Comma(n)
    n = math.floor(n + 0.5)
    local s = tostring(n)
    while true do
        local k
        s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

local function SaveCFG()
    CFG.ESP = ESP_ON
    CFG.AUTO = AUTO_ON
    CFG.PLACE = PLACE_ON
    CFG.HATCH = HATCH_ON
    pcall(function()
        if writefile then
            writefile(CONFIG_FILE, HttpService:JSONEncode({
                MIN_KG = CFG.MIN_KG,
                GO = CFG.GO,
                BACK = CFG.BACK,
                ESP = ESP_ON,
                AUTO = AUTO_ON,
                PLACE = PLACE_ON,
                HATCH = HATCH_ON,
            }))
        end
    end)
end

local running = true
local drawings = {}
local billboards = {}
local lastFire = {}
local hatchCD = {}
local placeCD = 0
local mode = "HUNT"
local moveTarget = nil
local moveSpeed = CFG.GO
local curEggId = nil
local lastCarriedShown = 0
local lastCarriedReal = 1
local lastCarriedName = ""
local function CarryCap()
    local mult = 1
    pcall(function()
        mult = General2.EggCarrySpeedMultiplier(lastCarriedReal, lastCarriedName)
    end)
    if type(mult) ~= "number" then
        mult = 1
    end
    local cap = math.floor(270 * mult * 0.9)
    if cap < 40 then
        cap = 40
    end
    return cap
end

_G.AIO_Off = function()
    running = false
    moveTarget = nil
    for id, d in pairs(drawings) do
        pcall(function() d.Name:Remove() end)
        pcall(function() d.KG:Remove() end)
        pcall(function() d.Dist:Remove() end)
    end
    table.clear(drawings)
    for id, g in pairs(billboards) do
        pcall(function() g:Destroy() end)
    end
    table.clear(billboards)
    pcall(function() _G.AIO_Gui:Destroy() end)
    _G.AIO_Off = nil
end

local function GetHRP()
    local c = LP.Character
    if c then return c:FindFirstChild("HumanoidRootPart") end
    return nil
end
local function HasClaimed(eggName, inst)
    if inst and inst:GetAttribute("AdminSpawn") == true then return false end
    local c = LP:GetAttribute("CollectedEggs")
    if type(c) == "string" and c ~= "" and eggName then
        return string.find(c, eggName .. ",", 1, true) ~= nil
    end
    return false
end
local function IsEthereal(n)
    local d = EggsData[n]
    if d then return d.Rarity == "Ethereal" end
    return false
end
local function EggWorldPos(inst, eggName, posAttr)
    local best = nil
    local bestD = nil
    local bestM = nil
    for _, m in ipairs(RenderedEggs:GetChildren()) do
        if m.Name == eggName and m:IsA("Model") then
            local ok, piv = pcall(function() return m:GetPivot().Position end)
            if ok then
                local d = (piv - posAttr).Magnitude
                if d < 120 and (not bestD or d < bestD) then
                    best = piv
                    bestD = d
                    bestM = m
                end
            end
        end
    end
    if best then return best, bestM end
    return posAttr, nil
end
local function GetMyPlot()
    local plots = Workspace:FindFirstChild("Plots")
    if plots then
        for _, p in ipairs(plots:GetChildren()) do
            local ok, mine = pcall(function()
                local data = p:FindFirstChild("Data")
                local owner = data and data:FindFirstChild("Owner")
                if owner and owner.Value == LP then return true end
                if p:GetAttribute("OwnerUserId") == LP.UserId then return true end
                if p.Name == LP.Name then return true end
                return false
            end)
            if ok and mine then return p end
        end
    end
    local ok, plot = pcall(function()
        local General = require(ReplicatedStorage:WaitForChild("GameServices"):WaitForChild("General"))
        return General:GetPlot(LP)
    end)
    if ok and plot then return plot end
    return nil
end
local function GetPlotPos()
    local p = GetMyPlot()
    local base = nil
    if p then base = p:FindFirstChild("Baseplate") end
    if base and base:IsA("BasePart") then
        return base.Position + Vector3.new(0, 5, 0)
    end
    return nil
end
local function IsVolcanic(n)
    return n == "Volcanic Egg"
end
local volcLeg = nil
local function VolcanoEntrance()
    local hrp = GetHRP()
    if not hrp then
        return nil
    end
    local v = workspace:FindFirstChild("Volcano")
    local isl = nil
    if v then
        isl = v:FindFirstChild("VolcanoIsland")
    end
    if not isl then
        return nil
    end
    local ok, cf, size = pcall(function()
        local a, b = isl:GetBoundingBox()
        return a, b
    end)
    if not ok or not cf or not size then
        return nil
    end
    local lp = cf:PointToObjectSpace(hrp.Position)
    local ex = math.clamp(lp.X, -size.X / 2, size.X / 2)
    local ez = math.clamp(lp.Z, -size.Z / 2, size.Z / 2)
    local edge = cf * Vector3.new(ex, size.Y / 2, ez)
    local out = hrp.Position - edge
    out = Vector3.new(out.X, 0, out.Z)
    if out.Magnitude < 1 then
        out = Vector3.new(0, 0, 1)
    end
    return edge + out.Unit * 80 + Vector3.new(0, 15, 0)
end
local function FindFreeNest(plot)
    if not plot then return nil end
    if LP:GetAttribute("NoNest") == true then return "NONEST" end
    local nests = plot:FindFirstChild("Nests")
    if not nests then return "NONEST" end
    for _, n in ipairs(nests:GetChildren()) do
        if n:GetAttribute("Unlocked") == true and not n:GetAttribute("Occupied") then
            return n
        end
    end
    return nil
end
local function ToolWeight(tool)
    local w = tonumber(tool:GetAttribute("Weight"))
    if not w then w = tonumber(tool:GetAttribute("EggWeight")) end
    if not w then w = tonumber(tool:GetAttribute("RealWeight")) end
    if not w then w = 1 end
    return w
end
local function BiggestEggTool()
    local best = nil
    local bestS = nil
    local char = LP.Character
    local bp = LP:FindFirstChildOfClass("Backpack")
    local function scan(container)
        if not container then return end
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") and t:HasTag("Egg") then
                local s = ShownKG(ToolWeight(t))
                if not bestS or s > bestS then
                    best = t
                    bestS = s
                end
            end
        end
    end
    scan(bp)
    scan(char)
    return best, bestS
end
local function EggReady(model)
    local cfg = EggsData[model.Name]
    local ed = model:FindFirstChild("EggData")
    local pt = nil
    local wt = nil
    if ed then
        pt = ed:FindFirstChild("PlaceTime")
        wt = ed:FindFirstChild("Weight")
    end
    if not cfg or not pt or pt.Value <= 0 then return false end
    local w = 1
    if wt then w = tonumber(wt.Value) or 1 end
    local total = General2.GrowthTimeFor(cfg.GrowthTime, w)
    local el = 0
    if model:GetAttribute("FlatGrow") == true then
        el = Workspace:GetServerTimeNow() - pt.Value
    else
        el = DayNight.GrowthElapsed(pt.Value)
    end
    return el >= total
end
local function BasketList()
    local b = LP:FindFirstChild("Basket")
    if b then return b:GetChildren() end
    return {}
end
local function Carrying()
    return #BasketList() > 0
end
local status = nil
local function UnequipAll()
    pcall(function()
        local char = LP.Character
        local hum = nil
        if char then hum = char:FindFirstChildOfClass("Humanoid") end
        if hum then hum:UnequipTools() end
    end)
end
local function SetStatus(s)
    if status then
        pcall(function() status.Text = s end)
    end
end

-- GUI
pcall(function()
    for _, v in ipairs(LP:WaitForChild("PlayerGui"):GetChildren()) do
        if v.Name == "AllInOne" then v:Destroy() end
    end
end)
local gui = Instance.new("ScreenGui")
gui.Name = "AllInOne"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = LP:WaitForChild("PlayerGui")
_G.AIO_Gui = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(210, 330)
frame.Position = UDim2.new(0, 12, 0, 60)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Visible = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local mini = Instance.new("TextButton")
mini.Name = "MinIcon"
mini.Size = UDim2.fromOffset(42, 42)
mini.Position = UDim2.new(0, 12, 1, -58)
mini.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
mini.TextColor3 = Color3.new(1, 1, 1)
mini.Font = Enum.Font.GothamBold
mini.TextSize = 16
mini.Text = "+"
mini.Active = true
mini.AutoButtonColor = true
mini.Visible = false
mini.ZIndex = 10
mini.Parent = gui
Instance.new("UICorner", mini).CornerRadius = UDim.new(1, 0)

local function ShowMenu()
    frame.Visible = true
    mini.Visible = false
end
local function HideMenu()
    frame.Visible = false
    mini.Visible = true
end
mini.MouseButton1Click:Connect(ShowMenu)
mini.Activated:Connect(ShowMenu)

do
    local UIS = game:GetService("UserInputService")
    local dragging = false
    local dragStart = nil
    local startPos = nil
    local moved = false
    mini.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            dragStart = input.Position
            startPos = mini.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - dragStart
            if d.Magnitude > 6 then moved = true end
            if moved then
                mini.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
        end
    end)
end

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -48, 0, 22)
title.Position = UDim2.new(0, 8, 0, 6)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Ride A Pet - Ethereal"
title.Parent = frame

local minB = Instance.new("TextButton")
minB.Size = UDim2.fromOffset(26, 22)
minB.Position = UDim2.new(1, -34, 0, 6)
minB.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
minB.TextColor3 = Color3.new(1, 1, 1)
minB.Font = Enum.Font.GothamBold
minB.TextSize = 14
minB.Text = "-"
minB.Parent = frame
Instance.new("UICorner", minB).CornerRadius = UDim.new(0, 6)
minB.Activated:Connect(HideMenu)
minB.MouseButton1Click:Connect(HideMenu)

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.new(0, 0, 0, 34)
scroll.Size = UDim2.new(1, 0, 1, -34)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new(0, 0, 0, 560)
scroll.Parent = frame

local function Label(txt, y, h)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -16, 0, h or 20)
    l.Position = UDim2.new(0, 8, 0, y)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.new(1, 1, 1)
    l.Font = Enum.Font.GothamBold
    l.TextSize = 13
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = txt
    l.Parent = scroll
    return l
end
local function Button(txt, y, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -16, 0, 28)
    b.Position = UDim2.new(0, 8, 0, y)
    b.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Text = txt
    b.Parent = scroll
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.Activated:Connect(cb)
    return b
end
local function Box(def, y, cb)
    local t = Instance.new("TextBox")
    t.Size = UDim2.new(1, -16, 0, 24)
    t.Position = UDim2.new(0, 8, 0, y)
    t.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    t.TextColor3 = Color3.new(1, 1, 1)
    t.Font = Enum.Font.Gotham
    t.TextSize = 13
    t.Text = tostring(def)
    t.ClearTextOnFocus = false
    t.Parent = scroll
    Instance.new("UICorner", t).CornerRadius = UDim.new(0, 6)
    t.FocusLost:Connect(function()
        local v = tonumber(t.Text)
        if v then
            cb(v)
            SaveCFG()
        else
            t.Text = tostring(def)
        end
    end)
    return t
end

status = Label("status: starting...", 0, 16)
status.TextColor3 = Color3.fromRGB(170, 255, 170)
status.TextSize = 12

local espB = nil
local autoB = nil
local placeB = nil
local hatchB = nil
local function Refresh()
    if espB then
        espB.Text = "ESP: " .. (ESP_ON and "ON" or "OFF")
        if ESP_ON then espB.BackgroundColor3 = Color3.fromRGB(40, 120, 60) else espB.BackgroundColor3 = Color3.fromRGB(45, 45, 55) end
    end
    if autoB then
        autoB.Text = "Auto: " .. (AUTO_ON and "ON" or "OFF")
        if AUTO_ON then autoB.BackgroundColor3 = Color3.fromRGB(40, 120, 60) else autoB.BackgroundColor3 = Color3.fromRGB(45, 45, 55) end
    end
    if placeB then
        placeB.Text = "Place egg: " .. (PLACE_ON and "ON" or "OFF")
        if PLACE_ON then placeB.BackgroundColor3 = Color3.fromRGB(40, 120, 60) else placeB.BackgroundColor3 = Color3.fromRGB(45, 45, 55) end
    end
    if hatchB then
        hatchB.Text = "Hatch egg: " .. (HATCH_ON and "ON" or "OFF")
        if HATCH_ON then hatchB.BackgroundColor3 = Color3.fromRGB(40, 120, 60) else hatchB.BackgroundColor3 = Color3.fromRGB(45, 45, 55) end
    end
end
espB = Button("ESP: OFF", 20, function()
    ESP_ON = not ESP_ON
    if not ESP_ON then
        for id, d in pairs(drawings) do
            pcall(function() d.Name:Remove() end)
            pcall(function() d.KG:Remove() end)
            pcall(function() d.Dist:Remove() end)
        end
        table.clear(drawings)
        for id, g in pairs(billboards) do
            pcall(function() g:Destroy() end)
        end
        table.clear(billboards)
    end
    Refresh()
    SaveCFG()
end)
autoB = Button("Auto: OFF", 52, function()
    AUTO_ON = not AUTO_ON
    if not AUTO_ON then
        moveTarget = nil
        mode = "HUNT"
        volcLeg = nil
    end
    Refresh()
    SaveCFG()
end)
placeB = Button("Place egg: OFF", 84, function()
    PLACE_ON = not PLACE_ON
    Refresh()
    SaveCFG()
end)
hatchB = Button("Hatch egg: OFF", 116, function()
    HATCH_ON = not HATCH_ON
    Refresh()
    SaveCFG()
end)
Label("KG (min pickup):", 148, 15)
Box(CFG.MIN_KG, 164, function(v) CFG.MIN_KG = v end)
Label("Go speed:", 194, 15)
Box(CFG.GO, 210, function(v)
    if v > 10 then CFG.GO = v end
end)
Label("Back speed:", 240, 15)
Box(CFG.BACK, 256, function(v)
    if v > 10 then CFG.BACK = v end
end)
scroll.CanvasSize = UDim2.new(0, 0, 0, 284)
Refresh()
SetStatus("status: ready")
print("[aio] build ok. drawing=" .. tostring(HAS_DRAWING))

-- stable mover
RunService.Heartbeat:Connect(function(dt)
    if not running then return end
    if not moveTarget then return end
    local hrp = GetHRP()
    if not hrp then return end
    local cur = hrp.Position
    local to = moveTarget - cur
    local dist = to.Magnitude
    if dist < 4 then return end
    local step = moveSpeed * math.min(dt, 0.05)
    if step > dist then step = dist end
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
    hrp.CFrame = CFrame.new(cur + to.Unit * step)
end)

task.spawn(function()
    while running do
        task.wait(1)
        if moveTarget then
            local char = LP.Character
            if char then
                pcall(function()
                    for _, p in ipairs(char:GetDescendants()) do
                        if p:IsA("BasePart") then p.CanCollide = false end
                    end
                end)
            end
        end
    end
end)

-- esp
local ETH = Color3.fromRGB(170, 170, 255)
local function ClearESP(id)
    local d = drawings[id]
    if d then
        pcall(function() d.Name.Visible = false end)
        pcall(function() d.KG.Visible = false end)
        pcall(function() d.Dist.Visible = false end)
        pcall(function() d.Name:Remove() end)
        pcall(function() d.KG:Remove() end)
        pcall(function() d.Dist:Remove() end)
        drawings[id] = nil
    end
    local g = billboards[id]
    if g then
        pcall(function() g:Destroy() end)
        billboards[id] = nil
    end
end
local function DrawBillboard(id, model, n, kgStr, distStr)
    local g = billboards[id]
    if not g then
        g = Instance.new("BillboardGui")
        g.Name = "AIO_ESP"
        g.Size = UDim2.new(0, 140, 0, 64)
        g.StudsOffset = Vector3.new(0, 5, 0)
        g.AlwaysOnTop = true
        g.MaxDistance = 6000
        local a = Instance.new("TextLabel")
        a.Name = "N"
        a.Size = UDim2.new(1, 0, 0, 22)
        a.BackgroundTransparency = 1
        a.Font = Enum.Font.GothamBold
        a.TextSize = 15
        a.TextColor3 = ETH
        a.TextStrokeTransparency = 0.3
        a.Parent = g
        local b = Instance.new("TextLabel")
        b.Name = "K"
        b.Size = UDim2.new(1, 0, 0, 20)
        b.Position = UDim2.new(0, 0, 0, 22)
        b.BackgroundTransparency = 1
        b.Font = Enum.Font.Gotham
        b.TextSize = 13
        b.TextColor3 = Color3.new(1, 1, 1)
        b.TextStrokeTransparency = 0.3
        b.Parent = g
        local c = Instance.new("TextLabel")
        c.Name = "D"
        c.Size = UDim2.new(1, 0, 0, 20)
        c.Position = UDim2.new(0, 0, 0, 42)
        c.BackgroundTransparency = 1
        c.Font = Enum.Font.Gotham
        c.TextSize = 13
        c.TextColor3 = Color3.new(0.7, 1, 0.7)
        c.TextStrokeTransparency = 0.3
        c.Parent = g
        g.Parent = LP:WaitForChild("PlayerGui")
        billboards[id] = g
    end
    local part = nil
    if model then part = model:FindFirstChildWhichIsA("BasePart", true) end
    if part then g.Adornee = part end
    g.N.Text = n
    g.K.Text = kgStr
    g.D.Text = distStr
    g.Enabled = true
end
task.spawn(function()
    while running do
        task.wait(0.2)
        if not ESP_ON then continue end
        local cam = Workspace.CurrentCamera
        if not cam then continue end
        local hrp = GetHRP()
        local hp = nil
        if hrp then hp = hrp.Position end
        local seen = {}
        for _, inst in ipairs(ActiveEggs:GetChildren()) do
            local n = inst:GetAttribute("Egg")
            local pa = inst:GetAttribute("Position")
            if n and pa and IsEthereal(n) then
                local priv = inst:GetAttribute("PrivateTo")
                if not (priv and priv ~= LP.UserId) and not HasClaimed(n, inst) then
                    local id = inst.Name
                    seen[id] = true
                    local wp, model = EggWorldPos(inst, n, pa)
                    local w = ShownKG(tonumber(inst:GetAttribute("Weight")) or 1)
                    local kgStr = Comma(w) .. " KG"
                    local distStr = "?"
                    if hp then distStr = tostring(math.floor((wp - hp).Magnitude + 0.5)) .. "m" end
                    if HAS_DRAWING then
                        local sp = nil
                        local ok = false
                        pcall(function()
                            sp, ok = cam:WorldToViewportPoint(wp)
                        end)
                        if sp and ok and sp.Z > 0 then
                            local d = drawings[id]
                            if not d then
                                local t1 = Drawing.new("Text")
                                t1.Size = 15
                                t1.Center = true
                                t1.Outline = true
                                t1.Color = ETH
                                local t2 = Drawing.new("Text")
                                t2.Size = 13
                                t2.Center = true
                                t2.Outline = true
                                t2.Color = Color3.new(1, 1, 1)
                                local t3 = Drawing.new("Text")
                                t3.Size = 13
                                t3.Center = true
                                t3.Outline = true
                                t3.Color = Color3.new(0.7, 1, 0.7)
                                d = {Name = t1, KG = t2, Dist = t3}
                                drawings[id] = d
                            end
                            d.Name.Position = Vector2.new(sp.X, sp.Y - 28)
                            d.Name.Text = n
                            d.Name.Visible = true
                            d.KG.Position = Vector2.new(sp.X, sp.Y - 12)
                            d.KG.Text = kgStr
                            d.KG.Visible = true
                            d.Dist.Position = Vector2.new(sp.X, sp.Y + 4)
                            d.Dist.Text = distStr
                            d.Dist.Visible = true
                        else
                            ClearESP(id)
                        end
                    else
                        DrawBillboard(id, model, n, kgStr, distStr)
                    end
                end
            end
        end
        for id, _ in pairs(drawings) do
            if not seen[id] then ClearESP(id) end
        end
        for id, _ in pairs(billboards) do
            if not seen[id] then ClearESP(id) end
        end
    end
end)

-- autohunt + return
task.spawn(function()
    while running do
        task.wait(0.5)
        local hrp = GetHRP()
        if not hrp then
            SetStatus("status: no character")
            continue
        end
        if Carrying() and mode ~= "RETURN" then
            mode = "RETURN"
            print("[aio] carrying, returning cap " .. tostring(CarryCap()))
        end
        if not AUTO_ON then
            moveTarget = nil
            SetStatus("status: auto off")
            continue
        end
        if mode == "RETURN" then
            if not Carrying() then
                mode = "HUNT"
                moveTarget = nil
                UnequipAll()
                lastCarriedShown = 0
                lastCarriedReal = 1
                lastCarriedName = ""
                volcLeg = nil
                SetStatus("status: deposited, unequipped")
                print("[aio] deposited, unequipped")
                continue
            end
            local pp = GetPlotPos()
            if IsVolcanic(lastCarriedName) then
                local outEnt = VolcanoEntrance()
                if outEnt then
                    local dOut = (outEnt - hrp.Position).Magnitude
                    if dOut > 30 then
                        moveSpeed = math.min(CFG.BACK, CarryCap())
                        moveTarget = outEnt
                        SetStatus("status: VOLC OUT " .. tostring(math.floor(dOut)) .. "m")
                        continue
                    end
                end
            end
            if pp then
                moveSpeed = math.min(CFG.BACK, CarryCap())
                local d = (pp - hrp.Position).Magnitude
                if d > 120 then
                    moveTarget = Vector3.new(pp.X, pp.Y + 70, pp.Z)
                else
                    moveTarget = pp
                end
                SetStatus("status: RETURN " .. tostring(math.floor(d + 0.5)) .. "m (" .. tostring(#BasketList()) .. " in basket)")
            else
                SetStatus("status: RETURN (plot?)")
            end
            continue
        end
        moveSpeed = CFG.GO
        local best = nil
        local bestS = nil
        local bestN = nil
        for _, inst in ipairs(ActiveEggs:GetChildren()) do
            local n = inst:GetAttribute("Egg")
            local pa = inst:GetAttribute("Position")
            if n and pa and IsEthereal(n) then
                local priv = inst:GetAttribute("PrivateTo")
                if not (priv and priv ~= LP.UserId) and not HasClaimed(n, inst) then
                    local w = ShownKG(tonumber(inst:GetAttribute("Weight")) or 1)
                    local drop = tonumber(inst:GetAttribute("DropEndsAt")) or 0
                    if drop <= Workspace:GetServerTimeNow() then
                        local cd = lastFire[inst.Name]
                        if not (cd and os.clock() - cd < 2) then
                            if w >= CFG.MIN_KG and (not bestS or w > bestS) then
                                best = inst
                                bestS = w
                                bestN = n
                            end
                        end
                    end
                end
            end
        end
        if not best then
            moveTarget = nil
            curEggId = nil
            SetStatus("status: HUNT (none)")
            continue
        end
        local pa = best:GetAttribute("Position")
        local rawWp, model = EggWorldPos(best, bestN, pa)
        local wpReal = rawWp + Vector3.new(0, 6, 0)
        local realDist = (wpReal - hrp.Position).Magnitude
        local ent = nil
        if IsVolcanic(bestN) then
            ent = VolcanoEntrance()
        end
        if curEggId ~= best.Name then
            curEggId = best.Name
            volcLeg = nil
            print("[aio] hunting: " .. tostring(bestN) .. " " .. tostring(math.floor(realDist)) .. "m " .. Comma(bestS) .. " KG")
            if IsVolcanic(bestN) and not ent then
                print("[aio] volcano not streamed, direct fly")
            end
        end
        if ent and volcLeg ~= "TOEGG" then
            local inside = LP:GetAttribute("InVolcano") == true
            if inside then
                volcLeg = "TOEGG"
            else
                volcLeg = "TOIN"
            end
        end
        if volcLeg == "TOIN" and ent then
            local dIn = (ent - hrp.Position).Magnitude
            if dIn > 30 then
                moveTarget = ent
                SetStatus("status: VOLC IN " .. tostring(math.floor(dIn)) .. "m")
                continue
            end
            volcLeg = "TOEGG"
        end
        if realDist > 16 then
            if curEggId ~= best.Name then
                curEggId = best.Name
                print("[aio] hunting: " .. tostring(bestN) .. " " .. tostring(math.floor(realDist)) .. "m " .. Comma(bestS) .. " KG")
            end
            if realDist > 120 then
                moveTarget = Vector3.new(wpReal.X, wpReal.Y + 70, wpReal.Z)
            else
                moveTarget = wpReal
            end
            SetStatus("status: HUNT " .. tostring(bestN) .. " " .. tostring(math.floor(realDist)) .. "m")
            continue
        end
        local wp = wpReal
        SetStatus("status: picking " .. tostring(bestN))
        moveTarget = nil
        lastFire[best.Name] = os.clock()
        lastCarriedShown = bestS
        lastCarriedName = bestN
        lastCarriedReal = tonumber(best:GetAttribute("Weight")) or 1
        local hrp2 = GetHRP()
        if hrp2 then
            pcall(function()
                hrp2.CFrame = CFrame.new(hrp2.Position, Vector3.new(wp.X, hrp2.Position.Y, wp.Z))
            end)
            task.wait(0.25)
        end
        local prompt = nil
        if model then prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true) end
        if prompt and prompt.Enabled then
            if fireproximityprompt then
                fireproximityprompt(prompt)
            else
                prompt:InputHoldBegin()
                task.wait((tonumber(prompt.HoldDuration) or 0) + 0.3)
                prompt:InputHoldEnd()
            end
            print("[aio] pickup (prompt): " .. tostring(bestN) .. " " .. Comma(bestS) .. " KG")
        else
            EggPickup:FireServer(best.Name)
            print("[aio] pickup (fallback): " .. tostring(bestN) .. " " .. Comma(bestS) .. " KG")
        end
        task.wait(1)
    end
end)

-- auto place: biggest egg tool -> free nest (skip if full)
task.spawn(function()
    while running do
        task.wait(2)
        if not PLACE_ON then continue end
        local plot = GetMyPlot()
        if not plot then continue end
        local nest = FindFreeNest(plot)
        if nest == nil then continue end
        local tool, shown = BiggestEggTool()
        if not tool then continue end
        if os.clock() - placeCD < 3 then continue end
        local char = LP.Character
        local hum = nil
        if char then hum = char:FindFirstChildOfClass("Humanoid") end
        if not hum then continue end
        SetStatus("status: PLACE " .. tostring(tool.Name) .. " " .. Comma(shown) .. " KG")
        pcall(function() hum:EquipTool(tool) end)
        task.wait(0.4)
        if tool.Parent ~= char then continue end
        if nest == "NONEST" then
            local base = plot:FindFirstChild("Baseplate")
            if base and base:IsA("BasePart") then
                local hx = base.Size.X / 2 - 4
                local hz = base.Size.Z / 2 - 4
                local pp = base.Position + Vector3.new(math.random(-hx, hx), 3, math.random(-hz, hz))
                placeCD = os.clock()
                EggPlacedR:FireServer({ PlantPosition = pp })
                print("[aio] placed (ground): " .. tostring(tool.Name) .. " " .. Comma(shown) .. " KG")
            end
        else
            placeCD = os.clock()
            EggPlacedR:FireServer({ NestId = nest.Name })
            print("[aio] placed: " .. tostring(tool.Name) .. " " .. Comma(shown) .. " KG nest " .. tostring(nest.Name))
        end
        task.wait(1)
        UnequipAll()
    end
end)

-- auto hatch
task.spawn(function()
    while running do
        task.wait(2)
        if not HATCH_ON then continue end
        local plot = GetMyPlot()
        local eggs = nil
        if plot then eggs = plot:FindFirstChild("Eggs") end
        if not eggs then continue end
        for _, m in ipairs(eggs:GetChildren()) do
            if not running or not HATCH_ON then break end
            local key = m:GetAttribute("EggKey")
            if key then
                if not m:HasTag("Hatching") then
                    local cd = hatchCD[key]
                    if not (cd and os.clock() - cd < 2) then
                        local okReady, ready = pcall(EggReady, m)
                        if okReady and ready then
                            hatchCD[key] = os.clock()
                            m:AddTag("Hatching")
                            HatchR:FireServer({ EggKey = key })
                            SetStatus("status: HATCH " .. tostring(m.Name))
                            print("[aio] hatch: " .. tostring(m.Name))
                            task.wait(1)
                        end
                    end
                end
            end
        end
    end
end)

print("[aio] build ok. drawing=" .. tostring(HAS_DRAWING))
