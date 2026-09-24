if _G.AIO_Off then _G.AIO_Off() return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

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

-- Config
getgenv().AIO = getgenv().AIO or {}
local CFG = getgenv().AIO
CFG.MIN_KG = CFG.MIN_KG or 2
CFG.GO = CFG.GO or CFG.FLY or 170
CFG.BACK = CFG.BACK or 340
local ESP_ON, AUTO_ON, PLACE_ON, HATCH_ON = false, false, false, false
CFG.ESP, CFG.AUTO, CFG.PLACE, CFG.HATCH = false, false, false, false

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
    while true do local k s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2") if k == 0 then break end end
    return s
end

local running = true
local drawings = {}
local lastFire = {}
local mode = "HUNT"
local moveTarget = nil
local moveSpeed = CFG.GO
local curEggId = nil

_G.AIO_Off = function()
    running = false
    moveTarget = nil
    for id, d in pairs(drawings) do pcall(function() d.Name:Remove() end) pcall(function() d.KG:Remove() end) pcall(function() d.Dist:Remove() end) end
    table.clear(drawings)
    pcall(function() _G.AIO_Gui:Destroy() end)
    _G.AIO_Off = nil
end

local function GetHRP() local c = LP.Character return c and c:FindFirstChild("HumanoidRootPart") or nil end
local function HasClaimed(eggName, inst)
    if inst and inst:GetAttribute("AdminSpawn") == true then return false end
    local c = LP:GetAttribute("CollectedEggs")
    if type(c) == "string" and c ~= "" and eggName then
        return string.find(c, eggName .. ",", 1, true) ~= nil
    end
    return false
end
local function IsEthereal(n) local d = EggsData[n] return d and d.Rarity == "Ethereal" end
local function EggWorldPos(inst, eggName, posAttr)
    local best, bestD, bestM
    for _, m in ipairs(RenderedEggs:GetChildren()) do
        if m.Name == eggName and m:IsA("Model") then
            local ok, piv = pcall(function() return m:GetPivot().Position end)
            if ok then local d = (piv - posAttr).Magnitude if d < 120 and (not bestD or d < bestD) then best, bestD, bestM = piv, d, m end end
        end
    end
    return best or posAttr, bestM
end
local function GetPlotPos()
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
            if ok and mine then
                local base = p:FindFirstChild("Baseplate")
                if base and base:IsA("BasePart") then return base.Position + Vector3.new(0, 5, 0) end
            end
        end
    end
    local ok, pos = pcall(function()
        local General = require(ReplicatedStorage:WaitForChild("GameServices"):WaitForChild("General"))
        local plot = General:GetPlot(LP)
        local base = plot and plot:FindFirstChild("Baseplate")
        return base and (base.Position + Vector3.new(0, 5, 0)) or nil
    end)
    if ok and pos then return pos end
    return nil
end
local function BasketList() local b = LP:FindFirstChild("Basket") return b and b:GetChildren() or {} end
local function Carrying() return #BasketList() > 0 end
local status = nil
local function UnequipAll()
    pcall(function()
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum:UnequipTools() end
    end)
end
local function SetStatus(s) if status then pcall(function() status.Text = s end) end end

-- auto place egg
local hatchCD = {}
local placeCD = 0
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
        or tonumber(tool:GetAttribute("EggWeight"))
        or tonumber(tool:GetAttribute("RealWeight"))
        or 1
    return w
end
local function BiggestEggTool()
    local best, bestS
    local char = LP.Character
    local bp = LP:FindFirstChildOfClass("Backpack")
    local function scan(container)
        if not container then return end
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") and t:HasTag("Egg") then
                local s = ShownKG(ToolWeight(t))
                if not bestS or s > bestS then best, bestS = t, s end
            end
        end
    end
    scan(bp) scan(char)
    return best, bestS
end
local function EggReady(model)
    local cfg = EggsData[model.Name]
    local ed = model:FindFirstChild("EggData")
    local pt = ed and ed:FindFirstChild("PlaceTime")
    local wt = ed and ed:FindFirstChild("Weight")
    if not cfg or not pt or pt.Value <= 0 then return false end
    local w = wt and tonumber(wt.Value) or 1
    local total = General2.GrowthTimeFor(cfg.GrowthTime, w)
    local el = model:GetAttribute("FlatGrow") == true
        and Workspace:GetServerTimeNow() - pt.Value
        or DayNight.GrowthElapsed(pt.Value)
    return el >= total
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
frame.Size = UDim2.fromOffset(210, 390)
frame.Position = UDim2.new(0, 12, 0.35, 0)
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
mini.TextColor3 = Color3.new(1,1,1)
mini.Font = Enum.Font.GothamBold
mini.TextSize = 16
mini.Text = "+"
mini.Active = true
mini.AutoButtonColor = true
mini.Visible = false
mini.ZIndex = 10
mini.Parent = gui
Instance.new("UICorner", mini).CornerRadius = UDim.new(1, 0)

local function ShowMenu() frame.Visible = true mini.Visible = false end
local function HideMenu() frame.Visible = false mini.Visible = true end
mini.MouseButton1Click:Connect(ShowMenu)
mini.Activated:Connect(ShowMenu)

do
    local UIS = game:GetService("UserInputService")
    local dragging, dragStart, startPos, moved = false, nil, nil, false
    mini.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dragStart, startPos = input.Position, mini.Position
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

local function Label(txt, y, h)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -16, 0, h or 20)
    l.Position = UDim2.new(0, 8, 0, y)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.new(1,1,1)
    l.Font = Enum.Font.GothamBold
    l.TextSize = 13
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = txt
    l.Parent = frame
    return l
end
local function Button(txt, y, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -16, 0, 30)
    b.Position = UDim2.new(0, 8, 0, y)
    b.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Text = txt
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.Activated:Connect(cb)
    return b
end
local function Box(def, y, cb)
    local t = Instance.new("TextBox")
    t.Size = UDim2.new(1, -16, 0, 26)
    t.Position = UDim2.new(0, 8, 0, y)
    t.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    t.TextColor3 = Color3.new(1,1,1)
    t.Font = Enum.Font.Gotham
    t.TextSize = 13
    t.Text = tostring(def)
    t.ClearTextOnFocus = false
    t.Parent = frame
    Instance.new("UICorner", t).CornerRadius = UDim.new(0, 6)
    t.FocusLost:Connect(function(enter) if enter then cb(tonumber(t.Text)) end end)
    return t
end

Label("Ride A Pet - Ethereal", 8)
local minB = Instance.new("TextButton")
minB.Size = UDim2.fromOffset(26, 22)
minB.Position = UDim2.new(1, -34, 0, 6)
minB.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
minB.TextColor3 = Color3.new(1,1,1)
minB.Font = Enum.Font.GothamBold
minB.TextSize = 14
minB.Text = "-"
minB.Parent = frame
Instance.new("UICorner", minB).CornerRadius = UDim.new(0, 6)
minB.Activated:Connect(HideMenu)
minB.MouseButton1Click:Connect(HideMenu)
status = Label("status: idle", 30, 16)
status.TextColor3 = Color3.fromRGB(170,255,170)
status.TextSize = 12

local espB, autoB, placeB, hatchB
local function Refresh()
    espB.Text = "ESP: " .. (ESP_ON and "ON" or "OFF")
    espB.BackgroundColor3 = ESP_ON and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(45, 45, 55)
    autoB.Text = "Auto: " .. (AUTO_ON and "ON" or "OFF")
    autoB.BackgroundColor3 = AUTO_ON and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(45, 45, 55)
    placeB.Text = "Place egg: " .. (PLACE_ON and "ON" or "OFF")
    placeB.BackgroundColor3 = PLACE_ON and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(45, 45, 55)
    hatchB.Text = "Hatch egg: " .. (HATCH_ON and "ON" or "OFF")
    hatchB.BackgroundColor3 = HATCH_ON and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(45, 45, 55)
    CFG.ESP, CFG.AUTO, CFG.PLACE, CFG.HATCH = ESP_ON, AUTO_ON, PLACE_ON, HATCH_ON
end
espB = Button("", 52, function() ESP_ON = not ESP_ON if not ESP_ON then for id, d in pairs(drawings) do pcall(function() d.Name:Remove() end) pcall(function() d.KG:Remove() end) pcall(function() d.Dist:Remove() end) end table.clear(drawings) end Refresh() end)
autoB = Button("", 86, function() AUTO_ON = not AUTO_ON if not AUTO_ON then moveTarget = nil mode = "HUNT" end Refresh() end)
placeB = Button("", 120, function() PLACE_ON = not PLACE_ON Refresh() end)
hatchB = Button("", 154, function() HATCH_ON = not HATCH_ON Refresh() end)
Label("KG (min to pickup):", 190, 16)
Box(CFG.MIN_KG, 206, function(v) if v then CFG.MIN_KG = v end end)
Label("Go speed (to egg):", 236, 16)
Box(CFG.GO, 252, function(v) if v and v > 10 then CFG.GO = v end end)
Label("Back speed (to plot):", 282, 16)
Box(CFG.BACK, 298, function(v) if v and v > 10 then CFG.BACK = v end end)
Label("tip: place=biggest first", 328, 14).TextColor3 = Color3.fromRGB(150,150,160)
Refresh()

-- fly mover (noclip applied in auto loop, not every frame)
RunService.Heartbeat:Connect(function(dt)
    if not running then return end
    if not moveTarget then return end
    local hrp = GetHRP()
    if not hrp then return end
    local cur = hrp.Position
    local to = moveTarget - cur
    local dist = to.Magnitude
    if dist < 4 then return end
    local step = math.min(dist, moveSpeed * math.min(dt, 0.05))
    pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero hrp.AssemblyAngularVelocity = Vector3.zero end)
    hrp.CFrame = CFrame.new(cur + to.Unit * step)
end)

-- cheap noclip, 1x/sec while moving
task.spawn(function()
    while running do
        task.wait(1)
        if moveTarget then
            local char = LP.Character
            if char then
                pcall(function() for _, p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = false end end end)
            end
        end
    end
end)

-- esp 
local ETH = Color3.fromRGB(170, 170, 255)
task.spawn(function()
    while running do
        task.wait(0.15)
        if not ESP_ON then continue end
        local seen = {}
        local hrp = GetHRP()
        local hp = hrp and hrp.Position
        for _, inst in ipairs(ActiveEggs:GetChildren()) do
        local n = inst:GetAttribute("Egg")
        local pa = inst:GetAttribute("Position")
        if not (n and pa) then continue end
        if not IsEthereal(n) then continue end
        if inst:GetAttribute("PrivateTo") and inst:GetAttribute("PrivateTo") ~= LP.UserId then continue end
        if HasClaimed(n, inst) then continue end
        local id = inst.Name
        seen[id] = true
        local wp = EggWorldPos(inst, n, pa)
        local sp, ok = Camera:WorldToViewportPoint(wp)
        if not ok or sp.Z <= 0 then continue end
        local d = drawings[id]
        if not d then
            local t1 = Drawing.new("Text") t1.Size = 15 t1.Center = true t1.Outline = true t1.Color = ETH
            local t2 = Drawing.new("Text") t2.Size = 13 t2.Center = true t2.Outline = true t2.Color = Color3.new(1,1,1)
            local t3 = Drawing.new("Text") t3.Size = 13 t3.Center = true t3.Outline = true t3.Color = Color3.new(0.7,1,0.7)
            d = {Name=t1, KG=t2, Dist=t3} drawings[id] = d
        end
        local w = ShownKG(tonumber(inst:GetAttribute("Weight")) or 1)
        d.Name.Position = Vector2.new(sp.X, sp.Y - 28) d.Name.Text = n d.Name.Visible = true
        d.KG.Position = Vector2.new(sp.X, sp.Y - 12) d.KG.Text = Comma(w) .. " KG" d.KG.Visible = true
        d.Dist.Position = Vector2.new(sp.X, sp.Y + 4) d.Dist.Text = hp and (math.floor((wp - hp).Magnitude + 0.5) .. "m") or "?m" d.Dist.Visible = true
    end
    for id, d in pairs(drawings) do if not seen[id] then pcall(function() d.Name:Remove() end) pcall(function() d.KG:Remove() end) pcall(function() d.Dist:Remove() end) drawings[id] = nil end end
    end
end)

-- auto get egg
task.spawn(function()
    while running do
        task.wait(0.5)
        local hrp = GetHRP()
        if not hrp then SetStatus("status: no character") continue end

        if Carrying() and mode ~= "RETURN" then
            mode = "RETURN"
            print("[aio] carrying, returning")
        end

        if not AUTO_ON then moveTarget = nil SetStatus("status: auto off") continue end

        if mode == "RETURN" then
            if not Carrying() then
                mode = "HUNT" moveTarget = nil
                UnequipAll()
                SetStatus("status: deposited, unequipped")
                print("[aio] deposited, unequipped")
                continue
            end
            local pp = GetPlotPos()
            if pp then
                moveSpeed = CFG.BACK
                local d = (pp - hrp.Position).Magnitude
                if d > 120 then
                    moveTarget = Vector3.new(pp.X, pp.Y + 70, pp.Z)
                else
                    moveTarget = pp
                end
                SetStatus("status: RETURN " .. math.floor(d + 0.5) .. "m (" .. #BasketList() .. " in basket)")
            else
                SetStatus("status: RETURN (plot?)")
            end
            continue
        end

        moveSpeed = CFG.GO
        local best, bestS, bestN
        for _, inst in ipairs(ActiveEggs:GetChildren()) do
            local n = inst:GetAttribute("Egg")
            local pa = inst:GetAttribute("Position")
            if not (n and pa) then continue end
            if not IsEthereal(n) then continue end
            if inst:GetAttribute("PrivateTo") and inst:GetAttribute("PrivateTo") ~= LP.UserId then continue end
            if HasClaimed(n, inst) then continue end
            local w = ShownKG(tonumber(inst:GetAttribute("Weight")) or 1)
            local drop = tonumber(inst:GetAttribute("DropEndsAt")) or 0
            if drop > Workspace:GetServerTimeNow() then continue end
            if lastFire[inst.Name] and os.clock() - lastFire[inst.Name] < 2 then continue end
            if w >= CFG.MIN_KG and (not bestS or w > bestS) then best, bestS, bestN = inst, w, n end
        end
        if not best then moveTarget = nil curEggId = nil SetStatus("status: HUNT (none)") continue end
        local pa = best:GetAttribute("Position")
        local rawWp, model = EggWorldPos(best, bestN, pa)
        local wpReal = rawWp + Vector3.new(0, 6, 0)
        local realDist = (wpReal - hrp.Position).Magnitude
        if realDist > 16 then
            if curEggId ~= best.Name then curEggId = best.Name print("[aio] hunting:", bestN, math.floor(realDist) .. "m", Comma(bestS) .. " KG") end
            if realDist > 120 then
                moveTarget = Vector3.new(wpReal.X, wpReal.Y + 70, wpReal.Z)
            else
                moveTarget = wpReal
            end
            SetStatus("status: HUNT " .. bestN .. " " .. math.floor(realDist) .. "m")
            continue
        end
        local wp = wpReal
        SetStatus("status: picking " .. bestN)
        moveTarget = nil
        lastFire[best.Name] = os.clock()
        do
            local hrp2 = GetHRP()
            if hrp2 then
                pcall(function() hrp2.CFrame = CFrame.new(hrp2.Position, Vector3.new(wp.X, hrp2.Position.Y, wp.Z)) end)
                task.wait(0.25)
            end
            local prompt = model and model:FindFirstChildWhichIsA("ProximityPrompt", true) or nil
            if prompt and prompt.Enabled then
                if fireproximityprompt then fireproximityprompt(prompt)
                else prompt:InputHoldBegin() task.wait((tonumber(prompt.HoldDuration) or 0) + 0.3) prompt:InputHoldEnd() end
                print("[aio] pickup (prompt):", bestN, Comma(bestS) .. " KG")
            else
                EggPickup:FireServer(best.Name)
                print("[aio] pickup (fallback):", bestN, Comma(bestS) .. " KG")
            end
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
        if not plot then SetStatus("status: PLACE (no plot)") continue end
        local nest = FindFreeNest(plot)
        if nest == nil then SetStatus("status: PLACE (plot full)") continue end
        local tool, shown = BiggestEggTool()
        if not tool then continue end
        if os.clock() - placeCD < 3 then continue end
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then continue end
        SetStatus("status: PLACE " .. tool.Name .. " " .. Comma(shown) .. " KG")
        pcall(function() hum:EquipTool(tool) end)
        task.wait(0.4)
        if tool.Parent ~= char then continue end
        if nest == "NONEST" then
            local base = plot:FindFirstChild("Baseplate")
            if base and base:IsA("BasePart") then
                local hx, hz = base.Size.X / 2 - 4, base.Size.Z / 2 - 4
                local pp = base.Position + Vector3.new(math.random(-hx, hx), 3, math.random(-hz, hz))
                placeCD = os.clock()
                EggPlacedR:FireServer({ PlantPosition = pp })
                print("[aio] placed (ground):", tool.Name, Comma(shown) .. " KG")
            end
        else
            placeCD = os.clock()
            EggPlacedR:FireServer({ NestId = nest.Name })
            print("[aio] placed:", tool.Name, Comma(shown) .. " KG", "nest", nest.Name)
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
        local eggs = plot and plot:FindFirstChild("Eggs")
        if not eggs then continue end
        for _, m in ipairs(eggs:GetChildren()) do
            if not running or not HATCH_ON then break end
            local key = m:GetAttribute("EggKey")
            if not key then continue end
            if m:HasTag("Hatching") then continue end
            if hatchCD[key] and os.clock() - hatchCD[key] < 2 then continue end
            local okReady, ready = pcall(EggReady, m)
            if okReady and ready then
                hatchCD[key] = os.clock()
                m:AddTag("Hatching")
                HatchR:FireServer({ EggKey = key })
                SetStatus("status: HATCH " .. m.Name)
                print("[aio] hatch:", m.Name)
                task.wait(1)
            end
        end
    end
end)

print("[aio] on. GO =", CFG.GO, "BACK =", CFG.BACK)
