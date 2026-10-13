-- Visuals V2
-- 2026-10-13: Cover direct/cached native throwable requests alongside the namecall route; expose transport checks.
-- 2026-10-13: Detach disabled throwable handlers and preserve native request forwarding across nested method checks.
-- 2026-10-13: Preserve native camera touch input; align throwable aim with the game's crosshair and GUI inset.
-- 2026-10-09: Preserve SprayPaint tool logic and native tool/emote playback with all FE presets.
-- 2026-10-09: Fixed MM2 skin choices: 357 guns and 631 knives, excluding defaults.
-- 2026-10-09: Original Voidscope/Matrixscope in MM2 and MMV; shared original scope hold.
-- 2026-10-09: Native MM2/MMV shift-lock throwable aiming, including touch inputs.
-- COMPLETE WEAPON RESTORE: latest fixes + Shoot Murderer + Guns & Knives + Gun+
-- COMPLETE BUILD: requested add-ons + accumulated fixes
-- Native Overdrive H addon

local shared = odh_shared_plugins

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TextChatService = game:GetService("TextChatService")

local mainTab = shared.CreateTab(
    "Visuals V2",
    "/0ludexioso/VisualsV2/refs/heads/main/icon"
)

-- Durable add-on settings.
-- writefile()/readfile() are rooted at the executor workspace, so this appears as:
-- ixry shizuka/plugins/workspace/VisualsV2_settings.json
-- It is intentionally separate from ODH's mm2.json.
local CFG_FILE = "VisualsV2_settings.json"
local ConfigData = {}
local PositionData = {}
local configResetting = false
local runtimeAlive = true

local env = {}
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then env = result end
end

-- Release a previous build's global aim handler before loading any settings
-- or cleaning up its callbacks. Legacy wrappers then pass native calls through.
local previousThrowableBridge=env.VisualsV2ThrowableAimBridge
if type(previousThrowableBridge)=="table" then previousThrowableBridge.handler=nil end

local read = type(readfile) == "function" and readfile or env.readfile
local write = type(writefile) == "function" and writefile or env.writefile
local exists = type(isfile) == "function" and isfile or env.isfile

-- A fresh install means this add-on has never created its own settings JSON.
-- On that first execution, feature toggles are seeded OFF except the requested
-- timer, statistic-color, and individual statistic display defaults.
local configExistedAtStart=false
if type(exists)=="function" then
    local ok,result=pcall(exists,CFG_FILE)
    configExistedAtStart=ok and result==true
elseif type(read)=="function" then
    configExistedAtStart=pcall(read,CFG_FILE)
end
local freshInstall=not configExistedAtStart
local defaultOnControls={
    aaIgnoreListEnabled=true,
    fireflyTimerEnabled=true,
    fireflyTimerColors=true,
    vv2FpsPingColors=true,
    vv2FpsPingShowFps=true,
    vv2FpsPingShowPing=true,
    vv2FpsPingShowPlayers=true,
}

local function isPositionKey(key)
    return type(key) == "string" and key:lower():find("position", 1, true) ~= nil
end

local function encodeConfigValue(value)
    if typeof(value) == "Color3" then
        return {color3 = {value.R, value.G, value.B}}
    end
    return value
end

local function decodeConfigValue(value, default)
    if typeof(default) == "Color3" and type(value) == "table" then
        local color = value.color3 or value
        if type(color) == "table" and #color >= 3 then
            local r, g, b = tonumber(color[1]), tonumber(color[2]), tonumber(color[3])
            if r and g and b then
                -- New config stores 0..1 Color3 channels. Old builds stored 0..255.
                if r > 1 or g > 1 or b > 1 then
                    return Color3.fromRGB(r, g, b)
                end
                return Color3.new(r, g, b)
            end
        end
    end
    return value
end

local function loadConfig()
    if type(read) ~= "function" then return end

    local found = true
    if type(exists) == "function" then
        local ok, result = pcall(exists, CFG_FILE)
        found = ok and result
    end
    if not found then return end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(read(CFG_FILE))
    end)
    if not ok or type(decoded) ~= "table" then return end

    -- Only load this add-on's standalone schema. Old flat settings are intentionally
    -- not imported so a fresh install starts with every feature disabled.
    if type(decoded.settings) == "table" then
        ConfigData = decoded.settings
    end
    if type(decoded.positions) == "table" then
        PositionData = decoded.positions
    end
end

local function saveConfig()
    if not runtimeAlive or type(write) ~= "function" then return false end
    local payload = {
        version = 2,
        settings = ConfigData,
        positions = PositionData,
    }
    return pcall(function()
        write(CFG_FILE, HttpService:JSONEncode(payload))
    end)
end

local function C(key, default)
    local source = isPositionKey(key) and PositionData or ConfigData
    local value = source[key]

    if value == nil then
        -- Feature toggles start disabled; the explicitly requested display
        -- defaults keep their enabled state. Style defaults are unchanged.
        local seededDefault=default
        if freshInstall and type(default)=="boolean" and not defaultOnControls[key] then
            seededDefault=false
        end

        if seededDefault ~= nil then
            source[key]=encodeConfigValue(seededDefault)
        end
        return seededDefault
    end

    return decodeConfigValue(value, default)
end

local function SetCfg(key, value)
    if configResetting or not runtimeAlive then return end
    local target = isPositionKey(key) and PositionData or ConfigData
    if value == nil then
        target[key] = nil
    else
        target[key] = encodeConfigValue(value)
    end
    saveConfig()
end

local function addToggle(section, name, defaultValue, callback)
    local state = false
    local rawToggle

    rawToggle = section:AddToggle(name, function(newState)
        state = not not newState
        callback(state)
    end)

    local controller = {}
    function controller:Set(newState)
        newState = not not newState
        if newState == state then return end

        -- ODH toggles expose a closure rather than Set(value). Try twice so a
        -- retained UI state from a previous execution cannot invert persistence.
        pcall(rawToggle)
        if state ~= newState then pcall(rawToggle) end
        if state ~= newState then
            state = newState
            callback(newState)
        end
    end
    function controller:Get()
        return state
    end

    if defaultValue then
        task.defer(function()
            controller:Set(true)
        end)
    end
    return controller
end

local function addDropdown(section, name, items, defaultValue, callback)
    local controller = section:AddDropdown(name, items, callback)
    if defaultValue then
        task.defer(function()
            local selected = false
            if controller and type(controller.Select)=="function" then
                selected = pcall(controller.Select, defaultValue)
                if not selected then
                    selected = pcall(function() controller:Select(defaultValue) end)
                end
            end
            -- Always apply the persisted value functionally even if this ODH
            -- build does not expose a working dropdown Select setter.
            callback(defaultValue)
        end)
    end
    return controller
end

loadConfig()

-- Clean up a previous execution of this build without changing its saved config.
-- This prevents old UI/effect connections from stacking when the addon is re-executed.
local previousRuntime = env.VisualsV2Runtime
if type(previousRuntime) == "table" and type(previousRuntime.Cleanup) == "function" then
    pcall(previousRuntime.Cleanup)
end

-- Runtime reset registry.
env.VisualsV2Runtime = {Resetters = {}}
env.VisualsV2Runtime.RegisterReset = function(callback)
    if type(callback) == "function" then table.insert(env.VisualsV2Runtime.Resetters, callback) end
end
env.VisualsV2Runtime.Cleanup = function()
    runtimeAlive = false
    configResetting = true
    for _, resetter in ipairs(env.VisualsV2Runtime.Resetters or {}) do pcall(resetter) end
    configResetting = false
end

-- Settings are already written immediately by SetCfg. These hooks add one
-- final best-effort save when teleporting/leaving so executor workspaces keep
-- the same config between servers and future executions.
pcall(function()
    LocalPlayer.OnTeleport:Connect(function()
        saveConfig()
    end)
end)
pcall(function()
    game:BindToClose(function()
        saveConfig()
    end)
end)

local player = LocalPlayer
local camera = workspace.CurrentCamera

-- =========================================================
-- COSMETIC: CHINESE HAT
-- =========================================================

;(function()
    local hatSection = mainTab:AddSection("Chinese Hat", "Cosmetic")

    local hatEnabled = C("hatEnabled", false)
    local legacyHatTransparency = tonumber(ConfigData["hatTransparency"])
    local hatTransparency = tonumber(C("hatTransparencyLevel", nil))
    if hatTransparency == nil then
        if legacyHatTransparency ~= nil then
            hatTransparency = math.clamp(math.floor((legacyHatTransparency * 4) + 1.5), 1, 5)
        else
            hatTransparency = 2
        end
    end
    hatTransparency = math.clamp(math.floor(hatTransparency + 0.5), 1, 5)
    local hatRainbow = C("hatRainbow", false)
    local hatDualColor = C("hatDualColor", false)
    local hatColor = C("hatColor",Color3.fromRGB(38,38,38))
    local hatColor1 = C("hatColor1",Color3.fromRGB(38,38,38))
    local hatColor2 = C("hatColor2",Color3.fromRGB(38,38,38))
    local hatSize = math.clamp(tonumber(C("hatSize", 1)) or 1, 1, 3)
    local hatHeight = C("hatHeight", 1.1)

    local hatPart = nil
    local hatConnection = nil
    local characterConnection = nil

    local function removeHat()
        if hatPart then
            pcall(function()
                hatPart:Destroy()
            end)
            hatPart = nil
        end

        local char = player.Character
        if char then
            local existing = char:FindFirstChild("VisualsV2_ChineseHat")
            if existing then
                existing:Destroy()
            end
        end
    end

    local function currentHatColor()
        if hatDualColor then
            local t = (math.sin(tick() * 2) + 1) / 2
            return hatColor1:Lerp(hatColor2, t)
        elseif hatRainbow then
            return Color3.fromHSV((tick() % 5) / 5, 1, 1)
        end
        return hatColor
    end

    local function updateHat()
        if not hatPart or not hatPart.Parent then return end

        hatPart.Transparency = ((math.clamp(tonumber(hatTransparency) or 2, 1, 5) - 1) / 4) * 0.8
        hatPart.Color = currentHatColor()

        local mesh = hatPart:FindFirstChildOfClass("SpecialMesh")
        if mesh then
            mesh.Scale = Vector3.new(
                2.4 * (tonumber(hatSize) or 1),
                1.6 * (tonumber(hatSize) or 1),
                2.4 * (tonumber(hatSize) or 1)
            )
        end

        local char = player.Character
        local head = char and char:FindFirstChild("Head")
        if head then
            hatPart.CFrame = head.CFrame * CFrame.new(0, tonumber(hatHeight) or 1.1, 0)
        end
    end

    local function addHat(char)
        if not hatEnabled or not char then return end

        local head = char:FindFirstChild("Head") or char:WaitForChild("Head", 5)
        if not head then return end

        removeHat()

        local hat = Instance.new("Part")
        hat.Name = "VisualsV2_ChineseHat"
        hat.Size = Vector3.new(1, 1, 1)
        hat.Transparency = ((math.clamp(tonumber(hatTransparency) or 2, 1, 5) - 1) / 4) * 0.8
        hat.Color = currentHatColor()
        hat.Material = Enum.Material.Neon
        hat.Anchored = false
        hat.CanCollide = false
        hat.CanTouch = false
        hat.CanQuery = false
        hat.CastShadow = false
        hat.Massless = true
        hat.CFrame = head.CFrame * CFrame.new(0, tonumber(hatHeight) or 1.1, 0)
        hat.Parent = char

        local mesh = Instance.new("SpecialMesh")
        mesh.MeshId = "rbxassetid://1033714"
        mesh.Scale = Vector3.new(
            2.4 * (tonumber(hatSize) or 1),
            1.6 * (tonumber(hatSize) or 1),
            2.4 * (tonumber(hatSize) or 1)
        )
        mesh.Parent = hat

        local weld = Instance.new("WeldConstraint")
        weld.Name = "VisualsV2_ChineseHatWeld"
        weld.Part0 = head
        weld.Part1 = hat
        weld.Parent = hat

        hatPart = hat
        updateHat()
    end

    local function refreshHatConnection()
        if hatConnection then
            hatConnection:Disconnect()
            hatConnection = nil
        end

        if hatEnabled then
            hatConnection = RunService.Heartbeat:Connect(function()
                if hatEnabled then
                    updateHat()
                end
            end)
        end
    end

    local enableToggle = addToggle(hatSection, "Enable Chinese Hat", hatEnabled, function(state)
        hatEnabled = state
        SetCfg("hatEnabled", state)

        if state then
            addHat(player.Character)
        else
            removeHat()
        end

        refreshHatConnection()
    end)

    local rainbowToggle = addToggle(hatSection, "Rainbow Hat", hatRainbow, function(state)
        hatRainbow = state
        SetCfg("hatRainbow", state)
        updateHat()
    end)

    local dualColorToggle = addToggle(hatSection, "Dual Color Hat", hatDualColor, function(state)
        hatDualColor = state
        SetCfg("hatDualColor", state)
        updateHat()
    end)

    hatSection:AddSlider("Transparency", 1, 5, hatTransparency, function(value)
        hatTransparency = math.clamp(math.floor((tonumber(value) or 2) + 0.5), 1, 5)
        SetCfg("hatTransparencyLevel", hatTransparency)
        updateHat()
    end)

    hatSection:AddColorpicker("Base Color", hatColor, function(color)
        hatColor = color
        SetCfg("hatColor", color)
        updateHat()
    end)

    hatSection:AddColorpicker("Color 1", hatColor1, function(color)
        hatColor1 = color
        SetCfg("hatColor1", color)
        updateHat()
    end)

    hatSection:AddColorpicker("Color 2", hatColor2, function(color)
        hatColor2 = color
        SetCfg("hatColor2", color)
        updateHat()
    end)

    hatSection:AddSlider("Hat Size", 1, 3, hatSize, function(value)
        hatSize = tonumber(value) or 1
        SetCfg("hatSize", hatSize)
        if hatEnabled then
            addHat(player.Character)
        end
    end)

    hatSection:AddSlider("Hat Height", 0.5, 3, hatHeight, function(value)
        hatHeight = tonumber(value) or 1.1
        SetCfg("hatHeight", hatHeight)
        if hatEnabled then
            addHat(player.Character)
        end
    end)

    characterConnection = player.CharacterAdded:Connect(function(char)
        if not hatEnabled then return end
        task.wait(1)
        if hatEnabled then
            addHat(char)
            refreshHatConnection()
        end
    end)

    env.VisualsV2Runtime.RegisterReset(function()
        enableToggle:Set(false)
        rainbowToggle:Set(false)
        dualColorToggle:Set(false)

        hatEnabled = false
        hatRainbow = false
        hatDualColor = false
        hatTransparency = 2
        hatColor = Color3.fromRGB(255, 255, 255)
        hatColor1 = Color3.fromRGB(255, 255, 255)
        hatColor2 = Color3.fromRGB(0, 0, 0)
        hatSize = 1
        hatHeight = 1.1

        if hatConnection then
            hatConnection:Disconnect()
            hatConnection = nil
        end

        removeHat()
    end)

    if hatEnabled and player.Character then
        task.defer(function()
            task.wait(0.5)
            if hatEnabled then
                addHat(player.Character)
                refreshHatConnection()
            end
        end)
    end
end)()

-- =========================================================

-- =========================================================
-- COSMETIC: MULTI HAT GIVER
-- =========================================================
;(function()
local section=mainTab:AddSection("Multi Hat Giver","Cosmetic")
local enabled=C("multiHatEnabled",false)
local names={"None","Dominus Astra","Valkyrie","Clockwork","Extreme Headphones","Fiery Horns","Frozen Horns","Poisoned Horns","Custom"}
local ids={["None"]=0,["Dominus Astra"]=162067148,["Valkyrie"]=1365767,["Clockwork"]=1235488,["Extreme Headphones"]=96079043,["Fiery Horns"]=215718515,["Frozen Horns"]=74891470,["Poisoned Horns"]=1744060292,["Custom"]=0}
local selected={C("multiHatSlot1","None"),C("multiHatSlot2","None"),C("multiHatSlot3","None")}
local custom={tonumber(C("multiHatCustom1",0)) or 0,tonumber(C("multiHatCustom2",0)) or 0,tonumber(C("multiHatCustom3",0)) or 0}
local active={}

local function clear(i)
    if active[i] then pcall(function() active[i]:Destroy() end); active[i]=nil end
end
local function findAttachment(root,name)
    for _,d in ipairs(root:GetDescendants()) do
        if d:IsA("Attachment") and d.Name==name then return d end
    end
end
local function apply(i)
    clear(i)
    if not enabled then return end
    local id=(selected[i]=="Custom") and custom[i] or (ids[selected[i]] or 0)
    if id==0 then return end
    local char=player.Character
    local head=char and char:FindFirstChild("Head")
    if not head then return end
    local ok,objects=pcall(function() return game:GetObjects("rbxassetid://"..id) end)
    if not ok or not objects or not objects[1] then return end
    local acc=objects[1]
    local handle=acc:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then pcall(function() acc:Destroy() end); return end
    acc.Name="VisualsV2_MultiHat_Slot"..i
    handle.CanCollide=false; handle.CanTouch=false; handle.CanQuery=false; handle.Massless=true
    acc.Parent=char
    local att=handle:FindFirstChildOfClass("Attachment")
    local weld=Instance.new("Weld")
    weld.Name="VisualsV2_MultiHatWeld"; weld.Part0=head; weld.Part1=handle
    if att then
        local parentAtt=findAttachment(head,att.Name)
        if parentAtt then weld.C0=parentAtt.CFrame; weld.C1=att.CFrame end
    else
        weld.C0=CFrame.new(0,0.5,0); weld.C1=acc.AttachmentPoint
    end
    weld.Parent=head
    active[i]=acc
end
local function refresh() for i=1,3 do apply(i) end end

local toggle=addToggle(section,"VV2 Enable Hat Giver",enabled,function(v)
    enabled=v; SetCfg("multiHatEnabled",v)
    if v then refresh() else for i=1,3 do clear(i) end end
end)
for i=1,3 do
    addDropdown(section,"VV2 Hat Slot "..i,names,selected[i],function(v)
        selected[i]=v; SetCfg("multiHatSlot"..i,v); if enabled then apply(i) end
    end)
    section:AddTextBox("VV2 Custom ID Slot "..i,function(v)
        local n=tonumber(v); if not n then return end
        custom[i]=n; SetCfg("multiHatCustom"..i,n)
        if enabled and selected[i]=="Custom" then apply(i) end
    end)
end
player.CharacterAdded:Connect(function() task.wait(1.5); if enabled then refresh() end end)
env.VisualsV2Runtime.RegisterReset(function()
    toggle:Set(false); enabled=false; for i=1,3 do clear(i) end
end)
if enabled then task.defer(refresh) end
end)()

-- =========================================================
-- COSMETIC: FE ANIMATIONS
-- 52 animation presets: 51 originally from 187 (aux0on/FE), plus R6 Gear Hold.
-- =========================================================
;(function()
local table_insert = table.insert

local Maid = {}
Maid.__index = Maid

function Maid.new()
    return setmetatable({_tasks = {}, _destroyed = false}, Maid)
end

function Maid:GiveTask(task)
    if self._destroyed then
        self:_cleanupTask(task)
        return
    end
    table_insert(self._tasks, task)
    return task
end

function Maid:GiveTasks(...)
    for _, task in ipairs({...}) do
        self:GiveTask(task)
    end
end

function Maid:_cleanupTask(task)
    local taskType = typeof(task)
    if taskType == "RBXScriptConnection" then
        task:Disconnect()
    elseif taskType == "Instance" then
        task:Destroy()
    elseif taskType == "function" then
        task()
    elseif taskType == "table" and type(task.Destroy) == "function" then
        task:Destroy()
    end
end

function Maid:DoCleaning()
    if self._destroyed then return end
    self._destroyed = true
    for _, task in ipairs(self._tasks) do
        self:_cleanupTask(task)
    end
    self._tasks = {}
end

function Maid:Destroy()
    self:DoCleaning()
end

local RootMaid = Maid.new()
local alive = true
local resetSection
env.VisualsV2Runtime.RegisterReset(function()
    if not runtimeAlive then
        alive = false
        RootMaid:DoCleaning()
    elseif resetSection then
        resetSection()
    end
end)

-- Preserve the standalone add-on's loader-version check without leaving a
-- second remote animation script or polling task running after re-execution.
local loaderCheck = task.spawn(function()
    local CoreGui = game:GetService("CoreGui")
    local target
    while alive and runtimeAlive and not target do
        target = CoreGui:FindFirstChild("@bubbles.elia", true)
        if not target then task.wait(0.1) end
    end
    if not alive or not runtimeAlive or not target or not target.Parent then return end
    local version = target.Parent:FindFirstChild("Version", true)
    while alive and runtimeAlive do
        if version and (version.Text:find("v3.2", 1, true) or version.Text:find("v3.5", 1, true)) then
            shared.kick("Malicious Loader Detected.\n\nUse the official script only available in discord.gg/overdrivehub")
            break
        end
        task.wait(0.1)
    end
end)
RootMaid:GiveTask(function() pcall(task.cancel, loaderCheck) end)





local feAnimSection = mainTab:AddSection("FE Animations", "Cosmetic")

local animPresets = {
            ["Default"] = nil,
            ["OG Rthro Run"] = {run = "http://www.roblox.com/asset/?id=9801814462"},
            ["Vampire"] = {
                idle1 = "http://www.roblox.com/asset/?id=1083445855",
                idle2 = "http://www.roblox.com/asset/?id=1083450166",
                walk  = "http://www.roblox.com/asset/?id=1083473930",
                run   = "http://www.roblox.com/asset/?id=1083462077",
                jump  = "http://www.roblox.com/asset/?id=1083455352",
                climb = "http://www.roblox.com/asset/?id=1083439238",
                fall  = "http://www.roblox.com/asset/?id=1083443587"
            },
            ["Hero"] = {
                idle1 = "http://www.roblox.com/asset/?id=616111295",
                idle2 = "http://www.roblox.com/asset/?id=616113536",
                walk  = "http://www.roblox.com/asset/?id=616122287",
                run   = "http://www.roblox.com/asset/?id=616117076",
                jump  = "http://www.roblox.com/asset/?id=616115533",
                climb = "http://www.roblox.com/asset/?id=616104706",
                fall  = "http://www.roblox.com/asset/?id=616108001"
            },
            ["Zombie Classic"] = {
                idle1 = "http://www.roblox.com/asset/?id=616158929",
                idle2 = "http://www.roblox.com/asset/?id=616160636",
                walk  = "http://www.roblox.com/asset/?id=616168032",
                run   = "http://www.roblox.com/asset/?id=616163682",
                jump  = "http://www.roblox.com/asset/?id=616161997",
                climb = "http://www.roblox.com/asset/?id=616156119",
                fall  = "http://www.roblox.com/asset/?id=616157476"
            },
            ["Mage"] = {
                idle1 = "http://www.roblox.com/asset/?id=707742142",
                idle2 = "http://www.roblox.com/asset/?id=707855907",
                walk  = "http://www.roblox.com/asset/?id=707897309",
                run   = "http://www.roblox.com/asset/?id=707861613",
                jump  = "http://www.roblox.com/asset/?id=707853694",
                climb = "http://www.roblox.com/asset/?id=707826056",
                fall  = "http://www.roblox.com/asset/?id=707829716"
            },
            ["Ghost"] = {
                idle1 = "http://www.roblox.com/asset/?id=616006778",
                idle2 = "http://www.roblox.com/asset/?id=616008087",
                walk  = "http://www.roblox.com/asset/?id=616010382",
                run   = "http://www.roblox.com/asset/?id=616013216",
                jump  = "http://www.roblox.com/asset/?id=616008936",
                climb = "http://www.roblox.com/asset/?id=616003713",
                fall  = "http://www.roblox.com/asset/?id=616005863"
            },
            ["Elder"] = {
                idle1 = "http://www.roblox.com/asset/?id=845397899",
                idle2 = "http://www.roblox.com/asset/?id=845400520",
                walk  = "http://www.roblox.com/asset/?id=845403856",
                run   = "http://www.roblox.com/asset/?id=845386501",
                jump  = "http://www.roblox.com/asset/?id=845398858",
                climb = "http://www.roblox.com/asset/?id=845392038",
                fall  = "http://www.roblox.com/asset/?id=845396048"
            },
            ["Levitation"] = {
                idle1 = "http://www.roblox.com/asset/?id=616006778",
                idle2 = "http://www.roblox.com/asset/?id=616008087",
                walk  = "http://www.roblox.com/asset/?id=616013216",
                run   = "http://www.roblox.com/asset/?id=616010382",
                jump  = "http://www.roblox.com/asset/?id=616008936",
                climb = "http://www.roblox.com/asset/?id=616003713",
                fall  = "http://www.roblox.com/asset/?id=616005863"
            },
            ["Astronaut"] = {
                idle1 = "http://www.roblox.com/asset/?id=891621366",
                idle2 = "http://www.roblox.com/asset/?id=891633237",
                walk  = "http://www.roblox.com/asset/?id=891667138",
                run   = "http://www.roblox.com/asset/?id=891636393",
                jump  = "http://www.roblox.com/asset/?id=891627522",
                climb = "http://www.roblox.com/asset/?id=891609353",
                fall  = "http://www.roblox.com/asset/?id=891617961"
            },
            ["Ninja"] = {
                idle1 = "http://www.roblox.com/asset/?id=656117400",
                idle2 = "http://www.roblox.com/asset/?id=656118341",
                walk  = "http://www.roblox.com/asset/?id=656121766",
                run   = "http://www.roblox.com/asset/?id=656118852",
                jump  = "http://www.roblox.com/asset/?id=656117878",
                climb = "http://www.roblox.com/asset/?id=656114359",
                fall  = "http://www.roblox.com/asset/?id=656115606"
            },
            ["Werewolf"] = {
                idle1 = "http://www.roblox.com/asset/?id=1083195517",
                idle2 = "http://www.roblox.com/asset/?id=1083214717",
                walk  = "http://www.roblox.com/asset/?id=1083178339",
                run   = "http://www.roblox.com/asset/?id=1083216690",
                jump  = "http://www.roblox.com/asset/?id=1083218792",
                climb = "http://www.roblox.com/asset/?id=1083182000",
                fall  = "http://www.roblox.com/asset/?id=1083189019"
            },
            ["Cartoon"] = {
                idle1 = "http://www.roblox.com/asset/?id=742637544",
                idle2 = "http://www.roblox.com/asset/?id=742638445",
                walk  = "http://www.roblox.com/asset/?id=742640026",
                run   = "http://www.roblox.com/asset/?id=742638842",
                jump  = "http://www.roblox.com/asset/?id=742637942",
                climb = "http://www.roblox.com/asset/?id=742636889",
                fall  = "http://www.roblox.com/asset/?id=742637151"
            },
            ["Pirate"] = {
                idle1 = "http://www.roblox.com/asset/?id=750781874",
                idle2 = "http://www.roblox.com/asset/?id=750782770",
                walk  = "http://www.roblox.com/asset/?id=750785693",
                run   = "http://www.roblox.com/asset/?id=750783738",
                jump  = "http://www.roblox.com/asset/?id=750782230",
                climb = "http://www.roblox.com/asset/?id=750779899",
                fall  = "http://www.roblox.com/asset/?id=750780242"
            },
            ["Sneaky"] = {
                idle1 = "http://www.roblox.com/asset/?id=1132473842",
                idle2 = "http://www.roblox.com/asset/?id=1132477671",
                walk  = "http://www.roblox.com/asset/?id=1132510133",
                run   = "http://www.roblox.com/asset/?id=1132494274",
                jump  = "http://www.roblox.com/asset/?id=1132489853",
                climb = "http://www.roblox.com/asset/?id=1132461372",
                fall  = "http://www.roblox.com/asset/?id=1132469004"
            },
            ["Toy"] = {
                idle1 = "http://www.roblox.com/asset/?id=782841498",
                idle2 = "http://www.roblox.com/asset/?id=782845736",
                walk  = "http://www.roblox.com/asset/?id=782843345",
                run   = "http://www.roblox.com/asset/?id=782842708",
                jump  = "http://www.roblox.com/asset/?id=782847020",
                climb = "http://www.roblox.com/asset/?id=782843869",
                fall  = "http://www.roblox.com/asset/?id=782846423"
            },
            ["Knight"] = {
                idle1 = "http://www.roblox.com/asset/?id=657595757",
                idle2 = "http://www.roblox.com/asset/?id=657568135",
                walk  = "http://www.roblox.com/asset/?id=657552124",
                run   = "http://www.roblox.com/asset/?id=657564596",
                jump  = "http://www.roblox.com/asset/?id=658409194",
                climb = "http://www.roblox.com/asset/?id=658360781",
                fall  = "http://www.roblox.com/asset/?id=657600338"
            },
            ["Confident"] = {
                idle1 = "http://www.roblox.com/asset/?id=1069977950",
                idle2 = "http://www.roblox.com/asset/?id=1069987858",
                walk  = "http://www.roblox.com/asset/?id=1070017263",
                run   = "http://www.roblox.com/asset/?id=1070001516",
                jump  = "http://www.roblox.com/asset/?id=1069984524",
                climb = "http://www.roblox.com/asset/?id=1069946257",
                fall  = "http://www.roblox.com/asset/?id=1069973677"
            },
            ["Popstar"] = {
                idle1 = "http://www.roblox.com/asset/?id=1212900985",
                idle2 = "http://www.roblox.com/asset/?id=1212900985",
                walk  = "http://www.roblox.com/asset/?id=1212980338",
                run   = "http://www.roblox.com/asset/?id=1212980348",
                jump  = "http://www.roblox.com/asset/?id=1212954642",
                climb = "http://www.roblox.com/asset/?id=1213044953",
                fall  = "http://www.roblox.com/asset/?id=1212900995"
            },
            ["Princess"] = {
                idle1 = "http://www.roblox.com/asset/?id=941003647",
                idle2 = "http://www.roblox.com/asset/?id=941013098",
                walk  = "http://www.roblox.com/asset/?id=941028902",
                run   = "http://www.roblox.com/asset/?id=941015281",
                jump  = "http://www.roblox.com/asset/?id=941008832",
                climb = "http://www.roblox.com/asset/?id=940996062",
                fall  = "http://www.roblox.com/asset/?id=941000007"
            },
            ["Cowboy"] = {
                idle1 = "http://www.roblox.com/asset/?id=1014390418",
                idle2 = "http://www.roblox.com/asset/?id=1014398616",
                walk  = "http://www.roblox.com/asset/?id=1014421541",
                run   = "http://www.roblox.com/asset/?id=1014401683",
                jump  = "http://www.roblox.com/asset/?id=1014394726",
                climb = "http://www.roblox.com/asset/?id=1014380606",
                fall  = "http://www.roblox.com/asset/?id=1014384571"
            },
            ["Patrol"] = {
                idle1 = "http://www.roblox.com/asset/?id=1149612882",
                idle2 = "http://www.roblox.com/asset/?id=1150842221",
                walk  = "http://www.roblox.com/asset/?id=1151231493",
                run   = "http://www.roblox.com/asset/?id=1150967949",
                jump  = "http://www.roblox.com/asset/?id=1150944216",
                climb = "http://www.roblox.com/asset/?id=1148811837",
                fall  = "http://www.roblox.com/asset/?id=1148863382"
            },
            ["Zombie FE"] = {
                idle1 = "http://www.roblox.com/asset/?id=3489171152",
                idle2 = "http://www.roblox.com/asset/?id=3489171152",
                walk  = "http://www.roblox.com/asset/?id=3489174223",
                run   = "http://www.roblox.com/asset/?id=3489173414",
                jump  = "http://www.roblox.com/asset/?id=616161997",
                climb = "http://www.roblox.com/asset/?id=616156119",
                fall  = "http://www.roblox.com/asset/?id=616157476"
            },
            ["Catwalk Glam"] = {
                idle1 = "http://www.roblox.com/asset/?id=133806214992291",
                idle2 = "http://www.roblox.com/asset/?id=133806214992291",
                walk  = "http://www.roblox.com/asset/?id=109168724482748",
                run   = "http://www.roblox.com/asset/?id=81024476153754",
                jump  = "http://www.roblox.com/asset/?id=116936326516985",
                climb = "http://www.roblox.com/asset/?id=119377220967554",
                fall  = "http://www.roblox.com/asset/?id=92294537340807"
            },
            ["Amazon Unboxed"] = {
                idle1 = "http://www.roblox.com/asset/?id=98281136301627",
                idle2 = "http://www.roblox.com/asset/?id=98281136301627",
                walk  = "http://www.roblox.com/asset/?id=90478085024465",
                run   = "http://www.roblox.com/asset/?id=134824450619865",
                jump  = "http://www.roblox.com/asset/?id=121454505477205",
                climb = "http://www.roblox.com/asset/?id=121145883950231",
                fall  = "http://www.roblox.com/asset/?id=94788218468396"
            },
            ["Glow Motion"] = {
                idle1 = "https://www.roblox.com/asset/?id=137764781910579",
                idle2 = "https://www.roblox.com/asset/?id=137764781910579",
                walk  = "http://www.roblox.com/asset/?id=85809016093530",
                run   = "http://www.roblox.com/asset/?id=101925097435036",
                jump  = "http://www.roblox.com/asset/?id=74159004634379",
                climb = "http://www.roblox.com/asset/?id=108236155509584",
                fall  = "https://www.roblox.com/asset/?id=98070939608691"
            },
            ["Bubbly"] = {
                idle1 = "https://www.roblox.com/asset/?id=10921054344",
                idle2 = "https://www.roblox.com/asset/?id=10921054344",
                walk  = "http://www.roblox.com/asset/?id=10980888364",
                run   = "http://www.roblox.com/asset/?id=10921057244",
                jump  = "http://www.roblox.com/asset/?id=10921062673",
                climb = "http://www.roblox.com/asset/?id=10921053544",
                fall  = "https://www.roblox.com/asset/?id=10921061530"
            },
            ["Adidas Comm"] = {
                idle1 = "https://www.roblox.com/asset/?id=122257458498464",
                idle2 = "https://www.roblox.com/asset/?id=122257458498464",
                walk  = "http://www.roblox.com/asset/?id=122150855457006",
                run   = "http://www.roblox.com/asset/?id=82598234841035",
                jump  = "http://www.roblox.com/asset/?id=75290611992385",
                climb = "http://www.roblox.com/asset/?id=88763136693023",
                fall  = "https://www.roblox.com/asset/?id=98600215928904"
            },
            ["KATSEYE"] = {
                idle1 = "https://www.roblox.com/asset/?id=108187809145790",
                idle2 = "https://www.roblox.com/asset/?id=108187809145790",
                walk  = "http://www.roblox.com/asset/?id=99182913548783",
                run   = "http://www.roblox.com/asset/?id=73117360545482",
                jump  = "http://www.roblox.com/asset/?id=103632305262747",
                climb = "http://www.roblox.com/asset/?id=106213237973858",
                fall  = "https://www.roblox.com/asset/?id=127802717128367"
            },
            ["Wicked Popular"] = {
                idle1 = "https://www.roblox.com/asset/?id=118832222982049",
                idle2 = "https://www.roblox.com/asset/?id=118832222982049",
                walk  = "http://www.roblox.com/asset/?id=92072849924640",
                run   = "http://www.roblox.com/asset/?id=72301599441680",
                jump  = "http://www.roblox.com/asset/?id=104325245285198",
                climb = "http://www.roblox.com/asset/?id=131326830509784",
                fall  = "https://www.roblox.com/asset/?id=121152442762481"
            },
            ["Dizzy"] = {
                idle1 = "http://www.roblox.com/asset/?id=132806359718468",
                idle2 = "http://www.roblox.com/asset/?id=132806359718468",
                walk  = "http://www.roblox.com/asset/?id=110106034100313",
                run   = "http://www.roblox.com/asset/?id=138305342272849",
                jump  = "http://www.roblox.com/asset/?id=108564434408211",
                climb = "http://www.roblox.com/asset/?id=93550710314258",
                fall  = "http://www.roblox.com/asset/?id=138967706335414"
            },
            ["WDTL"] = {
                idle1 = "http://www.roblox.com/asset/?id=92849173543269",
                idle2 = "http://www.roblox.com/asset/?id=92849173543269",
                walk  = "http://www.roblox.com/asset/?id=73718308412641",
                run   = "http://www.roblox.com/asset/?id=135515454877967",
                jump  = "http://www.roblox.com/asset/?id=78508480717326",
                climb = "http://www.roblox.com/asset/?id=129447497744818",
                fall  = "http://www.roblox.com/asset/?id=78147885297412"
            },
            ["Billie Eilish"] = {
                idle1 = "http://www.roblox.com/asset/?id=102934602884410",
                idle2 = "http://www.roblox.com/asset/?id=102934602884410",
                walk  = "http://www.roblox.com/asset/?id=81877886552514",
                run   = "http://www.roblox.com/asset/?id=100920560634123",
                jump  = "http://www.roblox.com/asset/?id=117602630922781",
                climb = "http://www.roblox.com/asset/?id=117873469361430",
                fall  = "http://www.roblox.com/asset/?id=81072141180299"
            },
            ["Cute Bouncy"] = {
                idle1 = "http://www.roblox.com/asset/?id=88464649697812",
                idle2 = "http://www.roblox.com/asset/?id=88464649697812",
                walk  = "http://www.roblox.com/asset/?id=98713727778027",
                run   = "http://www.roblox.com/asset/?id=133955346539948",
                jump  = "http://www.roblox.com/asset/?id=124147147418885",
                climb = "http://www.roblox.com/asset/?id=95542189442725",
                fall  = "http://www.roblox.com/asset/?id=128620818122982"
            },
            ["Cute"] = {
                idle1 = "http://www.roblox.com/asset/?id=85735421117197",
                idle2 = "http://www.roblox.com/asset/?id=85735421117197",
                walk  = "http://www.roblox.com/asset/?id=140409718187215",
                run   = "http://www.roblox.com/asset/?id=118375157537412",
                jump  = "http://www.roblox.com/asset/?id=132381016103721",
                climb = "http://www.roblox.com/asset/?id=86318575131600",
                fall  = "http://www.roblox.com/asset/?id=77496925287217"
            },
            ["Jolly"] = {
                idle1 = "http://www.roblox.com/asset/?id=136145727878709",
                idle2 = "http://www.roblox.com/asset/?id=136145727878709",
                walk  = "http://www.roblox.com/asset/?id=83277136078444",
                run   = "http://www.roblox.com/asset/?id=124419804298310",
                jump  = "http://www.roblox.com/asset/?id=122115816220842",
                climb = "http://www.roblox.com/asset/?id=107190574095036",
                fall  = "http://www.roblox.com/asset/?id=85263802503331"
            },
            ["Cute Kawaii"] = {
                idle1 = "http://www.roblox.com/asset/?id=72311682331639",
                idle2 = "http://www.roblox.com/asset/?id=72311682331639",
                walk  = "http://www.roblox.com/asset/?id=107212872423561",
                run   = "http://www.roblox.com/asset/?id=118582510545072",
                jump  = "http://www.roblox.com/asset/?id=112952548321695",
                climb = "http://www.roblox.com/asset/?id=126383408493776",
                fall  = "http://www.roblox.com/asset/?id=83307333809322"
            },
            ["Doll 3.0"] = {
                idle1 = "http://www.roblox.com/asset/?id=83032187271383",
                idle2 = "http://www.roblox.com/asset/?id=83032187271383",
                walk  = "http://www.roblox.com/asset/?id=78434960966537",
                run   = "http://www.roblox.com/asset/?id=129768396663808",
                jump  = "http://www.roblox.com/asset/?id=75369057994828",
                climb = "http://www.roblox.com/asset/?id=112371892133970",
                fall  = "http://www.roblox.com/asset/?id=81027444073311"
            },
            ["Victoria Model"] = {
                idle1 = "http://www.roblox.com/asset/?id=132069965396465",
                idle2 = "http://www.roblox.com/asset/?id=132069965396465",
                walk  = "http://www.roblox.com/asset/?id=84814915379579",
                run   = "http://www.roblox.com/asset/?id=84814915379579",
                jump  = "http://www.roblox.com/asset/?id=78163261581163",
                climb = "http://www.roblox.com/asset/?id=87772134905508",
                fall  = "http://www.roblox.com/asset/?id=110073924253388"
            },
            ["Bike/Bicyclist"] = {
                idle1 = "http://www.roblox.com/asset/?id=126390120399173",
                idle2 = "http://www.roblox.com/asset/?id=136791517336633",
                walk  = "http://www.roblox.com/asset/?id=98707881660541",
                run   = "http://www.roblox.com/asset/?id=102775737211919",
                jump  = "http://www.roblox.com/asset/?id=129144847881258",
                climb = "http://www.roblox.com/asset/?id=88267082364595",
                fall  = "http://www.roblox.com/asset/?id=110684787086498"
            },
            ["Animal"] = {
                idle1 = "http://www.roblox.com/asset/?id=128838183008466",
                idle2 = "http://www.roblox.com/asset/?id=99689776099970",
                walk  = "http://www.roblox.com/asset/?id=112238064449133",
                run   = "http://www.roblox.com/asset/?id=97412731442167",
                jump  = "http://www.roblox.com/asset/?id=123565665274439",
                climb = "http://www.roblox.com/asset/?id=75085836535654",
                fall  = "http://www.roblox.com/asset/?id=124705831982259"
            },
            ["It-Girl Essential Model"] = {
                idle1 = "http://www.roblox.com/asset/?id=132232079260125",
                idle2 = "http://www.roblox.com/asset/?id=102440789796215",
                walk  = "http://www.roblox.com/asset/?id=86579666661215",
                run   = "http://www.roblox.com/asset/?id=83336349930143",
                jump  = "http://www.roblox.com/asset/?id=103382156539106",
                climb = "http://www.roblox.com/asset/?id=77385815954046",
                fall  = "http://www.roblox.com/asset/?id=127262648208409"
            },
            ["Oldschool"] = {
                idle1 = "http://www.roblox.com/asset/?id=10921230744",
                idle2 = "http://www.roblox.com/asset/?id=10921232093",
                walk  = "http://www.roblox.com/asset/?id=10921244891",
                run   = "http://www.roblox.com/asset/?id=10921240218",
                jump  = "http://www.roblox.com/asset/?id=10921242013",
                climb = "http://www.roblox.com/asset/?id=10921229866",
                fall  = "http://www.roblox.com/asset/?id=10921241244"
            },
            ["Spider"] = {
                idle1 = "http://www.roblox.com/asset/?id=112316814377814",
                idle2 = "http://www.roblox.com/asset/?id=103439018552145",
                walk  = "http://www.roblox.com/asset/?id=109976439277879",
                run   = "http://www.roblox.com/asset/?id=119985832593347",
                jump  = "http://www.roblox.com/asset/?id=87979233462906",
                climb = "http://www.roblox.com/asset/?id=119278342251995",
                fall  = "http://www.roblox.com/asset/?id=71112238570777"
            },
            ["Joy"] = {
                idle1 = "http://www.roblox.com/asset/?id=119957475250242",
                idle2 = "http://www.roblox.com/asset/?id=101200477339169",
                walk  = "http://www.roblox.com/asset/?id=112597572150963",
                run   = "http://www.roblox.com/asset/?id=96521659811743",
                jump  = "http://www.roblox.com/asset/?id=82500357520736",
                climb = "http://www.roblox.com/asset/?id=110061716873830",
                fall  = "http://www.roblox.com/asset/?id=132095139090357"
            },
            ["Flying Aura"] = {
                idle1 = "http://www.roblox.com/asset/?id=122426844584505",
                idle2 = "http://www.roblox.com/asset/?id=122426844584505",
                walk  = "http://www.roblox.com/asset/?id=83077254246622",
                run   = "http://www.roblox.com/asset/?id=77053251062908",
                jump  = "http://www.roblox.com/asset/?id=125422018244301",
                climb = "http://www.roblox.com/asset/?id=95973965948476",
                fall  = "http://www.roblox.com/asset/?id=109790195947848"
            },
                        
            ["FHA V2"] = {
                idle1 = "http://www.roblox.com/asset/?id=77320840005481",
                idle2 = "http://www.roblox.com/asset/?id=77320840005481",
                walk  = "http://www.roblox.com/asset/?id=134493251445479",
                run   = "http://www.roblox.com/asset/?id=122214533401932",
                jump  = "http://www.roblox.com/asset/?id=80078165493816",
                climb = "http://www.roblox.com/asset/?id=114562994724647",
                fall  = "http://www.roblox.com/asset/?id=98383265864436"
            },
           
            ["Silent Nurse"] = {
                idle1 = "http://www.roblox.com/asset/?id=111047244862844",
                idle2 = "http://www.roblox.com/asset/?id=111047244862844",
                walk  = "http://www.roblox.com/asset/?id=94196382152901",
                run   = "http://www.roblox.com/asset/?id=94196382152901",
                jump  = "http://www.roblox.com/asset/?id=106098057235980",
                climb = "http://www.roblox.com/asset/?id=108985375609705",
                fall  = "http://www.roblox.com/asset/?id=131579609334755"
            },

            ["Supermodel"] = {
                idle1 = "http://www.roblox.com/asset/?id=91917730726110",
                idle2 = "http://www.roblox.com/asset/?id=91917730726110",
                walk  = "http://www.roblox.com/asset/?id=90320132970213",
                run   = "http://www.roblox.com/asset/?id=112051258179255",
                jump  = "http://www.roblox.com/asset/?id=91931403363860",
                climb = "http://www.roblox.com/asset/?id=82728029306069",
                fall  = "http://www.roblox.com/asset/?id=119173466228299"
            },
            
            ["Enchanted Fairy"] = {
                idle1 = "http://www.roblox.com/asset/?id=73650178233095",
                idle2 = "http://www.roblox.com/asset/?id=73650178233095",
                walk  = "http://www.roblox.com/asset/?id=94547195663763",
                run   = "http://www.roblox.com/asset/?id=76909584337943",
                jump  = "http://www.roblox.com/asset/?id=120533712803667",
                climb = "http://www.roblox.com/asset/?id=140663406485180",
                fall  = "http://www.roblox.com/asset/?id=100947971756348"
            },
            
            ["Furry"] = {
                idle1 = "http://www.roblox.com/asset/?id=111821292044705",
                idle2 = "http://www.roblox.com/asset/?id=111821292044705",
                walk  = "http://www.roblox.com/asset/?id=104011441852459",
                run   = "http://www.roblox.com/asset/?id=87770060317862",
                jump  = "http://www.roblox.com/asset/?id=102635582722041",
                climb = "http://www.roblox.com/asset/?id=76660530164497",
                fall  = "http://www.roblox.com/asset/?id=137079985547592"
            },
            
            ["Vlada Model"] = {
                idle1 = "http://www.roblox.com/asset/?id=100139116433530",
                idle2 = "http://www.roblox.com/asset/?id=100139116433530",
                walk  = "http://www.roblox.com/asset/?id=77983757225444",
                run   = "http://www.roblox.com/asset/?id=116717848244930",
                jump  = "http://www.roblox.com/asset/?id=120751055172567",
                climb = "http://www.roblox.com/asset/?id=70966616077778",
                fall  = "http://www.roblox.com/asset/?id=136118518255777"
            },
            ["R6 Converter"] = {
                idle1 = "http://www.roblox.com/asset/?id=90040240627854",
                idle2 = "http://www.roblox.com/asset/?id=90040240627854",
                walk  = "http://www.roblox.com/asset/?id=92149852708428",
                run   = "http://www.roblox.com/asset/?id=72259383092959",
                jump  = "http://www.roblox.com/asset/?id=130519980521511",
                climb = "http://www.roblox.com/asset/?id=80369171706383",
                fall  = "http://www.roblox.com/asset/?id=130011792193300"
            },
        
            ["R6 Gear Hold"] = {
                idle1 = "rbxassetid://92453281924797",
                idle2 = "rbxassetid://89893748940721",
                walk = "rbxassetid://114884344098450",
                run = "rbxassetid://131634789076585",
                jump = "rbxassetid://137659653949709",
                fall = "rbxassetid://75834860496519",
                climb = "rbxassetid://125215321499925",
                swim = "rbxassetid://113534064176043",
                swimidle = "rbxassetid://140107830121953",
            },
        }

local allAnimOptions = {
            "Default", "Vampire", "Hero", "Zombie Classic", "Mage", "Ghost",
            "Elder", "Levitation", "Astronaut", "Ninja", "Werewolf", "Cartoon",
            "Pirate", "Sneaky", "Toy", "Knight", "Confident", "Popstar",
            "Princess", "Cowboy", "Patrol", "Zombie FE", "Catwalk Glam", "Amazon Unboxed",
            "Glow Motion", "Bubbly", "Adidas Comm", "KATSEYE", "Wicked Popular",
            "Dizzy", "WDTL", "Billie Eilish", "Cute Bouncy", "Cute",
            "Jolly", "Cute Kawaii", "Doll 3.0", "Victoria Model",
            "Bike/Bicyclist", "Animal", "It-Girl Essential Model",
            "Oldschool", "Spider", "Joy", "Flying Aura", "FHA V2", "Silent Nurse", "Supermodel", "Enchanted Fairy", "Furry", "Vlada Model", "R6 Converter", "R6 Gear Hold"
        }

        local runAnimOptions = {
            "Default", "OG Rthro Run", "Vampire", "Hero", "Zombie Classic", "Mage", "Ghost",
            "Elder", "Levitation", "Astronaut", "Ninja", "Werewolf", "Cartoon",
            "Pirate", "Sneaky", "Toy", "Knight", "Confident", "Popstar",
            "Princess", "Cowboy", "Patrol", "Zombie FE", "Catwalk Glam", "Amazon Unboxed",
            "Glow Motion", "Bubbly", "Adidas Comm", "KATSEYE", "Wicked Popular",
            "Dizzy", "WDTL", "Billie Eilish", "Cute Bouncy", "Cute",
            "Jolly", "Cute Kawaii", "Doll 3.0", "Victoria Model",
            "Bike/Bicyclist", "Animal", "It-Girl Essential Model",
            "Oldschool", "Spider", "Joy", "Flying Aura", "FHA V2", "Silent Nurse", "Supermodel", "Enchanted Fairy", "Furry", "Vlada Model", "R6 Converter", "R6 Gear Hold"
        }
local swimAnimOptions = {"Default", "R6 Gear Hold"}


local presetKeys = {
    all = "feAnimPresetAll", idle = "feAnimPresetIdle", walk = "feAnimPresetWalk",
    run = "feAnimPresetRun", jump = "feAnimPresetJump", climb = "feAnimPresetClimb", fall = "feAnimPresetFall",
    swim = "feAnimPresetSwim",
}
local customSlots = {
    {key = "idle", label = "Idle", config = "feAnimCustomIdle"},
    {key = "walk", label = "Walk", config = "feAnimCustomWalk"},
    {key = "run", label = "Run", config = "feAnimCustomRun"},
    {key = "jump", label = "Jump", config = "feAnimCustomJump"},
    {key = "climb", label = "Climb", config = "feAnimCustomClimb"},
    {key = "fall", label = "Fall", config = "feAnimCustomFall"},
    {key = "swim", label = "Swim", config = "feAnimCustomSwim"},
}
local function cleanAnimationId(value)
    local text = tostring(value or ""):match("^%s*(.-)%s*$")
    if text == "" then return "" end
    local id = text:match("^(%d+)$") or text:match("^rbxassetid://(%d+)$")
        or text:match("^https?://[^/]*roblox%.com/.*[?&]id=(%d+)")
        or text:match("^https?://[^/]*roblox%.com/catalog/(%d+)")
        or text:match("^https?://[^/]*roblox%.com/library/(%d+)")
    return id and id:gsub("^0+", "") or nil
end

local animState, customAnims = {}, {}
local legacyEnabled = C("feAnimEnabled", false) == true
local hadCustom, hadPreset = false, false
for animType, key in pairs(presetKeys) do
    local selected = C(key, "Default")
    if selected == "Custom" then hadCustom = true; selected = "Default" end
    if type(selected) ~= "string" or (selected ~= "Default" and not animPresets[selected])
        or (selected == "OG Rthro Run" and animType ~= "run") then selected = "Default" end
    if selected ~= "Default" then hadPreset = true end
    animState[animType] = selected
    ConfigData[key] = selected
end
if ConfigData.feAnimCustomIdle == nil then
    local oldIdle = cleanAnimationId(ConfigData.feAnimCustomIdle1) or ""
    if oldIdle == "" then oldIdle = cleanAnimationId(ConfigData.feAnimCustomIdle2) or "" end
    ConfigData.feAnimCustomIdle = oldIdle
end
ConfigData.feAnimCustomIdle1, ConfigData.feAnimCustomIdle2 = nil, nil
for _, slot in ipairs(customSlots) do
    customAnims[slot.key] = cleanAnimationId(C(slot.config, "")) or ""
    ConfigData[slot.config] = customAnims[slot.key]
end
local presetsEnabled = C("feAnimPresetsEnabled", legacyEnabled and (hadPreset or not hadCustom)) == true
local customEnabled = C("feAnimCustomEnabled", legacyEnabled and hadCustom) == true
ConfigData.feAnimEnabled = presetsEnabled or customEnabled
local function enabled() return presetsEnabled or customEnabled end

-- These catalog containers use separate playback clips. Presets already
-- contain playback IDs; arbitrary custom catalog IDs are resolved on demand.
local assetRedirects = {
    ["103766334307435"] = "92453281924797",
    ["122068681350601"] = "114884344098450",
    ["101475660523078"] = "131634789076585",
    ["90924872939548"] = "137659653949709",
    ["126408720389134"] = "75834860496519",
    ["103902117192422"] = "125215321499925",
    ["103415879046292"] = "113534064176043",
}
local assetCache = env.VisualsV2FEAnimationAssets
if type(assetCache) ~= "table" then assetCache = {}; env.VisualsV2FEAnimationAssets = assetCache end
local aliases = {
    idle = "idle", idle1 = "idle", idle2 = "idle", animation1 = "idle", animation2 = "idle",
    walk = "walk", walkanim = "walk", run = "run", runanim = "run", jump = "jump", jumpanim = "jump",
    climb = "climb", climbanim = "climb", fall = "fall", fallanim = "fall",
    swim = "swim", swimanim = "swim", swimidle = "swimidle", swimidleanim = "swimidle",
}
local emoteGroups = {wave = true, point = true, dance = true, dance2 = true, dance3 = true, laugh = true, cheer = true,
    sit = true, sitting = true, emote = true, emotes = true}
local toolGroups = {toolnone = true, toolslash = true, toollunge = true}
local toolAnimationIds = {
    ["507768375"] = true, ["522635514"] = true, ["522638767"] = true,
    ["182393478"] = true, ["129967390"] = true, ["129967478"] = true,
}
local defaultMoves = {
    ["507766666"] = "idle", ["507766951"] = "idle", ["507766388"] = "idle",
    ["507777826"] = "walk", ["507767714"] = "run", ["507765000"] = "jump",
    ["507765644"] = "climb", ["507767968"] = "fall",
    ["507784897"] = "swim", ["507785072"] = "swimidle",
    ["180435571"] = "idle", ["180435792"] = "idle", ["180426354"] = "walk",
    ["125750702"] = "jump", ["180436148"] = "climb", ["180436334"] = "fall",
}

local session, generation = nil, 0
local updateMotion, refreshRuntime
local function valid(s)
    return alive and runtimeAlive and enabled() and session == s and s.token == generation
        and LocalPlayer.Character == s.character and s.character.Parent ~= nil
end
local function stopTrack(track, fade)
    if track then pcall(function() track:Stop(fade or 0.12) end) end
end
local function restoreWeights(s)
    for track, weight in pairs(s.weights or {}) do
        s.weights[track] = nil
        pcall(function() track:AdjustWeight(weight, 0.12) end)
    end
end
local function dropRecord(s, kind)
    local record = s.tracks[kind]
    if not record then return end
    s.tracks[kind] = nil; record.disposed = true
    if record.loopConnection then record.loopConnection:Disconnect(); record.loopConnection = nil end
    if s.current == record then s.current = nil; restoreWeights(s) end
    if record.track then
        s.ownTracks[record.track] = nil
        stopTrack(record.track)
        pcall(function() record.track:Destroy() end)
    end
    if record.animation then pcall(function() record.animation:Destroy() end) end
end
local function closeSession()
    generation = generation + 1
    local old = session; session = nil
    if not old then return end
    for _, connection in ipairs(old.connections) do pcall(function() connection:Disconnect() end) end
    restoreWeights(old)
    for kind in pairs(old.tracks) do dropRecord(old, kind) end
    if old.references then pcall(function() old.references:Destroy() end) end
end

local function animationGroup(animation, character)
    local node = animation
    if not node or not node:IsDescendantOf(character) then return nil end
    while node.Parent and node.Parent ~= character do
        if node.Parent:IsA("LuaSourceContainer") then
            local name = node.Parent.Name:lower()
            if name == "animate" or name == "r15anim" or name == "r6anim" then return node.Name:lower() end
            return nil
        end
        node = node.Parent
    end
end
local function movementGroup(group)
    if group == "animation1" or group == "animation2" then return nil end
    return group and aliases[group]
end
local function nativeKind(s, track)
    if s.ownTracks[track] then return nil end
    local animation = track.Animation
    if not animation or animation:FindFirstAncestorOfClass("Tool") then return nil end
    local group = animationGroup(animation, s.character)
    if group and (emoteGroups[group] or group:find("emote", 1, true)) then return nil end
    local id = cleanAnimationId(animation.AnimationId)
    if id and s.emoteIds[id] then return nil end
    local kind = movementGroup(group)
    if kind then return kind end
    if id and s.nativeIds[id] then return s.nativeIds[id] end
    -- Generic Animation1/Animation2 names are also used by sit, tool and game
    -- emotes. Only confirmed Animate groups or movement IDs can be suppressed.
    return id and defaultMoves[id]
end
local function isToolTrack(s, track)
    local animation = track.Animation
    if not animation then return false end
    if animation:FindFirstAncestorOfClass("Tool") then return true end
    local group = animationGroup(animation, s.character)
    if group and toolGroups[group] then return true end
    local id = cleanAnimationId(animation.AnimationId)
    if id and toolAnimationIds[id] then return true end
    local name = (tostring(track.Name or "") .. " " .. tostring(animation.Name or "")):lower():gsub("[%s_]", "")
    return name:find("toolnone", 1, true) ~= nil or name:find("toolhold", 1, true) ~= nil
        or name:find("customhold", 1, true) ~= nil or name:find("scopehold", 1, true) ~= nil
        or name:find("gunshoot", 1, true) ~= nil or name:find("reload", 1, true) ~= nil
end
local function isEmote(s, track)
    if s.ownTracks[track] or nativeKind(s, track) then return false end
    if isToolTrack(s, track) then
        -- Higher-priority native holds/actions can own their joints while our
        -- Core locomotion continues. A Core tool pose needs exclusive playback.
        return track.Priority == Enum.AnimationPriority.Core
    end
    -- Game emotes and avatar-wheel tracks need no particular name, parent or
    -- catalog registration to take control. Unknown tracks are never muted.
    return true
end
local function collectNativeIds(s)
    for _, child in ipairs(s.character:GetChildren()) do
        if child ~= s.references and child:IsA("LuaSourceContainer") then
            for _, animation in ipairs(child:GetDescendants()) do
                if animation:IsA("Animation") then
                    local group = animationGroup(animation, s.character)
                    local kind = movementGroup(group)
                    local id = cleanAnimationId(animation.AnimationId)
                    if id and kind then s.nativeIds[id] = kind end
                end
            end
        end
    end
end
local function playbackTargets()
    local result = {}
    local function selectedPreset(kind)
        if not presetsEnabled then return nil end
        local selected = animState[kind]
        if selected == "Default" then selected = animState.all end
        return animPresets[selected]
    end
    for _, slot in ipairs(customSlots) do
        local kind, id = slot.key, nil
        local preset = selectedPreset(kind)
        if preset then id = cleanAnimationId(preset[kind == "idle" and "idle1" or kind]) end
        if customEnabled and customAnims[kind] ~= "" then id = customAnims[kind] end
        if id and id ~= "" then result[kind] = assetRedirects[id] or id end
    end
    -- Preset idle variations do not require a second custom-id input.
    local idlePreset = selectedPreset("idle")
    if idlePreset and not (customEnabled and customAnims.idle ~= "") then
        local id = cleanAnimationId(idlePreset.idle2)
        if id and id ~= "" and id ~= result.idle then result.idle2 = assetRedirects[id] or id end
    end
    local swimPreset = selectedPreset("swim")
    if customEnabled and customAnims.swim ~= "" then
        result.swimidle = customAnims.swim == "103415879046292" and "140107830121953" or result.swim
    elseif swimPreset then
        local id = cleanAnimationId(swimPreset.swimidle)
        if id and id ~= "" then result.swimidle = assetRedirects[id] or id end
    end
    return result
end

local function resolveCatalog(id, kind)
    local key = id .. ":" .. kind
    if assetCache[key] then return assetCache[key] end
    local ok, objects = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
    if not ok or type(objects) ~= "table" then return id end
    local resolved, score = nil, -1
    local function inspect(animation)
        if not animation:IsA("Animation") then return end
        local candidate = cleanAnimationId(animation.AnimationId)
        if not candidate or candidate == "" then return end
        local name = animation.Name:lower()
        local match = aliases[name] == kind and 2 or 0
        if name == kind or (kind == "idle" and name == "animation1") then match = 3 end
        if match > score then resolved, score = candidate, match end
    end
    for _, object in ipairs(objects) do
        inspect(object)
        for _, child in ipairs(object:GetDescendants()) do inspect(child) end
        pcall(function() object:Destroy() end)
    end
    if resolved and alive and runtimeAlive then assetCache[key] = resolved end
    return resolved or id
end
local function reportLoadError(s, record)
    if not valid(s) or record.disposed or record.notified then return end
    record.notified = true
    shared.Notify("Error: Could not load the " .. record.kind .. " animation (" .. record.rawId .. "). Check its ID and animation access.", 0)
end
local function loadRecord(s, kind)
    local id = s.targets[kind]
    if not id then return nil end
    local old = s.tracks[kind]
    if old and old.rawId == id then return old end
    dropRecord(s, kind)
    local record = {rawId = id, kind = kind, pending = true}
    s.tracks[kind] = record
    local function stillCurrent() return valid(s) and not record.disposed and s.tracks[kind] == record end
    local function install(playbackId)
        if not stillCurrent() then return false end
        if record.loopConnection then record.loopConnection:Disconnect(); record.loopConnection = nil end
        if record.track then
            s.ownTracks[record.track] = nil; stopTrack(record.track)
            pcall(function() record.track:Destroy() end)
            record.track = nil
        end
        if record.animation then record.animation:Destroy() end
        local animation = Instance.new("Animation")
        animation.Name = "VisualsV2_FE_" .. kind
        animation.AnimationId = "rbxassetid://" .. playbackId
        animation.Parent = s.references
        record.animation = animation
        local ok, track = pcall(function() return s.animator:LoadAnimation(animation) end)
        if not stillCurrent() then
            if ok and track then pcall(function() track:Destroy() end) end
            animation:Destroy(); return false
        end
        if not ok or not track then return false end
        record.track = track; s.ownTracks[track] = true
        track.Priority = Enum.AnimationPriority.Core
        track.Looped = kind ~= "jump"
        if kind == "idle" or kind == "idle2" then
            record.loopConnection = track.DidLoop:Connect(function()
                if stillCurrent() and s.current == record and s.targets.idle2 then
                    s.idleVariant = kind == "idle" and "idle2" or "idle"
                    updateMotion(s)
                end
            end)
        end
        record.pending = false
        if s.current == record then s.current = nil end
        updateMotion(s)
        return true
    end
    task.spawn(function()
        local firstId = assetCache[id .. ":" .. kind] or id
        local loaded = install(firstId)
        if not loaded and stillCurrent() then
            local resolved = resolveCatalog(id, kind)
            loaded = resolved ~= firstId and install(resolved)
        end
        if not loaded then
            record.pending = false; record.failed = true
            reportLoadError(s, record); return
        end
        -- LoadAnimation can return before the clip has downloaded. Resolve
        -- catalog containers only when no playback data arrives, not per frame.
        task.wait(2)
        if not stillCurrent() or not record.track or record.track.Length > 0 then return end
        local resolved = resolveCatalog(id, kind)
        if not stillCurrent() then return end
        if resolved ~= firstId then install(resolved) end
        task.wait(6)
        if stillCurrent() and record.track and record.track.Length == 0 then
            record.failed = true
            stopTrack(record.track)
            if s.current == record then s.current = nil; restoreWeights(s) end
            reportLoadError(s, record)
        end
    end)
    return record
end

local function desiredMotion(s)
    local humanoid = s.humanoid
    local state = humanoid:GetState()
    if humanoid.Health <= 0 or humanoid.Sit or state == Enum.HumanoidStateType.Dead
        or state == Enum.HumanoidStateType.Seated or state == Enum.HumanoidStateType.PlatformStanding
        or state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.Ragdoll then return nil, 1 end
    if state == Enum.HumanoidStateType.Swimming then
        if (s.swimSpeed or 0) < 0.5 and humanoid.MoveDirection.Magnitude < 0.01 and s.targets.swimidle then
            return "swimidle", 1
        end
        return "swim", math.clamp((s.swimSpeed or 0) / 10, 0.1, 3)
    end
    if state == Enum.HumanoidStateType.Climbing then return "climb", math.clamp((s.climbSpeed or 0) / 12, -3, 3) end
    if state == Enum.HumanoidStateType.Jumping then return "jump", 1 end
    if state == Enum.HumanoidStateType.Freefall then
        if s.targets.jump and os.clock() - s.jumpedAt < 0.3 then return "jump", 1 end
        return "fall", 1
    end
    local speed = s.runSpeed or 0
    local moving = humanoid.MoveDirection.Magnitude > 0.01 or speed > 0.5
    if not moving then return s.idleVariant == "idle2" and s.targets.idle2 and "idle2" or "idle", 1 end
    if speed <= 0.5 then speed = humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed end
    local kind = speed >= math.max(humanoid.WalkSpeed * 0.75, 1) and "run" or "walk"
    if not s.targets[kind] then kind = kind == "run" and "walk" or "run" end
    return kind, math.clamp(speed / (kind == "walk" and 8 or 16), 0.1, 3)
end
local function sameMovement(native, active)
    if active == "idle2" then return native == "idle" end
    if active == "swim" or active == "swimidle" then return native == "swim" or native == "swimidle" end
    if active == "walk" or active == "run" then return native == "walk" or native == "run" end
    if active == "fall" then return native == "fall" or native == "jump" end
    return native == active
end
local function motionStep(s)
    if not valid(s) or not s.ready then return end
    local playing = s.animator:GetPlayingAnimationTracks()
    local kind, speed = desiredMotion(s)
    for _, track in ipairs(playing) do
        local weight = math.max(tonumber(track.WeightTarget) or 0, tonumber(track.WeightCurrent) or 0)
        if track.IsPlaying and weight > 0.001 and isEmote(s, track) then kind = nil; break end
    end
    if kind ~= "idle" and kind ~= "idle2" then s.idleVariant = nil end
    if not kind or not s.targets[kind] then
        if s.current then stopTrack(s.current.track); s.current = nil end
        restoreWeights(s); return
    end
    if s.current and s.current.kind ~= kind then
        stopTrack(s.current.track); s.current = nil; restoreWeights(s)
    end
    local record = loadRecord(s, kind)
    if not record or not record.track or record.pending or record.failed then return end
    if s.current ~= record then
        if s.current then stopTrack(s.current.track) end
        restoreWeights(s)
        s.current = record
        record.lastJump = nil
    end
    local track = record.track
    if not track.IsPlaying and (kind ~= "jump" or record.lastJump ~= s.jumpCount) then
        local ok = pcall(function() track:Play(0.12, 1, speed) end)
        if not ok then
            record.failed = true; stopTrack(track)
            s.current = nil; restoreWeights(s); reportLoadError(s, record); return
        end
        if kind == "jump" then record.lastJump = s.jumpCount end
    else
        track:AdjustSpeed(speed)
    end
    if not track.IsPlaying or track.Length <= 0 then restoreWeights(s); return end
    -- Leave native tracks running so disabling this feature restores them
    -- immediately. Only their competing movement weights are suppressed.
    local suppressed = {}
    for _, native in ipairs(playing) do
        local nativeMotion = nativeKind(s, native)
        if native.IsPlaying and nativeMotion and sameMovement(nativeMotion, kind) then
            local weight = native.WeightTarget
            if s.weights[native] == nil then s.weights[native] = weight end
            if weight > 0 then s.weights[native] = weight end
            native:AdjustWeight(0, 0.12)
            suppressed[native] = true
        end
    end
    for native, weight in pairs(s.weights) do
        if not suppressed[native] then
            s.weights[native] = nil
            pcall(function() native:AdjustWeight(weight, 0.12) end)
        end
    end
end
updateMotion = function(s)
    if not valid(s) or s.updating then return end
    s.updating = true
    local ok = pcall(motionStep, s)
    s.updating = false
    if not ok then
        if s.current then stopTrack(s.current.track); s.current = nil end
        restoreWeights(s)
    end
end

local function refreshTargets(s)
    if not valid(s) or not s.ready then return end
    local targets = playbackTargets()
    local oldTargets = s.targets or {}
    if targets.idle ~= oldTargets.idle or targets.idle2 ~= oldTargets.idle2 then s.idleVariant = nil end
    for kind, record in pairs(s.tracks) do
        if targets[kind] ~= record.rawId then dropRecord(s, kind) end
    end
    s.targets = targets
    updateMotion(s)
end
local function bindCharacter(character)
    closeSession()
    if not alive or not runtimeAlive or not enabled() or LocalPlayer.Character ~= character then return end
    local s = {character = character, token = generation, binding = true, connections = {}, tracks = {}, weights = {},
        ownTracks = setmetatable({}, {__mode = "k"}), nativeIds = {}, emoteIds = {}, jumpCount = 0, jumpedAt = -math.huge}
    session = s
    table.insert(s.connections, character.DescendantAdded:Connect(function(child)
        if not valid(s) then return end
        if (child:IsA("Animator") or child:IsA("Humanoid")) and not s.binding then
            if not s.ready or (child:IsA("Animator") and child ~= s.animator) then
                task.defer(function() if valid(s) then bindCharacter(character) end end)
            end
        end
    end))
    task.spawn(function()
        local humanoid = character:WaitForChild("Humanoid", 10)
        if not humanoid or not valid(s) then s.binding = false; return end
        local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 10)
        if not animator or not valid(s) then s.binding = false; return end
        s.humanoid, s.animator = humanoid, animator
        s.references = Instance.new("LocalScript")
        s.references.Name = "VisualsV2_FEAnimationReferences"; s.references.Disabled = true
        s.references.Parent = character
        collectNativeIds(s)
        s.ready, s.binding = true, false
        if humanoid:GetState() == Enum.HumanoidStateType.Jumping then s.jumpedAt = os.clock(); s.jumpCount = 1 end
        local function connect(event, callback) table.insert(s.connections, event:Connect(callback)) end
        connect(humanoid.Running, function(speed) s.runSpeed = speed; updateMotion(s) end)
        connect(humanoid.Climbing, function(speed) s.climbSpeed = speed; updateMotion(s) end)
        connect(humanoid.Swimming, function(speed) s.swimSpeed = speed; updateMotion(s) end)
        connect(humanoid.StateChanged, function(_, state)
            if state == Enum.HumanoidStateType.Jumping then s.jumpedAt = os.clock(); s.jumpCount = s.jumpCount + 1 end
            updateMotion(s)
        end)
        connect(humanoid.Died, function() if session == s then closeSession() end end)
        connect(animator.AnimationPlayed, function(track)
            if s.ownTracks[track] then return end
            updateMotion(s)
            task.defer(function() if valid(s) then updateMotion(s) end end)
        end)
        connect(character.DescendantAdded, function(child)
            if child:IsA("Animation") and not child:IsDescendantOf(s.references) then
                local group = animationGroup(child, character)
                local id = cleanAnimationId(child.AnimationId)
                local kind = movementGroup(group)
                if kind and id then s.nativeIds[id] = kind end
            end
        end)
        local elapsed = 0
        connect(RunService.Heartbeat, function(dt)
            elapsed = elapsed + dt
            if elapsed < 0.1 then return end
            elapsed = 0
            updateMotion(s)
        end)
        refreshTargets(s)
        task.spawn(function()
            local ok, description = pcall(function() return humanoid:GetAppliedDescription() end)
            if not ok or not description or not valid(s) then return end
            local success, emotes = pcall(function() return description:GetEmotes() end)
            if success and type(emotes) == "table" then
                for _, ids in pairs(emotes) do
                    if type(ids) == "table" then
                        for _, id in ipairs(ids) do local value = cleanAnimationId(id); if value then s.emoteIds[value] = true end end
                    end
                end
            end
        end)
    end)
end
refreshRuntime = function()
    if not alive or not runtimeAlive then return end
    if not enabled() then closeSession(); return end
    local character = LocalPlayer.Character
    if not character then return end
    if session and session.character == character and (session.ready or session.binding) then
        refreshTargets(session)
    else
        bindCharacter(character)
    end
end
RootMaid:GiveTask(LocalPlayer.CharacterAdded:Connect(function(character)
    if alive and runtimeAlive and enabled() then bindCharacter(character) end
end))
RootMaid:GiveTask(LocalPlayer.CharacterRemoving:Connect(function(character)
    if session and session.character == character then closeSession() end
end))
RootMaid:GiveTask(closeSession)

local presetToggle = addToggle(feAnimSection, "Enable Preset Animations", presetsEnabled, function(value)
    if not alive or not runtimeAlive then return end
    presetsEnabled = value
    SetCfg("feAnimPresetsEnabled", value); SetCfg("feAnimEnabled", enabled())
    refreshRuntime()
end)
local presetControllers = {}
local function addAnimationDropdown(label, kind, options)
    presetControllers[kind] = addDropdown(feAnimSection, label, options, animState[kind], function(selected)
        if not alive or not runtimeAlive or type(selected) ~= "string" then return end
        if selected ~= "Default" and not animPresets[selected] then return end
        if selected == "OG Rthro Run" and kind ~= "run" then return end
        animState[kind] = selected; SetCfg(presetKeys[kind], selected)
        refreshRuntime()
    end)
end
addAnimationDropdown("All Animations", "all", allAnimOptions)
for _, slot in ipairs(customSlots) do
    local options = slot.key == "run" and runAnimOptions or slot.key == "swim" and swimAnimOptions or allAnimOptions
    addAnimationDropdown(slot.label .. " Animation", slot.key, options)
end
local customToggle = addToggle(feAnimSection, "Enable Custom Animations", customEnabled, function(value)
    if not alive or not runtimeAlive then return end
    customEnabled = value
    SetCfg("feAnimCustomEnabled", value); SetCfg("feAnimEnabled", enabled())
    refreshRuntime()
end)
for _, slot in ipairs(customSlots) do
    feAnimSection:AddTextBox("Custom " .. slot.label .. " Animation ID", function(value)
        if not alive or not runtimeAlive then return end
        local id = cleanAnimationId(value)
        if id == nil then shared.Notify("Error: Enter an animation ID or asset URL. Leave it empty to clear it.", 0); return end
        customAnims[slot.key] = id; SetCfg(slot.config, id)
        refreshRuntime()
    end)
end

resetSection = function()
    presetToggle:Set(false); customToggle:Set(false)
    presetsEnabled, customEnabled = false, false
    closeSession()
    for kind in pairs(presetKeys) do
        animState[kind] = "Default"
        local control = presetControllers[kind]
        if control and type(control.Select) == "function" then
            local ok = pcall(function() control:Select("Default") end)
            if not ok then pcall(control.Select, "Default") end
        end
    end
    for _, slot in ipairs(customSlots) do customAnims[slot.key] = "" end
end
if enabled() then task.defer(refreshRuntime) end
end)()

-- COSMETIC: TRAIL
-- =========================================================

local trailSection = mainTab:AddSection("Trail", "Cosmetic")
local trailEnabled = C("trailEnabled", false)
local trailIsGradient = C("trailIsGradient", false)
local trailRainbow = C("trailRainbow", false)
local trailColorStatic = C("trailColorStatic",Color3.fromRGB(38,38,38))
local trailGradient1 = C("trailGradient1",Color3.fromRGB(38,38,38))
local trailGradient2 = C("trailGradient2",Color3.fromRGB(38,38,38))
local trailLifetime = math.max(0.2, tonumber(C("trailLifetime", 0.5)) or 0.5)
local trailTransparencyStart = math.clamp(tonumber(C("trailTransparency", 1)) or 1, 1, 4)
local trailObject = nil
local trailConnection = nil

local function removeTrail()
    if trailObject then
        trailObject:Destroy()
        trailObject = nil
    end
    local char = player.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local a0 = hrp:FindFirstChild("LV_TrailAttach0")
            local a1 = hrp:FindFirstChild("LV_TrailAttach1")
            if a0 then a0:Destroy() end
            if a1 then a1:Destroy() end
        end
    end
end

local function trailAlpha(value)
    value = math.clamp(tonumber(value) or 1, 1, 4)
    -- Never reaches 1, so the transparency slider cannot disable the feature.
    return 0.05 + ((value - 1) / 3) * 0.75
end

local function updateTrail()
    if not trailObject then return end
    trailObject.Lifetime = math.max(0.2, tonumber(trailLifetime) or 0.5)
    trailObject.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, trailAlpha(trailTransparencyStart)),
        NumberSequenceKeypoint.new(1, 1),
    })
    if trailIsGradient then
        trailObject.Color = ColorSequence.new(trailGradient1, trailGradient2)
    elseif trailRainbow then
        trailObject.Color = ColorSequence.new(Color3.fromHSV((tick() % 5) / 5, 1, 1))
    else
        trailObject.Color = ColorSequence.new(trailColorStatic)
    end
end

local function createTrail()
    removeTrail()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local a0 = Instance.new("Attachment")
    a0.Name = "LV_TrailAttach0"
    a0.Position = Vector3.new(0, 2, 0)
    a0.Parent = hrp

    local a1 = Instance.new("Attachment")
    a1.Name = "LV_TrailAttach1"
    a1.Position = Vector3.new(0, -2, 0)
    a1.Parent = hrp

    local trail = Instance.new("Trail")
    trail.Name = "LV_Trail"
    trail.Attachment0 = a0
    trail.Attachment1 = a1
    trail.LightEmission = 0.2
    trail.Parent = char
    trailObject = trail
    updateTrail()
end

local trailEnableToggle = addToggle(trailSection, "Enable Trail", trailEnabled, function(state)
    trailEnabled = state
    SetCfg("trailEnabled", state)
    if state then
        createTrail()
        if trailConnection then trailConnection:Disconnect() end
        trailConnection = RunService.Heartbeat:Connect(function()
            if trailRainbow and trailEnabled then updateTrail() end
        end)
    else
        if trailConnection then trailConnection:Disconnect(); trailConnection = nil end
        removeTrail()
    end
end)

local trailGradientToggle = addToggle(trailSection, "Use Gradient", trailIsGradient, function(state)
    trailIsGradient = state
    SetCfg("trailIsGradient", state)
    updateTrail()
end)

local trailRainbowToggle = addToggle(trailSection, "Rainbow", trailRainbow, function(state)
    trailRainbow = state
    SetCfg("trailRainbow", state)
    updateTrail()
end)

trailSection:AddColorpicker("Static Color", trailColorStatic, function(color)
    trailColorStatic = color
    SetCfg("trailColorStatic", color)
    updateTrail()
end)
trailSection:AddColorpicker("Gradient Color 1", trailGradient1, function(color)
    trailGradient1 = color
    SetCfg("trailGradient1", color)
    updateTrail()
end)
trailSection:AddColorpicker("Gradient Color 2", trailGradient2, function(color)
    trailGradient2 = color
    SetCfg("trailGradient2", color)
    updateTrail()
end)
trailSection:AddSlider("Trail Lifetime", 0.2, 3, trailLifetime, function(value)
    trailLifetime = math.max(0.2, tonumber(value) or 0.5)
    SetCfg("trailLifetime", trailLifetime)
    updateTrail()
end)
trailSection:AddSlider("Trail Transparency", 1, 4, trailTransparencyStart, function(value)
    trailTransparencyStart = math.clamp(math.floor((tonumber(value) or 1) + 0.5), 1, 4)
    SetCfg("trailTransparency", trailTransparencyStart)
    updateTrail()
end)

env.VisualsV2Runtime.RegisterReset(function()
    trailEnableToggle:Set(false)
    trailGradientToggle:Set(false)
    trailRainbowToggle:Set(false)
    trailEnabled = false
    trailIsGradient = false
    trailRainbow = false
    trailLifetime = 0.5
    trailTransparencyStart = 1
    trailColorStatic = Color3.fromRGB(255,255,255)
    trailGradient1 = Color3.fromRGB(255,255,255)
    trailGradient2 = Color3.fromRGB(0,0,0)
    if trailConnection then trailConnection:Disconnect(); trailConnection = nil end
    removeTrail()
end)

-- =========================================================
-- COSMETIC: SKIN
-- =========================================================
-- COSMETIC: SKIN
-- =========================================================

local skinSection = mainTab:AddSection("Skin", "Cosmetic")
local ffEnabled = C("ffEnabled", false)
local ffRainbow = C("ffRainbow", false)
local ffColor = C("ffColor",Color3.fromRGB(38,38,38))
local skinTrailEnabled = C("skinTrailEnabled", false)
local skinTrailRainbow = C("skinTrailRainbow", false)
local skinTrailColor = C("skinTrailColor",Color3.fromRGB(38,38,38))
local skinTrailLife = math.max(0.2, tonumber(C("skinTrailLife", 0.5)) or 0.5)
local skinTrailTransparency = math.clamp(tonumber(C("skinTrailTransparency", 0.0)) or 0, 0, 3)
local ffConnection = nil
local skinTrailRainbowConnection = nil

local FF_MATERIAL_ATTR = "VisualsV2_OriginalMaterial"
local FF_COLOR_ATTR = "VisualsV2_OriginalColor"

local function rememberForceFieldPart(part)
    if not part:IsA("BasePart") then return end
    if part:GetAttribute(FF_MATERIAL_ATTR) == nil then
        part:SetAttribute(FF_MATERIAL_ATTR, part.Material.Name)
    end
    if part:GetAttribute(FF_COLOR_ATTR) == nil then
        part:SetAttribute(FF_COLOR_ATTR, part.Color)
    end
end

local function restoreForceFieldPart(part)
    if not part:IsA("BasePart") then return end
    local materialName = part:GetAttribute(FF_MATERIAL_ATTR)
    local oldColor = part:GetAttribute(FF_COLOR_ATTR)
    if materialName then
        local ok, material = pcall(function()
            return Enum.Material[materialName]
        end)
        if ok and material then part.Material = material end
    end
    if typeof(oldColor) == "Color3" then part.Color = oldColor end
    part:SetAttribute(FF_MATERIAL_ATTR, nil)
    part:SetAttribute(FF_COLOR_ATTR, nil)
end

local function applyForceField()
    local char = player.Character
    if not char then return end
    local color = ffRainbow and Color3.fromHSV((os.clock() % 5) / 5, 1, 1) or ffColor
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            rememberForceFieldPart(part)
            part.Material = Enum.Material.ForceField
            part.Color = color
        end
    end
end

local function removeForceField()
    if ffConnection then
        ffConnection:Disconnect()
        ffConnection = nil
    end
    local char = player.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then restoreForceFieldPart(part) end
    end
end

local function refreshForceFieldConnection()
    if ffConnection then
        ffConnection:Disconnect()
        ffConnection = nil
    end
    if ffEnabled and ffRainbow then
        ffConnection = RunService.Heartbeat:Connect(applyForceField)
    end
end

local function clearSkinTrail()
    local char = player.Character
    if not char then return end
    for _, obj in ipairs(char:GetDescendants()) do
        if obj.Name == "LV_SkinTrail" or obj.Name == "LV_SkinPointer1" or obj.Name == "LV_SkinPointer2" then
            obj:Destroy()
        end
    end
end

local function currentSkinTrailColor()
    return skinTrailRainbow and Color3.fromHSV((os.clock() % 5) / 5, 1, 1) or skinTrailColor
end

local function currentSkinTrailTransparency()
    return math.clamp((tonumber(skinTrailTransparency) or 0) / 4, 0, 0.75)
end

local function applySkinTrail()
    clearSkinTrail()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not hrp then return end

    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and part ~= hrp then
            local a0 = Instance.new("Attachment")
            a0.Name = "LV_SkinPointer1"
            a0.Parent = part

            local a1 = Instance.new("Attachment")
            a1.Name = "LV_SkinPointer2"
            a1.Parent = hrp

            local trail = Instance.new("Trail")
            trail.Name = "LV_SkinTrail"
            trail.Texture = "rbxassetid://1390780157"
            trail.Attachment0 = a0
            trail.Attachment1 = a1
            trail.Color = ColorSequence.new(currentSkinTrailColor())
            trail.Transparency = NumberSequence.new(currentSkinTrailTransparency())
            trail.Lifetime = skinTrailLife
            trail.Parent = part
        end
    end
end

local function updateSkinTrail()
    local char = player.Character
    if not char then return end
    local color = currentSkinTrailColor()
    local transparency = currentSkinTrailTransparency()
    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("Trail") and obj.Name == "LV_SkinTrail" then
            obj.Color = ColorSequence.new(color)
            obj.Transparency = NumberSequence.new(transparency)
            obj.Lifetime = skinTrailLife
        end
    end
end

local function refreshSkinTrailRainbowConnection()
    if skinTrailRainbowConnection then
        skinTrailRainbowConnection:Disconnect()
        skinTrailRainbowConnection = nil
    end
    if skinTrailEnabled and skinTrailRainbow then
        skinTrailRainbowConnection = RunService.Heartbeat:Connect(updateSkinTrail)
    end
end

local forceFieldToggle = addToggle(skinSection, "Enable ForceField", ffEnabled, function(state)
    ffEnabled = state
    SetCfg("ffEnabled", state)
    if state then
        applyForceField()
        refreshForceFieldConnection()
    else
        removeForceField()
    end
end)

local rainbowForceFieldToggle = addToggle(skinSection, "Rainbow ForceField", ffRainbow, function(state)
    ffRainbow = state
    SetCfg("ffRainbow", state)
    if ffEnabled then
        applyForceField()
        refreshForceFieldConnection()
    end
end)

skinSection:AddColorpicker("ForceField Color", ffColor, function(color)
    ffColor = color
    SetCfg("ffColor", color)
    if ffEnabled and not ffRainbow then applyForceField() end
end)

local skinTrailToggle = addToggle(skinSection, "Enable Skin Trail", skinTrailEnabled, function(state)
    skinTrailEnabled = state
    SetCfg("skinTrailEnabled", state)
    if state then applySkinTrail() else clearSkinTrail() end
    refreshSkinTrailRainbowConnection()
end)

local rainbowSkinTrailToggle = addToggle(skinSection, "Rainbow Skin Trail", skinTrailRainbow, function(state)
    skinTrailRainbow = state
    SetCfg("skinTrailRainbow", state)
    if skinTrailEnabled then updateSkinTrail() end
    refreshSkinTrailRainbowConnection()
end)

skinSection:AddColorpicker("Skin Trail Color", skinTrailColor, function(color)
    skinTrailColor = color
    SetCfg("skinTrailColor", color)
    if skinTrailEnabled and not skinTrailRainbow then updateSkinTrail() end
end)

skinSection:AddSlider("Skin Trail Lifetime", 0.2, 3.0, skinTrailLife, function(value)
    skinTrailLife = math.max(0.2, tonumber(value) or 0.5)
    SetCfg("skinTrailLife", skinTrailLife)
    if skinTrailEnabled then updateSkinTrail() end
end)

skinSection:AddSlider("Skin Transparency", 0.0, 3.0, skinTrailTransparency, function(value)
    skinTrailTransparency = value
    SetCfg("skinTrailTransparency", value)
    if skinTrailEnabled then updateSkinTrail() end
end)

env.VisualsV2Runtime.RegisterReset(function()
    forceFieldToggle:Set(false)
    rainbowForceFieldToggle:Set(false)
    skinTrailToggle:Set(false)
    rainbowSkinTrailToggle:Set(false)
    removeForceField()
    clearSkinTrail()
end)

-- =========================================================

-- COSMETIC: AURAS
-- =========================================================

local auraSection = mainTab:AddSection("Auras", "Cosmetic")
local auraEnabled = C("auraEnabled", false)
local auraType = C("auraType", "Godly")
local currentAuraModel = nil
local auraEffects = {}

local AuraModels = {
    Godly = "rbxassetid://16699750981",
    ["Super Sayien"] = "rbxassetid://116109508364297",
    ["North Star"] = "rbxassetid://83945069652732",
    ["Blue Lord"] = "rbxassetid://10974316799",
    ["Pink Aura"] = "rbxassetid://115980859615239",
    ["Angel Wing"] = "rbxassetid://90022969696073",
    ["Sweet Heart"] = "rbxassetid://91724768175470",
    ["Ethereal Aura"] = "rbxassetid://97041568674250",
}

local function clearAura()
    for _, obj in ipairs(auraEffects) do
        if obj and obj.Parent then obj:Destroy() end
    end
    auraEffects = {}
end

local function loadAuraModel()
    currentAuraModel = nil
    local id = AuraModels[auraType]
    if not id then return end
    local ok, model = pcall(function()
        return game:GetObjects(id)[1]
    end)
    if ok and model then currentAuraModel = model end
end

local function originalNexiumAuraClone(char)
    local tempModel = currentAuraModel:Clone()
    for _, obj in pairs(tempModel:GetDescendants()) do
        if not obj:IsA("BasePart") then
            local clone = obj:Clone()
            local parentName = obj.Parent and obj.Parent.Name
            local target = char:FindFirstChild(parentName) or char:FindFirstChildWhichIsA("BasePart")
            if target and not target:FindFirstChild(clone.Name) then
                clone.Parent = target
                table.insert(auraEffects, clone)
            end
        end
    end
    tempModel:Destroy()
end

local function visualEffectsOnlyAuraClone(char)
    local tempModel = currentAuraModel:Clone()

    -- Clone only visual effect roots attached to source body parts. This avoids
    -- importing humanoids, rig parts, scripts, wings, or frozen character models.
    for _, obj in ipairs(tempModel:GetDescendants()) do
        local parent = obj.Parent
        if parent and parent:IsA("BasePart") and not obj:IsA("BasePart") then
            local visual = obj:IsA("Attachment")
                or obj:IsA("ParticleEmitter")
                or obj:IsA("Beam")
                or obj:IsA("Trail")
                or obj:IsA("PointLight")
                or obj:IsA("SpotLight")
                or obj:IsA("SurfaceLight")
                or obj:IsA("Fire")
                or obj:IsA("Smoke")
                or obj:IsA("Sparkles")

            if auraType == "Angel Wing" and parent.Name:lower():find("wing", 1, true) then
                visual = false
            end

            if visual then
                local target = char:FindFirstChild(parent.Name) or char:FindFirstChild("HumanoidRootPart")
                if target and not target:FindFirstChild(obj.Name) then
                    local clone = obj:Clone()
                    clone.Parent = target
                    table.insert(auraEffects, clone)
                end
            end
        end
    end

    tempModel:Destroy()
end

local function applyAura()
    clearAura()
    local char = player.Character
    if not char then return end
    if not currentAuraModel then loadAuraModel() end
    if not currentAuraModel then return end

    -- Blue Lord and Pink Aura use the original Nexium cloning behavior exactly.
    -- Super Sayien keeps the same original Nexium behavior from the previous fix.
    if auraType == "Blue Lord" or auraType == "Pink Aura" or auraType == "Super Sayien" then
        originalNexiumAuraClone(char)
    else
        visualEffectsOnlyAuraClone(char)
    end
end

local auraToggle = addToggle(auraSection, "Enable Local Aura", auraEnabled, function(state)
    auraEnabled = state
    SetCfg("auraEnabled", state)
    if state then applyAura() else clearAura() end
end)

local auraItems = {}
for name in pairs(AuraModels) do table.insert(auraItems, name) end
table.sort(auraItems)
addDropdown(auraSection, "Aura Type", auraItems, auraType, function(selected)
    auraType = selected
    SetCfg("auraType", selected)
    loadAuraModel()
    if auraEnabled then applyAura() end
end)

env.VisualsV2Runtime.RegisterReset(function()
    auraToggle:Set(false)
    clearAura()
end)

-- =========================================================


-- =========================================================
-- COSMETIC: DUAL EFFECT
-- =========================================================
;(function()
local section=mainTab:AddSection("Dual Effect","Cosmetic")
section:AddLabel("Must Own Dual Effect + Selected Effect")
local effects={"Vampiric2024","SynthEffect2025","Sunbeams2024","Snowstorm2024","Retro2025","Radioactive","Musical","Heatwave2025","Heartify","Gifts2024","Ghosts2024","Ghostify","FlamingoEffect2025","Burn","Cursed2024","Coal2025","Starry2024","Bats2024","Aquatic2025","Treats2025","Confetti2025","Bokeh2025","Lights2025","Jellyfish2024","Hearts26","XmasGlow2025","Cats2025","Carrots2025","BlueFire","Rainbows2025","Nightsky2025","Frost2025","Elitify","Electric","Dual","Abduction2025","SweetEffect26","UFOs2025","Strawberries26","Snowballs2025","Nightlife26","Leaves2025"}
local enabled=C("dualEffectEnabled",false)
local selected=C("dualEffectSelected","Electric")
local conn=nil
local token=0
local function stop() token+=1; if conn then conn:Disconnect(); conn=nil end end
local function hook()
    stop(); if not enabled then return end
    local remotes=game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local gameplay=remotes and remotes:FindFirstChild("Gameplay")
    local roleSelect=gameplay and gameplay:FindFirstChild("RoleSelect")
    local inventory=remotes and remotes:FindFirstChild("Inventory")
    local equip=inventory and inventory:FindFirstChild("Equip")
    if not roleSelect or not equip then return end
    local mine=token
    conn=roleSelect.OnClientEvent:Connect(function(role)
        if not enabled or role~="Murderer" then return end
        pcall(function() equip:FireServer("Dual","Effects") end)
        task.delay(15,function()
            if enabled and mine==token then pcall(function() equip:FireServer(selected,"Effects") end) end
        end)
    end)
end
addDropdown(section,"VV2 Select Second Effect",effects,selected,function(v) selected=v; SetCfg("dualEffectSelected",v) end)
local toggle=addToggle(section,"VV2 Auto Equip Dual Effect",enabled,function(v) enabled=v; SetCfg("dualEffectEnabled",v); hook() end)
env.VisualsV2Runtime.RegisterReset(function() toggle:Set(false); enabled=false; stop() end)
if enabled then hook() end
end)()

-- COSMETIC: JUMP CIRCLES
-- =========================================================

local jumpSection = mainTab:AddSection("Jump Circles", "Cosmetic")
local jumpCirclesEnabled = C("jumpCirclesEnabled", false)
local jumpCircleRainbow = C("jumpCircleRainbow", false)
local jumpCircleSize = C("jumpCircleSize", 5)
local jumpCircleTransparency = math.clamp(tonumber(C("jumpCircleTransparency", 1)) or 1, 0, 4)
local jumpCircleLifetime = math.max(0.2, tonumber(C("jumpCircleLifetime", 0.8)) or 0.8)
local jumpCircleColor = C("jumpCircleColor",Color3.fromRGB(38,38,38))

local function jumpAlpha(value)
    value = math.clamp(tonumber(value) or 1, 0, 4)
    return (value / 4) * 0.8
end

local function createJumpCircle(position)
    local ring = Instance.new("Part")
    ring.Name = "LV_JumpCircle"
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanTouch = false
    ring.CanQuery = false
    ring.CastShadow = false
    ring.Material = Enum.Material.Neon
    ring.Transparency = jumpAlpha(jumpCircleTransparency)
    ring.Color = jumpCircleRainbow and Color3.fromHSV((tick() % 5) / 5, 1, 1) or jumpCircleColor
    ring.Size = Vector3.new(1, 1, 1)
    ring.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0)
    ring.Parent = workspace

    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = "rbxassetid://3270017"
    mesh.Scale = Vector3.new(jumpCircleSize, jumpCircleSize, 0.15)
    mesh.Parent = ring

    local life = math.max(0.2, tonumber(jumpCircleLifetime) or 0.8)
    TweenService:Create(mesh, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Scale = Vector3.new(jumpCircleSize + 4, jumpCircleSize + 4, 0.15),
    }):Play()
    TweenService:Create(ring, TweenInfo.new(life), {Transparency = 1}):Play()
    task.delay(life, function()
        if ring and ring.Parent then ring:Destroy() end
    end)
end

local function setupJumpCircles(char)
    task.spawn(function()
        local humanoid = char:WaitForChild("Humanoid", 5)
        local hrp = char:WaitForChild("HumanoidRootPart", 5)
        if not humanoid or not hrp then return end
        local wasInAir = false
        local debounce = false
        while char.Parent do
            RunService.RenderStepped:Wait()
            if jumpCirclesEnabled and humanoid.Health > 0 then
                local state = humanoid:GetState()
                if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
                    wasInAir = true
                end
                if wasInAir and humanoid.FloorMaterial ~= Enum.Material.Air and not debounce then
                    debounce = true
                    wasInAir = false
                    createJumpCircle(hrp.Position - Vector3.new(0, 2.8, 0))
                    task.delay(0.15, function() debounce = false end)
                end
            end
        end
    end)
end

local jumpEnableToggle = addToggle(jumpSection, "Enable Jump Circles", jumpCirclesEnabled, function(state)
    jumpCirclesEnabled = state
    SetCfg("jumpCirclesEnabled", state)
end)
local jumpRainbowToggle = addToggle(jumpSection, "Rainbow", jumpCircleRainbow, function(state)
    jumpCircleRainbow = state
    SetCfg("jumpCircleRainbow", state)
end)
jumpSection:AddSlider("Circle Size", 2, 15, jumpCircleSize, function(value)
    jumpCircleSize = value
    SetCfg("jumpCircleSize", value)
end)
jumpSection:AddSlider("Transparency", 0, 4, jumpCircleTransparency, function(value)
    jumpCircleTransparency = math.clamp(tonumber(value) or 1, 0, 4)
    SetCfg("jumpCircleTransparency", jumpCircleTransparency)
end)
jumpSection:AddSlider("Lifetime", 0.2, 5, jumpCircleLifetime, function(value)
    jumpCircleLifetime = math.max(0.2, tonumber(value) or 0.8)
    SetCfg("jumpCircleLifetime", jumpCircleLifetime)
end)
jumpSection:AddColorpicker("Circle Color", jumpCircleColor, function(color)
    jumpCircleColor = color
    SetCfg("jumpCircleColor", color)
end)

env.VisualsV2Runtime.RegisterReset(function()
    jumpEnableToggle:Set(false)
    jumpRainbowToggle:Set(false)
    jumpCirclesEnabled = false
    jumpCircleRainbow = false
    jumpCircleSize = 5
    jumpCircleTransparency = 1
    jumpCircleLifetime = 0.8
    jumpCircleColor = Color3.fromRGB(255,255,255)
end)

-- =========================================================
-- COSMETIC: CHARACTER
-- =========================================================

local characterSection = mainTab:AddSection("Character", "Cosmetic")
local headlessEnabled = C("headlessEnabled", false)
local characterOriginal = setmetatable({}, {__mode = "k"})

characterSection:AddParagraph(
    "Character Appearance",
    "Headless and Korblox are client sided. Korblox works for R15 only."
)

local function rememberCharacterObject(obj)
    if not obj or characterOriginal[obj] then return end
    if obj:IsA("BasePart") then
        characterOriginal[obj] = {
            Transparency = obj.Transparency,
            LocalTransparencyModifier = obj.LocalTransparencyModifier,
        }
    elseif obj:IsA("Decal") then
        characterOriginal[obj] = {Transparency = obj.Transparency}
    end
end

local function restoreCharacterObject(obj)
    local data = characterOriginal[obj]
    if not obj or not data then return end
    if obj:IsA("BasePart") then
        pcall(function() obj.Transparency = data.Transparency end)
        pcall(function() obj.LocalTransparencyModifier = data.LocalTransparencyModifier end)
    elseif obj:IsA("Decal") then
        pcall(function() obj.Transparency = data.Transparency end)
    end
end

local function applyCharacterVisuals()
    local char = player.Character
    if not char then return end

    local head = char:FindFirstChild("Head")
    if head then
        rememberCharacterObject(head)
        if headlessEnabled then
            head.Transparency = 1
            head.LocalTransparencyModifier = 1
        else
            restoreCharacterObject(head)
        end

        for _, obj in ipairs(head:GetChildren()) do
            if obj:IsA("Decal") then
                rememberCharacterObject(obj)
                if headlessEnabled then
                    obj.Transparency = 1
                else
                    restoreCharacterObject(obj)
                end
            end
        end
    end
end

local headlessToggle = addToggle(characterSection, "Headless", headlessEnabled, function(state)
    headlessEnabled = state
    SetCfg("headlessEnabled", state)
    applyCharacterVisuals()
end)

local KorbloxSystem={
    RightEnabled=C("korbloxEnabled",false),
    LeftEnabled=C("korbloxLeftEnabled",false),
    RightToggle=nil,
    LeftToggle=nil,
}

;(function()
-- =========================================================
-- KORBLOX: GENUINE R15 BODY-PART REPLACEMENT
-- Uses Roblox's own R15 body-part replacement path so the Korblox meshes keep
-- their real knee/ankle attachments instead of being forced into another
-- avatar package's MeshPart bounds. Event-driven reapply also handles body
-- converters that rebuild the segmented R15 limbs without requiring a reset.
-- =========================================================

local PlayersService=game:GetService("Players")

local RIGHT_ASSET=139607718
local LEFT_ASSET=139607673
local KORBLOX_MARKER="VisualsV2KorbloxSide"

local SIDE_NAMES={
    Right={"RightUpperLeg","RightLowerLeg","RightFoot"},
    Left={"LeftUpperLeg","LeftLowerLeg","LeftFoot"},
}

local SIDE_ENUMS={
    Right={
        Enum.BodyPartR15.RightUpperLeg,
        Enum.BodyPartR15.RightLowerLeg,
        Enum.BodyPartR15.RightFoot,
    },
    Left={
        Enum.BodyPartR15.LeftUpperLeg,
        Enum.BodyPartR15.LeftLowerLeg,
        Enum.BodyPartR15.LeftFoot,
    },
}

local currentState=nil
local stateGeneration=0
local templateParts=nil
local templateBuilding=false
local templateBuildGeneration=0

local function sideEnabled(side)
    if side=="Right" then return KorbloxSystem.RightEnabled end
    return KorbloxSystem.LeftEnabled
end

local function disconnect(connection)
    if connection then
        pcall(function() connection:Disconnect() end)
    end
end

local function destroyMotorChildren(root)
    if not root then return end
    for _,obj in ipairs(root:GetDescendants()) do
        if obj:IsA("Motor6D") then
            pcall(function() obj:Destroy() end)
        end
    end
end

local function cloneBodyPart(part)
    if not part or not part:IsA("BasePart") then return nil end

    local originalArchivable=part.Archivable
    if not originalArchivable then
        pcall(function() part.Archivable=true end)
    end

    local ok,clone=pcall(function()
        return part:Clone()
    end)

    if not originalArchivable then
        pcall(function() part.Archivable=false end)
    end

    if not ok or not clone then return nil end
    destroyMotorChildren(clone)
    clone.Parent=nil
    return clone
end

local function clearStateConnections(state)
    if not state then return end
    for _,connection in ipairs(state.Connections or {}) do
        disconnect(connection)
    end
    state.Connections={}
    for _,side in ipairs({"Left","Right"}) do
        for _,connection in ipairs((state.PartConnections and state.PartConnections[side]) or {}) do
            disconnect(connection)
        end
        if state.PartConnections then state.PartConnections[side]={} end
    end
end

local function getHumanoid(char)
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid",2)
end

local function getSideParts(char,side)
    local names=SIDE_NAMES[side]
    if not char or not names then return nil end

    local parts={}
    for index,name in ipairs(names) do
        local part=char:FindFirstChild(name)
        if not part or not part:IsA("BasePart") then
            return nil
        end
        parts[index]=part
    end
    return parts
end

local function waitForSideParts(char,side,timeout)
    local deadline=os.clock()+(timeout or 2.5)
    repeat
        if player.Character~=char then return nil end
        local parts=getSideParts(char,side)
        if parts then return parts end
        task.wait(0.05)
    until os.clock()>=deadline
    return getSideParts(char,side)
end

local function captureBaselineDescription(state)
    if not state or not state.Humanoid then return end
    local ok,desc=pcall(function()
        return state.Humanoid:GetAppliedDescription()
    end)
    if ok and desc then
        state.BaselineDescription=desc
        state.BaselineLegIds={
            Left=desc.LeftLeg,
            Right=desc.RightLeg,
        }
    end
end

local function beginCharacterState(char)
    if currentState and currentState.Character==char then
        return currentState
    end

    stateGeneration+=1
    clearStateConnections(currentState)

    local humanoid=getHumanoid(char)
    currentState={
        Character=char,
        Humanoid=humanoid,
        Generation=stateGeneration,
        Connections={},
        PartConnections={Left={},Right={}},
        Originals={Left={},Right={}},
        RepairTokens={Left=0,Right=0},
        Applying={Left=false,Right=false},
        SuppressAppearanceUntil=0,
        BaselineDescription=nil,
        BaselineLegIds={Left=0,Right=0},
    }

    captureBaselineDescription(currentState)
    return currentState
end

local function captureOriginalPart(state,side,index,part,overwrite)
    if not state or not part or not part:IsA("BasePart") then return end
    local marked=part:GetAttribute(KORBLOX_MARKER)
    if marked==side then return end
    if state.Originals[side][index] and not overwrite then return end

    local clone=cloneBodyPart(part)
    if clone then
        clone:SetAttribute(KORBLOX_MARKER,nil)
        state.Originals[side][index]=clone
    end
end

local function captureOriginalSide(state,side,overwrite)
    local parts=getSideParts(state.Character,side)
    if not parts then return false end
    for index,part in ipairs(parts) do
        captureOriginalPart(state,side,index,part,overwrite)
    end
    return true
end

local function extractTemplates(model)
    if not model then return nil end
    local result={Left={},Right={}}

    for _,side in ipairs({"Left","Right"}) do
        for index,name in ipairs(SIDE_NAMES[side]) do
            local source=model:FindFirstChild(name)
            local clone=cloneBodyPart(source)
            if not clone then return nil end
            clone.Name=name
            result[side][index]=clone
        end
    end

    return result
end

local function buildTemplateParts()
    if templateParts then return true end

    if templateBuilding then
        local deadline=os.clock()+4
        repeat
            if templateParts then return true end
            if not templateBuilding then break end
            task.wait(0.05)
        until os.clock()>=deadline
        return templateParts~=nil
    end

    templateBuilding=true
    templateBuildGeneration+=1
    local buildGeneration=templateBuildGeneration

    local description=Instance.new("HumanoidDescription")
    description.LeftLeg=LEFT_ASSET
    description.RightLeg=RIGHT_ASSET

    local model=nil
    local ok=pcall(function()
        model=PlayersService:CreateHumanoidModelFromDescriptionAsync(
            description,
            Enum.HumanoidRigType.R15
        )
    end)

    if (not ok or not model) then
        ok=pcall(function()
            model=PlayersService:CreateHumanoidModelFromDescription(
                description,
                Enum.HumanoidRigType.R15
            )
        end)
    end

    local extracted=nil
    if ok and model then
        extracted=extractTemplates(model)
    end

    pcall(function() description:Destroy() end)
    if model then pcall(function() model:Destroy() end) end

    if buildGeneration==templateBuildGeneration and extracted then
        templateParts=extracted
    end

    templateBuilding=false
    return templateParts~=nil
end

local function replaceOnePart(state,side,index,source)
    if not state or not state.Humanoid or not source then return false end
    if player.Character~=state.Character then return false end

    local clone=cloneBodyPart(source)
    if not clone then return false end

    clone.Name=SIDE_NAMES[side][index]
    clone:SetAttribute(KORBLOX_MARKER,side)

    local ok,result=pcall(function()
        return state.Humanoid:ReplaceBodyPartR15(SIDE_ENUMS[side][index],clone)
    end)

    if not ok or result==false then
        pcall(function() clone:Destroy() end)
        return false
    end
    return true
end

local function applyDescriptionFallback(state)
    if not state or not state.Humanoid or player.Character~=state.Character then
        return false
    end

    local description=nil
    local ok=pcall(function()
        description=state.Humanoid:GetAppliedDescription()
    end)
    if not ok or not description then
        if state.BaselineDescription then
            description=state.BaselineDescription:Clone()
        else
            return false
        end
    end

    description.LeftLeg=KorbloxSystem.LeftEnabled and LEFT_ASSET or (state.BaselineLegIds.Left or 0)
    description.RightLeg=KorbloxSystem.RightEnabled and RIGHT_ASSET or (state.BaselineLegIds.Right or 0)

    state.SuppressAppearanceUntil=os.clock()+1.0

    local applied=pcall(function()
        if state.Humanoid.ApplyDescriptionResetAsync then
            state.Humanoid:ApplyDescriptionResetAsync(description)
        elseif state.Humanoid.ApplyDescriptionAsync then
            state.Humanoid:ApplyDescriptionAsync(description)
        else
            state.Humanoid:ApplyDescription(description)
        end
    end)

    pcall(function() description:Destroy() end)

    if applied and player.Character==state.Character then
        for _,side in ipairs({"Left","Right"}) do
            local parts=getSideParts(state.Character,side)
            if parts then
                for _,part in ipairs(parts) do
                    if sideEnabled(side) then
                        pcall(function() part:SetAttribute(KORBLOX_MARKER,side) end)
                    else
                        pcall(function() part:SetAttribute(KORBLOX_MARKER,nil) end)
                    end
                end
            end
        end
    end

    return applied
end

local hookCurrentSideParts

local function applySideNow(state,side)
    if not state or not sideEnabled(side) then return false end
    if player.Character~=state.Character then return false end

    local parts=waitForSideParts(state.Character,side,2.5)
    if not parts then return false end

    -- Capture the live body package before replacing it. This is also refreshed
    -- when a force-R6/body changer externally rebuilds a limb.
    captureOriginalSide(state,side,false)

    if not buildTemplateParts() then
        return applyDescriptionFallback(state)
    end

    state.Applying[side]=true
    local success=true

    for index=1,3 do
        if not replaceOnePart(state,side,index,templateParts[side][index]) then
            success=false
            break
        end
    end

    state.Applying[side]=false

    if not success then
        -- One controlled description application is the fallback. There are no
        -- repeating ApplyDescription chains, which avoids the old lag loop.
        local fallbackApplied=applyDescriptionFallback(state)
        if fallbackApplied then hookCurrentSideParts(state,side) end
        return fallbackApplied
    end

    hookCurrentSideParts(state,side)
    return true
end

local function restoreSideNow(state,side)
    if not state or player.Character~=state.Character then return false end
    local originals=state.Originals[side]

    local complete=true
    for index=1,3 do
        if not originals[index] then complete=false break end
    end

    if not complete then
        return applyDescriptionFallback(state)
    end

    state.Applying[side]=true
    local success=true
    for index=1,3 do
        local clone=cloneBodyPart(originals[index])
        if not clone then
            success=false
            break
        end
        clone.Name=SIDE_NAMES[side][index]
        clone:SetAttribute(KORBLOX_MARKER,nil)

        local ok,result=pcall(function()
            return state.Humanoid:ReplaceBodyPartR15(SIDE_ENUMS[side][index],clone)
        end)
        if not ok or result==false then
            pcall(function() clone:Destroy() end)
            success=false
            break
        end
    end
    state.Applying[side]=false

    for _,connection in ipairs((state.PartConnections and state.PartConnections[side]) or {}) do
        disconnect(connection)
    end
    if state.PartConnections then state.PartConnections[side]={} end

    if not success then
        return applyDescriptionFallback(state)
    end
    return true
end

local scheduleSide

hookCurrentSideParts=function(state,side)
    if not state or not state.PartConnections then return end

    for _,connection in ipairs(state.PartConnections[side] or {}) do
        disconnect(connection)
    end
    state.PartConnections[side]={}

    local parts=getSideParts(state.Character,side)
    if not parts then return end

    for _,part in ipairs(parts) do
        if part:IsA("MeshPart") then
            local function changed()
                if currentState~=state or player.Character~=state.Character then return end
                if state.Applying[side] or not sideEnabled(side) then return end
                if os.clock()<state.SuppressAppearanceUntil then return end
                scheduleSide(state,side,0.06)
            end

            local okMesh,meshConnection=pcall(function()
                return part:GetPropertyChangedSignal("MeshId"):Connect(changed)
            end)
            if okMesh and meshConnection then
                table.insert(state.PartConnections[side],meshConnection)
            end

            local okTexture,textureConnection=pcall(function()
                return part:GetPropertyChangedSignal("TextureID"):Connect(changed)
            end)
            if okTexture and textureConnection then
                table.insert(state.PartConnections[side],textureConnection)
            end
        end
    end
end

scheduleSide=function(state,side,delayTime)
    if not state then return end
    state.RepairTokens[side]+=1
    local token=state.RepairTokens[side]
    local generation=state.Generation

    task.delay(delayTime or 0,function()
        if currentState~=state then return end
        if state.Generation~=generation then return end
        if state.RepairTokens[side]~=token then return end
        if player.Character~=state.Character then return end
        if not sideEnabled(side) then return end

        applySideNow(state,side)

        -- One bounded verification only. If a body converter is still replacing
        -- parts, ChildAdded/ApplyDescriptionFinished will schedule the next repair.
        task.delay(0.22,function()
            if currentState~=state or state.Generation~=generation then return end
            if not sideEnabled(side) or player.Character~=state.Character then return end

            local parts=getSideParts(state.Character,side)
            local good=parts~=nil
            if good then
                for _,part in ipairs(parts) do
                    if part:GetAttribute(KORBLOX_MARKER)~=side then
                        good=false
                        break
                    end
                end
            end

            if not good then
                state.RepairTokens[side]+=1
                local verifyToken=state.RepairTokens[side]
                task.delay(0.18,function()
                    if currentState==state
                        and state.Generation==generation
                        and state.RepairTokens[side]==verifyToken
                        and player.Character==state.Character
                        and sideEnabled(side) then
                        applySideNow(state,side)
                    end
                end)
            end
        end)
    end)
end

local function hookCharacterState(state)
    if not state or not state.Character then return end
    local char=state.Character
    local humanoid=state.Humanoid
    if not humanoid then return end

    local nameToSide={}
    for _,name in ipairs(SIDE_NAMES.Left) do nameToSide[name]="Left" end
    for _,name in ipairs(SIDE_NAMES.Right) do nameToSide[name]="Right" end

    table.insert(state.Connections,char.ChildAdded:Connect(function(child)
        local side=nameToSide[child.Name]
        if not side or not child:IsA("BasePart") then return end
        if currentState~=state or player.Character~=char then return end
        if state.Applying[side] then return end
        if os.clock()<state.SuppressAppearanceUntil then return end

        local marker=child:GetAttribute(KORBLOX_MARKER)
        if marker==side then return end

        -- A body converter/forced-R6 feature rebuilt this limb. Treat the new
        -- part as the latest base body, then put Korblox back without a respawn.
        captureOriginalPart(state,side,table.find(SIDE_NAMES[side],child.Name),child,true)
        if sideEnabled(side) then
            scheduleSide(state,side,0.08)
        end
    end))

    local ok,connection=pcall(function()
        return humanoid.ApplyDescriptionFinished:Connect(function()
            if currentState~=state or player.Character~=char then return end
            if os.clock()<state.SuppressAppearanceUntil then return end

            -- External appearance/body changes can rebuild parts in place or all
            -- at once. Refresh the baseline and reapply enabled sides once.
            captureBaselineDescription(state)
            if KorbloxSystem.LeftEnabled then
                captureOriginalSide(state,"Left",true)
                scheduleSide(state,"Left",0.08)
            end
            if KorbloxSystem.RightEnabled then
                captureOriginalSide(state,"Right",true)
                scheduleSide(state,"Right",0.08)
            end
        end)
    end)
    if ok and connection then table.insert(state.Connections,connection) end

    local appearanceConnection
    local okAppearance=pcall(function()
        appearanceConnection=player.CharacterAppearanceLoaded:Connect(function(loadedChar)
            if loadedChar~=char or currentState~=state then return end
            if KorbloxSystem.LeftEnabled then scheduleSide(state,"Left",0.06) end
            if KorbloxSystem.RightEnabled then scheduleSide(state,"Right",0.06) end
        end)
    end)
    if okAppearance and appearanceConnection then
        table.insert(state.Connections,appearanceConnection)
    end
end

local function ensureCharacterState(char)
    if not char then return nil end
    local state=beginCharacterState(char)
    if state and #(state.Connections or {})==0 then
        hookCharacterState(state)
    end
    return state
end

local function applyRight(char)
    local state=ensureCharacterState(char or player.Character)
    if not state or not KorbloxSystem.RightEnabled then return false end
    return applySideNow(state,"Right")
end

local function applyLeft(char)
    local state=ensureCharacterState(char or player.Character)
    if not state or not KorbloxSystem.LeftEnabled then return false end
    return applySideNow(state,"Left")
end

local function removeRight()
    local state=currentState
    if not state then return end
    state.RepairTokens.Right+=1
    restoreSideNow(state,"Right")
end

local function removeLeft()
    local state=currentState
    if not state then return end
    state.RepairTokens.Left+=1
    restoreSideNow(state,"Left")
end

local function scheduleRight(char)
    local state=ensureCharacterState(char or player.Character)
    if state and KorbloxSystem.RightEnabled then
        scheduleSide(state,"Right",0)
    end
end

local function scheduleLeft(char)
    local state=ensureCharacterState(char or player.Character)
    if state and KorbloxSystem.LeftEnabled then
        scheduleSide(state,"Left",0)
    end
end

KorbloxSystem.ApplyRight=applyRight
KorbloxSystem.RemoveRight=removeRight
KorbloxSystem.ApplyLeft=applyLeft
KorbloxSystem.RemoveLeft=removeLeft
KorbloxSystem.ScheduleRight=scheduleRight
KorbloxSystem.ScheduleLeft=scheduleLeft

KorbloxSystem.Schedule=function(char)
    local state=ensureCharacterState(char)
    if not state then return end
    if KorbloxSystem.RightEnabled then scheduleSide(state,"Right",0) end
    if KorbloxSystem.LeftEnabled then scheduleSide(state,"Left",0) end
end

KorbloxSystem.Reset=function()
    local state=currentState
    if state then
        state.RepairTokens.Left+=1
        state.RepairTokens.Right+=1
        if KorbloxSystem.LeftEnabled then restoreSideNow(state,"Left") end
        if KorbloxSystem.RightEnabled then restoreSideNow(state,"Right") end
        clearStateConnections(state)
    end
    currentState=nil
    stateGeneration+=1
    KorbloxSystem.RightEnabled=false
    KorbloxSystem.LeftEnabled=false
end

KorbloxSystem.RightToggle=addToggle(
    characterSection,
    "Korblox Right Leg",
    KorbloxSystem.RightEnabled,
    function(state)
        KorbloxSystem.RightEnabled=state
        SetCfg("korbloxEnabled",state)
        if state then
            scheduleRight(player.Character)
        else
            removeRight()
        end
    end
)

KorbloxSystem.LeftToggle=addToggle(
    characterSection,
    "Korblox Left Leg",
    KorbloxSystem.LeftEnabled,
    function(state)
        KorbloxSystem.LeftEnabled=state
        SetCfg("korbloxLeftEnabled",state)
        if state then
            scheduleLeft(player.Character)
        else
            removeLeft()
        end
    end
)
end)()
characterSection:AddParagraph(
    "No interruption on emoting",
    "Runs ATAOs-style True Anti Fling for as long as a Roblox avatar emote is playing, then turns it off."
)

local noInterruptionEmote=C("noInterruptionEmote",false)
local setupAutomaticEmoteProtection

;(function()
-- ============================================================
-- NO INTERRUPTION ON EMOTING (self-contained)
--
-- While a Roblox avatar emote track is playing on the local Animator, this
-- runs ATAOs' True/IY Anti Fling step on RunService.Stepped:
--     every other player -> every BasePart in their Character -> CanCollide=false
-- When the last emote track is gone the step is disconnected and every part
-- this feature switched off is switched back on.
--
-- It never plays, stops, seeks, replaces or freezes an animation, never
-- anchors anything, and never touches the local character or its description.
--
-- Detection is by animation track lifetime (Animator.AnimationPlayed ->
-- AnimationTrack.Stopped, backed by IsPlaying / GetPlayingAnimationTracks),
-- never by movement. Each new track is classified once:
--   1. known locomotion / user-excluded id            -> not an emote
--   2. lives inside the character's Animate script    -> emote only if it sits
--      in an emote group (wave/point/dance*/laugh/cheer), otherwise locomotion
--   3. lives inside a Tool or elsewhere in the game   -> not an emote
--      (this is what keeps MM2's own animations out)
--   4. id is a known avatar emote id                  -> emote
--   5. anything else (engine-created, no parent)      -> emote, unless it is a
--      very short one-shot action
-- ============================================================

-- true = print one line per new track (verdict + reason) and when protection
-- turns on/off. Use it to confirm a Roblox emote is caught and an MM2 emote
-- is not.
local DEBUG=false

local GRACE=0.3                   -- seconds protection bridges a track hand-off
local WATCHDOG=0.25               -- seconds between safety re-scans
local TREAT_UNKNOWN_AS_EMOTE=true -- rule 5 above
local MIN_UNKNOWN_LENGTH=0.6      -- unknown one-shots shorter than this are ignored

-- Classic Animate emote animations (R15 then R6). Avatar-wheel emotes are NOT
-- listed by id here: they are recognised structurally (rule 5) and, where the
-- ids happen to match, through HumanoidDescription:GetEmotes().
local CLASSIC_EMOTE_IDS={
    [507770239]=true,[507770453]=true,[507771019]=true,[507776043]=true,
    [507777268]=true,[507770818]=true,[507770677]=true,
    [128777973]=true,[128853357]=true,[182435998]=true,[182491037]=true,
    [182491065]=true,[129423131]=true,[129423030]=true,
}

-- Backup list of default locomotion/pose animations (R15 then R6). The live
-- Animate script and HumanoidDescription are scanned too and are authoritative;
-- this only matters when something plays a default animation by raw id.
local LOCOMOTION_IDS={
    [507766666]=true,[507766951]=true,[507766388]=true,[507777826]=true,
    [507767714]=true,[507765000]=true,[507767968]=true,[507765644]=true,
    [507784897]=true,[507785072]=true,[2506281703]=true,[507768375]=true,
    [522635514]=true,[522638767]=true,
    [180435571]=true,[180435792]=true,[180426354]=true,[125750702]=true,
    [180436148]=true,[180436334]=true,[178130996]=true,[182393478]=true,
    [129967390]=true,[129967478]=true,
}

-- Put animation ids here to force "never an emote" (e.g. an MM2 emote that the
-- DEBUG output shows being treated as one).
local EXCLUDED_ANIMATION_IDS={}

local EMOTE_GROUPS={
    wave=true,point=true,dance=true,dance2=true,dance3=true,laugh=true,cheer=true,
}

local LOCOMOTION_PROPS={
    "ClimbAnimation","FallAnimation","IdleAnimation","JumpAnimation",
    "RunAnimation","SwimAnimation","WalkAnimation",
}

local emoteIds,locomotionIds=CLASSIC_EMOTE_IDS,LOCOMOTION_IDS
local active=setmetatable({}, {__mode="k"})   -- track -> true while an emote track is live
local verdicts=setmetatable({}, {__mode="k"})  -- track -> cached classification
local stoppedConns={}                          -- track -> Stopped connection
local changed=setmetatable({}, {__mode="k"})   -- part -> true (it was collidable before we cleared it)
local charConns,humanoidConns,animatorConns={}, {}, {}
local stepConn=nil
local graceUntil=0
local session=0
local boundChar,boundHumanoid,boundAnimator=nil,nil,nil
local resolveBindings

local function dprint(...)
    if DEBUG then print("[VisualsV2 emote]",...) end
end

local function numericId(value)
    if type(value)=="number" then
        if value>0 then return value end
        return nil
    end
    if type(value)~="string" then return nil end
    return tonumber(value:match("%d+"))
end

local function addId(set,value)
    local id=numericId(value)
    if id then set[id]=true end
end

local function disconnectAll(list)
    for i=#list,1,-1 do
        local conn=list[i]
        list[i]=nil
        pcall(function() conn:Disconnect() end)
    end
end

-- Name (lower-case) of the direct child of the character's Animate-style
-- script that contains this animation, or nil if it is not inside one.
local function animateGroupName(animation,char)
    if not char or not animation:IsDescendantOf(char) then return nil end
    local node=animation
    while node.Parent and node.Parent~=char do
        if node.Parent:IsA("LuaSourceContainer") then
            return node.Name:lower()
        end
        node=node.Parent
    end
    return nil
end

local function isEmoteGroup(name)
    if EMOTE_GROUPS[name] then return true end
    return name:find("emote",1,true)~=nil
end

-- Tool animations and anything parented inside the game belong to the game
-- (knife/gun animations, MM2's own emote system, other scripts).
local function isGameOwned(animation,char)
    if animation:FindFirstAncestorOfClass("Tool") then return true end
    if char and animation:IsDescendantOf(char) then return false end
    return animation:IsDescendantOf(game)
end

-- Rebuilds the id sets from the live Animate script and HumanoidDescription.
-- May yield, so it is only ever called from its own thread.
local function refreshCatalog(char,humanoid)
    local emotes,moves={}, {}
    for id in pairs(CLASSIC_EMOTE_IDS) do emotes[id]=true end
    for id in pairs(LOCOMOTION_IDS) do moves[id]=true end

    if char then
        for _,child in ipairs(char:GetChildren()) do
            if child:IsA("LuaSourceContainer") then
                for _,animation in ipairs(child:GetDescendants()) do
                    if animation:IsA("Animation") then
                        local id=numericId(animation.AnimationId)
                        local group=animateGroupName(animation,char)
                        if id and group then
                            if isEmoteGroup(group) then
                                emotes[id]=true
                            else
                                moves[id]=true
                            end
                        end
                    end
                end
            end
        end
    end

    if humanoid then
        local okDescription,description=pcall(function()
            return humanoid:GetAppliedDescription()
        end)
        if okDescription and description then
            for _,prop in ipairs(LOCOMOTION_PROPS) do
                local okProp,value=pcall(function() return description[prop] end)
                if okProp then addId(moves,value) end
            end
            local okEmotes,dictionary=pcall(function()
                return description:GetEmotes()
            end)
            if okEmotes and type(dictionary)=="table" then
                for _,ids in pairs(dictionary) do
                    if type(ids)=="table" then
                        for _,id in ipairs(ids) do addId(emotes,id) end
                    end
                end
            end
        end
    end

    -- an id the game's own Animate treats as locomotion can never be an emote
    for id in pairs(moves) do emotes[id]=nil end
    emoteIds,locomotionIds=emotes,moves
end

-- Returns isEmote, reason.
local function judgeTrack(track,char)
    local animation=track.Animation
    if not animation then return false,"track has no Animation" end

    local id=numericId(animation.AnimationId)
    if id and EXCLUDED_ANIMATION_IDS[id] then return false,"excluded id" end
    if id and locomotionIds[id] then return false,"locomotion id" end

    local group=animateGroupName(animation,char)
    if group then
        if isEmoteGroup(group) then return true,"Animate emote group '"..group.."'" end
        return false,"Animate group '"..group.."'"
    end

    if isGameOwned(animation,char) then return false,"game-owned animation" end
    if id and emoteIds[id] then return true,"known avatar emote id" end
    if not TREAT_UNKNOWN_AS_EMOTE then return false,"unknown animation" end

    if not track.Looped then
        local length=track.Length
        if length>0 and length<MIN_UNKNOWN_LENGTH then
            return false,"short one-shot action"
        end
    end
    return true,"unknown engine-created animation"
end

local function describeTrack(track)
    local animation=track.Animation
    local where="nil"
    if animation and animation.Parent then where=animation:GetFullName() end
    return string.format(
        "track=%s anim=%s id=%s parent=%s priority=%s looped=%s length=%.2f",
        tostring(track.Name),
        animation and tostring(animation.Name) or "nil",
        animation and tostring(animation.AnimationId) or "nil",
        where,tostring(track.Priority),tostring(track.Looped),track.Length
    )
end

local function readIsPlaying(track)
    return track.IsPlaying
end

local function trackPlaying(track)
    local ok,playing=pcall(readIsPlaying,track)
    return ok and playing==true
end

local function dropTrack(track)
    active[track]=nil
    local conn=stoppedConns[track]
    if conn then
        stoppedConns[track]=nil
        pcall(function() conn:Disconnect() end)
    end
    graceUntil=os.clock()+GRACE
end

local function clearEmotes()
    for track,conn in pairs(stoppedConns) do
        stoppedConns[track]=nil
        pcall(function() conn:Disconnect() end)
    end
    table.clear(active)
    graceUntil=0
end

-- True while any recognised emote track is playing (or just ended: GRACE
-- bridges multi-stage emotes that hand over from one track to the next).
local function emoteActive()
    for track in pairs(active) do
        if trackPlaying(track) then return true end
        dropTrack(track)
    end
    return os.clock()<graceUntil
end

-- ATAOs True/IY Anti Fling step. Only parts that were collidable are touched
-- and remembered, so restoring never alters anything this feature didn't change.
local function applyStep()
    for _,other in ipairs(Players:GetPlayers()) do
        if other~=player then
            local character=other.Character
            if character then
                for _,part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        changed[part]=true
                        part.CanCollide=false
                    end
                end
            end
        end
    end
end

local function setCollidable(part)
    part.CanCollide=true
end

local function restoreCollisions()
    local count=0
    for part in pairs(changed) do
        changed[part]=nil
        count+=1
        if part.Parent then pcall(setCollidable,part) end
    end
    return count
end

local function stopProtection()
    local wasRunning=stepConn~=nil
    if stepConn then
        local conn=stepConn
        stepConn=nil
        pcall(function() conn:Disconnect() end)
    end
    local restored=restoreCollisions()
    if wasRunning or restored>0 then
        dprint("anti-fling OFF, restored",restored,"parts")
    end
end

local function onStepped()
    if not noInterruptionEmote or not emoteActive() then
        stopProtection()
        return
    end
    applyStep()
end

local function ensureProtection()
    if not noInterruptionEmote or stepConn then return end
    stepConn=RunService.Stepped:Connect(onStepped)
    dprint("anti-fling ON")
    applyStep() -- no gap between the emote starting and the first Stepped
end

local function handleTrack(track)
    if not noInterruptionEmote or not track or active[track] then return end

    local verdict=verdicts[track]
    if verdict==nil then
        local ok,isEmote,reason=pcall(judgeTrack,track,boundChar)
        if ok then
            verdict=isEmote==true
        else
            verdict=false
            reason=tostring(isEmote)
        end
        verdicts[track]=verdict
        if DEBUG then
            local okInfo,info=pcall(describeTrack,track)
            dprint(verdict and "EMOTE" or "ignore","|",reason,"|",okInfo and info or "?")
        end
    end
    if not verdict then return end

    active[track]=true
    local okConn,conn=pcall(function()
        return track.Stopped:Connect(function()
            dropTrack(track)
        end)
    end)
    if okConn and conn then stoppedConns[track]=conn end
    ensureProtection()
end

local function scanPlaying(animator)
    local ok,tracks=pcall(function()
        return animator:GetPlayingAnimationTracks()
    end)
    if ok and type(tracks)=="table" then
        for _,track in ipairs(tracks) do handleTrack(track) end
    end
end

local function bindAnimator(animator)
    disconnectAll(animatorConns)
    boundAnimator=animator
    if not animator then return end
    pcall(function()
        table.insert(animatorConns,animator.AnimationPlayed:Connect(handleTrack))
    end)
    scanPlaying(animator)
end

local function bindHumanoid(humanoid)
    disconnectAll(humanoidConns)
    bindAnimator(nil)
    boundHumanoid=humanoid
    if not humanoid then return end

    -- Independent fallback for engines/forced rigs that race the Animator hook.
    pcall(function()
        table.insert(humanoidConns,humanoid.AnimationPlayed:Connect(handleTrack))
    end)
    pcall(function()
        table.insert(humanoidConns,humanoid.ChildAdded:Connect(function(child)
            if child:IsA("Animator") and boundChar then
                task.defer(resolveBindings,boundChar)
            end
        end))
    end)
    pcall(function()
        table.insert(humanoidConns,humanoid.ApplyDescriptionFinished:Connect(function()
            task.defer(refreshCatalog,boundChar,humanoid)
        end))
    end)
    task.spawn(refreshCatalog,boundChar,humanoid)
end

-- Re-resolves Humanoid and Animator from the live character and rebinds if
-- either was replaced (forced R6/R15 swaps, Animator rebuilds).
resolveBindings=function(char)
    if not char or boundChar~=char then return end
    local humanoid=char:FindFirstChildOfClass("Humanoid")
    if humanoid~=boundHumanoid then
        bindHumanoid(humanoid)
    end
    local animator=nil
    if humanoid then animator=humanoid:FindFirstChildOfClass("Animator") end
    if animator~=boundAnimator then
        bindAnimator(animator)
    end
end

local function teardown()
    session+=1
    disconnectAll(charConns)
    disconnectAll(humanoidConns)
    disconnectAll(animatorConns)
    clearEmotes()
    boundChar,boundHumanoid,boundAnimator=nil,nil,nil
    stopProtection()
end

-- Never yields: all waiting happens in its own thread, so callers (such as
-- the respawn hook that also sets up jump circles) are not delayed.
setupAutomaticEmoteProtection=function(char)
    teardown()
    if not noInterruptionEmote or not char then return end

    local mySession=session
    boundChar=char

    local function alive()
        return noInterruptionEmote
            and session==mySession
            and boundChar==char
            and char.Parent~=nil
            and player.Character==char
    end

    pcall(function()
        table.insert(charConns,player.CharacterRemoving:Connect(function(removing)
            if removing==char and session==mySession then
                clearEmotes()
                stopProtection()
            end
        end))
    end)
    pcall(function()
        table.insert(charConns,player.CharacterAppearanceLoaded:Connect(function(loaded)
            if loaded==char and alive() then
                task.spawn(refreshCatalog,char,boundHumanoid)
            end
        end))
    end)
    pcall(function()
        table.insert(charConns,char.ChildAdded:Connect(function(child)
            if not alive() then return end
            if child:IsA("Humanoid") then
                task.defer(resolveBindings,char)
            elseif child:IsA("LuaSourceContainer") then
                task.defer(refreshCatalog,char,boundHumanoid)
            end
        end))
    end)

    task.spawn(function()
        while alive() do
            resolveBindings(char)
            if boundAnimator then scanPlaying(boundAnimator) end
            if not stepConn and emoteActive() then ensureProtection() end
            task.wait(WATCHDOG)
        end
        if session==mySession then
            clearEmotes()
            stopProtection()
        end
    end)
end

local noInterruptionToggle=addToggle(
    characterSection,
    "No interruption on emoting",
    noInterruptionEmote,
    function(state)
        noInterruptionEmote=state
        SetCfg("noInterruptionEmote",state)

        if state then
            setupAutomaticEmoteProtection(player.Character)
        else
            teardown()
        end
    end
)

if noInterruptionEmote and player.Character then
    task.defer(function()
        setupAutomaticEmoteProtection(player.Character)
    end)
end

env.VisualsV2Runtime.RegisterReset(function()
    headlessToggle:Set(false)
    headlessEnabled=false
    applyCharacterVisuals()
    if KorbloxSystem.RightToggle then KorbloxSystem.RightToggle:Set(false) end
    if KorbloxSystem.LeftToggle then KorbloxSystem.LeftToggle:Set(false) end
    KorbloxSystem.Reset()

    noInterruptionToggle:Set(false)
    noInterruptionEmote=false
    teardown()
end)
end)()


-- =========================================================
-- UTILITIES: SPEED GLITCH
-- =========================================================

local speedSection = mainTab:AddSection("Speed Glitch", "Utilities")
speedSection:AddParagraph(
    "Speed Glitch",
    "Only works while Shift Lock is active. Using very high speeds for a fairly long period of time may cause the game to kick you."
)
local speedEnabled = C("speedGlitchEnabled", false)
local speedValue = C("speedValue", 50)
local speedButtonVisible = C("speedButtonVisible", false)
local speedButtonWidth = C("speedButtonWidth", 115)
local speedButtonHeight = C("speedButtonHeight", 45)
local speedButtonColor = C("speedButtonColor",Color3.fromRGB(38,38,38))
local speedButtonTransparency = C("speedButtonTransparency", 4)
if tonumber(speedButtonTransparency) and speedButtonTransparency < 1 then speedButtonTransparency = 1 + (speedButtonTransparency * 4) end
local speedBindButtonVisible = C("speedBindButtonVisible", false)
local speedBindButtonSize = math.clamp(tonumber(C("speedBindButtonSize", 5)) or 5, 1, 10)
local lockBigButtonPos = C("lockBigButtonPos", false)
local lockBindButtonPos = C("lockBindButtonPos", false)
local speedGui, speedButton, speedToggle
local BIG_BUTTON_DEFAULT = UDim2.new(0.5, 0, 0.5, 0)
local BIND_BUTTON_DEFAULT = UDim2.new(0.10, 0, 0.90, 0)

local function loadStoredPosition(key, fallback)
    local data = C(key, nil)
    if type(data) ~= "table" then
        SetCfg(key, {
            xs = fallback.X.Scale,
            xo = fallback.X.Offset,
            ys = fallback.Y.Scale,
            yo = fallback.Y.Offset,
        })
        return fallback
    end
    return UDim2.new(
        tonumber(data.xs or data.XS) or fallback.X.Scale,
        tonumber(data.xo or data.XO) or fallback.X.Offset,
        tonumber(data.ys or data.YS) or fallback.Y.Scale,
        tonumber(data.yo or data.YO) or fallback.Y.Offset
    )
end

local function saveStoredPosition(key, pos)
    SetCfg(key, {
        xs = pos.X.Scale,
        xo = pos.X.Offset,
        ys = pos.Y.Scale,
        yo = pos.Y.Offset,
    })
end

local function fiveStepTransparency(value)
    return math.clamp(((tonumber(value) or 1) - 1) / 4, 0, 1)
end

-- ODH bindable-button implementation, based on the supplied BindableButtons.luau.
-- Extra setters only adjust the SG button; the visual/interaction style remains ODH's.
local BindableButtons = (function()
    local buttons = {Buttons={}, Maids={}, Locked={}, Callbacks={}, Count=0}
    local shapes = {
        [0] = "rbxassetid://86221076925479",
        [1] = "rbxassetid://96242665417546",
        [2] = "rbxassetid://97129189935336",
        [3] = "rbxassetid://76165862027868",
        [4] = "rbxassetid://125868092127496",
    }
    local normalColor = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(0.133333, 0.827451, 0.494118)),
        ColorSequenceKeypoint.new(0.6, Color3.new(0.231373, 0.509804, 0.498039)),
        ColorSequenceKeypoint.new(1, Color3.new(0.501961, 0.501961, 0.501961)),
    })
    local toggledColor = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(0.0784314, 0.0784314, 0.0784314)),
        ColorSequenceKeypoint.new(0.75, Color3.new(0.0784314, 0.0784314, 0.54902)),
        ColorSequenceKeypoint.new(1, Color3.new(0.470588, 0.156863, 0.470588)),
    })

    local function storage()
        local roots={}
        if type(gethui)=="function" then
            local ok,result=pcall(gethui)
            if ok and typeof(result)=="Instance" then table.insert(roots,result) end
        end
        local okCore,core=pcall(function() return game:GetService("CoreGui") end)
        if okCore and typeof(core)=="Instance" then table.insert(roots,core) end
        local pg=player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")
        table.insert(roots,pg)
        for _,root in ipairs(roots) do
            local ok,existing=pcall(function() return root:FindFirstChild("@bindstorage") end)
            if ok and typeof(existing)=="Instance" and existing:IsA("ScreenGui") then return existing end
        end
        local sg=Instance.new("ScreenGui")
        sg.Name="@bindstorage"
        sg.ResetOnSpawn=false
        sg.IgnoreGuiInset=true
        pcall(function() sg.ScreenInsets=Enum.ScreenInsets.None end)
        sg.Parent=pg
        return sg
    end

    function buttons:DeleteBButton(id)
        local maid=self.Maids[id]
        if maid then
            for _,item in ipairs(maid) do
                if typeof(item)=="RBXScriptConnection" then pcall(function() item:Disconnect() end)
                elseif typeof(item)=="Instance" then pcall(function() item:Destroy() end) end
            end
        end
        local b=self.Buttons[id]
        if b then pcall(function() b:Destroy() end) end
        self.Buttons[id],self.Maids[id],self.Locked[id],self.Callbacks[id]=nil,nil,nil,nil
    end

    function buttons:SetShape(id,shape)
        local b=self.Buttons[id]
        if b and shapes[shape] then b.Image=shapes[shape] end
    end
    function buttons:SetLocked(id,state) self.Locked[id]=not not state end
    function buttons:SetVisible(id,state) local b=self.Buttons[id]; if b then b.Visible=not not state end end
    function buttons:SetText(id,text) local b=self.Buttons[id]; local l=b and b:FindFirstChild("@Text"); if l then l.Text=tostring(text or "") end end
    function buttons:SetPosition(id,pos) local b=self.Buttons[id]; if b then b.Position=pos end end
    function buttons:GetPosition(id) local b=self.Buttons[id]; return b and b.Position or nil end
    function buttons:SetSize(id,level)
        local b=self.Buttons[id]; if not b then return end
        level=math.clamp(tonumber(level) or 2,1,10)
        -- The stock ODH button is much larger. 1..10 maps down to 14..50 px
        -- so level 1 can be substantially smaller than ODH's normal minimum.
        local px=14+((level-1)*4)
        b.Size=UDim2.fromOffset(px,px)
        local label=b:FindFirstChild("@Text")
        if label and label:IsA("TextLabel") then
            label.TextSize=math.clamp(math.floor(px*0.34),6,10)
        end
    end
    function buttons:SetValue(id,state,runCallback)
        local b=self.Buttons[id]; if not b then return end
        local value=b:FindFirstChild("BindValue")
        if not value then return end
        state=not not state
        if value.Value~=state then
            value.Value=state
            if runCallback then
                local callbacks=self.Callbacks[id]
                if callbacks then
                    if state then pcall(callbacks[1]) else pcall(callbacks[2]) end
                end
            end
        end
        local stroke=b:FindFirstChild("@Stroke")
        if stroke and stroke:IsA("UIGradient") then stroke.Color=state and toggledColor or normalColor end
    end

    function buttons.AddBButton(id,text,onFunc,offFunc,onMoved)
        buttons:DeleteBButton(id)
        local root=storage()
        local old=root:FindFirstChild(id)
        if old then old:Destroy() end

        local cameraNow=workspace.CurrentCamera
        local screen=cameraNow and cameraNow.ViewportSize or Vector2.new(1920,1080)
        local buttonSizeY=0.11
        local widthScale=buttonSizeY*(screen.Y/math.max(1,screen.X))
        local xPos=0.1+((buttons.Count%8)*(widthScale+0.005))
        local yPos=0.9-(math.floor(buttons.Count/8)*(buttonSizeY+0.015))

        local b=Instance.new("ImageButton")
        b.Name=id
        b.Size=UDim2.new(widthScale,0,buttonSizeY,0)
        b.Position=UDim2.new(xPos,0,yPos,0)
        b.AnchorPoint=Vector2.new(0.5,0.5)
        b.Image=shapes[0]
        b.BackgroundTransparency=1
        b.BorderSizePixel=0
        b.ClipsDescendants=false
        b.AutoButtonColor=false
        b.Parent=root

        local value=Instance.new("BoolValue")
        value.Name="BindValue"
        value.Parent=b

        local label=Instance.new("TextLabel")
        label.Name="@Text"
        label.Size=UDim2.fromScale(0.8,0.8)
        label.Position=UDim2.fromScale(0.5,0.5)
        label.AnchorPoint=Vector2.new(0.5,0.5)
        label.BackgroundTransparency=1
        label.Font=Enum.Font.Jura
        label.Text=tostring(text or "")
        label.TextColor3=Color3.new(1,1,1)
        label.TextSize=10
        label.TextWrapped=true
        label.ZIndex=3
        label.Parent=b

        local aspect=Instance.new("UIAspectRatioConstraint")
        aspect.AspectRatio=1
        aspect.AspectType=Enum.AspectType.ScaleWithParentSize
        aspect.Parent=b

        local stroke=Instance.new("UIGradient")
        stroke.Name="@Stroke"
        stroke.Color=normalColor
        stroke.Parent=b

        local ripple=Instance.new("Frame")
        ripple.Name="@ripple"
        ripple.BackgroundColor3=Color3.fromRGB(0,155,255)
        ripple.BackgroundTransparency=0.5
        ripple.Size=UDim2.fromOffset(0,0)
        ripple.AnchorPoint=Vector2.new(0.5,0.5)
        ripple.Visible=false
        ripple.ZIndex=2
        ripple.Parent=b
        Instance.new("UICorner",ripple).CornerRadius=UDim.new(1,0)

        local sound=Instance.new("Sound")
        sound.SoundId="rbxassetid://3868133279"
        sound.Volume=0.5
        sound.Parent=b

        buttons.Buttons[id]=b
        buttons.Maids[id]={}
        buttons.Locked[id]=false
        buttons.Callbacks[id]={onFunc,offFunc}
        buttons.Count+=1

        local dragging=false
        local dragInput,dragStart,startPos
        local moved=false
        local debounce=false
        local conns=buttons.Maids[id]

        local function click()
            if debounce then return end
            debounce=true
            local fadeOut=TweenService:Create(b,TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.InOut),{ImageTransparency=1})
            fadeOut:Play(); fadeOut.Completed:Wait()
            value.Value=not value.Value
            stroke.Color=value.Value and toggledColor or normalColor
            if value.Value then pcall(onFunc) else pcall(offFunc) end
            local baseAlpha=tonumber(b:GetAttribute("VisualsV2BaseImageTransparency")) or 0
            local fadeIn=TweenService:Create(b,TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.InOut),{ImageTransparency=baseAlpha})
            fadeIn:Play(); fadeIn.Completed:Wait()
            debounce=false
        end

        table.insert(conns,b.InputBegan:Connect(function(input)
            if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
            dragging=true; moved=false; dragStart=input.Position; startPos=b.Position
            pcall(function() sound:Play() end)
            local abs=b.AbsolutePosition
            ripple.Position=UDim2.fromOffset(input.Position.X-abs.X,input.Position.Y-abs.Y)
            ripple.Size=UDim2.fromOffset(0,0); ripple.BackgroundTransparency=0.5; ripple.Visible=true
            TweenService:Create(ripple,TweenInfo.new(0.4,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(45,45),BackgroundTransparency=1}):Play()
        end))
        table.insert(conns,b.InputChanged:Connect(function(input)
            if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then dragInput=input end
        end))
        table.insert(conns,UserInputService.InputChanged:Connect(function(input)
            if input~=dragInput or not dragging or buttons.Locked[id] then return end
            local delta=input.Position-dragStart
            if delta.Magnitude>7 then moved=true end
            local parentSize=b.Parent.AbsoluteSize
            if parentSize.X>0 and parentSize.Y>0 then
                b.Position=UDim2.new(startPos.X.Scale+(delta.X/parentSize.X),0,startPos.Y.Scale+(delta.Y/parentSize.Y),0)
            end
        end))
        table.insert(conns,UserInputService.InputEnded:Connect(function(input)
            if not dragging then return end
            if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
            dragging=false
            if moved and not buttons.Locked[id] then
                if onMoved then pcall(onMoved,b.Position) end
            elseif not moved then
                task.spawn(click)
            end
        end))
        table.insert(conns,RunService.RenderStepped:Connect(function() stroke.Rotation=(stroke.Rotation+1)%360 end))
        return value
    end

    return buttons
end)()

local function updateSpeedButtonStyle()
    if speedButton then
        speedButton.Size=UDim2.fromOffset(speedButtonWidth,speedButtonHeight)
        speedButton.BackgroundColor3=speedButtonColor
        speedButton.BackgroundTransparency=fiveStepTransparency(speedButtonTransparency)
        speedButton.Text=speedEnabled and "Active" or "Off"
        speedButton.TextScaled=false
        speedButton.TextSize=math.max(10,math.floor(speedButtonHeight*0.38))
        speedButton.TextStrokeTransparency=1
        speedButton.Visible=speedButtonVisible
    end
    local id="VisualsV2_SpeedBind"
    BindableButtons:SetVisible(id,speedBindButtonVisible)
    BindableButtons:SetLocked(id,lockBindButtonPos)
    BindableButtons:SetSize(id,speedBindButtonSize)
    BindableButtons:SetText(id,"SG")
    BindableButtons:SetValue(id,speedEnabled,false)
end

local function setSpeedState(state)
    if speedToggle then speedToggle:Set(state) end
end

local function makeBigButtonDraggable(button)
    local active=false
    local moved=false
    local dragStart,startPos,dragInput
    button.InputBegan:Connect(function(input)
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        active=true; moved=false; dragStart=input.Position; startPos=button.Position
    end)
    button.InputChanged:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then dragInput=input end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not active or input~=dragInput or lockBigButtonPos then return end
        local delta=input.Position-dragStart
        if delta.Magnitude>7 then moved=true end
        button.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
    end)
    UserInputService.InputEnded:Connect(function(input)
        if not active then return end
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        active=false
        if moved and not lockBigButtonPos then
            saveStoredPosition("speedButtonPosition",button.Position)
        else
            setSpeedState(not speedEnabled)
        end
    end)
end

local function setupSpeedButtons()
    if speedGui then speedGui:Destroy() end
    BindableButtons:DeleteBButton("VisualsV2_SpeedBind")

    local gui=Instance.new("ScreenGui")
    gui.Name="VisualsV2_SpeedGlitchUI"
    gui.ResetOnSpawn=false
    gui.IgnoreGuiInset=true
    gui.Parent=player:WaitForChild("PlayerGui")
    speedGui=gui

    local big=Instance.new("TextButton")
    big.Name="SpeedGlitchBigButton"
    big.AnchorPoint=Vector2.new(0.5,0.5)
    big.Position=loadStoredPosition("speedButtonPosition",BIG_BUTTON_DEFAULT)
    big.BackgroundColor3=speedButtonColor
    big.BorderSizePixel=0
    big.TextColor3=Color3.new(1,1,1)
    big.Font=Enum.Font.Jura
    big.AutoButtonColor=false
    big.Active=true
    big.Parent=gui
    speedButton=big

    local corner=Instance.new("UICorner")
    corner.CornerRadius=UDim.new(0,5)
    corner.Parent=big
    makeBigButtonDraggable(big)

    BindableButtons.AddBButton(
        "VisualsV2_SpeedBind",
        "SG",
        function() setSpeedState(true) end,
        function() setSpeedState(false) end,
        function(pos) saveStoredPosition("speedBindButtonPosition",pos) end
    )
    BindableButtons:SetShape("VisualsV2_SpeedBind",1)
    BindableButtons:SetPosition("VisualsV2_SpeedBind",loadStoredPosition("speedBindButtonPosition",BIND_BUTTON_DEFAULT))
    updateSpeedButtonStyle()
end

speedToggle=addToggle(speedSection,"Enable Speed Glitch",speedEnabled,function(state)
    speedEnabled=state
    SetCfg("speedGlitchEnabled",state)
    updateSpeedButtonStyle()
end)
speedSection:AddSlider("Speed",1,300,speedValue,function(value)
    speedValue=value
    SetCfg("speedValue",value)
end)
local speedKeyName=tostring(C("speedGlitchKeybind","G"))
local speedKeyCode
pcall(function() speedKeyCode=Enum.KeyCode[speedKeyName] end)
if not speedKeyCode or speedKeyCode==Enum.KeyCode.Unknown then
    speedKeyName="G"
    speedKeyCode=Enum.KeyCode.G
    SetCfg("speedGlitchKeybind",speedKeyName)
end
local choosingSpeedKey=false
local speedKeyConnection
local function connectSpeedKeybind()
    if speedKeyConnection then return end
    speedKeyConnection=UserInputService.InputBegan:Connect(function(input,processed)
        if input.UserInputType~=Enum.UserInputType.Keyboard then return end
        if choosingSpeedKey then
            if input.KeyCode==Enum.KeyCode.Unknown then return end
            choosingSpeedKey=false
            if input.KeyCode==Enum.KeyCode.Escape then
                shared.Notify("Speed Glitch bind selection cancelled",2)
                return
            end
            speedKeyCode=input.KeyCode
            speedKeyName=speedKeyCode.Name
            SetCfg("speedGlitchKeybind",speedKeyName)
            shared.Notify("Speed Glitch bind saved: "..speedKeyName,2)
        elseif not processed and not UserInputService:GetFocusedTextBox() and input.KeyCode==speedKeyCode then
            setSpeedState(not speedEnabled)
        end
    end)
end
speedSection:AddButton("Speed Glitch Bind",function()
    choosingSpeedKey=true
    connectSpeedKeybind()
    shared.Notify("Press a key to bind Speed Glitch (current: "..speedKeyName.."). Escape cancels.",3)
end)
connectSpeedKeybind()
addToggle(speedSection,"Show Big Button",speedButtonVisible,function(state)
    speedButtonVisible=state; SetCfg("speedButtonVisible",state); updateSpeedButtonStyle()
end)
addToggle(speedSection,"Show Bindable Button",speedBindButtonVisible,function(state)
    speedBindButtonVisible=state; SetCfg("speedBindButtonVisible",state); updateSpeedButtonStyle()
end)
speedSection:AddSlider("Big Button Width",70,260,speedButtonWidth,function(value)
    speedButtonWidth=value; SetCfg("speedButtonWidth",value); updateSpeedButtonStyle()
end)
speedSection:AddSlider("Big Button Height",28,110,speedButtonHeight,function(value)
    speedButtonHeight=value; SetCfg("speedButtonHeight",value); updateSpeedButtonStyle()
end)
speedSection:AddColorpicker("Big Button Color",speedButtonColor,function(color)
    speedButtonColor=color; SetCfg("speedButtonColor",color); updateSpeedButtonStyle()
end)
speedSection:AddSlider("Big Button Transparency",1,5,speedButtonTransparency,function(value)
    speedButtonTransparency=math.clamp(tonumber(value) or 1,1,5)
    SetCfg("speedButtonTransparency",speedButtonTransparency)
    updateSpeedButtonStyle()
end)
speedSection:AddSlider("Bind Button Size",1,10,speedBindButtonSize,function(value)
    speedBindButtonSize=math.clamp(tonumber(value) or 5,1,10)
    SetCfg("speedBindButtonSize",speedBindButtonSize)
    updateSpeedButtonStyle()
end)
setupSpeedButtons()

local function shiftLockActive()
    return UserInputService.MouseBehavior==Enum.MouseBehavior.LockCenter
end

RunService.Heartbeat:Connect(function()
    local char=player.Character
    local humanoid=char and char:FindFirstChildOfClass("Humanoid")
    local hrp=char and char:FindFirstChild("HumanoidRootPart")
    if speedEnabled and shiftLockActive() and humanoid and hrp and humanoid.FloorMaterial==Enum.Material.Air then
        local moveDir=humanoid.MoveDirection
        if moveDir.Magnitude>0 then
            local vel=hrp.AssemblyLinearVelocity
            hrp.AssemblyLinearVelocity=Vector3.new(moveDir.X*speedValue,vel.Y,moveDir.Z*speedValue)
        end
    end
end)

env.VisualsV2Runtime.RegisterReset(function()
    choosingSpeedKey=false
    if speedKeyConnection then speedKeyConnection:Disconnect(); speedKeyConnection=nil end
    speedToggle:Set(false)
    speedEnabled=false
    speedButtonVisible=false
    speedBindButtonVisible=false
    lockBigButtonPos=false
    lockBindButtonPos=false
    speedButtonWidth=115
    speedButtonHeight=45
    speedButtonColor=Color3.fromRGB(0,0,0)
    speedButtonTransparency=4
    speedBindButtonSize=5
    if speedButton then speedButton.Position=BIG_BUTTON_DEFAULT; speedButton.Visible=false end
    BindableButtons:SetPosition("VisualsV2_SpeedBind",BIND_BUTTON_DEFAULT)
    BindableButtons:SetVisible("VisualsV2_SpeedBind",false)
    BindableButtons:SetLocked("VisualsV2_SpeedBind",false)
    updateSpeedButtonStyle()
end)

-- =========================================================
-- UTILITIES: ANTI-AIM EXTENSION
-- =========================================================

;(function()
local shared = odh_shared_plugins

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local userWantsEnabled = C("aaEnabled",false)
local enabled = false
local velocityConnection = nil
local hadKnifeLastFrame = false

local ignoreListEnabled = C("aaIgnoreListEnabled",true)
local slot1Player = nil
local slot2Player = nil
local slot3Player = nil

local aaSection = mainTab:AddSection("Anti-Aim Extension", "Utilities")
local slot1Name=tostring(C("aaIgnorePlayer1","None"))
local slot2Name=tostring(C("aaIgnorePlayer2","None"))
local slot3Name=tostring(C("aaIgnorePlayer3","None"))
local dropdownRefreshing=false

local function getPlayerList()
    local list = {"None"}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(list, p.Name)
        end
    end
    return list
end

local function findPlayerByName(name)
    if not name or name == "None" then return nil end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name == name then
            return p
        end
    end
    return nil
end

slot1Player=findPlayerByName(slot1Name)
slot2Player=findPlayerByName(slot2Name)
slot3Player=findPlayerByName(slot3Name)

local function hasKnife()
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local character = LocalPlayer.Character
    if backpack and backpack:FindFirstChild("Knife") then
        return true
    end
    if character and character:FindFirstChild("Knife") then
        return true
    end
    return false
end

local function isPlayerNearby(hrp)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local otherHrp = player.Character.HumanoidRootPart
            if (otherHrp.Position - hrp.Position).Magnitude <= 6 then
                return true
            end
        end
    end
    return false
end

local function isInWater(humanoid)
    local state = humanoid:GetState()
    return state == Enum.HumanoidStateType.Swimming or humanoid.FloorMaterial == Enum.Material.Water
end

local function isIgnoredPlayerArmed()
    if not ignoreListEnabled then
        return false
    end

    local targets = {slot1Player, slot2Player, slot3Player}
    for _, player in ipairs(targets) do
        if player and player.Parent then
            local backpack = player:FindFirstChild("Backpack")
            local character = player.Character
            
            if backpack then
                for _, item in ipairs(backpack:GetChildren()) do
                    if item:IsA("Tool") then
                        return true
                    end
                end
            end
            
            if character then
                for _, item in ipairs(character:GetChildren()) do
                    if item:IsA("Tool") then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function performRoleStep(humanoid)
    task.spawn(function()
        local randomX = math.random() > 0.5 and 1 or -1
        local randomZ = math.random() > 0.5 and 1 or -1
        local moveDir = Vector3.new(randomX, 0, randomZ).Unit

        local startTime = tick()
        while tick() - startTime < 0.15 do
            if humanoid and humanoid.Parent then
                humanoid:Move(moveDir, false)
            end
            RunService.RenderStepped:Wait()
        end
    end)
end

local function stopAntiAim()
    if velocityConnection then
        velocityConnection:Disconnect()
        velocityConnection = nil
    end
end

local function startAntiAim()
    if velocityConnection then return end
    velocityConnection = RunService.Heartbeat:Connect(function()
        if isIgnoredPlayerArmed() then
            if enabled then
                enabled = false
            end
            return
        else
            if userWantsEnabled and not enabled then
                enabled = true
            end
        end

        local character = LocalPlayer.Character
        if character and character:FindFirstChild("HumanoidRootPart") and character:FindFirstChild("Humanoid") then
            local humanoid = character.Humanoid
            if humanoid.Health > 0 then
                local hrp = character.HumanoidRootPart
                local currentlyHasKnife = hasKnife()

                if currentlyHasKnife and not hadKnifeLastFrame then
                    performRoleStep(humanoid)
                end
                hadKnifeLastFrame = currentlyHasKnife

                if currentlyHasKnife and not isPlayerNearby(hrp) and not isInWater(humanoid) then
                    local oldVelocity = hrp.AssemblyLinearVelocity
                    local state = humanoid:GetState()
                    local isJumping = (state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall)
                    local isStopped = (humanoid.MoveDirection.Magnitude == 0)

                    local multiplier = math.random(1, 2) == 1 and 320 or -320
                    
                    if isJumping then
                        local jumpMultY = math.random(1, 2) == 1 and 250 or -250
                        hrp.AssemblyLinearVelocity = Vector3.new(multiplier, jumpMultY, multiplier)
                    elseif isStopped then
                        local stopMult = math.random(1, 2) == 1 and 400 or -400
                        hrp.AssemblyLinearVelocity = Vector3.new(stopMult, 0, stopMult)
                    else
                        hrp.AssemblyLinearVelocity = Vector3.new(multiplier, 0, multiplier)
                    end
                    
                    RunService.RenderStepped:Wait()
                    hrp.AssemblyLinearVelocity = oldVelocity
                end
            end
        else
            hadKnifeLastFrame = false
        end
    end)
end

local antiAimToggle=addToggle(aaSection,"Enable Anti-Aim",userWantsEnabled,function(bool)
    SetCfg("aaEnabled",bool)
    userWantsEnabled = bool
    enabled = bool
    if bool then
        startAntiAim()
        shared.Notify("Anti-Aim Enabled", 2)
    else
        stopAntiAim()
        shared.Notify("Anti-Aim Disabled", 2)
    end
end)

local ignoreToggle=addToggle(aaSection,"Enable Ignore List",ignoreListEnabled,function(bool)
    SetCfg("aaIgnoreListEnabled",bool)
    ignoreListEnabled = bool
    if bool then
        shared.Notify("Ignore List Enabled", 2)
    else
        shared.Notify("Ignore List Disabled", 2)
    end
end)

local drop1, drop2, drop3

local function updateDropdowns()
    local list = getPlayerList()
    dropdownRefreshing=true
    local function refresh(drop,name)
        if not drop then return end
        pcall(function() drop.Change(list) end)
        if type(drop.Select)=="function" then
            local displayed=findPlayerByName(name) and name or "None"
            local ok=pcall(drop.Select,displayed)
            if not ok then pcall(function() drop:Select(displayed) end) end
        end
    end
    refresh(drop1,slot1Name)
    refresh(drop2,slot2Name)
    refresh(drop3,slot3Name)
    dropdownRefreshing=false
end

drop1 = addDropdown(aaSection,"Ignore Player 1",getPlayerList(),slot1Name,function(selected)
    if dropdownRefreshing then return end
    slot1Name=tostring(selected or "None")
    SetCfg("aaIgnorePlayer1",slot1Name)
    slot1Player = findPlayerByName(selected)
    if slot1Player then
        shared.Notify("Slot 1: " .. slot1Player.Name, 2)
    else
        shared.Notify("Slot 1: None", 2)
    end
end)

drop2 = addDropdown(aaSection,"Ignore Player 2",getPlayerList(),slot2Name,function(selected)
    if dropdownRefreshing then return end
    slot2Name=tostring(selected or "None")
    SetCfg("aaIgnorePlayer2",slot2Name)
    slot2Player = findPlayerByName(selected)
    if slot2Player then
        shared.Notify("Slot 2: " .. slot2Player.Name, 2)
    else
        shared.Notify("Slot 2: None", 2)
    end
end)

drop3 = addDropdown(aaSection,"Ignore Player 3",getPlayerList(),slot3Name,function(selected)
    if dropdownRefreshing then return end
    slot3Name=tostring(selected or "None")
    SetCfg("aaIgnorePlayer3",slot3Name)
    slot3Player = findPlayerByName(selected)
    if slot3Player then
        shared.Notify("Slot 3: " .. slot3Player.Name, 2)
    else
        shared.Notify("Slot 3: None", 2)
    end
end)

local playerAddedConnection=Players.PlayerAdded:Connect(function()
    slot1Player=findPlayerByName(slot1Name)
    slot2Player=findPlayerByName(slot2Name)
    slot3Player=findPlayerByName(slot3Name)
    updateDropdowns()
end)

local playerRemovingConnection=Players.PlayerRemoving:Connect(function(player)
    if slot1Player == player then slot1Player = nil end
    if slot2Player == player then slot2Player = nil end
    if slot3Player == player then slot3Player = nil end
    updateDropdowns()
end)


env.VisualsV2Runtime.RegisterReset(function()
    antiAimToggle:Set(false)
    ignoreToggle:Set(false)
    userWantsEnabled=false
    enabled=false
    hadKnifeLastFrame=false
    stopAntiAim()
    playerAddedConnection:Disconnect()
    playerRemovingConnection:Disconnect()
end)
end)()

-- =========================================================
-- UTILITIES: DISTANCE ESP ONLY
-- =========================================================

local espSection = mainTab:AddSection("Distance ESP", "Utilities")
local distanceEspEnabled = C("distanceEspEnabled", false)
local distanceRenderDistance = C("distanceRenderDistance", 200)
local distanceColor = C("distanceColor",Color3.fromRGB(0,0,0))
local distanceTextSize = C("distanceTextSize", 12)
local distancePosition = C("distancePosition", "Bottom")
local distanceObjects = {}

local function distanceOffset()
    if distancePosition == "Top" then return Vector3.new(0, 3.25, 0) end
    if distancePosition == "Middle" then return Vector3.new(0, 0, 0) end
    return Vector3.new(0, -3.0, 0)
end

local function removeDistanceObject(plr)
    local gui = distanceObjects[plr]
    if gui then gui:Destroy() end
    distanceObjects[plr] = nil
end

local function ensureDistanceObject(plr)
    if plr == player then return nil end
    local char = plr.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then removeDistanceObject(plr); return nil end

    local gui = distanceObjects[plr]
    if not gui or not gui.Parent then
        gui = Instance.new("BillboardGui")
        gui.Name = "VisualsV2_DistanceESP"
        gui.Size = UDim2.new(0, 100, 0, 26)
        gui.StudsOffset = distanceOffset()
        gui.AlwaysOnTop = true
        gui.Adornee = root
        gui.Parent = root

        local label = Instance.new("TextLabel")
        label.Name = "Distance"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Code
        label.TextStrokeTransparency = 1
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.Parent = gui
        distanceObjects[plr] = gui
    else
        gui.Adornee = root
        gui.StudsOffset = distanceOffset()
        gui.AlwaysOnTop = true
        if gui.Parent ~= root then gui.Parent = root end
    end
    return gui
end

local function clearDistanceEsp()
    for plr in pairs(distanceObjects) do removeDistanceObject(plr) end
end

local distanceToggle = addToggle(espSection, "Enable Distance ESP", distanceEspEnabled, function(state)
    distanceEspEnabled = state
    SetCfg("distanceEspEnabled", state)
    if not state then clearDistanceEsp() end
end)
espSection:AddSlider("Render Distance", 50, 2000, distanceRenderDistance, function(value)
    distanceRenderDistance = value
    SetCfg("distanceRenderDistance", value)
end)
espSection:AddColorpicker("Distance Color", distanceColor, function(color)
    distanceColor = color
    SetCfg("distanceColor", color)
end)
espSection:AddSlider("Text Size", 8, 30, distanceTextSize, function(value)
    distanceTextSize = value
    SetCfg("distanceTextSize", value)
end)
addDropdown(espSection, "Position", {"Top", "Middle", "Bottom"}, distancePosition, function(selected)
    distancePosition = selected
    SetCfg("distancePosition", selected)
    for _, gui in pairs(distanceObjects) do if gui and gui.Parent then gui.StudsOffset = distanceOffset() end end
end)

RunService.RenderStepped:Connect(function()
    if not distanceEspEnabled then return end
    local myChar = player.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then
            local char = plr.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            if root and humanoid and humanoid.Health > 0 then
                local distance = (root.Position - myRoot.Position).Magnitude
                if distance <= distanceRenderDistance then
                    local gui = ensureDistanceObject(plr)
                    if gui then
                        gui.Enabled = true
                        local label = gui:FindFirstChild("Distance")
                        if label then
                            label.Text = "[" .. tostring(math.floor(distance + 0.5)) .. "]"
                            label.TextColor3 = distanceColor
                            label.TextSize = distanceTextSize
                        end
                    end
                else
                    local gui = distanceObjects[plr]
                    if gui then gui.Enabled = false end
                end
            else
                removeDistanceObject(plr)
            end
        end
    end
end)
Players.PlayerRemoving:Connect(removeDistanceObject)

env.VisualsV2Runtime.RegisterReset(function()
    distanceToggle:Set(false)
    distanceEspEnabled=false
    distanceRenderDistance=200
    distanceColor=Color3.fromRGB(0,0,0)
    distanceTextSize=12
    distancePosition="Bottom"
    clearDistanceEsp()
end)

-- =========================================================
-- UTILITIES: SHOOT MURDERER BUTTON
-- Customizes only the existing ODH button. Position saves automatically.
-- =========================================================

;(function()
local section=mainTab:AddSection("Shoot Murderer Button","Utilities")
local customEnabled=C("shootCustomizationEnabled",false)
local buttonWidth=C("shootButtonWidth",100)
local buttonHeight=C("shootButtonHeight",40)
local keepGun=C("shootKeepGunEnabled",false)
local allowDrag=C("shootDragEnabled",false)
local hideText=C("shootHideText",false)
local button,scale,textObject,oldText,originalSize,originalPosition,originalAnchorPoint
local conns={}
local gunConn,gunTask
local dragging=false
local dragInput,dragStart,startPos
local DEFAULT_POS=UDim2.new(0.5,0,0.5,0)
local buttonPos=loadStoredPosition("shootMurdButtonPosition",DEFAULT_POS)

local resetShootMurdererPosition

local function normalize(value) return tostring(value or ""):lower():gsub("%s+","") end
local function roots()
    local result,seen={},{}
    local function add(root)
        if typeof(root)=="Instance" and not seen[root] then seen[root]=true; table.insert(result,root) end
    end
    pcall(function() add(game:GetService("CoreGui")) end)
    if type(gethui)=="function" then local ok,r=pcall(gethui); if ok then add(r) end end
    pcall(function() add(player:FindFirstChildOfClass("PlayerGui")) end)
    return result
end
local function isTarget(item)
    if not item or not item:IsA("TextButton") then return false end
    if normalize(item.Text):find("shootmurderer",1,true) then return true end
    local label=item:FindFirstChildWhichIsA("TextLabel",true)
    if label and normalize(label.Text):find("shootmurderer",1,true) then return true end
    return item:GetAttribute("ShootMurderButton")==true
end
local function findButton()
    for _,root in ipairs(roots()) do
        local ok,desc=pcall(function() return root:GetDescendants() end)
        if ok then
            for _,item in ipairs(desc) do
                if isTarget(item) then item:SetAttribute("ShootMurderButton",true); return item end
            end
        end
    end
end
local function getTextTarget(btn)
    if not btn then return nil,nil end
    if tostring(btn.Text or "")~="" then return btn,btn.Text end
    local label=btn:FindFirstChildWhichIsA("TextLabel",true)
    if label then return label,label.Text end
    return btn,"Shoot Murderer"
end
local function stopKeeper()
    if gunConn then gunConn:Disconnect(); gunConn=nil end
    if gunTask then pcall(task.cancel,gunTask); gunTask=nil end
end
local function keepEquipped()
    if not keepGun then return end
    local char=player.Character
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    local backpack=player:FindFirstChildOfClass("Backpack")
    if not hum or not backpack then return end
    local gun
    for _,container in ipairs({char,backpack}) do
        if container then
            for _,item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") and item.Name:lower():find("gun",1,true) then gun=item; break end
            end
        end
        if gun then break end
    end
    if not gun then return end
    stopKeeper()
    gunConn=gun.AncestryChanged:Connect(function(_,parent)
        if keepGun and parent==backpack then
            task.defer(function() if hum.Parent and gun.Parent then pcall(function() hum:EquipTool(gun) end) end end)
        end
    end)
    gunTask=task.delay(0.3,stopKeeper)
end
local function animate()
    if not scale then return end
    scale.Scale=0.91
    TweenService:Create(scale,TweenInfo.new(0.65,Enum.EasingStyle.Elastic,Enum.EasingDirection.Out),{Scale=1}):Play()
end
local function restoreOriginal()
    if not button then return end
    if originalSize then button.Size=originalSize end
    if originalPosition then button.Position=originalPosition end
    if originalAnchorPoint then button.AnchorPoint=originalAnchorPoint end
    if textObject and textObject.Parent and oldText~=nil then textObject.Text=oldText end
end
local function update()
    if not button or not customEnabled then return end
    button.Size=UDim2.new(0,buttonWidth,0,buttonHeight)
    button.AnchorPoint=Vector2.new(0.5,0.5)
    button.Position=buttonPos
    button.Active=true
    button.Modal=false
    button.Selectable=false
    if textObject and textObject.Parent then
        textObject.Text=hideText and "" or ((oldText and oldText~="") and oldText or "Shoot Murderer")
    end
end
local function clearConnections()
    for _,conn in ipairs(conns) do pcall(function() conn:Disconnect() end) end
    table.clear(conns)
    if scale then pcall(function() scale:Destroy() end); scale=nil end
end
local function bind(newButton)
    if not newButton or button==newButton then return end
    clearConnections()
    button=newButton
    button:SetAttribute("ShootMurderButton",true)
    textObject,oldText=getTextTarget(button)
    originalSize=button.Size
    originalPosition=button.Position
    originalAnchorPoint=button.AnchorPoint
    button.AutoButtonColor=false
    button.Active=true
    button.Modal=false
    button.Selectable=false
    scale=Instance.new("UIScale")
    scale.Parent=button
    update()

    -- No addon action is triggered by a random screen press.
    -- Dragging can only begin on this exact button.
    table.insert(conns,button.InputBegan:Connect(function(input)
        if not customEnabled or not allowDrag then return end
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        dragging=true
        dragInput=input
        dragStart=input.Position
        startPos=button.Position
    end))

    -- Keep-gun/animation helpers only run from an actual click on the button.
    table.insert(conns,button.MouseButton1Click:Connect(function()
        if not customEnabled or allowDrag then return end
        keepEquipped()
        animate()
    end))
    table.insert(conns,UserInputService.InputChanged:Connect(function(input)
        if not dragging or not customEnabled or not allowDrag or not button then return end
        if input.UserInputType~=Enum.UserInputType.MouseMovement and input.UserInputType~=Enum.UserInputType.Touch then return end
        if dragInput and dragInput.UserInputType==Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.Touch then return end
        local delta=input.Position-dragStart
        button.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
    end))
    table.insert(conns,UserInputService.InputEnded:Connect(function(input)
        if not dragging then return end
        if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=false; dragInput=nil
            if button then buttonPos=button.Position; saveStoredPosition("shootMurdButtonPosition",buttonPos) end
        end
    end))
    table.insert(conns,button:GetPropertyChangedSignal("Size"):Connect(function()
        if not customEnabled or not button then return end
        local wanted=UDim2.new(0,buttonWidth,0,buttonHeight)
        if button.Size~=wanted then button.Size=wanted end
    end))
    table.insert(conns,button.AncestryChanged:Connect(function()
        if button and not button:IsDescendantOf(game) then
            button=nil
            task.defer(function() local replacement=findButton(); if replacement then bind(replacement) end end)
        end
    end))
end

resetShootMurdererPosition=function()
    local centered=UDim2.new(0.5,0,0.5,0)
    buttonPos=centered
    PositionData["shootMurdButtonPosition"]=nil
    saveConfig()

    local target=button
    if not target or not target.Parent then
        target=findButton()
        if target then bind(target) end
    end
    if target then
        target.AnchorPoint=Vector2.new(0.5,0.5)
        target.Position=centered
    end
end
env.VisualsV2ResetShootMurdererPosition=resetShootMurdererPosition

local customToggle=addToggle(section,"Enable Button Customization",customEnabled,function(v)
    customEnabled=v; SetCfg("shootCustomizationEnabled",v)
    if v then update() else restoreOriginal(); dragging=false; dragInput=nil; stopKeeper() end
end)
section:AddSlider("Button Width",40,300,buttonWidth,function(v) buttonWidth=v; SetCfg("shootButtonWidth",v); update() end)
section:AddSlider("Button Height",20,150,buttonHeight,function(v) buttonHeight=v; SetCfg("shootButtonHeight",v); update() end)
local keepToggle=addToggle(section,"Keep Gun Equipped",keepGun,function(v) keepGun=v; SetCfg("shootKeepGunEnabled",v); if not v then stopKeeper() end end)
local dragToggle=addToggle(section,"Allow Drag",allowDrag,function(v) allowDrag=v; SetCfg("shootDragEnabled",v); dragging=false; dragInput=nil end)
local textToggle=addToggle(section,"Hide Button Text",hideText,function(v)
    hideText=v
    SetCfg("shootHideText",v)
    update()
end)
section:AddButton("Reset Shoot Murderer Button Position",resetShootMurdererPosition)

task.defer(function()
    task.wait(0.5)
    local found=findButton(); if found then bind(found) end
    for _,root in ipairs(roots()) do
        pcall(function()
            root.DescendantAdded:Connect(function(item) if isTarget(item) then task.defer(function() bind(item) end) end end)
        end)
    end
end)

env.VisualsV2Runtime.RegisterReset(function()
    customToggle:Set(false); keepToggle:Set(false); dragToggle:Set(false); textToggle:Set(false)
    customEnabled=false; keepGun=false; allowDrag=false; hideText=false
    buttonWidth=100; buttonHeight=40; buttonPos=UDim2.new(0.5,0,0.5,0)
    stopKeeper(); restoreOriginal()
end)
end)()

-- =========================================================
-- VISUALS: GUNS & KNIVES
-- Independent gun and knife tint and chams controls.
-- =========================================================

-- =========================================================
-- VISUALS: EQUIPPED WEAPON / TOOL CHAMS
-- ForceField, Flat and Chromatic renderers adapted from anya_bts's Tool Chams.
-- Chams own their colour/rainbow settings; source colours are untouched.
-- =========================================================

;(function()
local runtime=env.VisualsV2Runtime
local presets={"ForceField","Flat","Chromatic"}
local groups,states={},{}
local trackedCharacter,removingCharacter
local characterConnections,lifecycleConnections={},{}
local heartbeatConnection,chromConnection,shellConnection
local chromHost,chromView,chromWorld,chromCamera
local dirty,queued,resetting=true,false,false
local CHROM_SCALE,CHROM_ALPHA=1.012,0.025

local function disconnectAll(connections)
    for _,connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
end

local function presetName(value)
    if type(value)=="table" then value=value[1] end
    for _,preset in ipairs(presets) do if value==preset then return value end end
    return "ForceField"
end

local function groupFor(tool)
    if not tool or not tool:IsA("Tool") then return nil end
    for _,group in ipairs(groups) do
        if group.enabled and group.matches(tool) then return group end
    end
end

local function clearFlat(state)
    if state.flat then state.flat:Destroy() end
    state.flat,state.flatHighlight,state.visibleHighlight,state.flatEntries=nil,nil,nil,nil
end

local function clearChromatic(state)
    if state.chrom then state.chrom:Destroy() end
    state.chrom,state.chromEntries,state.chromColor=nil,nil,nil
end

local function clearForceField(state)
    for _,entry in ipairs(state.forceEntries or {}) do
        pcall(function()
            -- Restore only our local visibility layer. Native materials,
            -- textures, appearances and paint colours were never changed.
            if entry.source.LocalTransparencyModifier==1 then
                entry.source.LocalTransparencyModifier=entry.alpha
            end
        end)
    end
    if state.force then state.force:Destroy() end
    state.force,state.forceEntries=nil,nil
end

local function clearState(state)
    clearFlat(state)
    clearChromatic(state)
    clearForceField(state)
end

local function stopShellSync()
    if shellConnection then shellConnection:Disconnect(); shellConnection=nil end
end

local function destroyViewport()
    if chromConnection then chromConnection:Disconnect(); chromConnection=nil end
    if chromHost then chromHost:Destroy() end
    chromHost,chromView,chromWorld,chromCamera=nil,nil,nil,nil
end

local function ensureViewport()
    if chromWorld and chromWorld.Parent and chromHost and chromHost.Parent then return true end
    destroyViewport()
    local parent=player:FindFirstChildOfClass("PlayerGui")
    if not parent and type(gethui)=="function" then
        local ok,value=pcall(gethui)
        if ok then parent=value end
    end
    if not parent then return false end
    chromHost=Instance.new("ScreenGui")
    chromHost.Name="VisualsV2_ChamsViewport"
    chromHost.ResetOnSpawn=false
    chromHost.IgnoreGuiInset=true
    chromHost.DisplayOrder=100
    chromHost.Parent=parent
    chromView=Instance.new("ViewportFrame")
    chromView.Name="ChamsViewport"
    chromView.Size=UDim2.fromScale(1,1)
    chromView.Position=UDim2.fromScale(0,0)
    chromView.BackgroundTransparency=1
    chromView.BorderSizePixel=0
    chromView.Ambient=Color3.new(1,1,1)
    chromView.LightColor=Color3.new(1,1,1)
    chromView.LightDirection=Vector3.new(-1,-1,-1)
    chromView.ZIndex=999
    chromView.Parent=chromHost
    chromCamera=Instance.new("Camera")
    chromCamera.Name="VisualsV2_ChamsCamera"
    chromCamera.Parent=chromView
    chromView.CurrentCamera=chromCamera
    local sky=Lighting:FindFirstChildOfClass("Sky")
    if sky then pcall(function() sky:Clone().Parent=chromView end) end
    chromWorld=Instance.new("WorldModel")
    chromWorld.Name="ChamsWorld"
    chromWorld.Parent=chromView
    chromConnection=RunService.RenderStepped:Connect(function()
        local cameraNow=workspace.CurrentCamera
        if cameraNow and chromCamera then
            chromCamera.CFrame=cameraNow.CFrame
            chromCamera.FieldOfView=cameraNow.FieldOfView
            chromCamera.FieldOfViewMode=cameraNow.FieldOfViewMode
        end
        for tool,state in pairs(states) do
            if state.chromEntries then
                for _,entry in ipairs(state.chromEntries) do
                    local source,clone=entry[1],entry[2]
                    local visible=source.Parent and tool.Parent==player.Character
                        and math.max(source.Transparency,source.LocalTransparencyModifier)<1
                    if source.Parent then clone.CFrame=source.CFrame end
                    clone.Transparency=visible and CHROM_ALPHA or 1
                end
            end
        end
    end)
    return true
end

local function deformable(part)
    if part:FindFirstChildWhichIsA("WrapLayer") or part:FindFirstChildWhichIsA("Bone") then return true end
    local ok,skinned=pcall(function() return part.HasSkinnedMesh end)
    return ok and skinned==true
end

local function shell(source,scale)
    local archivable=source.Archivable
    if not archivable and not pcall(function() source.Archivable=true end) then return nil end
    local ok,clone=pcall(function() return source:Clone() end)
    if not archivable then pcall(function() source.Archivable=archivable end) end
    if not ok or not clone then return nil end
    for _,child in ipairs(clone:GetChildren()) do
        if not child:IsA("DataModelMesh") then child:Destroy() end
    end
    local mesh=clone:FindFirstChildWhichIsA("DataModelMesh")
    if mesh then
        pcall(function() mesh.Scale=mesh.Scale*scale end)
        pcall(function() mesh.TextureId="" end)
    else
        clone.Size=clone.Size*scale
    end
    pcall(function() clone.TextureID="" end)
    pcall(function() clone.MaterialVariant="" end)
    clone.CanCollide=false; clone.CanQuery=false; clone.CanTouch=false
    clone.Massless=true; clone.CastShadow=false; clone.LocalTransparencyModifier=0
    return clone
end

local function syncForceField(tool,state,color)
    for _,entry in ipairs(state.forceEntries or {}) do
        local source,clone=entry.source,entry.clone
        if source.Parent then
            local alpha=source.LocalTransparencyModifier
            if alpha~=1 then entry.alpha=alpha end
            local visible=tool.Parent==player.Character and math.max(source.Transparency,entry.alpha)<1
            clone.CFrame=source.CFrame
            clone.Transparency=visible and math.max(source.Transparency,entry.alpha) or 1
            clone.Color=color
            local mesh=clone:FindFirstChildWhichIsA("SpecialMesh")
            if mesh then mesh.VertexColor=Vector3.new(1,1,1) end
            source.LocalTransparencyModifier=1
        else clone.Transparency=1 end
    end
end

local function ensureShellSync()
    if shellConnection then return end
    shellConnection=RunService.RenderStepped:Connect(function()
        for tool,state in pairs(states) do
            if state.forceEntries then syncForceField(tool,state,state.group.color()) end
            for _,entry in ipairs(state.flatEntries or {}) do
                local source,clone=entry[1],entry[2]
                local visible=source.Parent and tool.Parent==player.Character
                    and math.max(source.Transparency,source.LocalTransparencyModifier)<1
                if source.Parent then clone.CFrame=source.CFrame end
                clone.Transparency=visible and source.Transparency or 1
            end
        end
    end)
end

local function applyFlat(tool,state,color)
    if not state.flat or not state.flat.Parent then
        clearFlat(state)
        local model=Instance.new("Model")
        model.Name="VisualsV2_FlatChams_"..tool.Name
        local entries={}
        for _,source in ipairs(state.parts) do
            local clone=not deformable(source) and shell(source,0.99) or nil
            if clone then
                clone.Anchored=true
                clone.CFrame=source.CFrame
                clone.Parent=model
                entries[#entries+1]={source,clone}
            end
        end
        model.Parent=workspace
        local occluded=Instance.new("Highlight")
        occluded.Name="VisualsV2_FlatChamsShell"
        occluded.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
        occluded.OutlineTransparency=1; occluded.FillTransparency=0
        occluded.Adornee=model; occluded.Parent=model
        local visible=Instance.new("Highlight")
        visible.Name="VisualsV2_FlatChamsVisible"
        visible.DepthMode=Enum.HighlightDepthMode.Occluded
        visible.OutlineTransparency=1; visible.FillTransparency=0
        visible.Adornee=tool; visible.Parent=model
        state.flat,state.flatHighlight,state.visibleHighlight,state.flatEntries=model,occluded,visible,entries
    end
    ensureShellSync()
    state.flatHighlight.FillColor=color
    state.visibleHighlight.FillColor=color
    for _,entry in ipairs(state.flatEntries) do
        local source,clone=entry[1],entry[2]
        clone.Transparency=math.max(source.Transparency,source.LocalTransparencyModifier)>=1 and 1 or source.Transparency
    end
end

local function applyChromatic(tool,state,color)
    if not ensureViewport() then return end
    if not state.chrom or not state.chrom.Parent then
        clearChromatic(state)
        local model=Instance.new("Model")
        model.Name="VisualsV2_ChromaticChams_"..tool.Name
        local entries={}
        for _,source in ipairs(state.parts) do
            local clone=not deformable(source) and shell(source,CHROM_SCALE) or nil
            if clone then
                clone.Anchored=true
                clone.Material=Enum.Material.Foil
                clone.Reflectance=0.12
                clone.Transparency=math.max(source.Transparency,source.LocalTransparencyModifier)>=1 and 1 or CHROM_ALPHA
                clone.Color=color
                clone.CFrame=source.CFrame
                clone.Parent=model
                entries[#entries+1]={source,clone}
            end
        end
        model.Parent=chromWorld
        state.chrom,state.chromEntries,state.chromColor=model,entries,color
    end
    -- Static colours and rainbow colours take the same rendering path.
    state.chromColor=color
    for _,entry in ipairs(state.chromEntries) do entry[2].Color=color end
end

local function applyForceField(tool,state,color)
    if not state.force or not state.force.Parent then
        clearForceField(state)
        local model=Instance.new("Model")
        model.Name="VisualsV2_ForceFieldChams_"..tool.Name
        model:SetAttribute("VisualsV2_ChamsVisual",true)
        local entries={}
        -- Clone visual geometry only. The real SprayPaint Handle and its
        -- SurfaceAppearance/Decal/Texture children remain where its script
        -- expects them, with their native material and paint colour intact.
        for _,source in ipairs(state.parts) do
            local clone=not deformable(source) and shell(source,1.005) or nil
            if clone then
                clone.Anchored=true
                clone.Material=Enum.Material.ForceField
                clone.Color=color
                clone.CFrame=source.CFrame
                clone.Parent=model
                entries[#entries+1]={source=source,clone=clone,alpha=source.LocalTransparencyModifier}
            end
        end
        model.Parent=workspace
        state.force,state.forceEntries=model,entries
    end
    ensureShellSync()
    syncForceField(tool,state,color)
end

local update
local function queueUpdate()
    if queued or resetting or not runtimeAlive then return end
    queued=true
    task.defer(function()
        queued=false
        if not resetting and runtimeAlive then update() end
    end)
end

local function relevantChange(object)
    if object:IsA("Tool") or object:IsA("BasePart") or object:IsA("DataModelMesh")
        or object:IsA("Bone") or object:IsA("WrapLayer")
        or object:IsA("SurfaceAppearance") then
        dirty=true
        queueUpdate()
    end
end

local function bindCharacter(character)
    if trackedCharacter==character then return end
    disconnectAll(characterConnections)
    for tool,state in pairs(states) do clearState(state); states[tool]=nil end
    trackedCharacter=character
    dirty=true
    if character then
        characterConnections[1]=character.DescendantAdded:Connect(relevantChange)
        characterConnections[2]=character.DescendantRemoving:Connect(relevantChange)
    end
end

local function active()
    for _,group in ipairs(groups) do if group.enabled then return true end end
    return false
end

local function stopWatching()
    if heartbeatConnection then heartbeatConnection:Disconnect(); heartbeatConnection=nil end
    disconnectAll(lifecycleConnections)
    disconnectAll(characterConnections)
    trackedCharacter=nil
    for tool,state in pairs(states) do clearState(state); states[tool]=nil end
    stopShellSync()
    destroyViewport()
    dirty=true
end

update=function()
    if resetting or not runtimeAlive then return end
    if not active() then stopWatching(); return end
    bindCharacter(player.Character~=removingCharacter and player.Character or nil)
    if dirty then
        dirty=false
        for tool,state in pairs(states) do clearState(state); states[tool]=nil end
        if trackedCharacter then
            for _,tool in ipairs(trackedCharacter:GetChildren()) do
                local group=groupFor(tool)
                if group then
                    local state={group=group,preset=group.preset,parts={}}
                    for _,object in ipairs(tool:GetDescendants()) do
                        if object:IsA("BasePart") then state.parts[#state.parts+1]=object
                        end
                    end
                    states[tool]=state
                end
            end
        end
    end
    local chromatic,shells=false,false
    for tool,state in pairs(states) do
        if tool.Parent~=trackedCharacter or groupFor(tool)~=state.group then
            clearState(state); states[tool]=nil
        elseif #state.parts>0 then
            local color=state.group.color()
            if state.preset=="Flat" then applyFlat(tool,state,color); shells=true
            elseif state.preset=="Chromatic" then
                applyChromatic(tool,state,color)
                chromatic=state.chrom~=nil or chromatic
            else applyForceField(tool,state,color); shells=true end
        end
    end
    if not chromatic then destroyViewport() end
    if not shells then stopShellSync() end
end

local function refresh()
    if resetting or not runtimeAlive then return end
    dirty=true
    if active() and not heartbeatConnection then
        lifecycleConnections[1]=player.CharacterAdded:Connect(function(character)
            removingCharacter=nil
            bindCharacter(character)
            queueUpdate()
        end)
        lifecycleConnections[2]=player.CharacterRemoving:Connect(function(character)
            removingCharacter=character or player.Character
            bindCharacter(nil)
            destroyViewport()
        end)
        local elapsed=0
        heartbeatConnection=RunService.Heartbeat:Connect(function(dt)
            elapsed+=math.max(tonumber(dt) or 0,0)
            if elapsed>=0.1 then elapsed=0; update() end
        end)
    end
    update()
end
runtime.RefreshChams=refresh

runtime.RegisterChamsFeature=function(section,key,label,matches)
    section:AddParagraph(label.." Chams","All presets use Chams Color. Tint controls are separate.")
    local group={
        enabled=C(key.."Enabled",false),
        preset=presetName(C(key.."Preset","ForceField")),
        matches=matches,
        colorValue=C(key.."Color",Color3.fromRGB(255,200,0)),
        rainbow=C(key.."Rainbow",false),
        rainbowSpeed=math.clamp(tonumber(C(key.."RainbowSpeed",3)) or 3,1,10),
    }
    group.color=function()
        if group.rainbow then return Color3.fromHSV((os.clock()*(group.rainbowSpeed*0.1))%1,1,1) end
        return group.colorValue
    end
    groups[#groups+1]=group
    group.toggle=addToggle(section,label.." Chams",group.enabled,function(value)
        group.enabled=value
        SetCfg(key.."Enabled",value)
        refresh()
    end)
    group.dropdown=addDropdown(section,label.." Chams Preset",presets,group.preset,function(value)
        group.preset=presetName(value)
        SetCfg(key.."Preset",group.preset)
        refresh()
    end)
    section:AddColorpicker(label.." Chams Color",group.colorValue,function(color)
        group.colorValue=color
        SetCfg(key.."Color",color)
        update()
    end)
    group.rainbowToggle=addToggle(section,"Rainbow "..label.." Chams",group.rainbow,function(value)
        group.rainbow=value
        SetCfg(key.."Rainbow",value)
        update()
    end)
    section:AddSlider(label.." Chams Rainbow Speed",1,10,group.rainbowSpeed,function(value)
        group.rainbowSpeed=math.clamp(tonumber(value) or 3,1,10)
        SetCfg(key.."RainbowSpeed",group.rainbowSpeed)
        update()
    end)
    if group.enabled then refresh() end
end

runtime.RegisterReset(function()
    resetting=true
    for _,group in ipairs(groups) do
        group.enabled=false
        group.preset="ForceField"
        group.rainbow=false
        group.colorValue=Color3.fromRGB(255,200,0)
        group.rainbowSpeed=3
        group.toggle:Set(false)
        group.rainbowToggle:Set(false)
    end
    stopWatching()
    removingCharacter=nil
    resetting=false
end)
end)()

-- =========================================================
-- COSMETIC: FIXED CLIENT GUN / KNIFE SKINS (MM2 / MMV)
-- Dropdown choices are supplied when the controls are created.
-- No database requires, catalog requests, background scans or refresh buttons.
-- =========================================================
;(function()
local section=mainTab:AddSection("Client Gun & Knife Skins","Cosmetic")
local MARKER="VisualsV2_ClientWeaponSkin"
local NONE="None"
local alive=true
local refreshing=false
local catalog={Gun={},Knife={}}
local connections={}
local toolStates={}
local heartbeat=nil
local hideFrame=nil
local refreshTools,updateWatching
local kinds={
    Gun={enabled=C("clientGunEnabled",false),selected=tostring(C("clientGunSkin",NONE)),key="clientGun"},
    Knife={enabled=C("clientKnifeEnabled",false),selected=tostring(C("clientKnifeSkin",NONE)),key="clientKnife"},
}
local function notify(message)
    if alive and runtimeAlive then pcall(function() shared.Notify(message,4) end) end
end

local function compact(value)
    return type(value)=="string" and value:lower():gsub("[^%w]","") or ""
end

local function weaponKind(value)
    local name=compact(value)
    if name=="gun" or name=="guns" or name=="pistol" or name=="revolver"
        or name=="firearm" or name=="gunskins" then return "Gun" end
    if name=="knife" or name=="knives" or name=="melee" or name=="sword"
        or name=="knifeskins" then return "Knife" end
end

local function properties(data)
    local result={}
    if type(data)=="table" then
        for key,value in pairs(data) do
            if type(key)=="string" then result[compact(key)]=value end
        end
    end
    return result
end

local function isDefault(id,data)
    if data.isdefault==true or data.default==true then return true end
    local key=compact(id)
    if key=="default" or key=="defaultgun" or key=="defaultknife"
        or key=="gun" or key=="knife" then return true end
    local name=compact(data.itemname or data.displayname or data.name)
    return name=="defaultgun" or name=="defaultknife" or name=="default"
end

local function register(kind,id,data,source)
    if not kind or id==nil then return end
    id=tostring(id)
    if id=="" or isDefault(id,data) then return end
    local entry=catalog[kind][id]
    if not entry then
        entry={id=id,kind=kind,data={},revision=0}
        catalog[kind][id]=entry
    end
    local changed=false
    for key,value in pairs(data) do
        if entry.data[key]~=value then entry.data[key]=value; changed=true end
    end
    if source and entry.source~=source then entry.source=source; changed=true end
    entry.name=tostring(entry.data.itemname or entry.data.displayname or entry.data.name or id)
    if entry.data.chroma==true and not entry.name:lower():find("chroma",1,true) then
        entry.name="Chroma "..entry.name
    end
    if changed then entry.revision=entry.revision+1 end
    return entry
end

-- Fixed original weapon records from the supplied MM2/MMV exports.
-- 355 MM2 guns and 631 knives, plus the two original MMV scope models.
-- This data never changes through runtime scanning or inventory ownership.
local staticMM2={
    {"Gun","Ace",{["itemid"]=238546577,["itemname"]="Ace",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","AduriteGun",{["itemid"]=196752289,["itemname"]="Adurite",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Aid",{["itemid"]=203807397,["itemname"]="Juice",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Aliens_G_2021",{["itemid"]=7800250906,["itemname"]="Aliens",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","AmericaGun",{["itemid"]=196751752,["itemname"]="America",["itemtype"]="Gun",["rarity"]="Classic"}},
    {"Gun","Amerilaser",{["itemid"]=446050753,["itemname"]="Amerilaser",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Apoc_G_2022",{["itemid"]=11255501940,["itemname"]="Apocalypse",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Aquarium_G_2025",{["itemid"]=129460052425837,["itemname"]="Aquarium",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Arctic_G_2022",{["itemid"]=11834443783,["itemname"]="Arctic",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Asteroid",{["itemid"]=476599365,["itemname"]="Asteroid",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","AuroraGun",{["itemid"]=108635848059846,["itemname"]="Borealis",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Aurora_G_2019",{["itemid"]=4534875165,["itemname"]="Aurora",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Aurora_G_2021",{["itemid"]=8304766165,["itemname"]="Aurora",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Bacon",{["itemid"]=238546467,["itemname"]="Bacon",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","BatsG",{["itemid"]=2513741174,["itemname"]="Bats",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Bats_G_2024",{["itemid"]=71258273720666,["itemname"]="Bats",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Bauble",{["itemid"]=84481559639371,["itemname"]="Bauble",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","BaubleChroma",{["chroma"]=true,["itemid"]=84481559639371,["itemname"]="Bauble",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","BigKill",{["itemid"]=196752330,["itemname"]="Big Kill",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Biogun",{["itemid"]=4659627458,["itemname"]="Biogun",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Bit",{["itemid"]=238549030,["itemname"]="Bit",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Blaster",{["itemid"]=386277381,["itemname"]="Blaster",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Bleed",{["itemid"]=315100702,["itemname"]="Rupture",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Blizzard",{["itemid"]=88928894807422,["itemname"]="Blizzard",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","BlizzardChroma",{["chroma"]=true,["itemid"]=88928894807422,["itemname"]="Blizzard",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Blossom_G",{["itemid"]=12339377105,["itemname"]="Blossom",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","BlueHarvester",{["itemid"]=8194219645,["itemname"]="Blue Harvester",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","BlueSugar",{["itemid"]=3215262120,["itemname"]="Blue Sugar",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","BluesteelGun",{["itemid"]=196752379,["itemname"]="Bluesteel",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Bones2019",{["itemid"]=4210926347,["itemname"]="Bones",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Brains_G_2022",{["itemid"]=11284145298,["itemname"]="Brains",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","BronzeHarvester",{["itemid"]=8194221072,["itemname"]="Bronze Harvester",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","BronzeIceblaster",{["itemid"]=6404167442,["itemname"]="Bronze Iceblaster",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","BronzeSugar",{["itemid"]=3215261913,["itemname"]="Bronze Sugar",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","Butterflies_G_2025",{["itemid"]=135662872427976,["itemname"]="Butterflies",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Camo",{["itemid"]=196752456,["itemname"]="Camo",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Candied_G_2022",{["itemid"]=11834435627,["itemname"]="Candied",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Candleflame_G_2024",{["itemid"]=90595111293037,["itemname"]="Candleflame",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","CandyCorn_G_2020",{["itemid"]=5866454590,["itemname"]="Candy Corn",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","CandyCorn_G_2022",{["itemid"]=11255558166,["itemname"]="Candy Corn",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","CandyCorn_G_2024",{["itemid"]=117473869340749,["itemname"]="Candy Corn",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","CandyCorn_G_2025",{["itemid"]=129781304866793,["itemname"]="Candy Corn",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","CandySwirl_G_2019",{["itemid"]=4534874602,["itemname"]="Candy Swirl",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","CaneGun",{["itemid"]=332497187,["itemname"]="Cane",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Cane_G_2018",{["itemid"]=2669785546,["itemname"]="Cane",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Cane_G_2021",{["itemid"]=8304768700,["itemname"]="Cane",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Canes_G_2023",{["itemid"]=15635558982,["itemname"]="Canes",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Carrot_G_2024",{["itemid"]=16960082652,["itemname"]="Carrot",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Carved_G_2020",{["itemid"]=5866457985,["itemname"]="Carved",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Cat_G_2021",{["itemid"]=7800253444,["itemname"]="Cat",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Caution",{["itemid"]=238546422,["itemname"]="Caution",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Cavern_G_2019",{["itemid"]=4534875511,["itemname"]="Cavern",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Cheddar",{["itemid"]=203808317,["itemname"]="Cheddar",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Cherries_G_2026",{["itemid"]=96164363513384,["itemname"]="Cherries",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","ChromaDarkbringer",{["chroma"]=true,["itemid"]=4751501078,["itemname"]="Darkbringer",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","ChromaLightbringer",{["chroma"]=true,["itemid"]=4751500761,["itemname"]="Lightbringer",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Chromatic_G_2023",{["itemid"]=12965339774,["itemname"]="Chromatic",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Clown_G",{["itemid"]=4659627976,["itemname"]="Clown",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Clown_G_2024",{["itemid"]=71982363966070,["itemname"]="Clown",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Clownfish_G_2024",{["itemid"]=18322197952,["itemname"]="Clownfish",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Coal_G_2018",{["itemid"]=2669784920,["itemname"]="Coal",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Coal_G_2021",{["itemid"]=8304769409,["itemname"]="Coal",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Coal_G_2022",{["itemid"]=11834434264,["itemname"]="Coal",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Cola",{["itemid"]=238546400,["itemname"]="Soda",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Cold",{["itemid"]=196752499,["itemname"]="Cold",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Constellation",{["itemid"]=114197436469014,["itemname"]="Constellation",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","ConstellationChroma",{["chroma"]=true,["itemid"]=114197436469014,["itemname"]="Constellation",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Constellation_Bronze",{["itemid"]=112811587103866,["itemname"]="Bronze Constellation",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","Constellation_G_2024",{["itemid"]=94311965719769,["itemname"]="Nightsky",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Constellation_Gold",{["itemid"]=132975248521820,["itemname"]="Gold Constellation",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","Constellation_Red",{["itemid"]=85766514163212,["itemname"]="Red Constellation",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","Constellation_Silver",{["itemid"]=100747436297625,["itemname"]="Silver Constellation",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","Cookie_G_2021",{["itemid"]=8304771148,["itemname"]="Cookie",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Cracks_G_2021",{["itemid"]=7800254737,["itemname"]="Cracks",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Cursed_G_2024",{["itemid"]=122855768693454,["itemname"]="Cursed",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Dark_G_2023",{["itemid"]=15091406343,["itemname"]="Darkgun",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Darkbringer",{["itemid"]=4749071819,["itemname"]="Darkbringer",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Darkness_G_2022",{["itemid"]=11255507374,["itemname"]="Darkness",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Darkshot",{["itemid"]=15080280688,["itemname"]="Darkshot",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Dartbringer",{["itemid"]=8626617523,["itemname"]="Dartbringer",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","Disint",{["itemid"]=196751943,["itemname"]="Laser",["itemtype"]="Gun",["rarity"]="Classic"}},
    {"Gun","Duckies_G_2026",{["itemid"]=124567820488562,["itemname"]="Duckies",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","ElderwoodGun",{["itemid"]=4211142894,["itemname"]="Elderwood Revolver",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","ElderwoodGunBlue",{["itemid"]=4468574885,["itemname"]="Blue Elderwood",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","ElderwoodGunBronze",{["itemid"]=4468585407,["itemname"]="Bronze Elderwood",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","ElderwoodGunGold",{["itemid"]=4468584345,["itemname"]="Gold Elderwood",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","ElderwoodGunSilver",{["itemid"]=4468583758,["itemname"]="Silver Elderwood",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","ElfGun",{["itemid"]=332767999,["itemname"]="Elf",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Elf_G_2023",{["itemid"]=15635569893,["itemname"]="Elf",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Emptybringer",{["itemid"]=4749071819,["itemname"]="???",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","EmptybringerChroma",{["chroma"]=true,["itemid"]=4749071819,["itemname"]="???",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Energized_G_2025",{["itemid"]=114403390530326,["itemname"]="Energized",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Engraved",{["itemid"]=203807690,["itemname"]="Engraved",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Eyes_G_2020",{["itemid"]=5866459380,["itemname"]="Watcher",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Eyes_G_2025",{["itemid"]=90751163516480,["itemname"]="Eyes",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","FallCamo_G_2021",{["itemid"]=7800257544,["itemname"]="Fall Camo",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Fall_G_2025",{["itemid"]=78153346812503,["itemname"]="Fall",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Fallout",{["itemid"]=196752601,["itemname"]="Fallout",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Floatie_G_2024",{["itemid"]=18322194067,["itemname"]="Floatie",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Flora",{["itemid"]=138204709945147,["itemname"]="Flora",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Floral_G_2024",{["itemid"]=18323751219,["itemname"]="Floral",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Floral_G_2026",{["itemid"]=107508982214346,["itemname"]="Floral",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","FlowerwoodGun",{["itemid"]=16963894455,["itemname"]="Flowerwood Gun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Forest_G_2024",{["itemid"]=78199422065424,["itemname"]="Forest",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Fragile_G_2023",{["itemid"]=12965349193,["itemname"]="Fragile",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Frosted_G_2019",{["itemid"]=4534866678,["itemname"]="Frosted",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Frostfade_G_2023",{["itemid"]=15635577623,["itemname"]="Frostfade",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Frostflame_G_2024",{["itemid"]=114781759936576,["itemname"]="Frostflame",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Frozen_G_2019",{["itemid"]=4534873956,["itemname"]="Frozen",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Frozen_G_2022",{["itemid"]=11834445016,["itemname"]="Frozen",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Frozen_G_2023",{["itemid"]=15635571468,["itemname"]="Frozen",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Frozen_G_2025",{["itemid"]=90622014285727,["itemname"]="Frozen",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Galactic",{["itemid"]=196752683,["itemname"]="Galactic",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Ghastly_G_2023",{["itemid"]=15091342564,["itemname"]="Ghastly",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","GhostG2018",{["itemid"]=2513741407,["itemname"]="Ghost",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Ghost_G_2026",{["itemid"]=120512330305244,["itemname"]="Ghost",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Ghostfire_G_2022",{["itemid"]=11284140034,["itemname"]="Ghostfire",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Ghosts_G_2020",{["itemid"]=5866465099,["itemname"]="Ghosts",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Ghosts_G_2021",{["itemid"]=7800251557,["itemname"]="Wraiths",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Gift_G_2020",{["itemid"]=6121867603,["itemname"]="Wrap",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Giftbag_G_2020",{["itemid"]=6121864813,["itemname"]="Gift Bag",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Gifts_G_2019",{["itemid"]=4534867381,["itemname"]="Gifts",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","GingerGun",{["itemid"]=332497038,["itemname"]="Ginger",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","GingerLuger",{["itemid"]=2674983099,["itemname"]="Ginger Luger",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Ginger_G_2018",{["itemid"]=2669785821,["itemname"]="Ginger",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Gingerbread_G_2019",{["itemid"]=4534872116,["itemname"]="Gingerbread",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Gingerbread_G_2020",{["itemid"]=6121860619,["itemname"]="Gingerbread",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Gingerbread_G_2021",{["itemid"]=8304772140,["itemname"]="Gingerbread",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Gingerbread_G_2022",{["itemid"]=11834442414,["itemname"]="Gingerbread",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Gingerbread_G_2025",{["itemid"]=74908113882525,["itemname"]="Gingerbread",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Gingercookie_G_2025",{["itemid"]=99160839686845,["itemname"]="Gingercookie",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Gingermint_G",{["itemid"]=11872179646,["itemname"]="Gingermint",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Gingerscope",{["itemid"]=15666469505,["itemname"]="Gingerscope",["itemtype"]="Gun",["rarity"]="Ancient"}},
    {"Gun","Gingerscope_Blue",{["itemid"]=16964462231,["itemname"]="Blue Gingerscope",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","Gingerscope_Bronze",{["itemid"]=16964465320,["itemname"]="Bronze Gingerscope",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","Gingerscope_Gold",{["itemid"]=16964471890,["itemname"]="Gold Gingerscope",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","Gingerscope_Silver",{["itemid"]=16964468980,["itemname"]="Silver Gingerscope",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","GoldHarvester",{["itemid"]=8194222523,["itemname"]="Gold Harvester",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","GoldIceblaster",{["itemid"]=6404165933,["itemname"]="Gold Iceblaster",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","GoldSugar",{["itemid"]=3215260149,["itemname"]="Gold Sugar",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","GoldenGun",{["itemid"]=196751989,["itemname"]="Golden",["itemtype"]="Gun",["rarity"]="Classic"}},
    {"Gun","Gothic_G_2021",{["itemid"]=7800253970,["itemname"]="Gothic",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","GraveG",{["itemid"]=2513731746,["itemname"]="Grave",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","GreenLuger",{["itemid"]=332044679,["itemname"]="Green Luger",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Gun1",{["itemid"]=196752052,["itemname"]="Cowboy",["itemtype"]="Gun",["rarity"]="Classic"}},
    {"Gun","HL2",{["itemid"]=238546100,["itemname"]="HL2",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Hacker",{["itemid"]=203819271,["itemname"]="Hacker",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Hallowgun",{["itemid"]=5878721461,["itemname"]="Hallowgun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Harvester",{["itemid"]=7800847534,["itemname"]="Harvester",["itemtype"]="Gun",["rarity"]="Ancient"}},
    {"Gun","HauntedG",{["itemid"]=2513741901,["itemname"]="Haunted",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Hazard_G_2022",{["itemid"]=11255505449,["itemname"]="Hazard",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Heartbreak_G_2026",{["itemid"]=79235438948261,["itemname"]="Heartbreak",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Holly_G_2018",{["itemid"]=2669786261,["itemname"]="Holly",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Hologram_G_2025",{["itemid"]=108751717527377,["itemname"]="Hologram",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","IceCamo_G_2021",{["itemid"]=8304767724,["itemname"]="Ice Camo",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Icebeam",{["itemid"]=8311005531,["itemname"]="Icebeam",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Iceblaster",{["itemid"]=6125814417,["itemname"]="Iceblaster",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Icedriller_G_2020",{["itemid"]=6121866490,["itemname"]="Icedriller",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Icepiercer",{["itemid"]=11874071041,["itemname"]="Icepiercer",["itemtype"]="Gun",["rarity"]="Ancient"}},
    {"Gun","IcepiercerBronze",{["itemid"]=12226920195,["itemname"]="Bronze Icepiercer",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","IcepiercerGold",{["itemid"]=12226688172,["itemname"]="Gold Icepiercer",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","IcepiercerRed",{["itemid"]=12227133450,["itemname"]="Red Icepiercer",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","IcepiercerSilver",{["itemid"]=12226843957,["itemname"]="Silver Icepiercer",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","Icicles_G_2018",{["itemid"]=2669786044,["itemname"]="Icicles",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Igloo_G_2024",{["itemid"]=95517099886712,["itemname"]="Igloo",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Imbued",{["itemid"]=196752718,["itemname"]="Imbued",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Infected_G_2022",{["itemid"]=11255502768,["itemname"]="Infected",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Infiltrator",{["itemid"]=203806022,["itemname"]="Infiltrator",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Iron",{["itemid"]=196752812,["itemname"]="Iron",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Jinglegun",{["itemid"]=6125742758,["itemname"]="Jinglegun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Laser",{["itemid"]=238546983,["itemname"]="Laser",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","LaserChroma",{["chroma"]=true,["itemid"]=3187395952,["itemname"]="Laser",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Latte_G_2023",{["itemid"]=15413116029,["itemname"]="Latte",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Lava_G_2025",{["itemid"]=90170220549489,["itemname"]="Lava",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Leaves_G_2024",{["itemid"]=129970927613267,["itemname"]="Leaves",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Lightbringer",{["itemid"]=4749070432,["itemname"]="Lightbringer",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Lights_G_2019",{["itemid"]=4534872673,["itemname"]="Lights",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Lights_G_2025",{["itemid"]=104258636970738,["itemname"]="Lights",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","LoveGun",{["itemid"]=203867650,["itemname"]="Love",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Luger",{["itemid"]=198042673,["itemname"]="Luger",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","LugerChroma",{["chroma"]=true,["itemid"]=3187395551,["itemname"]="Luger",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Lugercane",{["itemid"]=4535482609,["itemname"]="Lugercane",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Magma_G_2021",{["itemid"]=7800252572,["itemname"]="Magma",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Makeshift",{["itemid"]=11229837140,["itemname"]="Makeshift",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Marina",{["itemid"]=203808190,["itemname"]="Marina",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Meadow_G_2025",{["itemid"]=107321881182350,["itemname"]="Meadow",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Melon_G_2023",{["itemid"]=13944153861,["itemname"]="Melon",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Minty",{["itemid"]=4535408229,["itemname"]="Minty",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","MintyBlue",{["itemid"]=4753347062,["itemname"]="Blue Minty",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","MintyBronze",{["itemid"]=4753348263,["itemname"]="Bronze Minty",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","MintyGold",{["itemid"]=4753347636,["itemname"]="Gold Minty",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","MintySilver",{["itemid"]=4753346087,["itemname"]="Silver Minty",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","Mistletoe_G_2022",{["itemid"]=11834438982,["itemname"]="Mistletoe",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Molten",{["itemid"]=203869308,["itemname"]="Molten",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Monster",{["itemid"]=4210941474,["itemname"]="Monster",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Moonlight_G_2022",{["itemid"]=11284143055,["itemname"]="Moonlight",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Mummy",{["itemid"]=315155591,["itemname"]="Mummy",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","MummyG2018",{["itemid"]=2513741663,["itemname"]="Mummy",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Mummy_G_2020",{["itemid"]=5866463755,["itemname"]="Mummy",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Neon_G_2023",{["itemid"]=15635560825,["itemname"]="Neon",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Neon_G_2025",{["itemid"]=134429631587448,["itemname"]="Neon",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","News",{["itemid"]=238546032,["itemname"]="News",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Night",{["itemid"]=197829003,["itemname"]="Night",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Nightfire",{["itemid"]=4659626966,["itemname"]="Nightfire",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Nuke_G_2023",{["itemid"]=12965335931,["itemname"]="Nuke",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Nutcracker",{["itemid"]=332497657,["itemname"]="Nutcracker",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Ocean_G",{["itemid"]=13945898892,["itemname"]="Ocean",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Ornament1Gun",{["itemid"]=332497144,["itemname"]="Ornament1",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Ornament2Gun",{["itemid"]=332497550,["itemname"]="Ornament2",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Ornaments_G_2020",{["itemid"]=6121863515,["itemname"]="Ornaments",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Overseer",{["itemid"]=197830043,["itemname"]="Overseer",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Painted_G_2023",{["itemid"]=12965344675,["itemname"]="Painted",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Palms_G_2024",{["itemid"]=18322192817,["itemname"]="Palms",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Paws_G_2026",{["itemid"]=120089556380493,["itemname"]="Paws",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Pea",{["itemid"]=238545971,["itemname"]="Pea",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Pearl_G",{["itemid"]=18322646152,["itemname"]="Pearlshine",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Peppermint_G_2025",{["itemid"]=73148873488539,["itemname"]="Peppermint",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Phaser",{["itemid"]=196752144,["itemname"]="Phaser",["itemtype"]="Gun",["rarity"]="Classic"}},
    {"Gun","Pine_G_2019",{["itemid"]=4534871260,["itemname"]="Pine",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Pirate",{["itemid"]=3183639867,["itemname"]="Pirate",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Plaid_G_2026",{["itemid"]=121681210724670,["itemname"]="Plaid",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Plasmabeam",{["itemid"]=10014717343,["itemname"]="Plasmabeam",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","PopArt_G_2025",{["itemid"]=90526048501163,["itemname"]="Pop Art",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Popsicle_G_2024",{["itemid"]=18322191060,["itemname"]="Popsicle",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Portal_G_2020",{["itemid"]=5866461926,["itemname"]="Portal",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","PotionG2018",{["itemid"]=2513742133,["itemname"]="Potion",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Predator",{["itemid"]=203810176,["itemname"]="Predator",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Prince_G_2026",{["itemid"]=87296563281923,["itemname"]="Prince",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","PumpkinPatch_G_2025",{["itemid"]=117088166092009,["itemname"]="Pumpkin Patch",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Pumpkin_G_2023",{["itemid"]=15091327743,["itemname"]="Pumpkin",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","RIP",{["itemid"]=4210947993,["itemname"]="RIP",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","RainbowGun",{["itemid"]=3183640145,["itemname"]="Rainbow",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Rainbow_G",{["itemid"]=12966354606,["itemname"]="Rainbow Gun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Raygun",{["itemid"]=139431943195380,["itemname"]="Raygun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","RaygunBronze",{["itemid"]=138881346504998,["itemname"]="Bronze Raygun",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","RaygunChroma",{["chroma"]=true,["itemid"]=139431943195380,["itemname"]="Raygun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","RaygunGold",{["itemid"]=76250851065456,["itemname"]="Gold Raygun",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","RaygunRed",{["itemid"]=132354489228618,["itemname"]="Red Raygun",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","RaygunSilver",{["itemid"]=71511736314707,["itemname"]="Silver Raygun",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","RedIceblaster",{["itemid"]=6404168049,["itemname"]="Red Iceblaster",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","RedLuger",{["itemid"]=332044583,["itemname"]="Red Luger",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Ripper_G_2020",{["itemid"]=5866460591,["itemname"]="Ripper",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Ritual_G_2024",{["itemid"]=122021199074749,["itemname"]="Ritual",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Sands",{["itemid"]=119213058412452,["itemname"]="Sands",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","SandsChroma",{["chroma"]=true,["itemid"]=119213058412452,["itemname"]="Sands",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Sandy_G_2024",{["itemid"]=18323752709,["itemname"]="Sandy",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","SantaGun",{["itemid"]=332496861,["itemname"]="Santa",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Santa_G_2018",{["itemid"]=2669785184,["itemname"]="Elf",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Santa_G_2023",{["itemid"]=15635550625,["itemname"]="Santa",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Shadow_G_2026",{["itemid"]=131289807674112,["itemname"]="Shadow",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Shark",{["itemid"]=203858533,["itemname"]="Shark",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","SharkChroma",{["chroma"]=true,["itemid"]=3187395738,["itemname"]="Shark",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","SharkSeeker",{["itemid"]=6967771328,["itemname"]="SharkSeeker",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","SilentNight_G_2020",{["itemid"]=6121862034,["itemname"]="Silent Night",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","SilverHarvester",{["itemid"]=8194217388,["itemname"]="Silver Harvester",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","SilverIceblaster",{["itemid"]=6404166698,["itemname"]="Silver Iceblaster",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","SilverSugar",{["itemid"]=3215261680,["itemname"]="Silver Sugar",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","Sketch",{["itemid"]=203808108,["itemname"]="Sketch",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","SlimeG",{["itemid"]=2513742319,["itemname"]="Slime",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","SlouseClownGun",{["itemid"]=4659627976,["itemname"]="Clown",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","SnakebiteG",{["itemid"]=4210925026,["itemname"]="Snakebite",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Snowball_G_2025",{["itemid"]=104416405402940,["itemname"]="Snowball",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Snowcannon",{["itemid"]=129186939023729,["itemname"]="Snowcannon",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","SnowcannonBronze",{["itemid"]=84743767811732,["itemname"]="Bronze Snowcannon",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","SnowcannonChroma",{["chroma"]=true,["itemid"]=129186939023729,["itemname"]="Snowcannon",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","SnowcannonGold",{["itemid"]=115609046800090,["itemname"]="Gold Snowcannon",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","SnowcannonRed",{["itemid"]=110812086479763,["itemname"]="Red Snowcannon",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","SnowcannonSilver",{["itemid"]=83838802472095,["itemname"]="Silver Snowcannon",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","Snowflake_G_2018",{["itemid"]=2669786515,["itemname"]="Snowflake",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Snowflake_G_2022",{["itemid"]=11834437796,["itemname"]="Snowflake",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Snowflake_G_2023",{["itemid"]=15635575718,["itemname"]="Snowflake",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Snowflakes_G_2019",{["itemid"]=4534866065,["itemname"]="Snowflakes",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","SnowmanGun",{["itemid"]=332497603,["itemname"]="Snowman",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Snowman_G_2018",{["itemid"]=2669786846,["itemname"]="Snowman",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Snowman_G_2021",{["itemid"]=8304766932,["itemname"]="Snowman",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Snowman_G_2022",{["itemid"]=11834436620,["itemname"]="Snowman",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Snowman_G_2023",{["itemid"]=15635572427,["itemname"]="Snowman",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Soda_G_2025",{["itemid"]=132525981806780,["itemname"]="Soda",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Sparkle",{["itemid"]=203869110,["itemname"]="Sparkle",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Spearmint_G_2025",{["itemid"]=81352860339620,["itemname"]="Spearmint",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Spectral_G_2021",{["itemid"]=7800255531,["itemname"]="Spectral",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Spectre2022",{["itemid"]=11229779932,["itemname"]="Spectre",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Spitfire",{["itemid"]=197829561,["itemname"]="Spitfire",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Splash_G",{["itemid"]=4659626370,["itemname"]="Splash",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Splat",{["itemid"]=3183639522,["itemname"]="Splat",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Star",{["itemid"]=203807904,["itemname"]="Star",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Starfish_G_2024",{["itemid"]=18322189584,["itemname"]="Starfish",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Starry_G_2020",{["itemid"]=5930731295,["itemname"]="Starry",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Starry_G_2021",{["itemid"]=8304772774,["itemname"]="Starry",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Stars_G_2023",{["itemid"]=15635574031,["itemname"]="Stars",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Steel_G_2023",{["itemid"]=15091341552,["itemname"]="Steel",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","StickersX_G_2022",{["itemid"]=11834432971,["itemname"]="Stickers",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","StickersX_G_2025",{["itemid"]=127489830827583,["itemname"]="Stickers",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Stickers_G_2021",{["itemid"]=7800257010,["itemname"]="Stickers",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Stickers_G_2024",{["itemid"]=108122054293502,["itemname"]="Stickers",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Stickers_G_2025",{["itemid"]=75123474631661,["itemname"]="Stickers",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Stickers_X_G_2024",{["itemid"]=91224254479440,["itemname"]="Stickers",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Stockings_G_2022",{["itemid"]=11834440319,["itemname"]="Stockings",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Stockings_G_2024",{["itemid"]=76288270695961,["itemname"]="Stockings",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Strawberries_G_2026",{["itemid"]=128646835922561,["itemname"]="Strawberries",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Striped_G_2025",{["itemid"]=118530164125152,["itemname"]="Striped",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Sugar",{["itemid"]=332848695,["itemname"]="Sugar",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Summer_Stickers_G_2023",{["itemid"]=13944151514,["itemname"]="Stickers",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Sunny_G_2025",{["itemid"]=93906279038399,["itemname"]="Sunny",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","SunsetGun",{["itemid"]=129480661108374,["itemname"]="Sunrise",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","SunsetGunChroma",{["chroma"]=true,["itemid"]=129480661108374,["itemname"]="Sunrise",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Sunset_G_2023",{["itemid"]=13944155639,["itemname"]="Sun",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Sunset_G_2026",{["itemid"]=120907601916735,["itemname"]="Sunset",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Sweater_G_2018",{["itemid"]=2669787088,["itemname"]="Sweater",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Sweater_G_2025",{["itemid"]=118557229750245,["itemname"]="Sweater",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","SwirlyGun",{["itemid"]=8305264097,["itemname"]="Swirly Gun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","SwirlyGunBlue",{["itemid"]=9552060741,["itemname"]="Blue Swirly",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","SwirlyGunBronze",{["itemid"]=9552063524,["itemname"]="Bronze Swirly",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","SwirlyGunChroma",{["chroma"]=true,["itemid"]=8311393414,["itemname"]="Swirly Gun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","SwirlyGunGold",{["itemid"]=9552065167,["itemname"]="Gold Swirly",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","SwirlyGunSilver",{["itemid"]=9552064240,["itemname"]="Silver Swirly",["itemtype"]="Gun",["rarity"]="Unique"}},
    {"Gun","ToxicG",{["itemid"]=2513742519,["itemname"]="Toxic",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","Toy_G_2023",{["itemid"]=13944152795,["itemname"]="Toy",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","TravelerGun",{["itemid"]=15091442039,["itemname"]="Traveler's Gun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","TravelerGunChroma",{["chroma"]=true,["itemid"]=15097897227,["itemname"]="Traveler's Gun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Traveler_G_2023",{["itemid"]=15091344462,["itemname"]="Traveler",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Treat",{["itemid"]=131626924640663,["itemname"]="Treat",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","TreatChroma",{["chroma"]=true,["itemid"]=131626924640663,["itemname"]="Treat",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Treats_G_2025",{["itemid"]=76537883908961,["itemname"]="Treats",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","TreeGun",{["itemid"]=332497688,["itemname"]="Tree",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","TreeGun2023",{["itemid"]=15682703596,["itemname"]="Evergun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","TreeGun2023Chroma",{["chroma"]=true,["itemid"]=15682703596,["itemname"]="Evergun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Tree_G_2022",{["itemid"]=11834441321,["itemname"]="Tree",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","UFOs_G_2025",{["itemid"]=84030107970606,["itemname"]="UFOs",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Universe",{["itemid"]=238546660,["itemname"]="Universe",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","VampireG2018",{["itemid"]=2513742751,["itemname"]="Vampire",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","VampireGun",{["itemid"]=90274872705656,["itemname"]="Vampire's Gun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","VampireGunChroma",{["chroma"]=true,["itemid"]=90274872705656,["itemname"]="Vampire's Gun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Vampire_G_2022",{["itemid"]=11255503583,["itemname"]="Vampire",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Vines_G_2023",{["itemid"]=15091402817,["itemname"]="Vines",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Viper",{["itemid"]=196752926,["itemname"]="Viper",["itemtype"]="Gun",["rarity"]="Legendary"}},
    {"Gun","Watcher_G_2021",{["itemid"]=7800256309,["itemname"]="Watcher",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","WaterBalloons_G_2024",{["itemid"]=18323751962,["itemname"]="Balloons",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Watergun",{["itemid"]=18351388416,["itemname"]="Watergun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","WatergunChroma",{["chroma"]=true,["itemid"]=18351401528,["itemname"]="Watergun",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Wavy_G_2024",{["itemid"]=16960077712,["itemname"]="Wavy",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","WebbedG",{["itemid"]=4210936652,["itemname"]="Webbed",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Webs_G_2022",{["itemid"]=11284147880,["itemname"]="Webs",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Wooden",{["itemid"]=238546356,["itemname"]="Wooden",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","WraithGun",{["itemid"]=75233248021696,["itemname"]="Soul",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Wraith_G_2022",{["itemid"]=11255504462,["itemname"]="Wraith",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","WrappedGun",{["itemid"]=332497103,["itemname"]="Wrapped",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","Wrapped_G_2018",{["itemid"]=2669787533,["itemname"]="Wrapped",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","Wrapped_G_2024",{["itemid"]=109929760056853,["itemname"]="Wrapped",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","XenoGun",{["itemid"]=79722325448464,["itemname"]="Xenoshot",["itemtype"]="Gun",["rarity"]="Godly"}},
    {"Gun","Xeno_G_2025",{["itemid"]=139755862211442,["itemname"]="Xeno",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Gun","XmasStickers_G_2021",{["itemid"]=8304770115,["itemname"]="Stickers",["itemtype"]="Gun",["rarity"]="Common"}},
    {"Gun","ZombieG2018",{["itemid"]=2513743298,["itemname"]="Zombie",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","ZombifiedG",{["itemid"]=4210944924,["itemname"]="Zombified",["itemtype"]="Gun",["rarity"]="Uncommon"}},
    {"Gun","iRevolver",{["itemid"]=203809168,["itemname"]="iRevolver",["itemtype"]="Gun",["rarity"]="Rare"}},
    {"Knife","2015",{["itemid"]=199026945,["itemname"]="2015",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","8bit",{["itemid"]=198438554,["itemname"]="8bit",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Abduction_K_2025",{["itemid"]=107510647616718,["itemname"]="Abduction",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Abstract",{["itemid"]=365569428,["itemname"]="Abstract",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Adurite",{["itemid"]=196749885,["itemname"]="Adurite",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Alex",{["itemid"]=546159020,["itemname"]="Alex",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","AmericaSword",{["itemid"]=473570051,["itemname"]="Old Glory",["itemtype"]="Knife",["offset"]={["X"]=-0.1,["Y"]=0,["Z"]=0.55},["rarity"]="Godly"}},
    {"Knife","Apoc_K_2022",{["itemid"]=11254172968,["itemname"]="Apocalypse",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Aqua",{["itemid"]=315501208,["itemname"]="Aqua",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Aquarium_K_2025",{["itemid"]=80900354672590,["itemname"]="Aquarium",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Arctic_K_2022",{["itemid"]=11834401547,["itemname"]="Arctic",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","AuroraKnife",{["itemid"]=101343256002049,["itemname"]="Australis",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Aurora_K_2019",{["itemid"]=4534860689,["itemname"]="Aurora",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Aurora_K_2021",{["itemid"]=8304750877,["itemname"]="Aurora",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Bats",{["itemid"]=531873625,["itemname"]="Bats",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","BatsK",{["itemid"]=2513732731,["itemname"]="Bats",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Bats_K_2020",{["itemid"]=5930729222,["itemname"]="Bats",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Bats_K_2024",{["itemid"]=104747488009018,["itemname"]="Bats",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Bats_K_2025",{["itemid"]=140366567839959,["itemname"]="Cats",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","BattleAxe",{["itemid"]=1133237368,["itemname"]="BattleAxe",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","BattleAxe2",{["itemid"]=2513535503,["itemname"]="BattleAxe II",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Batwing",{["itemid"]=196751515,["itemname"]="Glitch1",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","BaubleKnife",{["itemid"]=111092946728824,["itemname"]="Ornament",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","BaubleKnifeChroma",{["chroma"]=true,["itemid"]=111092946728824,["itemname"]="Ornament",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Beach_K_2023",{["itemid"]=13944135892,["itemname"]="Beach",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Beachy",{["itemid"]=120888453565511,["itemname"]="Beachy",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","BeachyChroma",{["chroma"]=true,["itemid"]=120888453565511,["itemname"]="Beachy",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Bells_K_2023",{["itemid"]=15635570486,["itemname"]="Bells",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Bio_K_2023",{["itemid"]=12965298174,["itemname"]="Bio",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Bioblade",{["itemid"]=4751539262,["itemname"]="Bioblade",["itemtype"]="Knife",["offset"]={["X"]=-0.1,["Y"]=-0.2,["Z"]=0.6},["rarity"]="Godly"}},
    {"Knife","Bleached",{["itemid"]=315500879,["itemname"]="Bleached",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","BloodKnife",{["itemid"]=473573464,["itemname"]="Blood",["itemtype"]="Knife",["rarity"]="Classic"}},
    {"Knife","Bloom",{["itemid"]=128553215441980,["itemname"]="Bloom",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Blossom",{["itemid"]=363150561,["itemname"]="Blossom",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Blossom_K_2026",{["itemid"]=110160120309916,["itemname"]="Blossom",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","BlueCamo_K_2022",{["itemid"]=11254146743,["itemname"]="Survivor Camo",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","BlueCandy",{["itemid"]=1489495701,["itemname"]="Blue Candy",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","BlueSeer",{["itemid"]=3184125087,["itemname"]="Blue Seer",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","BlueVampiresEdge",{["itemid"]=6084854835,["itemname"]="Blue Vamp's Edge",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Bluesteel",{["itemid"]=196750197,["itemname"]="Bluesteel",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Boneblade",{["itemid"]=2513505477,["itemname"]="Boneblade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","BonebladeChroma",{["chroma"]=true,["itemid"]=2513598419,["itemname"]="Boneblade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Bones",{["itemid"]=531873816,["itemname"]="Bones",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Bones_K_2020",{["itemid"]=5872492951,["itemname"]="Bones",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Bones_K_2022",{["itemid"]=11254152435,["itemname"]="Boney",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Bones_K_2024",{["itemid"]=76461209737867,["itemname"]="Bones",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Borders",{["itemid"]=198434881,["itemname"]="Borders",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Brains",{["itemid"]=531873956,["itemname"]="Brains",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Brains2019",{["itemid"]=4210929184,["itemname"]="Brains",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Branches",{["itemid"]=4210943691,["itemname"]="Branches",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Broken_K_2023",{["itemid"]=12339323856,["itemname"]="Broken",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","BronzeCandy",{["itemid"]=1520189487,["itemname"]="Bronze Candy",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","BronzeHallow",{["itemid"]=2511342846,["itemname"]="Bronze Hallow",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","BronzeIcebreaker",{["itemid"]=6404127119,["itemname"]="Bronze Icebreaker",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","BronzeVampiresEdge",{["itemid"]=6084842077,["itemname"]="Bronze Vamp's Edge",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Brush",{["itemid"]=365568602,["itemname"]="Brush",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Bubbles_K_2026",{["itemid"]=138388933477235,["itemname"]="Bubbles",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Bunnies_K_2025",{["itemid"]=90549252812333,["itemname"]="Bunnies",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Bunny",{["itemid"]=387874365,["itemname"]="Bunny",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","CamoKnife",{["itemid"]=3183606225,["itemname"]="Camo",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Candied_K_2022",{["itemid"]=11834384755,["itemname"]="Candied",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Candle_K_2020",{["itemid"]=5872491708,["itemname"]="Candle",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Candleflame",{["itemid"]=7805833970,["itemname"]="Candleflame",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","CandleflameChroma",{["chroma"]=true,["itemid"]=7806121918,["itemname"]="Candleflame",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Candles_K_2024",{["itemid"]=133654810681274,["itemname"]="Candles",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Candy",{["itemid"]=332021011,["itemname"]="Candy",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","CandyCorn",{["itemid"]=1133337797,["itemname"]="CandyCorn",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","CandyCorn2019",{["itemid"]=4210934082,["itemname"]="Candy Corn",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","CandyCorn_K_2020",{["itemid"]=5866435364,["itemname"]="Candy Corn",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","CandyCorn_K_2022",{["itemid"]=11254057417,["itemname"]="Candy Corn",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","CandyCorn_K_2024",{["itemid"]=115093067149752,["itemname"]="Candy Corn",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","CandyCorn_K_2025",{["itemid"]=86405207895194,["itemname"]="Candy Corn",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","CandySwirl_K_2019",{["itemid"]=4534860226,["itemname"]="Candy Swirl",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Cane",{["itemid"]=331140746,["itemname"]="Cane",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Cane_K_2018",{["itemid"]=2669638508,["itemname"]="Cane",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Cane_K_2021",{["itemid"]=8304750295,["itemname"]="Cane",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Canes_K_2023",{["itemid"]=15635574962,["itemname"]="Canes",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Cardboard",{["itemid"]=235366729,["itemname"]="Cardboard",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Carrot",{["itemid"]=387874071,["itemname"]="Carrot",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Carrot_K_2023",{["itemid"]=12965307410,["itemname"]="Carrot",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Carrot_K_2024",{["itemid"]=16959771850,["itemname"]="Carrot",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Carrots_K_2025",{["itemid"]=76914260444878,["itemname"]="Carrots",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Carved_K_2020",{["itemid"]=5866436906,["itemname"]="Carved",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Cavern_K_2019",{["itemid"]=4534861110,["itemname"]="Cavern",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Celestial",{["itemid"]=136673966529736,["itemname"]="Celestial",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","Celestial_Bronze",{["itemid"]=119399643874968,["itemname"]="Bronze Celestial",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Celestial_Gold",{["itemid"]=104229967982042,["itemname"]="Gold Celestial",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Celestial_Red",{["itemid"]=119157529694972,["itemname"]="Red Celestial",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Celestial_Silver",{["itemid"]=90241292303974,["itemname"]="Silver Celestial",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Checker",{["itemid"]=198443382,["itemname"]="Checker",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Cheesy",{["itemid"]=198440101,["itemname"]="Cheesy",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Cherry",{["itemid"]=6711852603,["itemname"]="Cherry",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Chick_K_2025",{["itemid"]=116361515042274,["itemname"]="Chick",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Chill",{["itemid"]=332022166,["itemname"]="Chill",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Chips",{["itemid"]=473626317,["itemname"]="Blue",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Choco",{["itemid"]=387874991,["itemname"]="Choco",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Chromatic_K_2023",{["itemid"]=12965304445,["itemname"]="Chromatic",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Circuit",{["itemid"]=235366945,["itemname"]="Circuit",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Clan",{["itemid"]=235366460,["itemname"]="Clan",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Clockwork",{["itemid"]=473570519,["itemname"]="Clockwork",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Clown",{["itemid"]=315501118,["itemname"]="Clown",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Clownfish_K_2024",{["itemid"]=18322183619,["itemname"]="Clownfish",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Coal",{["itemid"]=1268699677,["itemname"]="Coal",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Coal_K_2018",{["itemid"]=2669638285,["itemname"]="Coal",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Coal_K_2021",{["itemid"]=8304751659,["itemname"]="Coal",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Coal_K_2022",{["itemid"]=11834390120,["itemname"]="Coal",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Coconut_K_2025",{["itemid"]=75237025203058,["itemname"]="Coconut",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Combat",{["itemid"]=3183604570,["itemname"]="Combat",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Combat2",{["itemid"]=4972196241,["itemname"]="Combat II",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Constellation_K_2024",{["itemid"]=113979322866878,["itemname"]="Nightstar",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Cookie_K_2021",{["itemid"]=8304752586,["itemname"]="Cookie",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Cookieblade",{["itemid"]=6125733703,["itemname"]="Cookieblade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Copper",{["itemid"]=3183605392,["itemname"]="Copper",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Corl",{["itemid"]=546161858,["itemname"]="Corl",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","CottonCandy",{["itemid"]=435933179,["itemname"]="Cotton Candy",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Cowboy_K_2026",{["itemid"]=137905346768007,["itemname"]="Cowboy",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Cracks_K_2021",{["itemid"]=7800224981,["itemname"]="Cracks",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Cupid_K_2026",{["itemid"]=123955324398353,["itemname"]="Cupid",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Cursed_K_2024",{["itemid"]=132565936309463,["itemname"]="Cursed",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Damp",{["itemid"]=198443956,["itemname"]="Damp",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Dark_K_2023",{["itemid"]=15091343579,["itemname"]="Darkknife",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Darkness_K_2022",{["itemid"]=11254081561,["itemname"]="Darkness",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Darksword",{["itemid"]=15080267070,["itemname"]="Darksword",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Deathshard",{["itemid"]=196750305,["itemname"]="Deathshard",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","DeathshardChroma",{["chroma"]=true,["itemid"]=3187390667,["itemname"]="Deathshard",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Decorated_K_2025",{["itemid"]=124860763249593,["itemname"]="Decorated",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","DeepSea",{["itemid"]=4659634072,["itemname"]="Deep Sea",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Denis",{["itemid"]=546161062,["itemname"]="Denis",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Dew",{["itemid"]=473626646,["itemname"]="Black",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Doge",{["itemid"]=235371276,["itemname"]="Doge",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Dolphins_K_2025",{["itemid"]=133219566412887,["itemname"]="Dolphins",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Donut",{["itemid"]=235366815,["itemname"]="Donut",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Doritos",{["itemid"]=473626740,["itemname"]="Purple",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Dungeon",{["itemid"]=4210920512,["itemname"]="Dungeon",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Eclipse_K_2023",{["itemid"]=15091404278,["itemname"]="Eclipse",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Eco",{["itemid"]=365567889,["itemname"]="Eco",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Ecto",{["itemid"]=1133331679,["itemname"]="Ecto",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Eggblade",{["itemid"]=6607277825,["itemname"]="Eggblade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Eggs",{["itemid"]=387875405,["itemname"]="Egg",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","ElderwoodKnife",{["itemid"]=11262771067,["itemname"]="Elderwood Blade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","ElderwoodKnifeBlue",{["itemid"]=11505913287,["itemname"]="Blue Elderwood",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","ElderwoodKnifeBronze",{["itemid"]=11505914752,["itemname"]="Bronze Elderwood",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","ElderwoodKnifeChroma",{["chroma"]=true,["itemid"]=11254975176,["itemname"]="Elderwood Blade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","ElderwoodKnifeGold",{["itemid"]=11505917850,["itemname"]="Gold Elderwood",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","ElderwoodKnifeSilver",{["itemid"]=11505916486,["itemname"]="Silver Elderwood",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","ElderwoodScythe",{["itemid"]=4211148191,["itemname"]="Elderwood Scythe",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","Elf",{["itemid"]=331746317,["itemname"]="Elf",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Elf2017",{["itemid"]=1268703023,["itemname"]="Elf",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Elite",{["itemid"]=241095344,["itemname"]="Elite",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","EliteBlue",{["itemid"]=1269374321,["itemname"]="Blue Elite",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","EliteGreen",{["itemid"]=332731156,["itemname"]="Green Elite",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Emerald",{["itemid"]=198444909,["itemname"]="Emerald",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Energized_K_2025",{["itemid"]=86258299490709,["itemname"]="Energized",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Eternal",{["itemid"]=619605312,["itemname"]="Eternal",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Eternal2",{["itemid"]=2545253030,["itemname"]="Eternal II",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Eternal3",{["itemid"]=3279011390,["itemname"]="Eternal III",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Eternal4",{["itemid"]=4999958740,["itemname"]="Eternal IV",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","EternalCane",{["itemid"]=4488391411,["itemname"]="Eternalcane",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Euro",{["itemid"]=305504173,["itemname"]="Euro",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Eyeball_K_2022",{["itemid"]=11254065007,["itemname"]="Eyeball",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Eyes_K_2020",{["itemid"]=5866438542,["itemname"]="Watcher",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Fade",{["itemid"]=315501640,["itemname"]="Fade",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Fang",{["itemid"]=198442811,["itemname"]="Fang",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","FangChroma",{["chroma"]=true,["itemid"]=3187392501,["itemname"]="Fang",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Fanta",{["itemid"]=473626025,["itemname"]="Orange",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Fireplace_K_2023",{["itemid"]=15635558021,["itemname"]="Fireplace",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Flames",{["itemid"]=585873746,["itemname"]="Flames",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Floral_K_2023",{["itemid"]=13944134705,["itemname"]="Floral",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","FlowerwoodKnife",{["itemid"]=16963860501,["itemname"]="Flowerwood",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Fragile_K_2023",{["itemid"]=12965294432,["itemname"]="Fragile",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Frostbite",{["itemid"]=4528484880,["itemname"]="Frostbite",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Frosted_K_2019",{["itemid"]=4534853444,["itemname"]="Frosted",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Frostfade_K_2023",{["itemid"]=15635565488,["itemname"]="Frostfade",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Frostflame_K_2024",{["itemid"]=104988218477551,["itemname"]="Frostflame",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Frostsaber",{["itemid"]=1269580035,["itemname"]="Frostsaber",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Frosty",{["itemid"]=1268704507,["itemname"]="Frosty",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Frozen_K_2019",{["itemid"]=4534857523,["itemname"]="Frozen",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Frozen_K_2022",{["itemid"]=11834404402,["itemname"]="Frozen",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Frozen_K_2023",{["itemid"]=15635556891,["itemname"]="Frozen",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Frozen_K_2025",{["itemid"]=108996627787763,["itemname"]="Frozen",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Fusion",{["itemid"]=365569686,["itemname"]="Fusion",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Future",{["itemid"]=197638833,["itemname"]="Future",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Galaxy",{["itemid"]=196750422,["itemname"]="Galaxy",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Gemstone",{["itemid"]=3183598040,["itemname"]="Gemstone",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","GemstoneChroma",{["chroma"]=true,["itemid"]=3183597816,["itemname"]="Gemstone",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Ghastly_K_2023",{["itemid"]=15091407068,["itemname"]="Ghastly",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","GhostK2018",{["itemid"]=2513732969,["itemname"]="Ghost",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","GhostKnife",{["itemid"]=473574401,["itemname"]="Ghost",["itemtype"]="Knife",["rarity"]="Classic"}},
    {"Knife","GhostRbx_K_2022",{["itemid"]=11117375743,["itemname"]="Ghostly",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Ghostblade",{["itemid"]=4221789003,["itemname"]="Ghostblade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Ghosts_K_2020",{["itemid"]=5866442790,["itemname"]="Ghosts",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Ghosts_K_2021",{["itemid"]=7808362279,["itemname"]="Wraiths",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Ghosts_K_2023",{["itemid"]=15091326116,["itemname"]="Ghosts",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Ghosts_K_2024",{["itemid"]=134681523511387,["itemname"]="Ghosts",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Ghosty",{["itemid"]=531873080,["itemname"]="Ghosty",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Gift_K_2020",{["itemid"]=6121854816,["itemname"]="Wrap",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Giftbag_K_2020",{["itemid"]=6121847170,["itemname"]="Gift Bag",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Gifted",{["itemid"]=197626358,["itemname"]="Gifted",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Gifts_K_2019",{["itemid"]=4534856285,["itemname"]="Gifts",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Gifts_K_2024",{["itemid"]=129290011017110,["itemname"]="Gifts",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Giftwrap_K_2021",{["itemid"]=8304754179,["itemname"]="Giftwrap",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Ginger",{["itemid"]=331744703,["itemname"]="Ginger",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Ginger_K_2018",{["itemid"]=2669638742,["itemname"]="Ginger",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Gingerblade",{["itemid"]=2669336659,["itemname"]="Gingerblade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","GingerbladeChroma",{["chroma"]=true,["itemid"]=2672349340,["itemname"]="Gingerblade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Gingerbread2017",{["itemid"]=1268705527,["itemname"]="Gingerbread",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Gingerbread_K_2019",{["itemid"]=4534856940,["itemname"]="Gingerbread",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Gingerbread_K_2020",{["itemid"]=6121850031,["itemname"]="Gingerbread",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Gingerbread_K_2022",{["itemid"]=11834399071,["itemname"]="Gingerbread",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Gingerbread_K_2025",{["itemid"]=134478959354477,["itemname"]="Gingerbread",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Gingercookie_K_2025",{["itemid"]=111408683823094,["itemname"]="Gingercookie",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Gingerheart_K_2024",{["itemid"]=115273559455814,["itemname"]="Gingerheart",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Gingermint_K",{["itemid"]=11855306927,["itemname"]="Cookiecane",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Gingermint_KChroma",{["chroma"]=true,["itemid"]=11873640255,["itemname"]="Cookiecane",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Gingerscythe",{["itemid"]=15683138101,["itemname"]="Gingerscythe",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Gingerscythe_Ancient",{["itemid"]=15683188776,["itemname"]="Gingerscythe",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","Gingerscythe_Blue",{["itemid"]=16964448042,["itemname"]="Blue Gingerscythe",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Gingerscythe_Bronze",{["itemid"]=16964449392,["itemname"]="Bronze Gingerscythe",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Gingerscythe_Godly",{["itemid"]=15683175970,["itemname"]="Gingerscythe",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Gingerscythe_Gold",{["itemid"]=16964452491,["itemname"]="Gold Gingerscythe",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Gingerscythe_Legendary",{["itemid"]=15683140564,["itemname"]="Gingerscythe",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Gingerscythe_Silver",{["itemid"]=16964450895,["itemname"]="Silver Gingerscythe",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Glowy_K_2023",{["itemid"]=15091403551,["itemname"]="Glowy",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","GoldCandy",{["itemid"]=1520188792,["itemname"]="Gold Candy",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","GoldHallow",{["itemid"]=2511340308,["itemname"]="Gold Hallow",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","GoldIcebreaker",{["itemid"]=6404115112,["itemname"]="Gold Icebreaker",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","GoldVampiresEdge",{["itemid"]=6084838617,["itemname"]="Gold Vamp's Edge",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Golden_K_2026",{["itemid"]=117280525154459,["itemname"]="Golden",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Goo",{["itemid"]=237336076,["itemname"]="Goo",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Gothic_K_2021",{["itemid"]=7800221141,["itemname"]="Gothic",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Graffiti",{["itemid"]=4659634630,["itemname"]="Graffiti",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","GraveK",{["itemid"]=2513728474,["itemname"]="Grave",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","GreenCamo_K_2022",{["itemid"]=11254145154,["itemname"]="Zombie Camo",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","GreenFire",{["itemid"]=1268706374,["itemname"]="Green Fire",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","GreenMarble",{["itemid"]=1133366830,["itemname"]="Green Marble",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Grind",{["itemid"]=305503942,["itemname"]="Grind",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Hallow",{["itemid"]=531878205,["itemname"]="Hallow's Edge",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","HallowsBlade",{["itemid"]=1132775323,["itemname"]="Hallow's Blade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Hallowscythe",{["itemid"]=5877016863,["itemname"]="Hallowscythe",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","Handsaw",{["itemid"]=473572138,["itemname"]="Handsaw",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Hardened",{["itemid"]=3183605810,["itemname"]="Hardened",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","HauntedHouse_K_2025",{["itemid"]=90194465176219,["itemname"]="Haunted",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","HauntedK",{["itemid"]=2513733741,["itemname"]="Haunted",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Haunted_K_2021",{["itemid"]=7800222135,["itemname"]="Haunted",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Hazard_K_2022",{["itemid"]=11254083234,["itemname"]="Hazard",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Hazmat",{["itemid"]=315501297,["itemname"]="Hazmat",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","HeartWand",{["itemid"]=118334707962654,["itemname"]="Heart Wand",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","HeartWandChroma",{["chroma"]=true,["itemid"]=78479059410850,["itemname"]="Heart Wand",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Heart_K_2023",{["itemid"]=12339327069,["itemname"]="Heart",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Heartblade",{["itemid"]=6413145922,["itemname"]="Heartblade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Hearts",{["itemid"]=363352211,["itemname"]="Hearts",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Hearts_K_2026",{["itemid"]=99939659856909,["itemname"]="Hearts",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Heat",{["itemid"]=201238541,["itemname"]="Heat",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","HeatChroma",{["chroma"]=true,["itemid"]=3187395238,["itemname"]="Heat",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","HighTech",{["itemid"]=4659635055,["itemname"]="High Tech",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Hive",{["itemid"]=315501434,["itemname"]="Hive",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Holly_K_2018",{["itemid"]=2669638990,["itemname"]="Holly",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Hologram_K_2025",{["itemid"]=77773918675860,["itemname"]="Hologram",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","HotChocolate_K_2024",{["itemid"]=133307062463653,["itemname"]="Hot Chocolate",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Hunter_K_2022",{["itemid"]=11254154978,["itemname"]="Hunter",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Ice",{["itemid"]=196750668,["itemname"]="Ice",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","IceDragon",{["itemid"]=585872642,["itemname"]="Ice Dragon",["itemtype"]="Knife",["offset"]={["X"]=0,["Y"]=0,["Z"]=0.55},["rarity"]="Godly"}},
    {"Knife","IceHammer",{["itemid"]=11855360152,["itemname"]="Icecrusher",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","IceHammerBronze",{["itemid"]=12227148356,["itemname"]="Bronze Icecrusher",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","IceHammerGold",{["itemid"]=12227137860,["itemname"]="Gold Icecrusher",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","IceHammerRed",{["itemid"]=12227186408,["itemname"]="Red Icecrusher",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","IceHammerSilver",{["itemid"]=12227142478,["itemname"]="Silver Icecrusher",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","IceHammer_Ancient",{["itemid"]=11855274019,["itemname"]="Icecrusher",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","IceHammer_Godly",{["itemid"]=11855282546,["itemname"]="Icecrusher",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","IceHammer_Legendary",{["itemid"]=11855361567,["itemname"]="Icecrusher",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","IceShard",{["itemid"]=1268710824,["itemname"]="Ice Shard",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Icebreaker",{["itemid"]=6125729383,["itemname"]="Icebreaker",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","Icecracker_K_2020",{["itemid"]=6121848805,["itemname"]="Icecracker",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Icecream",{["itemid"]=87189663191639,["itemname"]="Icecream",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","IcecreamChroma",{["chroma"]=true,["itemid"]=87189663191639,["itemname"]="Icecream",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Iceflake",{["itemid"]=8304818186,["itemname"]="Iceflake",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Icewing",{["itemid"]=3183085102,["itemname"]="Icewing",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","Icicles_K_2018",{["itemid"]=2669639638,["itemname"]="Icicles",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Igloo_K_2024",{["itemid"]=73203940450745,["itemname"]="Igloo",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Indy",{["itemid"]=305506951,["itemname"]="Indy",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Infected",{["itemid"]=200953094,["itemname"]="Infected",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Infected_K_2022",{["itemid"]=11254175272,["itemname"]="Infected",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","JD",{["itemid"]=566867312,["itemname"]="JD",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Jack",{["itemid"]=315099010,["itemname"]="Jack",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Jack_K_2022",{["itemid"]=11254093910,["itemname"]="Lantern",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Jellyfish_K_2024",{["itemid"]=18322181701,["itemname"]="Jellyfish",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Jigsaw",{["itemid"]=365569126,["itemname"]="Jigsaw",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Knife1",{["itemid"]=473574001,["itemname"]="Splitter",["itemtype"]="Knife",["rarity"]="Classic"}},
    {"Knife","Kool",{["itemid"]=473625906,["itemname"]="Yellow",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Korblox",{["itemid"]=315501501,["itemname"]="Korblox",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Kraken_K_2024",{["itemid"]=116059045830205,["itemname"]="Kraken",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Krypto",{["itemid"]=198440414,["itemname"]="Krypto",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","LMFAO",{["itemid"]=473626473,["itemname"]="Pink",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Laser_K_2026",{["itemid"]=76785021563290,["itemname"]="Laser",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Latte_K_2023",{["itemid"]=15413114703,["itemname"]="Latte",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Lava_K_2025",{["itemid"]=131417913843701,["itemname"]="Lava",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Leaf",{["itemid"]=4659636452,["itemname"]="Leaf",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Leaves_K_2023",{["itemid"]=15091400883,["itemname"]="Leaves",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Leaves_K_2025",{["itemid"]=73486056426142,["itemname"]="Leaves",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Lights_K_2019",{["itemid"]=4534858185,["itemname"]="Lights",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Lights_K_2025",{["itemid"]=71228862432065,["itemname"]="Lights",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Linked",{["itemid"]=198433893,["itemname"]="Linked",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Log",{["itemid"]=365567962,["itemname"]="Log",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Logchopper",{["itemid"]=4535644282,["itemname"]="Logchopper",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","LogchopperBlue",{["itemid"]=4753353471,["itemname"]="Blue Logchopper",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","LogchopperBronze",{["itemid"]=4753354123,["itemname"]="Bronze Logchopper",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","LogchopperGold",{["itemid"]=4753354638,["itemname"]="Gold Logchopper",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","LogchopperSilver",{["itemid"]=4753352581,["itemname"]="Silver Logchopper",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Logcutter_K_2024",{["itemid"]=71088901904009,["itemname"]="Logcutter",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Love",{["itemid"]=196750845,["itemname"]="Love",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Love_K_2023",{["itemid"]=12339328595,["itemname"]="Love",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Lovely",{["itemid"]=4659635584,["itemname"]="Lovely",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Lucky",{["itemid"]=365569265,["itemname"]="Lucky",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","MLG",{["itemid"]=473626979,["itemname"]="Shiny",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","MagmaK",{["itemid"]=1133317890,["itemname"]="Magma",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Magma_K_2021",{["itemid"]=7800225996,["itemname"]="Magma",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Marble_K_2023",{["itemid"]=12965302237,["itemname"]="Marble",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Marley",{["itemid"]=473625785,["itemname"]="Green",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Melon",{["itemid"]=315501369,["itemname"]="Melon",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Meltdown_K_2023",{["itemid"]=15091340751,["itemname"]="Meltdown",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Midnight",{["itemid"]=197663897,["itemname"]="Midnight",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Missing",{["itemid"]=198439692,["itemname"]="Missing",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Mistletoe_K_2022",{["itemid"]=11834394793,["itemname"]="Mistletoe",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","MoltenKnife",{["itemid"]=235371809,["itemname"]="Molten",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Monster_K_2024",{["itemid"]=109292073070223,["itemname"]="Monster",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Moon_K_2021",{["itemid"]=7800224197,["itemname"]="Moon",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Moons",{["itemid"]=531873154,["itemname"]="Moons",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Moons_K_2024",{["itemid"]=91446990047399,["itemname"]="Moons",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Mummified",{["itemid"]=4210946577,["itemname"]="Mummified",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","MummyK",{["itemid"]=1133352032,["itemname"]="Mummy",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","MummyK2018",{["itemid"]=2513733542,["itemname"]="Mummy",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Mummy_K_2020",{["itemid"]=5866447521,["itemname"]="Mummy",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Musical",{["itemid"]=365569566,["itemname"]="Musical",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Nebula",{["itemid"]=6598123521,["itemname"]="Nebula",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Neon",{["itemid"]=198566885,["itemname"]="Neon",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Neopolitan_K_2026",{["itemid"]=73980008491741,["itemname"]="Neopolitan",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Nether",{["itemid"]=197656593,["itemname"]="Nether",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Nightblade",{["itemid"]=475478854,["itemname"]="Nightblade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","NikKnife",{["itemid"]=2533351841,["itemname"]="Nik's Scythe",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","Noodle_K_2023",{["itemid"]=13944132845,["itemname"]="Pool Noodle",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Nova",{["itemid"]=235371686,["itemname"]="Nova",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Oily",{["itemid"]=315501170,["itemname"]="Oily",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Ollie",{["itemid"]=305504399,["itemname"]="Ollie",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","OrangeMarble",{["itemid"]=531873011,["itemname"]="Orange Marble",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","OrangeSeer",{["itemid"]=3184124504,["itemname"]="Orange Seer",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Ornament1",{["itemid"]=331745428,["itemname"]="Ornament",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Ornament2",{["itemid"]=331745341,["itemname"]="Ornament2",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Ornaments_K_2020",{["itemid"]=6121853160,["itemname"]="Ornaments",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Ornaments_K_2025",{["itemid"]=132504094164819,["itemname"]="Ornaments",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","OverseerKnife",{["itemid"]=198441413,["itemname"]="Overseer",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Painted_K_2023",{["itemid"]=12965311567,["itemname"]="Painted",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Palms_K_2024",{["itemid"]=18322137551,["itemname"]="Palms",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Paper",{["itemid"]=235366870,["itemname"]="Paper",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Passion",{["itemid"]=363150334,["itemname"]="Passion",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Patrick",{["itemid"]=383476085,["itemname"]="Patrick",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Pearl_K",{["itemid"]=18322621319,["itemname"]="Pearl",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Penguin_K_2025",{["itemid"]=93320180084418,["itemname"]="Penguin",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Pepper",{["itemid"]=473625645,["itemname"]="Brown",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Peppermint",{["itemid"]=6085035357,["itemname"]="Peppermint",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Peppermint_K_2025",{["itemid"]=84605926178412,["itemname"]="Peppermint",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Phantom",{["itemid"]=1133332075,["itemname"]="Phantom",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Phantom2022",{["itemid"]=11229732037,["itemname"]="Phantom",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Phaser_K_2026",{["itemid"]=88433569053641,["itemname"]="Phaser",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Pier_K_2026",{["itemid"]=127570773123670,["itemname"]="Pier",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Pine_K_2019",{["itemid"]=4534855710,["itemname"]="Pine",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Pixel",{["itemid"]=473573054,["itemname"]="Pixel",["itemtype"]="Knife",["offset"]={["X"]=0,["Y"]=0.2,["Z"]=0.5},["rarity"]="Godly"}},
    {"Knife","Plasmablade",{["itemid"]=10014680882,["itemname"]="Plasmablade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Plasmite",{["itemid"]=196750899,["itemname"]="Plasmite",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","PolarBear_K_2025",{["itemid"]=120422092957504,["itemname"]="Polar Bear",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Pool_K_2025",{["itemid"]=112511843095202,["itemname"]="Pool",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","PopArt_K_2025",{["itemid"]=123269723073737,["itemname"]="Pop Art",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Popsicle_K_2023",{["itemid"]=13944131195,["itemname"]="Popsicle",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Portal_K_2020",{["itemid"]=5866444722,["itemname"]="Portal",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Potion",{["itemid"]=1133366632,["itemname"]="Potion",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","PotionK2018",{["itemid"]=2513733987,["itemname"]="Potion",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","PredatorKnife",{["itemid"]=235372015,["itemname"]="Predator",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Present",{["itemid"]=1268699212,["itemname"]="Present",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Present_K_2023",{["itemid"]=15635553149,["itemname"]="Present",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Prism",{["itemid"]=306046703,["itemname"]="Prism",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Prismatic",{["itemid"]=5360359935,["itemname"]="Prismatic",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","PumpkinPatch",{["itemid"]=4210931354,["itemname"]="Pumpkin",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","PumpkinPatch_K_2025",{["itemid"]=119626042140839,["itemname"]="Pumpkin",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","PumpkinPie_K_2023",{["itemid"]=15413117611,["itemname"]="Pumpkin Pie",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Pumpkin_K_2020",{["itemid"]=5872490600,["itemname"]="Pumpkin",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Pumpking",{["itemid"]=1138143590,["itemname"]="Pumpking",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","PurpleSeer",{["itemid"]=3184125244,["itemname"]="Purple Seer",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","RBKnife",{["itemid"]=5984754897,["itemname"]="RB Knife",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Rainbow",{["itemid"]=196750963,["itemname"]="Rainbow",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Rainbow_K",{["itemid"]=12966184630,["itemname"]="Rainbow",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","RandLuger",{["itemid"]=196751515,["itemname"]="Glitch2",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","RbxScary_K_2023",{["itemid"]=14967668214,["itemname"]="Ghoulish",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Reaver",{["itemid"]=7791484774,["itemname"]="Reaver",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Reaver_Ancient",{["itemid"]=7791640819,["itemname"]="Reaver",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","Reaver_Godly",{["itemid"]=7791511648,["itemname"]="Reaver",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Reaver_Legendary",{["itemid"]=7791485669,["itemname"]="Reaver",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","RedFire",{["itemid"]=1269256860,["itemname"]="Red Fire",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","RedHallow",{["itemid"]=2511343130,["itemname"]="Red Hallow",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","RedIcebreaker",{["itemid"]=6404129111,["itemname"]="Red Icebreaker",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","RedSeer",{["itemid"]=3184122829,["itemname"]="Red Seer",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Reindeer_K_2024",{["itemid"]=109101361674956,["itemname"]="Reindeer",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Reindeer_K_2025",{["itemid"]=122078592955794,["itemname"]="Reindeer",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Reptile",{["itemid"]=197499641,["itemname"]="Reptile",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Retro_K_2025",{["itemid"]=85299848190695,["itemname"]="Retro",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Ribbon_K_2023",{["itemid"]=15635552019,["itemname"]="Ribbon",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Ribbons_K_2021",{["itemid"]=8304754882,["itemname"]="Ribbons",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Ripper_K_2020",{["itemid"]=5866441301,["itemname"]="Ripper",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Robot_K_2024",{["itemid"]=16959778188,["itemname"]="Robot",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Rose_K_2023",{["itemid"]=12339325736,["itemname"]="Rose",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Roses",{["itemid"]=363352002,["itemname"]="Roses",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Rune",{["itemid"]=3183607894,["itemname"]="Rune",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Runic_K_2022",{["itemid"]=11254123390,["itemname"]="Curse",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Sakura_K",{["itemid"]=12339366064,["itemname"]="Sakura",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Sand_K_2026",{["itemid"]=138109619662236,["itemname"]="Sand",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Sandy",{["itemid"]=365568056,["itemname"]="Sandy",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Santa",{["itemid"]=331746096,["itemname"]="Santa",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Santa2017",{["itemid"]=1268703618,["itemname"]="Santa",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Santa_K_2018",{["itemid"]=2669637780,["itemname"]="Santa",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","SantasMagic",{["itemid"]=4535483042,["itemname"]="Santa's Magic",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","SantasSpirit",{["itemid"]=6123357775,["itemname"]="Santa's Spirit",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Saw",{["itemid"]=235381341,["itemname"]="Saw",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","SawChroma",{["chroma"]=true,["itemid"]=3187392992,["itemname"]="Saw",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Scarf_K_2023",{["itemid"]=15415482999,["itemname"]="Scarf",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Scratch",{["itemid"]=531873371,["itemname"]="Scratch",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","ScratchBlue",{["itemid"]=1133316381,["itemname"]="Scratch",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Scythe",{["itemid"]=2511791893,["itemname"]="Batwing",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","Season1TestKnife",{["itemid"]=196751515,["itemname"]="S1 Test Knife",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","SeerChroma",{["chroma"]=true,["itemid"]=3184125538,["itemname"]="Seer",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Shaded",{["itemid"]=4659636085,["itemname"]="Shaded",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","ShadowKnife",{["itemid"]=474030882,["itemname"]="Shadow",["itemtype"]="Knife",["rarity"]="Classic"}},
    {"Knife","Sharky_K_2024",{["itemid"]=18322179563,["itemname"]="Sharky",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Sidewinder",{["itemid"]=305503783,["itemname"]="Sidewinder",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","SilentNight_K_2020",{["itemid"]=6121851313,["itemname"]="Silent Night",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","SilverCandy",{["itemid"]=1520190188,["itemname"]="Silver Candy",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","SilverHallow",{["itemid"]=2511341094,["itemname"]="Silver Hallow",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","SilverIcebreaker",{["itemid"]=6404126280,["itemname"]="Silver Icebreaker",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","SilverVampiresEdge",{["itemid"]=6084840560,["itemname"]="Silver Vamp's Edge",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","SketchYT",{["itemid"]=546161470,["itemname"]="Sketchy",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Skool",{["itemid"]=295269977,["itemname"]="Skool",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Skull_K_2023",{["itemid"]=15091321393,["itemname"]="Etched",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Skulls",{["itemid"]=4210915060,["itemname"]="Skulls",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Skulls_K_2021",{["itemid"]=7800220325,["itemname"]="Skulls",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Skyline_K_2025",{["itemid"]=75608370390005,["itemname"]="Skyline",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Slashed_K_2020",{["itemid"]=5929317433,["itemname"]="Slashed",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Slasher",{["itemid"]=315506122,["itemname"]="Slasher",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","SlasherChroma",{["chroma"]=true,["itemid"]=3187393285,["itemname"]="Slasher",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Slate",{["itemid"]=198434520,["itemname"]="Slate",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Sleigh_K_2024",{["itemid"]=74917318027165,["itemname"]="Sleigh",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","SlimeK",{["itemid"]=2513734227,["itemname"]="Slime",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","SlimyK",{["itemid"]=4210932676,["itemname"]="Slimy",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","SlouseClown",{["itemid"]=315501118,["itemname"]="Clown",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","SnakebiteK",{["itemid"]=4210939388,["itemname"]="Snakebite",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Snoop",{["itemid"]=473626150,["itemname"]="Red",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","SnowDagger",{["itemid"]=95328449981238,["itemname"]="Snow Dagger",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","SnowDaggerBronze",{["itemid"]=134312132943601,["itemname"]="Bronze Snow Dagger",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","SnowDaggerChroma",{["chroma"]=true,["itemid"]=95328449981238,["itemname"]="Snow Dagger",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","SnowDaggerGold",{["itemid"]=70701057041846,["itemname"]="Gold Snow Dagger",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","SnowDaggerRed",{["itemid"]=87617250559234,["itemname"]="Red Snow Dagger",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","SnowDaggerSilver",{["itemid"]=128427983277729,["itemname"]="Silver Snow Dagger",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Snowball_K_2025",{["itemid"]=119914093248842,["itemname"]="Snowball",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Snowfall_K_2023",{["itemid"]=15635568751,["itemname"]="Snowfall",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Snowflake",{["itemid"]=1268932977,["itemname"]="Snowflake",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Snowflake_K_2018",{["itemid"]=2669639913,["itemname"]="Snowflake",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Snowflake_K_2022",{["itemid"]=11834397133,["itemname"]="Snowflake",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Snowflakes_K_2019",{["itemid"]=4534855045,["itemname"]="Snowflakes",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Snowflakes_K_2020",{["itemid"]=6123338102,["itemname"]="Snowflakes",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Snowglobe_K_2023",{["itemid"]=15635576863,["itemname"]="Snowglobe",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Snowman",{["itemid"]=331745799,["itemname"]="Snowman",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Snowman_K_2018",{["itemid"]=2669640152,["itemname"]="Snowman",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Snowman_K_2021",{["itemid"]=8304753468,["itemname"]="Snowman",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Snowman_K_2022",{["itemid"]=11834391469,["itemname"]="Snowman",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Snowman_K_2024",{["itemid"]=85751270338066,["itemname"]="Snowman",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Snowstorm",{["itemid"]=70973050894155,["itemname"]="Snowstorm",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","SnowstormChroma",{["chroma"]=true,["itemid"]=70973050894155,["itemname"]="Snowstorm",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Snowy",{["itemid"]=332011125,["itemname"]="Snowy",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Snowy2017",{["itemid"]=1268705947,["itemname"]="Snowy",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Soda_K_2025",{["itemid"]=89899263078420,["itemname"]="Soda",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Sorry",{["itemid"]=197879343,["itemname"]="Corrupt",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Space",{["itemid"]=3183607442,["itemname"]="Space",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Sparkle1",{["itemid"]=310709709,["itemname"]="Sparkle1",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Sparkle10",{["itemid"]=310715768,["itemname"]="Sparkle10",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Sparkle2",{["itemid"]=310710191,["itemname"]="Sparkle2",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Sparkle3",{["itemid"]=310710694,["itemname"]="Sparkle3",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Sparkle4",{["itemid"]=310712788,["itemname"]="Sparkle4",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Sparkle5",{["itemid"]=310713235,["itemname"]="Sparkle5",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Sparkle6",{["itemid"]=310713648,["itemname"]="Sparkle6",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Sparkle7",{["itemid"]=310714089,["itemname"]="Sparkle7",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Sparkle8",{["itemid"]=310714407,["itemname"]="Sparkle8",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Sparkle9",{["itemid"]=310715104,["itemname"]="Sparkle9",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Spearmint_K_2025",{["itemid"]=98506456649552,["itemname"]="Spearmint",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Spectral_K_2021",{["itemid"]=7800226793,["itemname"]="Spectral",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Spectrum",{["itemid"]=198441038,["itemname"]="Spectrum",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Spider",{["itemid"]=473571549,["itemname"]="Spider",["itemtype"]="Knife",["offset"]={["X"]=0,["Y"]=0,["Z"]=0.55},["rarity"]="Godly"}},
    {"Knife","Spider_K_2023",{["itemid"]=15091399982,["itemname"]="Spider",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Splash",{["itemid"]=235371439,["itemname"]="Splash",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Splatter",{["itemid"]=16964346058,["itemname"]="Splatter",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Spring_K_2024",{["itemid"]=16959775902,["itemname"]="Spring",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Squire",{["itemid"]=315501560,["itemname"]="Squire",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Stainless",{["itemid"]=235366771,["itemname"]="Stainless",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Stalker",{["itemid"]=198439107,["itemname"]="Stalker",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Starfish_K_2024",{["itemid"]=18322176343,["itemname"]="Starfish",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Starry_K_2021",{["itemid"]=8304757707,["itemname"]="Starry",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Starry_K_2026",{["itemid"]=130537925107449,["itemname"]="Starry",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Stars_K_2023",{["itemid"]=15635559978,["itemname"]="Stars",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Static",{["itemid"]=365568163,["itemname"]="Static",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Steel_K_2023",{["itemid"]=15091405483,["itemname"]="Steel",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","StickersH_K_2025",{["itemid"]=100461386281007,["itemname"]="Stickers",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","StickersT2025",{["itemid"]=115280072896190,["itemname"]="Stickers",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","StickersX25",{["itemid"]=115280072896190,["itemname"]="Stickers",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","StickersX_K_2022",{["itemid"]=11834387858,["itemname"]="Stickers",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","StickersX_K_2025",{["itemid"]=102283625659356,["itemname"]="Stickers",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Stickers_K_2021",{["itemid"]=7800229084,["itemname"]="Stickers",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Stickers_K_2022",{["itemid"]=11254067158,["itemname"]="Stickers",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Stickers_K_2024",{["itemid"]=120248733900674,["itemname"]="Stickers",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Stickers_K_2025",{["itemid"]=98868784444742,["itemname"]="Stickers",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Stickers_X_K_2024",{["itemid"]=83843575465564,["itemname"]="Stickers",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Stockings_K_2020",{["itemid"]=6123335682,["itemname"]="Stockings",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Stockings_K_2022",{["itemid"]=11834392930,["itemname"]="Stockings",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Storm_K_2024",{["itemid"]=97369825731567,["itemname"]="Storm",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Strawberries_K_2026",{["itemid"]=73897192147749,["itemname"]="Strawberries",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Striped_K_2025",{["itemid"]=136747578920542,["itemname"]="Striped",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Sub",{["itemid"]=546159250,["itemname"]="Sub",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Summer_Stickers_K_2023",{["itemid"]=13944129596,["itemname"]="Stickers",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","SunsetKnife",{["itemid"]=103526268515240,["itemname"]="Sunset",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","SunsetKnifeChroma",{["chroma"]=true,["itemid"]=103526268515240,["itemname"]="Sunset",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Survivors_K_2022",{["itemid"]=11254180750,["itemname"]="Makeshift",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Sweater",{["itemid"]=1268704902,["itemname"]="Sweater",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Sweater_K_2018",{["itemid"]=2669640567,["itemname"]="Sweater",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Sweater_K_2025",{["itemid"]=102130993592804,["itemname"]="Sweater",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Sweet",{["itemid"]=126937716954396,["itemname"]="Sweet",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","SweetChroma",{["chroma"]=true,["itemid"]=126937716954396,["itemname"]="Sweet",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Sweet_K_2026",{["itemid"]=113677688954146,["itemname"]="Yummy",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Sweetheart",{["itemid"]=363150761,["itemname"]="Sweetheart",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Swirl_K_2021",{["itemid"]=8304757110,["itemname"]="Swirl",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","SwirlyAxe",{["itemid"]=8304801000,["itemname"]="Swirly Axe",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","SwirlyAxeBlue",{["itemid"]=9552048857,["itemname"]="Blue Swirly",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","SwirlyAxeBronze",{["itemid"]=9552050165,["itemname"]="Bronze Swirly",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","SwirlyAxeGold",{["itemid"]=9552054920,["itemname"]="Gold Swirly",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","SwirlyAxeSilver",{["itemid"]=9552051805,["itemname"]="Silver Swirly",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","SwirlyBlade",{["itemid"]=8304805693,["itemname"]="Swirly Blade",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Synthwave",{["itemid"]=84935740002917,["itemname"]="Synthwave",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Synthwave_Ancient",{["itemid"]=133828016595037,["itemname"]="Synthwave",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","Synthwave_Blue",{["itemid"]=122762984016505,["itemname"]="Blue Synthwave",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Synthwave_Bronze",{["itemid"]=72230744607038,["itemname"]="Bronze Synthwave",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Synthwave_Godly",{["itemid"]=15683175970,["itemname"]="Synthwave",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Synthwave_Gold",{["itemid"]=138834911796124,["itemname"]="Gold Synthwave",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Synthwave_Legendary",{["itemid"]=132040985617451,["itemname"]="Synthwave",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Synthwave_Silver",{["itemid"]=103455022994358,["itemname"]="Silver Synthwave",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","TNL",{["itemid"]=201542790,["itemname"]="TNL",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Tailslide",{["itemid"]=305506822,["itemname"]="Tailslide",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","TheSeer",{["itemid"]=198441783,["itemname"]="Seer",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Tides",{["itemid"]=473569625,["itemname"]="Tides",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","TidesChroma",{["chroma"]=true,["itemid"]=3187394934,["itemname"]="Tides",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Tiger",{["itemid"]=3183606579,["itemname"]="Tiger",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","TimeKnife",{["itemid"]=473575049,["itemname"]="Prince",["itemtype"]="Knife",["rarity"]="Classic"}},
    {"Knife","Tourist_K_2026",{["itemid"]=135606903872678,["itemname"]="Tourist",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","ToxicK",{["itemid"]=2513734535,["itemname"]="Toxic",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Toy_K_2023",{["itemid"]=13944127959,["itemname"]="Toy",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","TravelerAxe",{["itemid"]=15070870271,["itemname"]="Traveler's Axe",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","TravelerAxeBronze",{["itemid"]=15695407020,["itemname"]="Bronze Traveler's",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","TravelerAxeGold",{["itemid"]=15695408631,["itemname"]="Gold Traveler's",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","TravelerAxeRed",{["itemid"]=15695405379,["itemname"]="Red Traveler's",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","TravelerAxeSilver",{["itemid"]=15695407742,["itemname"]="Silver Traveler's",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","Traveler_K_2023",{["itemid"]=15091407901,["itemname"]="Traveler",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Treats_K_2025",{["itemid"]=115298865715727,["itemname"]="Treats",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Tree",{["itemid"]=331745577,["itemname"]="Tree",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Tree2017",{["itemid"]=1268704124,["itemname"]="Tree",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","TreeKnife2023",{["itemid"]=15667157715,["itemname"]="Evergreen",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","TreeKnife2023Chroma",{["chroma"]=true,["itemid"]=15694110573,["itemname"]="Evergreen",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Tree_K_2021",{["itemid"]=8304756423,["itemname"]="Tree",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Tree_K_2022",{["itemid"]=11834400185,["itemname"]="Tree",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Tree_K_2023",{["itemid"]=15635563249,["itemname"]="Tree",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Trees_K_2020",{["itemid"]=6123336879,["itemname"]="Trees",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Tropical_K_2025",{["itemid"]=111291962899457,["itemname"]="Tropical",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Tulip",{["itemid"]=387874661,["itemname"]="Tulip",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Turkey2023",{["itemid"]=15413149176,["itemname"]="Turkey",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Turtle_K_2024",{["itemid"]=18322166908,["itemname"]="Turtle",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Turtles_K_2026",{["itemid"]=77271917200992,["itemname"]="Turtles",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","UFOKnife",{["itemid"]=77607127867154,["itemname"]="Alienbeam",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","UFOKnifeChroma",{["chroma"]=true,["itemid"]=77607127867154,["itemname"]="Alienbeam",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","UFOs_K_2025",{["itemid"]=97641024072972,["itemname"]="UFOs",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Valentine",{["itemid"]=363150149,["itemname"]="Valentine",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Vampire",{["itemid"]=531873248,["itemname"]="Vampire",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","VampireAxe",{["itemid"]=130837676383567,["itemname"]="Vampire's Axe",["itemtype"]="Knife",["rarity"]="Ancient"}},
    {"Knife","VampireAxe_Bronze",{["itemid"]=130837676383567,["itemname"]="Vampire's Axe",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","VampireAxe_Gold",{["itemid"]=130837676383567,["itemname"]="Vampire's Axe",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","VampireAxe_Purple",{["itemid"]=130837676383567,["itemname"]="Vampire's Axe",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","VampireAxe_Silver",{["itemid"]=130837676383567,["itemname"]="Vampire's Axe",["itemtype"]="Knife",["rarity"]="Unique"}},
    {"Knife","VampireK2018",{["itemid"]=2513734708,["itemname"]="Vampire",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Vampire_K_2022",{["itemid"]=11254125546,["itemname"]="Vampire",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","VampiresEdge",{["itemid"]=5873256998,["itemname"]="Vampire's Edge",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Vines_K_2023",{["itemid"]=15091325210,["itemname"]="Vines",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Virtual",{["itemid"]=386276987,["itemname"]="Virtual",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","VoidRbx",{["itemid"]=11548082732,["itemname"]="Void",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Vortex",{["itemid"]=235371508,["itemname"]="Vortex",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Wanwood",{["itemid"]=196751441,["itemname"]="Wanwood",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Watcher_K_2021",{["itemid"]=7800227475,["itemname"]="Watcher",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Waves_K",{["itemid"]=13945892398,["itemname"]="Waves",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Waves_K_2024",{["itemid"]=18322178053,["itemname"]="Waves",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Wavy_K_2024",{["itemid"]=16959755393,["itemname"]="Wavy",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Web",{["itemid"]=315104004,["itemname"]="Web",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","WebbedK",{["itemid"]=4210949599,["itemname"]="Webbed",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Webs",{["itemid"]=1133325465,["itemname"]="Webs",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Whiteout",{["itemid"]=196751515,["itemname"]="Whiteout",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","WintersEdge",{["itemid"]=1268708987,["itemname"]="Winter's Edge",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Witch",{["itemid"]=531873553,["itemname"]="Witch",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","WitchBrew_K_2024",{["itemid"]=108331177567412,["itemname"]="Witch's Brew",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Witch_K_2022",{["itemid"]=11254115609,["itemname"]="Witchbrew",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Witched",{["itemid"]=4210938270,["itemname"]="Witched",["itemtype"]="Knife",["rarity"]="Legendary"}},
    {"Knife","Wolf",{["itemid"]=531873487,["itemname"]="Wolf",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Wood_K_2023",{["itemid"]=15091401811,["itemname"]="Wood",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","WraithKnife",{["itemid"]=107190526940939,["itemname"]="Spirit",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Wraith_K_2022",{["itemid"]=11254118399,["itemname"]="Wraith",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Wrapped",{["itemid"]=331745500,["itemname"]="Wrapped",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Wrapped_K_2018",{["itemid"]=2669640357,["itemname"]="Wrapped",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Wrapped_K_2022",{["itemid"]=11834403282,["itemname"]="Wrapped",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","Wrapped_K_2024",{["itemid"]=72638846676083,["itemname"]="Wrapped",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Wreaths_K_2024",{["itemid"]=78432760615312,["itemname"]="Wreaths",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Xbox",{["itemid"]=439325100,["itemname"]="Xbox",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","XenoKnife",{["itemid"]=100576599313371,["itemname"]="Xenoknife",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Xeno_K_2025",{["itemid"]=80492487454400,["itemname"]="Xeno",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","Xmas",{["itemid"]=473572568,["itemname"]="Xmas",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","XmasStickers_K_2021",{["itemid"]=8304755417,["itemname"]="Stickers",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","YellowSeer",{["itemid"]=3184124768,["itemname"]="Yellow Seer",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","Zombie",{["itemid"]=1133331885,["itemname"]="Zombie",["itemtype"]="Knife",["rarity"]="Common"}},
    {"Knife","ZombieBat",{["itemid"]=11229814357,["itemname"]="Bat",["itemtype"]="Knife",["rarity"]="Godly"}},
    {"Knife","ZombieK2018",{["itemid"]=2513734908,["itemname"]="Zombie",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Zombie_K_2021",{["itemid"]=7800222975,["itemname"]="Zombie",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Zombie_K_2023",{["itemid"]=15091339932,["itemname"]="Zombie",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","ZombifiedK",{["itemid"]=4210928053,["itemname"]="Zombified",["itemtype"]="Knife",["rarity"]="Uncommon"}},
    {"Knife","Zombified_K_2022",{["itemid"]=11254182560,["itemname"]="Zombified",["itemtype"]="Knife",["rarity"]="Rare"}},
    {"Knife","molten",{["itemid"]=11254158802,["itemname"]="TestItem",["itemtype"]="Knife",["rarity"]="Common"}},
}
local sharedScopes={
    {"Gun","Matrixscope",{["itemid"]=117266088063706,["itemname"]="Matrixscope",["itemtype"]="Gun",["rarity"]="Secret"}},
    {"Gun","Voidscope",{["itemid"]=84264267520629,["itemname"]="Voidscope",["itemtype"]="Gun",["rarity"]="Secret"}},
}
local mmv=game.GameId==10413186812 or game.PlaceId==93017634738276
if not mmv then
    for _,row in ipairs(staticMM2) do register(row[1],row[2],row[3]) end
end
for _,row in ipairs(sharedScopes) do
    local entry=register(row[1],row[2],row[3])
    entry.originalModelId=string.format("%.0f",row[3].itemid)
end

local ORIGINAL_SCOPE_HOLD="134818020160275"
local scopeHoldWarnings={}
local nativeScopeHolds={}
local function isScope(entry)
    if not entry or entry.kind~="Gun" then return false end
    local name=compact(entry.id)..compact(entry.name)
    return name:find("gingerscope",1,true)~=nil or name:find("voidscope",1,true)~=nil
        or name:find("matrixscope",1,true)~=nil
end

local function visualRoot(object)
    if object:IsA("BasePart") then return object end
    local handle=object:FindFirstChild("Handle",true)
    if handle and handle:IsA("BasePart") then return handle end
    if object:IsA("Model") and object.PrimaryPart then return object.PrimaryPart end
    return object:FindFirstChildWhichIsA("BasePart",true)
end

local function cloneObject(source)
    local previous=source.Archivable
    pcall(function() source.Archivable=true end)
    local ok,clone=pcall(function() return source:Clone() end)
    pcall(function() source.Archivable=previous end)
    return ok and clone or nil
end

local function assetId(value)
    if type(value)=="number" and value>0 then return string.format("%.0f",math.floor(value)) end
    if type(value)=="string" then
        return value:match("^%s*(%d+)%s*$") or value:match("rbxassetid://(%d+)")
            or value:match("[?&]id=(%d+)")
    end
end

local function originalHold(container)
    if not container then return nil end
    for _,object in ipairs(container:GetDescendants()) do
        if object:IsA("Animation") then
            local name=compact(object.Name)
            if name=="customhold" or name=="scopehold" or name=="gingerscopehold" or name=="hold2" then
                local marked=false
                local ancestor=object
                while ancestor and ancestor~=container do
                    if ancestor:GetAttribute(MARKER) then marked=true; break end
                    ancestor=ancestor.Parent
                end
                local id=not marked and assetId(object.AnimationId)
                if id then return id end
            end
        end
    end
end

local function vector(value,fallback)
    if typeof(value)=="Vector3" then return value end
    if type(value)=="table" then
        local x,y,z=tonumber(value.X or value.x or value[1]),tonumber(value.Y or value.y or value[2]),tonumber(value.Z or value.z or value[3])
        if x and y and z then return Vector3.new(x,y,z) end
    end
    return fallback
end

-- Resolve only a record's explicit original model path, without enumerating
-- the game's assets or adding choices at runtime. Exported paths are arrays so
-- weapon names containing periods remain intact.
local function resolveModel(path)
    if type(path)~="table" then return nil end
    local current=game
    for _,name in ipairs(path) do
        if name~="game" then current=current and current:FindFirstChild(tostring(name)) end
        if not current then return nil end
    end
    return current
end

local function buildTemplate(entry)
    local data=entry.data
    local modelData=type(data.model)=="table" and properties(data.model) or data
    local source=resolveModel(data.sourcepath)
    local loaded={}
    local clone=source and cloneObject(source) or nil
    if not clone then
        local primaryId=assetId(data.modelid) or assetId(data.assetid) or assetId(data.weaponasset)
            or assetId(data.model) or assetId(data.itemid)
        local ids={}
        if primaryId then ids[#ids+1]=primaryId end
        if entry.originalModelId and entry.originalModelId~=primaryId then ids[#ids+1]=entry.originalModelId end
        for _,id in ipairs(ids) do
            local ok,objects=pcall(function() return game:GetObjects("rbxassetid://"..id) end)
            if ok and type(objects)=="table" then
                for _,object in ipairs(objects) do
                    loaded[#loaded+1]=object
                    if not clone and visualRoot(object) then clone=object end
                end
            end
            if clone then break end
        end
    end
    if not clone then
        local meshId=assetId(modelData.meshid or data.meshid or modelData.mesh)
        if meshId then
            local part=Instance.new("Part")
            part.Name="Handle"
            part.Size=vector(modelData.size or data.size,Vector3.new(1,1,1))
            local mesh=Instance.new("SpecialMesh")
            mesh.MeshType=Enum.MeshType.FileMesh
            mesh.MeshId="rbxassetid://"..meshId
            local texture=assetId(modelData.textureid or modelData.texture or data.textureid or data.texture)
            mesh.TextureId=texture and "rbxassetid://"..texture or ""
            mesh.Scale=vector(modelData.meshscale or modelData.scale or data.meshscale,Vector3.new(1,1,1))
            mesh.Offset=vector(modelData.offset,Vector3.new())
            mesh.Parent=part
            if typeof(modelData.color or data.color)=="Color3" then part.Color=modelData.color or data.color end
            clone=part
        end
    end
    for _,object in ipairs(loaded) do if object~=clone then pcall(function() object:Destroy() end) end end
    if not clone then return nil,"The game did not expose a loadable model for "..entry.name end
    local root=visualRoot(clone)
    if not root then clone:Destroy(); return nil,"No weapon mesh was found for "..entry.name end
    local texture=assetId(modelData.textureid or modelData.texture or data.textureid or data.texture)
    if texture then
        local mesh=root:FindFirstChildWhichIsA("SpecialMesh")
        if mesh then mesh.TextureId="rbxassetid://"..texture end
        if root:IsA("MeshPart") then root.TextureID="rbxassetid://"..texture end
    end
    local grip=typeof(data.grip)=="CFrame" and data.grip or nil
    local scopeHold=isScope(entry) and originalHold(clone) or nil
    if clone:IsA("Tool") then grip=clone.Grip end
    local ancestor=root.Parent
    while ancestor and ancestor~=clone do
        if ancestor:IsA("Tool") then grip=ancestor.Grip; break end
        ancestor=ancestor.Parent
    end
    -- Keep visual assets and their attachments/PBR/bones. Never run an asset's
    -- scripts, remotes, physical joints, sounds or interaction objects.
    local allowed={Model=true,Folder=true,Attachment=true,Bone=true,SurfaceAppearance=true,
        Tool=true,WrapLayer=true,WrapTarget=true,ParticleEmitter=true,Trail=true,Beam=true,Fire=true,
        Smoke=true,Sparkles=true,PointLight=true,SpotLight=true,SurfaceLight=true}
    for _,object in ipairs(clone:GetDescendants()) do
        if not object:IsA("BasePart") and not object:IsA("DataModelMesh")
            and not object:IsA("Decal") and not allowed[object.ClassName] then object:Destroy() end
    end
    for _,object in ipairs(clone:GetDescendants()) do
        if object:IsA("Tool") then
            local parent=object.Parent
            for _,child in ipairs(object:GetChildren()) do child.Parent=parent end
            object:Destroy()
        end
    end
    local model=Instance.new("Model")
    model.Name="VisualsV2_ClientWeaponTemplate"
    model:SetAttribute(MARKER,true)
    if clone:IsA("BasePart") then clone.Parent=model
    else
        for _,object in ipairs(clone:GetChildren()) do object.Parent=model end
        clone:Destroy()
    end
    if not root:IsDescendantOf(model) then model:Destroy(); return nil,"The weapon Handle is unavailable" end
    model.PrimaryPart=root
    return {model=model,root=root,grip=grip,scopeHold=scopeHold,chroma=data.chroma==true,
        revision=entry.revision,lastUsed=os.clock()}
end

local cache={}
local loading={}
local failed={}
local warned={}
local function cacheKey(entry) return entry.kind..":"..entry.id end

local function templateFor(entry)
    local key=cacheKey(entry)
    local cached=cache[key]
    if cached and cached.revision==entry.revision then cached.lastUsed=os.clock(); return cached end
    if cached then cached.model:Destroy(); cache[key]=nil end
    local failure=failed[key]
    if loading[key] or (failure and failure.revision==entry.revision and failure.untilTime>os.clock()) then return nil end
    if failure and failure.revision~=entry.revision then warned[key]=nil end
    loading[key]=true
    local startedRevision=entry.revision
    task.spawn(function()
        local ok,result,reason=pcall(buildTemplate,entry)
        loading[key]=nil
        if not alive or not runtimeAlive then
            if ok and result then result.model:Destroy() end
            return
        end
        if entry.revision~=startedRevision then
            if ok and result then result.model:Destroy() end
            task.defer(refreshTools)
            return
        end
        if ok and result then
            failed[key]=nil
            warned[key]=nil
            cache[key]=result
            local count=0
            for _ in pairs(cache) do count=count+1 end
            if count>6 then
                local oldestKey,oldestTime=nil,math.huge
                for candidate,value in pairs(cache) do
                    local selected=false
                    for _,state in pairs(kinds) do
                        if candidate==state.key:gsub("^client","")..":"..state.selected then selected=true end
                    end
                    if not selected and value.lastUsed<oldestTime then oldestKey,oldestTime=candidate,value.lastUsed end
                end
                if oldestKey then cache[oldestKey].model:Destroy(); cache[oldestKey]=nil end
            end
            refreshTools()
        else
            failed[key]={untilTime=os.clock()+15,revision=entry.revision}
            local state=kinds[entry.kind]
            if state.enabled and state.selected==entry.id and not warned[key] then
                warned[key]=true
                notify(reason or "Could not load "..entry.name.."; your original weapon is still available")
            end
        end
    end)
    return cache[key]
end

local function owned(object,tool)
    while object and object~=tool do
        if object:GetAttribute(MARKER) then return true end
        object=object.Parent
    end
    return false
end

local function stopScopeHold(state)
    state.holdGeneration=(state.holdGeneration or 0)+1
    state.holdPending=nil
    local hold=state.hold
    state.hold=nil
    if not hold then return end
    if hold.died then hold.died:Disconnect() end
    for track,weight in pairs(hold.suppressed) do
        pcall(function() if track.IsPlaying then track:AdjustWeight(weight,0.12) end end)
    end
    if hold.owned then
        pcall(function() hold.track:Stop(0.12) end)
        pcall(function() hold.track:Destroy() end)
    end
    if hold.animation then hold.animation:Destroy() end
end

local function playingTracks(animator)
    local ok,tracks=pcall(function() return animator:GetPlayingAnimationTracks() end)
    return ok and tracks or {}
end

local function suppressToolHold(tool,hold)
    local ids={}
    local nativeId=originalHold(tool)
    if nativeId then ids[nativeId]=true end
    local animate=player.Character and player.Character:FindFirstChild("Animate")
    local toolNone=animate and animate:FindFirstChild("toolnone")
    if toolNone then
        for _,animation in ipairs(toolNone:GetDescendants()) do
            if animation:IsA("Animation") then
                local id=assetId(animation.AnimationId)
                if id then ids[id]=true end
            end
        end
    end
    for _,track in ipairs(playingTracks(hold.animator)) do
        local animation=track.Animation
        if track~=hold.track and animation and ids[assetId(animation.AnimationId)] then
            -- Affect only the competing tool-hold clips, preserving movement,
            -- emotes, the gun's firing/reloading and all unrelated animations.
            if hold.suppressed[track]==nil then
                hold.suppressed[track]=tonumber(track.WeightTarget) or tonumber(track.WeightCurrent) or 1
            end
            pcall(function() track:AdjustWeight(0,0.08) end)
        end
    end
end

local function updateScopeHold(tool,state,entry)
    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local animator=humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not isScope(entry) or tool.Parent~=character or not state.model or not animator
        or humanoid.Health<=0 then
        if state.hold or state.holdPending then stopScopeHold(state) end
        return
    end
    local rig=tostring(humanoid.RigType)
    local mmv=game.GameId==10413186812 or game.PlaceId==93017634738276
    local nativeId=originalHold(tool) or (not nativeScopeHolds[rig] and state.scopeTemplateHold)
    if nativeId and not mmv then nativeScopeHolds[rig]=nativeId end
    -- MMV uses the confirmed shared Hold2 clip for every scope variant.
    -- MM2 can supply its own authorized original CustomHold; share that clip
    -- across the other colours/trophies instead of changing it per model.
    local id=not mmv and nativeScopeHolds[rig] or ORIGINAL_SCOPE_HOLD
    id=id or ORIGINAL_SCOPE_HOLD
    local signature=state.applied..":"..id
    local hold=state.hold
    if hold and hold.animator==animator and hold.signature==signature and hold.track.IsPlaying then
        suppressToolHold(tool,hold)
        return
    end
    local pending=state.holdPending
    if pending and pending.animator==animator and pending.signature==signature then return end
    if state.holdRetry and state.holdRetry.signature==signature and state.holdRetry.untilTime>os.clock() then return end
    stopScopeHold(state)
    local generation=state.holdGeneration
    local model=state.model
    pending={animator=animator,signature=signature}
    state.holdPending=pending
    local function current()
        return alive and runtimeAlive and toolStates[tool]==state and state.holdGeneration==generation
            and state.holdPending==pending and state.model==model and tool.Parent==character
            and player.Character==character and humanoid.Health>0
            and humanoid:FindFirstChildOfClass("Animator")==animator
    end
    task.spawn(function()
        local track=nil
        local animation=nil
        local ownsTrack=false
        -- Reuse the game's original hold if it is already playing. Disabling
        -- the cosmetic must never stop a track owned by the gun's own scripts.
        for _,candidate in ipairs(playingTracks(animator)) do
            if candidate.IsPlaying and candidate.Animation and assetId(candidate.Animation.AnimationId)==id then
                track=candidate; break
            end
        end
        if not track then
            ownsTrack=true
            animation=Instance.new("Animation")
            animation.Name="VisualsV2ScopeHold"
            animation:SetAttribute(MARKER,true)
            animation.AnimationId="rbxassetid://"..id
            animation.Parent=model
            local ok,result=pcall(function() return animator:LoadAnimation(animation) end)
            if ok then track=result end
            local deadline=os.clock()+6
            while track and current() and track.Length<=0 and os.clock()<deadline do task.wait(0.1) end
        end
        local function discard()
            if ownsTrack and track then
                pcall(function() track:Stop(0) end)
                pcall(function() track:Destroy() end)
            end
            if animation then animation:Destroy() end
        end
        if not current() then discard(); return end
        local ok=track and (not ownsTrack or track.Length>0)
        if ok and ownsTrack then
            ok=pcall(function()
                track.Priority=Enum.AnimationPriority.Action
                track.Looped=true
                track:Play(0.12,1,1)
            end)
        end
        if not ok then
            discard()
            state.holdPending=nil
            state.holdRetry={signature=signature,untilTime=os.clock()+30}
            local warning=rig..":"..id
            if not scopeHoldWarnings[warning] then
                scopeHoldWarnings[warning]=true
                notify("The original scope hold could not load in this game ("..id.."); the scope skin is still enabled.")
            end
            return
        end
        state.holdPending=nil
        state.holdRetry=nil
        hold={track=track,animation=animation,animator=animator,signature=signature,
            owned=ownsTrack,suppressed={}}
        state.hold=hold
        model:SetAttribute("ScopeHoldAnimationID",id)
        hold.died=humanoid.Died:Connect(function()
            if state.hold==hold then stopScopeHold(state) end
        end)
        suppressToolHold(tool,hold)
    end)
end

local function restoreVisuals(state)
    stopScopeHold(state)
    state.holdRetry=nil
    state.scopeTemplateHold=nil
    if state.model then state.model:Destroy(); state.model=nil end
    for object,record in pairs(state.originals) do
        pcall(function() object[record.property]=record.value end)
    end
    table.clear(state.originals)
    state.applied=nil
    state.handle=nil
    state.appliedGrip=nil
    state.chromaTargets=nil
end

local function chromaTargets(model,root)
    local targets={}
    for _,part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local marked=part:GetAttribute("Chroma")==true or compact(part.Name):find("chroma",1,true)~=nil
            for _,child in ipairs(part:GetChildren()) do
                if child:IsA("DataModelMesh") and compact(child.Name):find("chroma",1,true) then marked=true end
            end
            if marked then targets[#targets+1]=part end
        end
    end
    if #targets==0 then targets[1]=root end
    return targets
end

local function updateChroma(state)
    if not state.chromaTargets then return end
    local color=Color3.fromHSV((os.clock()*0.15)%1,1,1)
    for _,part in ipairs(state.chromaTargets) do
        local mesh=part:FindFirstChildWhichIsA("SpecialMesh")
        if mesh then
            part.Color=Color3.new(1,1,1)
            mesh.VertexColor=Vector3.new(color.R,color.G,color.B)
        else part.Color=color end
    end
end

local function hideOriginals(tool,state)
    for _,object in ipairs(tool:GetDescendants()) do
        if not owned(object,tool) then
            local property,value=nil,nil
            if object:IsA("BasePart") then property,value="LocalTransparencyModifier",1
            elseif object:IsA("Decal") then property,value="Transparency",1
            elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
                or object:IsA("Fire") or object:IsA("Smoke") or object:IsA("Sparkles")
                or object:IsA("Light") then property,value="Enabled",false end
            if property then
                if not state.originals[object] then state.originals[object]={property=property,value=object[property]} end
                pcall(function() object[property]=value end)
            end
        end
    end
end

local function localTool(tool)
    return tool.Parent==player.Character or tool.Parent==player:FindFirstChildOfClass("Backpack")
end

local function actualKind(tool)
    return weaponKind(tool.Name) or weaponKind(tool:GetAttribute("WeaponType") or tool:GetAttribute("ItemType"))
end

local function apply(tool,state)
    local kind=actualKind(tool)
    local settings=kind and kinds[kind]
    local entry=settings and catalog[kind][settings.selected]
    if not settings or not settings.enabled or not entry or not localTool(tool) then
        if state.model or state.hold or state.holdPending then restoreVisuals(state) end
        return
    end
    local handle=tool:FindFirstChild("Handle") or visualRoot(tool)
    if not handle or not handle:IsA("BasePart") then restoreVisuals(state); return end
    local signature=cacheKey(entry)..":"..entry.revision
    if state.applied==signature and state.handle==handle and state.appliedGrip==tool.Grip
        and state.model and state.model.Parent==tool then
        updateScopeHold(tool,state,entry)
        return
    end
    local template=templateFor(entry)
    if not template then
        -- Never leave the previous selection or an invisible Handle behind.
        if state.model then restoreVisuals(state) end
        return
    end
    local model=cloneObject(template.model)
    if not model then return end
    local root=model.PrimaryPart or visualRoot(model)
    if not root then model:Destroy(); return end
    local origin=root.CFrame
    local offset=template.grip and tool.Grip*template.grip:Inverse() or CFrame.new()
    local partCount=0
    for _,part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local relative=offset*origin:ToObjectSpace(part.CFrame)
            part.Anchored=false; part.CanCollide=false; part.CanTouch=false; part.CanQuery=false
            part.Massless=true; part.CastShadow=false; part.LocalTransparencyModifier=0
            part.CFrame=handle.CFrame*relative
            local weld=Instance.new("Weld")
            weld.Name="VisualsV2_ClientSkinWeld"
            weld.Part0=handle; weld.Part1=part; weld.C0=relative; weld.C1=CFrame.new()
            weld.Parent=part
            partCount=partCount+1
        end
    end
    if partCount==0 then model:Destroy(); return end
    restoreVisuals(state)
    model.Name="VisualsV2_Client"..kind.."Skin"
    model:SetAttribute("WeaponID",entry.id)
    state.model=model; state.handle=handle; state.applied=signature
    state.appliedGrip=tool.Grip
    state.scopeTemplateHold=template.scopeHold
    state.chromaTargets=template.chroma and chromaTargets(model,root) or nil
    model.Parent=tool
    updateChroma(state)
    hideOriginals(tool,state)
    updateScopeHold(tool,state,entry)
end

local function forgetTool(tool)
    local state=toolStates[tool]
    if not state then return end
    toolStates[tool]=nil
    for _,connection in ipairs(state.connections) do connection:Disconnect() end
    restoreVisuals(state)
end

local function trackTool(tool)
    if not tool:IsA("Tool") or not actualKind(tool) then return end
    local state=toolStates[tool]
    if not state then
        state={originals={},connections={},queued=false}
        toolStates[tool]=state
        local function changed(object)
            if object and owned(object,tool) then return end
            if state.queued then return end
            state.queued=true
            task.defer(function()
                state.queued=false
                if alive and runtimeAlive and toolStates[tool]==state then
                    if localTool(tool) then
                        if state.model then hideOriginals(tool,state) end
                        apply(tool,state)
                    else forgetTool(tool) end
                end
            end)
        end
        state.connections[1]=tool.DescendantAdded:Connect(changed)
        state.connections[2]=tool.DescendantRemoving:Connect(changed)
        state.connections[3]=tool.AncestryChanged:Connect(function() changed() end)
    end
    apply(tool,state)
end

refreshTools=function()
    if not alive or not runtimeAlive then return end
    for tool,state in pairs(toolStates) do
        if localTool(tool) then apply(tool,state) else forgetTool(tool) end
    end
    if not kinds.Gun.enabled and not kinds.Knife.enabled then return end
    local function scan(container)
        if container then for _,tool in ipairs(container:GetChildren()) do trackTool(tool) end end
    end
    scan(player.Character)
    scan(player:FindFirstChildOfClass("Backpack"))
end

updateWatching=function()
    if heartbeat then heartbeat:Disconnect(); heartbeat=nil end
    if hideFrame then hideFrame:Disconnect(); hideFrame=nil end
    refreshTools()
    if not alive or not runtimeAlive or (not kinds.Gun.enabled and not kinds.Knife.enabled) then
        for tool in pairs(toolStates) do forgetTool(tool) end
        return
    end
    local elapsed=0
    heartbeat=RunService.Heartbeat:Connect(function(dt)
        elapsed=elapsed+math.max(tonumber(dt) or 0,0)
        if elapsed>=0.25 then elapsed=0; refreshTools() end
    end)
    hideFrame=RunService.RenderStepped:Connect(function()
        -- Roblox's first-person transparency controller can change the original
        -- Handle every frame. Enforce only the saved originals, never the skin.
        for tool,state in pairs(toolStates) do
            if state.model then updateChroma(state) end
            if state.model and tool.Parent==player.Character then
                for object,record in pairs(state.originals) do
                    pcall(function()
                        if record.property=="Enabled" then object.Enabled=false else object[record.property]=1 end
                    end)
                end
            end
        end
    end)
end

local function setDropdown(controller,method,value)
    if type(controller)~="table" or type(controller[method])~="function" then return end
    local ok=pcall(controller[method],value)
    if not ok then pcall(controller[method],controller,value) end
end

for _,kind in ipairs({"Gun","Knife"}) do
    local state=kinds[kind]
    local entries={}
    for _,entry in pairs(catalog[kind]) do entries[#entries+1]=entry end
    table.sort(entries,function(a,b)
        if a.name:lower()==b.name:lower() then return a.id<b.id end
        return a.name:lower()<b.name:lower()
    end)
    local options={NONE}
    state.labels={}
    local names={}
    for _,entry in ipairs(entries) do names[entry.name:lower()]=(names[entry.name:lower()] or 0)+1 end
    for _,entry in ipairs(entries) do
        entry.label=names[entry.name:lower()]>1 and entry.name.." ["..entry.id.."]" or entry.name
        options[#options+1]=entry.label
        state.labels[entry.label]=entry.id
    end
    local selected=catalog[kind][state.selected]
    state.dropdown=addDropdown(section,kind.." Skin",options,selected and selected.label or nil,function(value)
        if refreshing then return end
        if type(value)=="table" then value=value[1] or value.Value or value.value end
        local id=value==NONE and NONE or state.labels[value]
        if not id and type(value)=="string" and catalog[kind][value] then id=value end
        if not id then return end
        state.selected=id
        SetCfg(state.key.."Skin",id)
        refreshTools()
    end)
    state.toggle=addToggle(section,"Enable Custom Client "..kind,state.enabled,function(value)
        state.enabled=value
        SetCfg(state.key.."Enabled",value)
        updateWatching()
    end)
end

connections[#connections+1]=player.CharacterAdded:Connect(function()
    task.defer(function() if alive and runtimeAlive then refreshTools() end end)
end)
connections[#connections+1]=player.ChildAdded:Connect(function(child)
    if child:IsA("Backpack") then task.defer(function() if alive and runtimeAlive then refreshTools() end end) end
end)
env.VisualsV2Runtime.ClientWeaponSkins={
    Catalog=catalog,
    GetCounts=function()
        local counts={Gun=0,Knife=0}
        for kind,entries in pairs(catalog) do for _ in pairs(entries) do counts[kind]=counts[kind]+1 end end
        return counts
    end,
}
env.VisualsV2Runtime.RegisterReset(function()
    for _,state in pairs(kinds) do
        state.enabled=false; state.selected=NONE
        state.toggle:Set(false)
    end
    updateWatching()
    refreshing=true
    for _,state in pairs(kinds) do setDropdown(state.dropdown,"Select",NONE) end
    refreshing=false
    if not runtimeAlive then
        alive=false
        for _,connection in ipairs(connections) do connection:Disconnect() end
        for _,template in pairs(cache) do template.model:Destroy() end
        table.clear(cache)
        table.clear(nativeScopeHolds)
    end
end)
updateWatching()
end)()

-- =========================================================
-- UTILITIES: NATIVE SHIFT LOCK AIM FOR THROWABLES (MM2 / MMV)
-- Reads the game's lock state. Never changes the camera, cursor, character
-- rotation, input bindings or lock UI. Native tools still perform the throw.
-- =========================================================
;(function()
local section=mainTab:AddSection("Shift Lock & Throwables","Utilities")
local GuiService=game:GetService("GuiService")
local mouse=player:GetMouse()
local alive=true
local aimEnabled=C("vv2ThrowableCentreAim",false)
local frameBound=false
local activeAim=nil
local nativeCameras=nil
local aimToggle
local FRAME="VisualsV2_ShiftLockFrame"
local castParams=RaycastParams.new()
castParams.FilterType=Enum.RaycastFilterType.Exclude
castParams.IgnoreWater=true
local checkCaller=checkcaller or env.checkcaller
local callingScript=getcallingscript or env.getcallingscript
local namecallMethod=getnamecallmethod or env.getnamecallmethod
local restoreNamecallMethod=setnamecallmethod or env.setnamecallmethod
local hookMeta=hookmetamethod or env.hookmetamethod
local hookFunction=hookfunction or env.hookfunction
local makeClosure=newcclosure or env.newcclosure
local callbackValue=getcallbackvalue or env.getcallbackvalue
local callbackRecords={}
local hookReady=false
local refresh

-- Cache native method functions before attaching the hook. Calling these with
-- dot syntax avoids nested __namecall dispatch replacing FireServer/InvokeServer
-- in the original calling thread. Aim is sampled separately at render time.
local instanceIsA=game.IsA
local instanceDescendant=game.IsDescendantOf
local instanceFindChild=game.FindFirstChild
local instanceFindClass=game.FindFirstChildOfClass
local nativeFocusedTextBox=UserInputService.GetFocusedTextBox

local function notify(message)
    if alive and runtimeAlive then pcall(function() shared.Notify(message,4) end) end
end
local function compact(value) return type(value)=="string" and value:lower():gsub("[^%w]","") or "" end
local function throwable(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local name=compact(tool.Name)
    if name=="knife" or name=="gun" then return false end
    return tool:GetAttribute("Throwable")==true or tool:GetAttribute("IsThrowable")==true
        or name:find("bomb",1,true)~=nil or name:find("grenade",1,true)~=nil
        or name:find("snowball",1,true)~=nil or name:find("dynamite",1,true)~=nil
        or name:find("throwable",1,true)~=nil or name=="fakec4" or name=="c4"
end

local function equippedThrowable(character)
    if character then
        for _,tool in ipairs(character:GetChildren()) do if throwable(tool) then return tool end end
    end
end

local function nativeCrosshair()
    local gui=instanceFindClass(player,"PlayerGui")
    local topbar=gui and instanceFindChild(gui,"GameTopbar")
    local crosshair=topbar and instanceFindChild(topbar,"Crosshair")
    if not crosshair or not instanceIsA(crosshair,"GuiObject") then return nil,false end
    local current=crosshair
    while current and current~=gui do
        if instanceIsA(current,"GuiObject") and not current.Visible then return crosshair,false end
        if instanceIsA(current,"ScreenGui") and not current.Enabled then return crosshair,false end
        current=current.Parent
    end
    return crosshair,true
end

local function nativeLocked()
    -- MMV's original crosshair distinguishes shift lock from camera dragging
    -- and first-person cursor locking. Respect its visible state when present.
    local crosshair,visible=nativeCrosshair()
    if crosshair then return visible end
    if nativeCameras then
        for _,key in ipairs({"activeMouseLockController","activeCameraController"}) do
            local controller=nativeCameras[key]
            if type(controller)=="table" and type(controller.GetIsMouseLocked)=="function" then
                local ok,value=pcall(controller.GetIsMouseLocked,controller)
                if ok and value==true then return true end
            end
        end
    end
    for _,object in pairs({player,player.Character,player:FindFirstChildOfClass("PlayerGui")}) do
        for _,key in ipairs({"ShiftLocked","ShiftLock","IsShiftLocked","MouseLocked"}) do
            if object:GetAttribute(key)==true then return true end
            local flag=object:FindFirstChild(key,true)
            if flag and flag:IsA("BoolValue") and flag.Value then return true end
        end
    end
    return UserInputService.MouseBehavior==Enum.MouseBehavior.LockCenter
end

local function allowedCamera(character,humanoid,cam)
    if not character or not humanoid or humanoid.Health<=0 or not cam
        or cam.CameraType==Enum.CameraType.Scriptable or UserInputService:GetFocusedTextBox()
        or GuiService.MenuIsOpen then return false end
    local subject=cam.CameraSubject
    return subject==humanoid or (subject and subject:IsDescendantOf(character)) or false
end

local function centreAim(cam,character,tool)
    local size=cam.ViewportSize
    if size.X<=0 or size.Y<=0 then return nil end
    local ok,inset=pcall(function() return GuiService:GetGuiInset() end)
    if not ok or typeof(inset)~="Vector2" then inset=Vector2.new(0,0) end
    local x,y=size.X/2,size.Y/2
    local guiX,guiY=x-inset.X,y-inset.Y
    local crosshair,visible=nativeCrosshair()
    if visible then
        local position,extent=crosshair.AbsolutePosition,crosshair.AbsoluteSize
        if typeof(position)=="Vector2" and typeof(extent)=="Vector2" and extent.X>0 and extent.Y>0 then
            local candidateX,candidateY=position.X+extent.X/2,position.Y+extent.Y/2
            local viewportX,viewportY=candidateX+inset.X,candidateY+inset.Y
            if viewportX>=0 and viewportX<=size.X and viewportY>=0 and viewportY<=size.Y then
                guiX,guiY=candidateX,candidateY
                x,y=viewportX,viewportY
            end
        end
    end
    -- AbsolutePosition/Mouse.X/Y use inset GUI coordinates. Camera viewport
    -- rays and GetMouseLocation use the corresponding viewport coordinates.
    -- The captured MMV reticle (384,122) plus inset (0,58) targets (384,180).
    local ray=cam:ViewportPointToRay(x,y,0)
    local ignore={character,cam}
    local targetFilter=mouse.TargetFilter
    if targetFilter then ignore[#ignore+1]=targetFilter end
    castParams.FilterDescendantsInstances=ignore
    local result=workspace:Raycast(ray.Origin,ray.Direction*1000,castParams)
    local position=result and result.Position or ray.Origin+ray.Direction*1000
    local handle=tool:FindFirstChild("Handle")
    local root=character:FindFirstChild("HumanoidRootPart")
    local origin=(handle and handle:IsA("BasePart") and handle.Position) or (root and root.Position) or ray.Origin
    local towards=position-origin
    return {tool=tool,camera=cam,ray=ray,position=position,
        hit=CFrame.new(position)*cam.CFrame.Rotation,target=result and result.Instance or nil,
        origin=origin,direction=towards.Magnitude>0.001 and towards.Unit or ray.Direction,
        x=x,y=y,mouseX=guiX,mouseY=guiY,screenX=x,screenY=y}
end

local function sampleAim()
    if not alive or not runtimeAlive or not aimEnabled or not nativeLocked() then return nil end
    local character=player.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local cam=workspace.CurrentCamera
    if not allowedCamera(character,humanoid,cam) then return nil end
    local tool=equippedThrowable(character)
    if not tool then return nil end
    return centreAim(cam,character,tool)
end

local function currentAim()
    local aim=activeAim
    if not alive or not runtimeAlive or not aimEnabled or not aim
        or aim.tool.Parent~=player.Character or aim.camera~=workspace.CurrentCamera
        or aim.camera.CameraType==Enum.CameraType.Scriptable or GuiService.MenuIsOpen
        or nativeFocusedTextBox(UserInputService) then return nil end
    local character=player.Character
    local humanoid=character and instanceFindClass(character,"Humanoid")
    if not humanoid or humanoid.Health<=0 then return nil end
    local subject=aim.camera.CameraSubject
    if subject~=humanoid and (not subject or not instanceDescendant(subject,character)) then return nil end
    local crosshair,visible=nativeCrosshair()
    if crosshair and not visible then return nil end
    return aim
end

local function gameCaller(aim,toolRemote)
    if not alive or not runtimeAlive or not aimEnabled or not aim then return false end
    if type(checkCaller)=="function" then
        local ok,result=pcall(checkCaller)
        if not ok or result then return false end
    end
    -- An exact remote inside the currently equipped throwable is enough to
    -- identify its native request, even when a shared module owns the caller.
    if toolRemote then return true end
    if type(callingScript)=="function" then
        local ok,source=pcall(callingScript)
        return ok and typeof(source)=="Instance" and instanceDescendant(source,aim.tool) or false
    end
    return false
end

local function targetValue(value,aim,direction)
    local valueType=typeof(value)
    if valueType=="Vector3" then return direction and aim.direction*value.Magnitude or aim.position end
    if valueType=="CFrame" then return aim.hit end
    if valueType=="Ray" then return Ray.new(value.Origin,aim.direction*value.Direction.Magnitude) end
    return value
end

local function rewritePayload(payload,aim)
    if type(payload)~="table" then return nil end
    local result=nil
    local positions={position=true,targetposition=true,mouseposition=true,mouselocation=true,
        mousehit=true,hit=true,target=true}
    for key,value in pairs(payload) do
        local name=compact(key)
        local valueType=typeof(value)
        if (positions[name] or name=="direction" or name=="throwdirection")
            and (valueType=="Vector3" or valueType=="CFrame" or valueType=="Ray") then
            if not result then result=table.clone(payload) end
            result[key]=targetValue(value,aim,name=="direction" or name=="throwdirection")
        end
    end
    return result
end

local function rewriteArguments(remote,args,aim)
    local toolLocal=instanceDescendant(remote,aim.tool)
    local name=compact(remote.Name)
    local command=type(args[1])=="string" and compact(args[1]) or ""
    local function aimOperation(value)
        return value:find("throw",1,true)~=nil or value:find("toss",1,true)~=nil
            or value:find("launch",1,true)~=nil or value:find("mousepos",1,true)~=nil
            or value:find("mouseloc",1,true)~=nil or value=="aim" or value=="settarget"
            or value=="plantbomb" or value=="leftdown" or value=="leftclick"
            or value=="button1down" or value=="mouseclick" or value=="click"
            or value=="activated" or value=="activate"
    end
    local operation=aimOperation(name) or aimOperation(command)
    -- The MMV export exposes FakeBomb.Remote inside the equipped tool. Do not
    -- infer another remote's protocol from a generic "Throw" command alone.
    if not toolLocal then return nil end
    -- Generic gear remotes must carry a throw/aim command or an unambiguous
    -- target payload. Explode, equip, purchase and cooldown messages pass through.
    if not operation and command~="" then return nil end
    if not operation and name~="remoteevent" and name~="remotefunction"
        and name~="remote" and name~="clientcontrol" and name~="servercontrol" then return nil end
    local output=nil
    local candidates={}
    for index=1,args.n do
        local value=args[index]
        local valueType=typeof(value)
        if valueType=="table" then
            local payload=rewritePayload(value,aim)
            if payload then
                output=output or table.clone(args)
                output[index]=payload
            end
        elseif valueType=="Vector3" or valueType=="CFrame" or valueType=="Ray" then
            candidates[#candidates+1]=index
        end
    end
    if #candidates==1 then
        local index=candidates[1]
        output=output or table.clone(args)
        local value=args[index]
        local direction=name:find("direction",1,true)~=nil or command:find("direction",1,true)~=nil
            or (operation and typeof(value)=="Vector3" and math.abs(value.Magnitude-1)<=0.001)
        output[index]=targetValue(value,aim,direction)
    elseif #candidates==2 and operation then
        -- Known origin + target/direction layouts: preserve the launch origin.
        -- Ambiguous multi-vector layouts are left to the Mouse/ray input path.
        local first,second=args[candidates[1]],args[candidates[2]]
        local origin=typeof(first)=="Vector3" and first or (typeof(first)=="CFrame" and first.Position)
        if origin and (origin-aim.origin).Magnitude<=8 then
            output=output or table.clone(args)
            local isDirection=typeof(second)=="Vector3" and second.Magnitude<=1.01
            output[candidates[2]]=targetValue(second,aim,isDirection)
        end
    end
    return output
end

-- One persistent bridge is reused across add-on executions. Wrappers are
-- installed once and become pass-through when their current owner is reset.
-- This preserves other add-ons' hooks and avoids an ever-growing hook chain.
local bridge=env.VisualsV2ThrowableAimBridge
if type(bridge)~="table" or bridge.version~=2 then
    if type(bridge)=="table" then bridge.handler=nil end
    bridge={version=2,dispatchers=setmetatable({}, {__mode="k"})}
    env.VisualsV2ThrowableAimBridge=bridge
end
local handler={}
handler.Enabled=function() return alive and runtimeAlive and aimEnabled end
handler.Remote=function(object,method,args)
    if not handler.Enabled() or typeof(object)~="Instance" then return nil end
    local aim=currentAim()
    if not aim or not instanceDescendant(object,aim.tool) or not gameCaller(aim,true) then return nil end
    if (method=="FireServer" and instanceIsA(object,"RemoteEvent"))
        or (method=="InvokeServer" and instanceIsA(object,"RemoteFunction")) then
        local rewritten=rewriteArguments(object,args,aim)
        if rewritten then return "args",rewritten end
    end
end
handler.Index=function(object,key)
    -- Touch input objects are shared with the camera, movement and menus.
    -- Leave them untouched and redirect the native tool's aim reads instead.
    if not handler.Enabled() or typeof(object)~="Instance" or not instanceIsA(object,"Mouse") then return false end
    local aim=currentAim()
    if not gameCaller(aim) or type(key)~="string" then return false end
    local name=key:lower()
    if name=="hit" then return true,aim.hit end
    if name=="target" then return true,aim.target end
    if name=="unitray" then return true,aim.ray end
    if name=="origin" then return true,CFrame.lookAt(aim.ray.Origin,aim.ray.Origin+aim.ray.Direction) end
    if name=="x" then return true,aim.mouseX end
    if name=="y" then return true,aim.mouseY end
    return false
end
handler.Namecall=function(object,method,args)
    if not handler.Enabled() then return nil end
    local remoteRequest=(method=="FireServer" and instanceIsA(object,"RemoteEvent"))
        or (method=="InvokeServer" and instanceIsA(object,"RemoteFunction"))
    local cameraRequest=method=="ScreenPointToRay" or method=="ViewportPointToRay"
    if not remoteRequest and not cameraRequest and method~="GetMouseLocation" then return nil end
    if type(checkCaller)=="function" then
        local ok,result=pcall(checkCaller)
        if not ok or result then return nil end
    end
    local aim=currentAim()
    if not aim then return nil end
    local toolRemote=remoteRequest and instanceDescendant(object,aim.tool)
    if not gameCaller(aim,toolRemote) then return nil end
    if object==aim.camera and (method=="ScreenPointToRay" or method=="ViewportPointToRay") then
        local depth=tonumber(args[3]) or 0
        return "value",Ray.new(aim.ray.Origin+aim.ray.Direction*depth,aim.ray.Direction)
    end
    if object==UserInputService and method=="GetMouseLocation" then
        return "value",Vector2.new(aim.screenX,aim.screenY)
    end
    if remoteRequest then
        local rewritten=rewriteArguments(object,args,aim)
        if rewritten then return "args",rewritten end
    end
end
-- Inactive handlers are detached, including on first execution. The global
-- wrappers are only installed when aiming is explicitly enabled.
bridge.handler=nil

-- Direct/cached FireServer and InvokeServer calls can bypass __namecall.
-- Hook their native method functions too, without generating any new request.
-- These shared wrappers forward exactly once and are inert with no owner.
bridge.remoteMethods=bridge.remoteMethods or {}
local function installNativeRemoteMethods()
    if type(hookFunction)~="function" then return false end
    for _,spec in ipairs({{"FireServer","RemoteEvent"},{"InvokeServer","RemoteFunction"}}) do
        local method,class=spec[1],spec[2]
        local record=bridge.remoteMethods[method]
        if not record then record={calls=0}; bridge.remoteMethods[method]=record end
        if not record.ready then
            local temporary=Instance.new(class)
            local ok,native=pcall(function() return temporary[method] end)
            temporary:Destroy()
            if ok and type(native)=="function" then
                local previous
                local wrapper=function(object,...)
                    local current=bridge.handler
                    local thread=coroutine.running() or bridge
                    if previous and current and current.Enabled() and not bridge.dispatchers[thread] then
                        record.calls=record.calls+1
                        local savedMethod
                        if type(restoreNamecallMethod)=="function" and type(namecallMethod)=="function" then
                            local success,value=pcall(namecallMethod)
                            if success and type(value)=="string" then savedMethod=value end
                        end
                        bridge.dispatchers[thread]=true
                        local success,action,args=pcall(current.Remote,object,method,table.pack(...))
                        bridge.dispatchers[thread]=nil
                        if savedMethod then pcall(restoreNamecallMethod,savedMethod) end
                        if success and action=="args" then return previous(object,table.unpack(args,1,args.n)) end
                    end
                    return previous(object,...)
                end
                if type(makeClosure)=="function" then wrapper=makeClosure(wrapper) end
                local success,original=pcall(hookFunction,native,wrapper)
                if success and type(original)=="function" then
                    previous=original; record.ready=true; record.error=nil
                else record.error=tostring(original) end
            else record.error=tostring(native) end
        end
    end
    local event=bridge.remoteMethods.FireServer
    return event and event.ready==true or false
end

local function installHooks()
    local nativeReady=installNativeRemoteMethods()
    if bridge.indexReady and bridge.namecallReady then return true end
    if type(namecallMethod)~="function" or (type(checkCaller)~="function" and type(callingScript)~="function") then return nativeReady end
    local hook=hookMeta
    if type(hook)~="function" then
        local rawMeta=getrawmetatable or env.getrawmetatable
        local readOnly=setreadonly or env.setreadonly
        local isReadOnly=isreadonly or env.isreadonly
        if type(rawMeta)~="function" or type(readOnly)~="function" then return nativeReady end
        hook=function(object,key,replacement)
            local mt=rawMeta(object)
            local old=mt[key]
            local previous=true
            if type(isReadOnly)=="function" then previous=isReadOnly(mt) end
            readOnly(mt,false)
            mt[key]=replacement
            readOnly(mt,previous)
            return old
        end
    end
    if not bridge.indexReady then
        local previous
        local wrapper=function(object,key)
            local current=bridge.handler
            local thread=coroutine.running() or bridge
            if current and current.Enabled() and not bridge.dispatchers[thread] then
                local method
                if type(restoreNamecallMethod)=="function" and type(namecallMethod)=="function" then
                    local ok,value=pcall(namecallMethod)
                    if ok and type(value)=="string" then method=value end
                end
                bridge.dispatchers[thread]=true
                local ok,handled,value=pcall(current.Index,object,key)
                bridge.dispatchers[thread]=nil
                if type(restoreNamecallMethod)=="function" and type(method)=="string" then
                    pcall(restoreNamecallMethod,method)
                end
                if ok and handled then return value end
            end
            return previous(object,key)
        end
        if type(makeClosure)=="function" then wrapper=makeClosure(wrapper) end
        local ok,original=pcall(hook,game,"__index",wrapper)
        if not ok or type(original)~="function" then return nativeReady end
        previous=original
        bridge.indexReady=true
    end
    if not bridge.namecallReady then
        local previous
        local wrapper=function(object,...)
            local current=bridge.handler
            local thread=coroutine.running() or bridge
            if current and current.Enabled() and not bridge.dispatchers[thread] then
                local method=namecallMethod()
                if method=="FireServer" or method=="InvokeServer" then
                    bridge.namecallRequests=(bridge.namecallRequests or 0)+1
                end
                bridge.dispatchers[thread]=true
                local ok,action,value=pcall(current.Namecall,object,method,table.pack(...))
                bridge.dispatchers[thread]=nil
                if type(restoreNamecallMethod)=="function" and type(method)=="string" then
                    pcall(restoreNamecallMethod,method)
                end
                if ok and action=="value" then return value end
                if ok and action=="args" then return previous(object,table.unpack(value,1,value.n)) end
            end
            return previous(object,...)
        end
        if type(makeClosure)=="function" then wrapper=makeClosure(wrapper) end
        local ok,original=pcall(hook,game,"__namecall",wrapper)
        if not ok or type(original)~="function" then return nativeReady end
        previous=original
        bridge.namecallReady=true
    end
    return true
end

-- Classic Roblox toys ask the client for MousePosition through
-- ClientControl.OnClientInvoke instead of sending a position in FireServer.
-- Preserve that callback's execution and every non-aim return value.
local function readCallback(remote)
    if type(callbackValue)=="function" then
        local ok,value=pcall(callbackValue,remote,"OnClientInvoke")
        if ok and type(value)=="function" then return value end
    end
    local ok,value=pcall(function() return remote.OnClientInvoke end)
    return ok and type(value)=="function" and value or nil
end

local function releaseCallback(remote,record)
    record.active=false
    if readCallback(remote)==record.wrapper then
        pcall(function() remote.OnClientInvoke=record.original end)
    end
    callbackRecords[remote]=nil
end

local function wrapCallback(remote,tool)
    local original=readCallback(remote)
    if not original then return end
    local existing=callbackRecords[remote]
    if existing and original==existing.wrapper then return end
    if existing then releaseCallback(remote,existing) end
    local record={original=original,tool=tool,active=true}
    record.wrapper=function(...)
        local args=table.pack(...)
        local results=table.pack(original(...))
        if not record.active then return table.unpack(results,1,results.n) end
        local mode=args[1]
        if type(mode)=="table" then mode=mode.Mode or mode.mode or mode.Action or mode.action end
        local name=compact(mode)
        local position=name=="mouseposition" or name=="getmouseposition" or name=="targetposition"
        local hit=name=="mousehit" or name=="getmousehit"
        local location=name=="mouselocation" or name=="getmouselocation"
        local ray=name=="unitray" or name=="mouseunitray"
        if position or hit or location or ray then
            local aim=currentAim()
            if aim and aim.tool==tool then
                local kind=typeof(results[1])
                if kind=="Vector2" then
                    results[1]=location and Vector2.new(aim.screenX,aim.screenY)
                        or Vector2.new(aim.mouseX,aim.mouseY)
                elseif kind=="Vector3" or kind=="CFrame" or kind=="Ray" then
                    results[1]=targetValue(results[1],aim,false)
                elseif results[1]==nil then
                    results[1]=hit and aim.hit or (ray and aim.ray)
                        or (location and Vector2.new(aim.screenX,aim.screenY)) or aim.position
                    results.n=math.max(results.n,1)
                end
            end
        end
        return table.unpack(results,1,results.n)
    end
    local ok=pcall(function() remote.OnClientInvoke=record.wrapper end)
    if ok then callbackRecords[remote]=record end
end

local function refreshCallbacks()
    local seen={}
    if aimEnabled and alive and runtimeAlive then
        for _,container in pairs({player.Character,player:FindFirstChildOfClass("Backpack")}) do
            for _,tool in ipairs(container:GetChildren()) do
                if throwable(tool) then
                    for _,remote in ipairs(tool:GetDescendants()) do
                        if remote:IsA("RemoteFunction") then seen[remote]=true; wrapCallback(remote,tool) end
                    end
                end
            end
        end
    end
    for remote,record in pairs(callbackRecords) do
        if not seen[remote] then releaseCallback(remote,record) end
    end
end

local elapsed=0
refresh=function()
    activeAim=nil
    if bridge.handler==handler then bridge.handler=nil end
    refreshCallbacks()
    if not alive or not runtimeAlive or not aimEnabled then
        if frameBound then RunService:UnbindFromRenderStep(FRAME); frameBound=false end
        return
    end
    if hookReady then bridge.handler=handler end
    if not frameBound then
        RunService:BindToRenderStep(FRAME,Enum.RenderPriority.Camera.Value+1,function(dt)
            local ok,aim=pcall(sampleAim)
            activeAim=ok and aim or nil
            elapsed=elapsed+(tonumber(dt) or 0.016)
            if elapsed>=0.25 then elapsed=0; pcall(refreshCallbacks) end
        end)
        frameBound=true
    end
end

aimToggle=addToggle(section,"Centre Aim for Throwables",aimEnabled,function(value)
    if value then hookReady=installHooks() end
    if value and not hookReady and type(callbackValue)~="function" then
        aimEnabled=false
        SetCfg("vv2ThrowableCentreAim",false)
        task.defer(function() if aimToggle then aimToggle:Set(false) end end)
        notify("This executor cannot redirect the native throwable aim.")
    else aimEnabled=value; SetCfg("vv2ThrowableCentreAim",value) end
    refresh()
end)

env.VisualsV2Runtime.ShiftLockThrowables={
    IsLocked=nativeLocked,
    GetAim=currentAim,
    GetTransport=function()
        local event=bridge.remoteMethods.FireServer or {}
        local invoke=bridge.remoteMethods.InvokeServer or {}
        return {namecallReady=bridge.namecallReady==true,indexReady=bridge.indexReady==true,
            nativeFireServerReady=event.ready==true,nativeInvokeServerReady=invoke.ready==true,
            namecallRequests=bridge.namecallRequests or 0,
            nativeFireServerRequests=event.calls or 0,nativeInvokeServerRequests=invoke.calls or 0,
            nativeFireServerError=event.error,nativeInvokeServerError=invoke.error}
    end,
}
env.VisualsV2Runtime.RegisterReset(function()
    aimEnabled=false; activeAim=nil
    aimToggle:Set(false)
    refresh()
    if not runtimeAlive then
        alive=false
        if bridge.handler==handler then bridge.handler=nil end
    end
end)
task.spawn(function()
    local scripts=player:FindFirstChild("PlayerScripts")
    local module=scripts and scripts:FindFirstChild("PlayerModule")
    if module and module:IsA("ModuleScript") then
        local ok,result=pcall(require,module)
        if ok and type(result)=="table" and type(result.GetCameras)=="function" then
            local cameraOk,cameras=pcall(result.GetCameras,result)
            if cameraOk and type(cameras)=="table" and alive and runtimeAlive then nativeCameras=cameras end
        end
    end
end)
if aimEnabled then
    hookReady=installHooks()
    if not hookReady and type(callbackValue)~="function" then
        aimEnabled=false; SetCfg("vv2ThrowableCentreAim",false)
    end
end
refresh()
end)()

;(function()
local section=mainTab:AddSection("Custom Knife/Gun","Visuals")
local legacyEnabled=C("gunsVisualEnabled",false)
local legacyColor=C("gunsTintColor",Color3.fromRGB(38,38,38))
local legacyRainbow=C("gunsRainbow",false)
local legacySpeed=C("gunsRainbowSpeed",3)
local tints={}
local highlighted=setmetatable({}, {__mode="k"})
local watched=setmetatable({}, {__mode="k"})
local watchConnections={}
local rainbowConnection
local HIGHLIGHT_NAME="VisualsV2_GunsKnivesHighlight"

local function allTools()
    local result={}
    local function scan(container)
        if not container then return end
        for _,tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                local name=tool.Name:lower()
                if name=="knife" or name=="gun" then result[#result+1]=tool end
            end
        end
    end
    scan(player.Character)
    scan(player:FindFirstChildOfClass("Backpack"))
    return result
end

local function removeHighlight(tool)
    local highlight=tool and tool:FindFirstChild(HIGHLIGHT_NAME)
    if highlight then highlight:Destroy() end
    highlighted[tool]=nil
end

local function colorNow(tint)
    if tint.rainbow then
        return Color3.fromHSV((os.clock()*(tint.speed*0.1))%1,1,1)
    end
    return tint.color
end

local function applyTool(tool)
    if not tool or not tool:IsA("Tool") then return end
    local tint=tints[tool.Name:lower()]
    if not tint then return end
    if not tint.enabled then removeHighlight(tool); return end
    local highlight=tool:FindFirstChild(HIGHLIGHT_NAME)
    if not highlight then
        highlight=Instance.new("Highlight")
        highlight.Name=HIGHLIGHT_NAME
        highlight.Adornee=tool
        highlight.DepthMode=Enum.HighlightDepthMode.Occluded
        highlight.FillTransparency=0.5
        highlight.OutlineTransparency=1
        highlight.Parent=tool
    end
    highlight.FillColor=colorNow(tint)
    highlighted[tool]=true
end

local function applyAll()
    if not runtimeAlive then return end
    for _,tool in ipairs(allTools()) do applyTool(tool) end
end

local function refresh()
    if rainbowConnection then rainbowConnection:Disconnect(); rainbowConnection=nil end
    if not runtimeAlive then return end
    applyAll()
    for _,tint in pairs(tints) do
        if tint.enabled and tint.rainbow then
            rainbowConnection=RunService.RenderStepped:Connect(applyAll)
            break
        end
    end
end

local function watch(container)
    if not container or watched[container] then return end
    watched[container]=true
    watchConnections[#watchConnections+1]=container.ChildAdded:Connect(function(tool)
        if tool:IsA("Tool") then
            task.defer(function() if runtimeAlive then applyTool(tool) end end)
        end
    end)
end
watch(player.Character)
watch(player:FindFirstChildOfClass("Backpack"))
watchConnections[#watchConnections+1]=player.CharacterAdded:Connect(function(character)
    watch(character)
    task.defer(applyAll)
end)
watchConnections[#watchConnections+1]=player.ChildAdded:Connect(function(child)
    if child:IsA("Backpack") then watch(child); task.defer(applyAll) end
end)
env.VisualsV2Runtime.RefreshGunsKnives=refresh

local function addTint(key,label,name)
    -- Seed each new setting from the former shared controls once. Subsequent
    -- executions use each weapon's own saved settings.
    local tint={
        enabled=C(key.."Enabled",legacyEnabled),
        color=C(key.."Color",legacyColor),
        rainbow=C(key.."Rainbow",legacyRainbow),
        speed=math.clamp(tonumber(C(key.."RainbowSpeed",legacySpeed)) or 3,1,10),
    }
    tints[name]=tint
    section:AddParagraph(label.." Tint","Tint controls affect only your "..name..". Chams have separate colour and rainbow controls.")
    tint.toggle=addToggle(section,"Enable "..label.." Tint",tint.enabled,function(value)
        tint.enabled=value
        SetCfg(key.."Enabled",value)
        refresh()
    end)
    section:AddColorpicker(label.." Tint Color",tint.color,function(color)
        tint.color=color
        SetCfg(key.."Color",color)
        applyAll()
    end)
    tint.rainbowToggle=addToggle(section,"Rainbow "..label.." Tint",tint.rainbow,function(value)
        tint.rainbow=value
        SetCfg(key.."Rainbow",value)
        refresh()
    end)
    section:AddSlider(label.." Tint Rainbow Speed",1,10,tint.speed,function(value)
        tint.speed=math.clamp(tonumber(value) or 3,1,10)
        SetCfg(key.."RainbowSpeed",tint.speed)
        applyAll()
    end)
end

addTint("knifeTint","Knife","knife")
env.VisualsV2Runtime.RegisterChamsFeature(section,"knifeChams","Knife",function(tool) return tool.Name:lower()=="knife" end)
addTint("gunTint","Gun","gun")
env.VisualsV2Runtime.RegisterChamsFeature(section,"gunChams","Gun",function(tool) return tool.Name:lower()=="gun" end)

env.VisualsV2Runtime.RegisterReset(function()
    for _,tint in pairs(tints) do
        tint.enabled=false; tint.rainbow=false
        tint.toggle:Set(false); tint.rainbowToggle:Set(false)
        tint.color=Color3.fromRGB(38,38,38); tint.speed=3
    end
    if rainbowConnection then rainbowConnection:Disconnect(); rainbowConnection=nil end
    for _,tool in ipairs(allTools()) do removeHighlight(tool) end
    for tool in pairs(highlighted) do removeHighlight(tool) end
    if not runtimeAlive then
        for _,connection in ipairs(watchConnections) do connection:Disconnect() end
        table.clear(watchConnections)
        table.clear(watched)
    end
end)
task.defer(refresh)
end)()

-- =========================================================
-- UTILITIES: GUN+
-- Adapted from drowsynicolas/tuffODHaddons; numeric sliders intentionally omitted.
-- =========================================================

;(function()
local section=mainTab:AddSection("Gun+","Utilities")
local blockAnimations=C("gunPlusBlockAnimations",false)
local equipSound=C("gunPlusEquipSound",false)
local dropForceField=C("gunPlusDropForceField",false)
local dropFireColorEnabled=C("gunPlusDropFireColorEnabled",false)
local forceFieldColor=C("gunPlusForceFieldColor",Color3.fromRGB(38,38,38))
local dropFireColor=C("gunPlusDropFireColor",Color3.fromRGB(38,38,38))
local SOUND_ID="rbxassetid://7158356564"
local START_OFFSET=0.3
local BLOCKED={
    ["123606547020560"]=true,["134826825394657"]=true,
    ["124281955370937"]=true,["127786188145385"]=true,
}
local animConn
local seenGuns=setmetatable({}, {__mode="k"})
local sounds=setmetatable({}, {__mode="k"})
local dropWatchConn
local fireOriginals=setmetatable({}, {__mode="k"})
local FORCE_FIELD_NAME="VisualsV2_GunDropForceField"

local function playSound()
    local char=player.Character
    local hrp=char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local old=sounds[char]
    if old then pcall(function() old:Stop(); old:Destroy() end) end
    local sound=Instance.new("Sound")
    sound.SoundId=SOUND_ID; sound.Volume=1; sound.Parent=hrp
    pcall(function() sound.TimePosition=START_OFFSET end)
    sound:Play(); sounds[char]=sound
    sound.Ended:Once(function()
        if sounds[char]==sound then sounds[char]=nil end
        if sound.Parent then sound:Destroy() end
    end)
end
local function hookGun(tool)
    if not tool or not tool:IsA("Tool") or tool.Name~="Gun" or seenGuns[tool] then return end
    seenGuns[tool]=true
    tool.Equipped:Connect(function() if equipSound then playSound() end end)
    tool.Unequipped:Connect(function() if equipSound then playSound() end end)
end
local function scanGuns(container)
    if not container then return end
    for _,obj in ipairs(container:GetChildren()) do if obj:IsA("Tool") then hookGun(obj) end end
end
local backpack=player:FindFirstChildOfClass("Backpack")
if backpack then
    scanGuns(backpack)
    backpack.ChildAdded:Connect(function(obj) if obj:IsA("Tool") then hookGun(obj) end end)
end
local function watchCharacter(char)
    scanGuns(char)
    char.ChildAdded:Connect(function(obj) if obj:IsA("Tool") then hookGun(obj) end end)
end
if player.Character then watchCharacter(player.Character) end
player.CharacterAdded:Connect(watchCharacter)

local function refreshAnimationLoop()
    if animConn then animConn:Disconnect(); animConn=nil end
    if not blockAnimations then return end
    animConn=RunService.RenderStepped:Connect(function()
        local char=player.Character
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        for _,track in ipairs(hum:GetPlayingAnimationTracks()) do
            local anim=track.Animation
            local id=anim and anim.AnimationId and anim.AnimationId:match("%d+")
            if id and BLOCKED[id] then track:Stop(0) end
        end
    end)
end

local function findForceField(drop)
    return drop and drop:FindFirstChild(FORCE_FIELD_NAME)
end
local function applyForceField(drop)
    if not dropForceField or not drop or drop.Name~="GunDrop" or not drop:IsA("BasePart") then return end
    local sphere=findForceField(drop)
    if not sphere then
        sphere=Instance.new("Part")
        sphere.Name=FORCE_FIELD_NAME
        sphere.Shape=Enum.PartType.Ball
        sphere.Size=Vector3.new(3.5,3.5,3.5)
        sphere.Material=Enum.Material.ForceField
        sphere.Transparency=0.3
        sphere.CanCollide=false; sphere.CanTouch=false; sphere.CanQuery=false; sphere.CastShadow=false; sphere.Massless=true
        sphere.CFrame=drop.CFrame
        sphere.Parent=drop
        local weld=Instance.new("WeldConstraint")
        weld.Name="VisualsV2_GunDropForceFieldWeld"
        weld.Part0=drop; weld.Part1=sphere; weld.Parent=sphere
    end
    sphere.Color=forceFieldColor
end
local function removeForceFields()
    for _,obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name=="GunDrop" then
            local sphere=findForceField(obj); if sphere then sphere:Destroy() end
        end
    end
end
local function applyFire(fire)
    if not dropFireColorEnabled or not fire or not fire:IsA("Fire") then return end
    local parent=fire.Parent
    if not parent or parent.Name~="GunDrop" then return end
    if not fireOriginals[fire] then fireOriginals[fire]={Color=fire.Color,SecondaryColor=fire.SecondaryColor} end
    fire.Color=dropFireColor; fire.SecondaryColor=dropFireColor
end
local function applyDrop(drop)
    if not drop or drop.Name~="GunDrop" or not drop:IsA("BasePart") then return end
    applyForceField(drop)
    local fire=drop:FindFirstChildOfClass("Fire"); if fire then applyFire(fire) end
end
local function restoreFireColors()
    for fire,data in pairs(fireOriginals) do
        if fire and fire.Parent then pcall(function() fire.Color=data.Color; fire.SecondaryColor=data.SecondaryColor end) end
    end
    fireOriginals=setmetatable({}, {__mode="k"})
end
local function applyExistingDrops()
    for _,obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name=="GunDrop" then applyDrop(obj)
        elseif obj:IsA("Fire") and obj.Parent and obj.Parent.Name=="GunDrop" then applyFire(obj) end
    end
end
local function refreshDropWatcher()
    if dropWatchConn then dropWatchConn:Disconnect(); dropWatchConn=nil end
    if not dropForceField and not dropFireColorEnabled then return end
    dropWatchConn=workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("BasePart") and obj.Name=="GunDrop" then task.defer(function() applyDrop(obj) end)
        elseif obj:IsA("Fire") and obj.Parent and obj.Parent.Name=="GunDrop" then task.defer(function() applyFire(obj) end) end
    end)
    applyExistingDrops()
end

local blockToggle=addToggle(section,"Disable Gun Animations",blockAnimations,function(v)
    blockAnimations=v; SetCfg("gunPlusBlockAnimations",v); refreshAnimationLoop()
end)
local soundToggle=addToggle(section,"Equip/Unequip Gun Sound",equipSound,function(v)
    equipSound=v; SetCfg("gunPlusEquipSound",v)
    if not v then
        for char,sound in pairs(sounds) do pcall(function() sound:Stop(); sound:Destroy() end); sounds[char]=nil end
    end
end)
local ffToggle=addToggle(section,"Dropped Gun Force Field Color",dropForceField,function(v)
    dropForceField=v; SetCfg("gunPlusDropForceField",v)
    if v then refreshDropWatcher() else removeForceFields(); refreshDropWatcher() end
end)
section:AddColorpicker("Force Field Color",forceFieldColor,function(color)
    forceFieldColor=color; SetCfg("gunPlusForceFieldColor",color)
    for _,obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name=="GunDrop" then local sphere=findForceField(obj); if sphere then sphere.Color=color end end
    end
end)
local fireToggle=addToggle(section,"Dropped Gun Fire Color",dropFireColorEnabled,function(v)
    dropFireColorEnabled=v; SetCfg("gunPlusDropFireColorEnabled",v)
    if v then refreshDropWatcher() else restoreFireColors(); refreshDropWatcher() end
end)
section:AddColorpicker("Dropped Gun Fire Color",dropFireColor,function(color)
    dropFireColor=color; SetCfg("gunPlusDropFireColor",color)
    if dropFireColorEnabled then applyExistingDrops() end
end)

refreshAnimationLoop(); refreshDropWatcher()
env.VisualsV2Runtime.RegisterReset(function()
    blockToggle:Set(false); soundToggle:Set(false); ffToggle:Set(false); fireToggle:Set(false)
    blockAnimations=false; equipSound=false; dropForceField=false; dropFireColorEnabled=false
    if animConn then animConn:Disconnect(); animConn=nil end
    if dropWatchConn then dropWatchConn:Disconnect(); dropWatchConn=nil end
    removeForceFields(); restoreFireColors()
    for char,sound in pairs(sounds) do pcall(function() sound:Stop(); sound:Destroy() end); sounds[char]=nil end
end)
end)()

-- =========================================================
-- VISUALS: ESTIMATED SERVER POSITION
-- =========================================================

;(function()
local section=mainTab:AddSection("Estimated Server Pos","Visuals")
local enabled=C("serverPosEnabled",false)
local markerColor=C("serverPosColor",Color3.fromRGB(38,38,38))
local transparency=math.clamp(tonumber(C("serverPosTransparency",2.5)) or 2.5,1,4)
local marker,root,humanoid,heartbeat,healthConn,charConn
local history={}

local function alpha()
    local v=math.clamp(tonumber(transparency) or 2.5,1,4)
    return 0.1+((v-1)/3)*0.75
end
local function destroyMarker()
    if heartbeat then heartbeat:Disconnect(); heartbeat=nil end
    if healthConn then healthConn:Disconnect(); healthConn=nil end
    if marker then marker:Destroy(); marker=nil end
    table.clear(history)
end
local function ping()
    local ok,value=pcall(function() return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() end)
    return ok and math.clamp(value,10,1000) or 10
end
local function createMarker(char)
    destroyMarker()
    root=char:WaitForChild("HumanoidRootPart")
    humanoid=char:WaitForChild("Humanoid")
    marker=Instance.new("Part")
    marker.Name="VisualsV2_ServerPosition"
    marker.Size=Vector3.new(2,2,1)
    marker.Color=markerColor
    marker.Material=Enum.Material.Plastic
    marker.Transparency=alpha()
    marker.Anchored=true; marker.CanCollide=false; marker.CanTouch=false; marker.CanQuery=false; marker.CastShadow=false
    marker.Parent=workspace
    healthConn=humanoid.HealthChanged:Connect(function(health) if health<=0 then destroyMarker() end end)
    heartbeat=RunService.Heartbeat:Connect(function()
        if not marker or not marker.Parent or not root or not root.Parent then return end
        table.insert(history,{position=root.Position,rotation=root.CFrame-root.Position,time=tick()})
        while #history>120 do table.remove(history,1) end
        local target=tick()-ping()/1000
        local closest=history[1]
        if not closest then return end
        for _,entry in ipairs(history) do if math.abs(entry.time-target)<math.abs(closest.time-target) then closest=entry end end
        marker.CFrame=CFrame.new(closest.position)*closest.rotation
    end)
end
local function enable()
    if not charConn then charConn=player.CharacterAdded:Connect(function(char) task.wait(); if enabled then createMarker(char) end end) end
    if player.Character then createMarker(player.Character) end
end
local function disable()
    if charConn then charConn:Disconnect(); charConn=nil end
    destroyMarker()
end

local enableToggle=addToggle(section,"Show Server Pos",enabled,function(v)
    enabled=v; SetCfg("serverPosEnabled",v); if v then enable() else disable() end
end)
section:AddSlider("Marker Transparency",1,4,transparency,function(v)
    transparency=math.clamp(tonumber(v) or 2.5,1,4); SetCfg("serverPosTransparency",transparency)
    if marker then marker.Transparency=alpha() end
end)
section:AddColorpicker("Marker Color",markerColor,function(color)
    markerColor=color; SetCfg("serverPosColor",color); if marker then marker.Color=color end
end)

env.VisualsV2Runtime.RegisterReset(function()
    enableToggle:Set(false); enabled=false; transparency=2.5; markerColor=Color3.fromRGB(255,255,255); disable()
end)
end)()

-- =========================================================
-- VISUALS: TOOL TINT
-- Highlight-based tint so transparency always has a visible effect.
-- =========================================================

;(function()
local section=mainTab:AddSection("Custom Tool","Visuals")
section:AddParagraph("Tool Tint","Applies a configurable highlight tint to tools other than Gun and Knife.")
local enabled=C("toolTintEnabled",false)
local tintColor=C("toolTintColor",Color3.fromRGB(38,38,38))
local rainbow=C("toolTintRainbow",false)
local rainbowSpeed=C("toolTintRainbowSpeed",3)
local transparency=C("toolTintTransparency",5)
local rainbowConn
local HIGHLIGHT_NAME="VisualsV2_ToolTint"

local function isGunKnife(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local name=tool.Name:lower()
    return name=="gun" or name=="knife"
end

local function allTools()
    local result={}
    local function scan(container)
        if container then
            for _,obj in ipairs(container:GetChildren()) do
                if obj:IsA("Tool") and not isGunKnife(obj) then result[#result+1]=obj end
            end
        end
    end
    scan(player.Character)
    scan(player:FindFirstChildOfClass("Backpack"))
    return result
end
local function colorNow()
    if rainbow then return Color3.fromHSV((os.clock()*((tonumber(rainbowSpeed) or 3)*0.1))%1,1,1) end
    return tintColor
end
local function fillAlpha()
    local v=math.clamp(tonumber(transparency) or 5,1,10)
    return 0.05+((v-1)/9)*0.85
end
local function removeHighlight(tool)
    if not tool then return end
    local h=tool:FindFirstChild(HIGHLIGHT_NAME)
    if h then h:Destroy() end
end

local function apply(tool)
    if not enabled or not tool or not tool:IsA("Tool") then return end
    if isGunKnife(tool) then removeHighlight(tool); return end
    local h=tool:FindFirstChild(HIGHLIGHT_NAME)
    if not h then
        h=Instance.new("Highlight")
        h.Name=HIGHLIGHT_NAME
        h.Adornee=tool
        h.DepthMode=Enum.HighlightDepthMode.Occluded
        h.OutlineTransparency=1
        h.Parent=tool
    end
    h.FillColor=colorNow()
    h.FillTransparency=fillAlpha()
end
local function applyAll() for _,tool in ipairs(allTools()) do apply(tool) end end
local function restoreAll()
    if rainbowConn then rainbowConn:Disconnect(); rainbowConn=nil end
    for _,tool in ipairs(allTools()) do removeHighlight(tool) end
end
local function refreshAll()
    restoreAll()
    if enabled then applyAll() end
    if enabled and rainbow then rainbowConn=RunService.RenderStepped:Connect(applyAll) end
end
local function watch(container)
    if not container then return end
    container.ChildAdded:Connect(function(obj) if obj:IsA("Tool") and enabled then task.defer(function() apply(obj) end) end end)
end
watch(player:FindFirstChildOfClass("Backpack")); watch(player.Character)
player.CharacterAdded:Connect(function(char) watch(char); if enabled then task.defer(applyAll) end end)

env.VisualsV2Runtime.RefreshToolTint=refreshAll

local enabledToggle=addToggle(section,"Enable Tool Tint",enabled,function(v)
    enabled=v
    SetCfg("toolTintEnabled",v)
    if v then refreshAll() else restoreAll() end
end)
section:AddColorpicker("Tool Tint Color",tintColor,function(color)
    tintColor=color; SetCfg("toolTintColor",color); if enabled and not rainbow then applyAll() end
end)
local rainbowToggle=addToggle(section,"Rainbow Tool Tint",rainbow,function(v)
    rainbow=v
    SetCfg("toolTintRainbow",v)
    refreshAll()
end)
section:AddSlider("Rainbow Speed",1,10,rainbowSpeed,function(v)
    rainbowSpeed=math.clamp(tonumber(v) or 3,1,10); SetCfg("toolTintRainbowSpeed",rainbowSpeed)
end)
section:AddSlider("Tint Transparency",1,10,transparency,function(v)
    transparency=math.clamp(tonumber(v) or 5,1,10); SetCfg("toolTintTransparency",transparency); if enabled then applyAll() end
end)

env.VisualsV2Runtime.RegisterChamsFeature(section,"toolChams","Tool",function(tool) return not isGunKnife(tool) end)

env.VisualsV2Runtime.RegisterReset(function()
    enabledToggle:Set(false); rainbowToggle:Set(false)
    enabled=false; rainbow=false; tintColor=Color3.fromRGB(255,255,255); rainbowSpeed=3; transparency=5
    restoreAll()
end)
end)()

-- =========================================================
-- VISUALS: CUSTOM CHAT COLORS
-- VISUALS: CUSTOM CHAT COLORS
-- Sound-related controls intentionally excluded.
-- =========================================================

;(function()
local section=mainTab:AddSection("Custom Chat","Visuals")
local enabled=C("chatColorEnabled",false)
local bubbleColor=C("chatBubbleColor",Color3.fromRGB(0,0,0))
local textColor=C("chatTextColor",Color3.fromRGB(255,255,255))

local originalBubble,originalText
local childConn

local function getConfig()
    return TextChatService:FindFirstChildOfClass("BubbleChatConfiguration") or TextChatService:FindFirstChild("BubbleChatConfiguration")
end
local function apply()
    local config=getConfig(); if not config then return end
    if originalBubble==nil then originalBubble=config.BackgroundColor3; originalText=config.TextColor3 end
    config.BackgroundColor3=bubbleColor; config.TextColor3=textColor
end
local function restore()
    local config=getConfig(); if not config then return end
    if originalBubble~=nil then config.BackgroundColor3=originalBubble end
    if originalText~=nil then config.TextColor3=originalText end
end
local function refreshWatcher()
    if childConn then childConn:Disconnect(); childConn=nil end
    if enabled then
        childConn=TextChatService.ChildAdded:Connect(function(child)
            if child:IsA("BubbleChatConfiguration") or child.Name=="BubbleChatConfiguration" then task.defer(apply) end
        end)
        apply()
    end
end

local enableToggle=addToggle(section,"Custom Chat Colors",enabled,function(v)
    enabled=v; SetCfg("chatColorEnabled",v); if v then refreshWatcher() else if childConn then childConn:Disconnect(); childConn=nil end; restore() end
end)
section:AddColorpicker("Chat Bubble Color",bubbleColor,function(color)
    bubbleColor=color; SetCfg("chatBubbleColor",color); if enabled then apply() end
end)
section:AddColorpicker("Chat Text Color",textColor,function(color)
    textColor=color; SetCfg("chatTextColor",color); if enabled then apply() end
end)

env.VisualsV2Runtime.RegisterReset(function()
    enableToggle:Set(false); enabled=false
    if childConn then childConn:Disconnect(); childConn=nil end
    restore()
end)
end)()

-- =========================================================

-- =========================================================
-- CUSTOMIZATION
-- =========================================================
;(function()
local section=mainTab:AddSection("Customization","Visuals")
local pg=player:WaitForChild("PlayerGui")
local motion=C("vv2MotionBlur",false)
local blurStrength=math.clamp(tonumber(C("vv2BlurStrength",8)) or 8,1,24)
local jumpResize=C("vv2JumpResize",false)
local jumpSize=math.clamp(tonumber(C("vv2JumpSize",100)) or 100,50,125)
local toolTrans=C("vv2ToolTransparency",false)
local toolLevel=math.clamp(tonumber(C("vv2ToolTransparencyLevel",5)) or 5,0,10)
local hideControls=C("vv2HideTouchControls",false)
local blur=Lighting:FindFirstChild("VisualsV2_MotionBlur") or Instance.new("BlurEffect")
blur.Name="VisualsV2_MotionBlur"; blur.Parent=Lighting; if not motion then blur.Size=0 end
local lastCFrame=(workspace.CurrentCamera and workspace.CurrentCamera.CFrame) or CFrame.new()
RunService.RenderStepped:Connect(function(dt)
    local cam=workspace.CurrentCamera; if not cam then return end
    if not motion then blur.Size=0; lastCFrame=cam.CFrame; return end
    local c=cam.CFrame
    local d=math.abs(c.X-lastCFrame.X)+math.abs(c.Y-lastCFrame.Y)+math.abs(c.Z-lastCFrame.Z)
    local r=(c.LookVector-lastCFrame.LookVector).Magnitude
    local target=(d+r)*60
    blur.Size=math.clamp(math.lerp(blur.Size,target*4,dt*20),0,blurStrength)
    if blur.Size>0.1 then blur.Size=math.clamp(blur.Size-(0.5*(dt*60)),0,blurStrength) end
    lastCFrame=c
end)
local motionToggle=addToggle(section,"VV2 Enable Motion Blur",motion,function(v) motion=v; SetCfg("vv2MotionBlur",v); if not v then blur.Size=0 end end)
section:AddSlider("VV2 Blur Strength",1,24,blurStrength,function(v) blurStrength=v; SetCfg("vv2BlurStrength",v) end)

local function findJump()
    local tg=pg:FindFirstChild("TouchGui"); if not tg then return end
    local tcf=tg:FindFirstChild("TouchControlFrame")
    local jb=tcf and tcf:FindFirstChild("JumpButton",true)
    if jb then return jb end
    for _,d in ipairs(tg:GetDescendants()) do if d.Name=="JumpButton" and d:IsA("GuiButton") then return d end end
end
local function applyJump()
    if not jumpResize or not UserInputService.TouchEnabled then return end
    local jb=findJump(); local cam=workspace.CurrentCamera; if not jb or not cam then return end
    local maxSize=math.min(cam.ViewportSize.X,cam.ViewportSize.Y)*0.25
    local size=math.clamp(jumpSize,50,maxSize)
    jb.Size=UDim2.new(0,size,0,size); jb.Position=UDim2.new(1,-size-20,1,-size-20)
end
RunService.RenderStepped:Connect(applyJump)
local jumpToggle=addToggle(section,"VV2 Jump Button Size Changer (Mobile & Tablet)",jumpResize,function(v) jumpResize=v; SetCfg("vv2JumpResize",v) end)
section:AddSlider("VV2 Jump Button Size",50,125,jumpSize,function(v) jumpSize=v; SetCfg("vv2JumpSize",v); applyJump() end)

local originals=setmetatable({}, {__mode="k"})
local function applyTool(t)
    if not t or not t:IsA("Tool") then return end
    for _,p in ipairs(t:GetDescendants()) do
        if p:IsA("BasePart") then
            if originals[p]==nil then originals[p]=p.Transparency end
            p.Transparency=toolTrans and (toolLevel/10) or originals[p]
        end
    end
end
local function allTools()
    for _,c in ipairs({player.Character,player:FindFirstChildOfClass("Backpack")}) do
        if c then for _,t in ipairs(c:GetChildren()) do if t:IsA("Tool") then applyTool(t) end end end
    end
end
local function restoreTools()
    for p,v in pairs(originals) do if p and p.Parent then pcall(function() p.Transparency=v end) end end
    originals=setmetatable({}, {__mode="k"})
end
local toolToggle=addToggle(section,"VV2 Tool Transparency",toolTrans,function(v) toolTrans=v; SetCfg("vv2ToolTransparency",v); if v then allTools() else restoreTools() end end)
section:AddSlider("VV2 Tool Transparency Level",0,10,toolLevel,function(v) toolLevel=v; SetCfg("vv2ToolTransparencyLevel",v); if toolTrans then allTools() end end)

local hideToken=0
local function invisible(o)
    if not o:IsA("GuiObject") then return end
    o.BackgroundTransparency=1
    if o:IsA("ImageLabel") or o:IsA("ImageButton") then o.ImageTransparency=1 end
    if o:IsA("TextLabel") or o:IsA("TextButton") then o.TextTransparency=1 end
end
local function hideLoop()
    hideToken+=1; local tok=hideToken
    if not hideControls then return end
    task.spawn(function()
        while hideControls and tok==hideToken do
            local tg=pg:FindFirstChild("TouchGui")
            if tg then for _,o in ipairs(tg:GetDescendants()) do invisible(o) end end
            task.wait(0.1)
        end
    end)
end
local hideToggle=addToggle(section,"VV2 Hide Joystick & Jump Button",hideControls,function(v) hideControls=v; SetCfg("vv2HideTouchControls",v); hideLoop() end)
env.VisualsV2Runtime.RegisterReset(function()
    motionToggle:Set(false); jumpToggle:Set(false); toolToggle:Set(false); hideToggle:Set(false)
    motion=false; jumpResize=false; toolTrans=false; hideControls=false; hideToken+=1; blur.Size=0; restoreTools()
end)
if toolTrans then task.defer(allTools) end
if hideControls then hideLoop() end
end)()

-- =========================================================
-- VISUAL STAT SPOOFER
-- =========================================================
;(function()
local section=mainTab:AddSection("Visual Stat Spoofer","Visuals")
local pg=player:WaitForChild("PlayerGui")
local enabled=C("visualStatSpooferEnabled",false)
local v1=tostring(C("visualStat1","0")); local v2=tostring(C("visualStat2","0")); local v3=tostring(C("visualStat3","0"))
local alive=true
local toggle=addToggle(section,"VV2 Enable Visual Stat Spoofer",enabled,function(v) enabled=v; SetCfg("visualStatSpooferEnabled",v) end)
section:AddTextBox("VV2 Stat 1 (Murderer / Eliminations)",function(v) v1=tostring(v or "0"); SetCfg("visualStat1",v1) end)
section:AddTextBox("VV2 Stat 2 (Sheriff / Saves)",function(v) v2=tostring(v or "0"); SetCfg("visualStat2",v2) end)
section:AddTextBox("VV2 Stat 3 (Innocent / Survivals)",function(v) v3=tostring(v or "0"); SetCfg("visualStat3",v3) end)
task.spawn(function()
    local cache={}; local last=0
    while alive do
        task.wait(0.5)
        if enabled then pcall(function()
            if tick()-last>3 or #cache==0 then
                last=tick(); table.clear(cache)
                local mg=pg:FindFirstChild("MainGUI")
                if mg then
                    for _,d in ipairs(mg:GetDescendants()) do
                        if d.Name=="Season1Stats" or d.Name=="Stats" or d.Name=="Container" then
                            local e=d:FindFirstChild("Eliminations"); local s=d:FindFirstChild("Saves"); local u=d:FindFirstChild("Survivals")
                            local row={}
                            if e and e:FindFirstChild("Amount") then row.e=e.Amount end
                            if s and s:FindFirstChild("Amount") then row.s=s.Amount end
                            if u and u:FindFirstChild("Amount") then row.u=u.Amount end
                            if row.e or row.s or row.u then table.insert(cache,row) end
                        end
                    end
                end
            end
            for _,r in ipairs(cache) do
                if r.e and r.e.Parent then r.e.Text=v1 end
                if r.s and r.s.Parent then r.s.Text=v2 end
                if r.u and r.u.Parent then r.u.Text=v3 end
            end
        end) else table.clear(cache) end
    end
end)
env.VisualsV2Runtime.RegisterReset(function() toggle:Set(false); enabled=false; alive=false end)
end)()

-- =========================================================
-- COIN AURA
-- =========================================================
;(function()
local section=mainTab:AddSection("Coin Aura","Utilities")
local enabled=C("coinAuraEnabled",false)
local radius=math.clamp(tonumber(C("coinAuraRadius",8)) or 8,1,10)
local conn=nil
local addedConn,removingConn
local coins,coinIndices,nextTouch={},{},{}
local cursor=1
local elapsed=0
local STEP_INTERVAL=0.1
local RETOUCH_DELAY=0.25
local MAX_CHECKS=256
local MAX_TOUCHES=8
local function hasFireTouchInterest()
    return type(firetouchinterest)=="function"
end

local function fireTouch(a,b)
    -- Match the working AFP implementation directly for Delta.
    if type(firetouchinterest)~="function" then return false end
    local ok0=pcall(function() firetouchinterest(a,b,0) end)
    local ok1=pcall(function() firetouchinterest(a,b,1) end)
    return ok0 or ok1
end

local function isCoinPart(part)
    if not part or not part:IsA("BasePart") or not part:FindFirstChild("TouchInterest") then return false end
    local ancestor=part.Parent
    while ancestor and ancestor~=workspace do
        if ancestor.Name=="CoinContainer" then return true end
        ancestor=ancestor.Parent
    end
    return false
end

local function removeCoin(part)
    local index=coinIndices[part]
    if not index then return end
    local last=coins[#coins]
    coins[index]=last
    coins[#coins]=nil
    coinIndices[part]=nil
    nextTouch[part]=nil
    if last~=part then coinIndices[last]=index end
    if cursor>#coins then cursor=1 end
end

local function addCoin(part)
    if coinIndices[part] or not isCoinPart(part) then return end
    coins[#coins+1]=part
    coinIndices[part]=#coins
end

local function discover(item)
    if item:IsA("BasePart") then
        addCoin(item)
    elseif item.Name=="TouchInterest" and item.Parent then
        addCoin(item.Parent)
    end
end

local function collect(dt)
    if not enabled then return end
    elapsed=elapsed+(tonumber(dt) or STEP_INTERVAL)
    if elapsed<STEP_INTERVAL then return end
    elapsed=elapsed%STEP_INTERVAL
    local char=player.Character
    local root=char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local rootPos=root.Position
    local radiusSquared=radius*radius
    local now=os.clock()
    local checked,touched=0,0
    local total=#coins
    while #coins>0 and checked<total and checked<MAX_CHECKS and touched<MAX_TOUCHES do
        if cursor>#coins then cursor=1 end
        local part=coins[cursor]
        cursor=cursor+1
        checked=checked+1
        if part.Parent and part:FindFirstChild("TouchInterest") then
            if now>=(nextTouch[part] or 0) then
                local delta=part.Position-rootPos
                local distanceSquared=delta.X*delta.X+delta.Y*delta.Y+delta.Z*delta.Z
                if distanceSquared<=radiusSquared then
                    nextTouch[part]=now+RETOUCH_DELAY
                    if fireTouch(root,part) then touched=touched+1 end
                end
            end
        else
            removeCoin(part)
        end
    end
end

local function refresh()
    if conn then conn:Disconnect(); conn=nil end
    if addedConn then addedConn:Disconnect(); addedConn=nil end
    if removingConn then removingConn:Disconnect(); removingConn=nil end
    table.clear(coins); table.clear(coinIndices); table.clear(nextTouch)
    cursor=1; elapsed=0
    if not enabled then return end

    -- Enumerate once; subsequent coin spawns/removals maintain the cache.
    addedConn=workspace.DescendantAdded:Connect(discover)
    removingConn=workspace.DescendantRemoving:Connect(function(item)
        if coinIndices[item] then
            removeCoin(item)
        elseif item.Name=="TouchInterest" and item.Parent then
            removeCoin(item.Parent)
        end
    end)
    for _,item in ipairs(workspace:GetDescendants()) do discover(item) end
    conn=RunService.Heartbeat:Connect(collect)
end
local toggle=addToggle(section,"VV2 Coin Aura",enabled,function(v)
    enabled=v
    SetCfg("coinAuraEnabled",v)

    if v and not hasFireTouchInterest() then
        pcall(function()
            shared.Notify("Coin Aura could not find firetouchinterest in this executor session",3)
        end)
    end

    refresh()
end)
section:AddSlider("VV2 Coin Aura Radius",1,10,radius,function(v)
    radius=math.clamp(tonumber(v) or 8,1,10)
    SetCfg("coinAuraRadius",radius)
end)
env.VisualsV2Runtime.RegisterReset(function() toggle:Set(false); enabled=false; refresh() end)
if enabled then refresh() end
end)()

-- FIREFLY CLUTCH
-- Core behavior rebuilt directly from the attached FFC addon.
-- =========================================================

;(function()
local section=mainTab:AddSection("Firefly Clutch","Utilities")
local autoClutch=C("fireflyAutoClutch",false)
local timerEnabled=C("fireflyTimerEnabled",true)
local timerColors=C("fireflyTimerColors",true)
local timerSize=math.clamp(tonumber(C("fireflyTimerSize",10)) or 10,1,10)
local timerLocked=C("fireflyTimerLocked",false)
-- The supplied recording releases the lid about 3s after activation.
local COUNTDOWN=3.0
local COOLDOWN=16
local TRIGGER_POINT=0.24
local JUMP_GAP=0.40
local TIMER_GREEN=Color3.fromRGB(0,255,0)
local TIMER_YELLOW=Color3.fromRGB(255,200,0)
local TIMER_RED=Color3.fromRGB(255,0,0)
local TIMER_BLACK=Color3.fromRGB(0,0,0)
local DEFAULT_POS=UDim2.new(0.5,0,0.05,0)

local function timerCountdownColor(remaining,total)
    total=math.max(tonumber(total) or 1,0.001)
    local ratio=math.clamp((tonumber(remaining) or 0)/total,0,1)
    if ratio>=(2/3) then return TIMER_GREEN end
    if ratio>=(1/3) then return TIMER_YELLOW end
    return TIMER_RED
end

local gui,timerLabel
local timerDragConnections={}
local countdownConnection,cooldownConnection,blockConnection
local watchConnections={}
local hookedTools=setmetatable({}, {__mode="k"})
local scanToken=0
local isOnCooldown=false
local cooldownGateReady=false
local jumpTriggered=false
local cycleToken=0
local cycleStartedAt=nil
local countdownRemaining=nil
local cooldownEndsAt=nil

local function updateTimerDisplay()
    if not timerLabel then return end
    timerLabel.Visible=timerEnabled
    if not timerEnabled then return end

    local now=os.clock()
    local remaining,total
    if countdownRemaining and countdownRemaining>0 then
        remaining,total=countdownRemaining,COUNTDOWN
    elseif cooldownEndsAt and now<cooldownEndsAt then
        remaining,total=cooldownEndsAt-now,COOLDOWN
    end

    if remaining then
        timerLabel.Text=string.format("%.1fCD",math.max(0,remaining))
        timerLabel.TextColor3=timerColors and timerCountdownColor(remaining,total) or TIMER_BLACK
    else
        timerLabel.Text="Ready"
        timerLabel.TextColor3=TIMER_BLACK
    end
end

local function disconnect(conn)
    if conn then pcall(function() conn:Disconnect() end) end
end

local function ownsFireflyTool(tool)
    local backpack=player:FindFirstChildOfClass("Backpack")
    return (player.Character and tool.Parent==player.Character)
        or (backpack and tool.Parent==backpack) or false
end

local function blockToolActivation(tool,state)
    if not autoClutch or not isOnCooldown or not cooldownGateReady or not ownsFireflyTool(tool) then return end
    state.blocked=true
    if tool.Enabled then pcall(function() tool.Enabled=false end) end
end

local function blockFireflyTools()
    for tool,state in pairs(hookedTools) do blockToolActivation(tool,state) end
end

local function releaseToolBlocks()
    cooldownGateReady=false
    for tool,state in pairs(hookedTools) do
        if state.blocked then
            state.blocked=false
            pcall(function()
                if not tool.Enabled then tool.Enabled=state.originalEnabled end
            end)
        end
    end
end

local function clearTimerGuis()
    local pg=player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    for _,name in ipairs({"VisualsV2_FireflyTimer","FireflyTimerGui","FireflyCooldownGui"}) do
        local old=pg:FindFirstChild(name)
        if old and old~=gui then pcall(function() old:Destroy() end) end
    end
end

local function applyTimerSize()
    if not timerLabel then return end
    local width=72+((timerSize-1)*8)
    local height=24+((timerSize-1)*2)
    timerLabel.Size=UDim2.fromOffset(width,height)
    timerLabel.TextSize=math.max(12,math.floor(height*0.65))
end

local function buildTimer()
    if gui and gui.Parent and timerLabel then return end
    clearTimerGuis()

    gui=Instance.new("ScreenGui")
    gui.Name="VisualsV2_FireflyTimer"
    gui.ResetOnSpawn=false
    gui.IgnoreGuiInset=true
    gui.Parent=player:WaitForChild("PlayerGui")

    timerLabel=Instance.new("TextLabel")
    timerLabel.Name="FireflyTimer"
    timerLabel.AnchorPoint=Vector2.new(0.5,0.5)
    timerLabel.Position=loadStoredPosition("fireflyTimerPosition",DEFAULT_POS)
    timerLabel.BackgroundTransparency=1
    timerLabel.BorderSizePixel=0
    timerLabel.TextColor3=Color3.new(0,0,0)
    timerLabel.TextStrokeTransparency=1
    timerLabel.Font=Enum.Font.GothamBold
    timerLabel.Text="Ready"
    timerLabel.Visible=timerEnabled
    timerLabel.Active=true
    timerLabel.Parent=gui
    applyTimerSize()
    updateTimerDisplay()

    local dragging=false
    local moved=false
    local dragInput,dragStart,startPos

    timerLabel.InputBegan:Connect(function(input)
        if timerLocked then return end
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        dragging=true
        moved=false
        dragStart=input.Position
        startPos=timerLabel.Position
    end)
    timerLabel.InputChanged:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then dragInput=input end
    end)
    table.insert(timerDragConnections,UserInputService.InputChanged:Connect(function(input)
        if not dragging or timerLocked or not timerEnabled or not timerLabel or input~=dragInput then return end
        local delta=input.Position-dragStart
        if delta.Magnitude>7 then moved=true end
        timerLabel.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
    end))
    table.insert(timerDragConnections,UserInputService.InputEnded:Connect(function(input)
        if not dragging then return end
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        dragging=false
        if moved and timerLabel then saveStoredPosition("fireflyTimerPosition",timerLabel.Position) end
    end))
end

local function fireJump()
    local char=player.Character
    local humanoid=char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health<=0 then return end

    -- Match the Debug addon: force the jump state directly. This is important
    -- for the second jump because FloorMaterial can already be Air.
    humanoid.Jump=true
    pcall(function()
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end)
end

local function startTwoJumpSequence(myCycle)
    -- Jump shortly before the jar releases its lid, then again 0.40s later.
    fireJump()
    task.delay(JUMP_GAP,function()
        if autoClutch and myCycle==cycleToken then
            fireJump()
        end
    end)
end

local function stopCycle()
    disconnect(countdownConnection)
    disconnect(cooldownConnection)
    disconnect(blockConnection)
    countdownConnection=nil
    cooldownConnection=nil
    blockConnection=nil
    cycleToken+=1
    isOnCooldown=false
    releaseToolBlocks()
    jumpTriggered=false
    cycleStartedAt=nil
    countdownRemaining=nil
    cooldownEndsAt=nil
    updateTimerDisplay()
end

-- Keep the displayed countdown and first-jump trigger on the same Heartbeat
-- clock. The release duration matches the supplied in-game recording.
local function startCountdown()
    if not autoClutch then return end
    buildTimer()
    disconnect(countdownConnection)
    countdownConnection=nil
    jumpTriggered=false
    local myCycle=cycleToken
    updateTimerDisplay()

    countdownConnection=RunService.Heartbeat:Connect(function(dt)
        if not autoClutch or myCycle~=cycleToken or not countdownRemaining then return end
        countdownRemaining=math.max(0,countdownRemaining-dt)
        if not jumpTriggered and countdownRemaining<=TRIGGER_POINT then
            jumpTriggered=true
            startTwoJumpSequence(myCycle)
        end
        updateTimerDisplay()
        -- Trigger before finishing even if a slow frame crosses the whole window.
        if countdownRemaining<=0 then
            disconnect(countdownConnection)
            countdownConnection=nil
        end
    end)
end

local function startCooldownPanel()
    buildTimer()
    disconnect(cooldownConnection)
    cooldownConnection=nil
    cooldownConnection=RunService.Heartbeat:Connect(function()
        if not cycleStartedAt or not cooldownEndsAt then return end
        local now=os.clock()
        if countdownRemaining and countdownRemaining>0 then return end
        local remaining=cooldownEndsAt-now
        if remaining<=0 then
            updateTimerDisplay()
            disconnect(cooldownConnection)
            cooldownConnection=nil
            return
        end
        updateTimerDisplay()
    end)
end

local function startBlockTimer()
    isOnCooldown=true
    local myCycle=cycleToken
    -- Let the accepted activation reach the game's own handlers before locking
    -- the Tool. The lock prevents subsequent clicks from replaying its animation.
    task.defer(function()
        if autoClutch and isOnCooldown and myCycle==cycleToken then
            cooldownGateReady=true
            blockFireflyTools()
        end
    end)
    disconnect(blockConnection)
    blockConnection=nil
    blockConnection=RunService.Heartbeat:Connect(function()
        if cooldownEndsAt and os.clock()>=cooldownEndsAt then
            isOnCooldown=false
            releaseToolBlocks()
            disconnect(blockConnection)
            blockConnection=nil
        elseif cooldownGateReady then
            blockFireflyTools()
        end
    end)
end

local function startOriginalCycle()
    if not autoClutch or isOnCooldown then return end
    buildTimer()
    cycleToken+=1
    cycleStartedAt=os.clock()
    countdownRemaining=COUNTDOWN
    cooldownEndsAt=cycleStartedAt+COOLDOWN
    startCountdown()
    startCooldownPanel()
    startBlockTimer()
end

local function connectToTool(tool)
    if not tool or not tool:IsA("Tool") or tool.Name~="Fireflies" then return end
    if hookedTools[tool] then
        blockToolActivation(tool,hookedTools[tool])
        return
    end

    local state={originalEnabled=tool.Enabled,blocked=false}
    hookedTools[tool]=state
    table.insert(watchConnections,tool:GetPropertyChangedSignal("Enabled"):Connect(function()
        if autoClutch and isOnCooldown then
            if tool.Enabled then state.originalEnabled=true end
            blockToolActivation(tool,state)
        elseif not state.blocked then
            state.originalEnabled=tool.Enabled
        end
    end))
    table.insert(watchConnections,tool.Activated:Connect(function()
        if not autoClutch or isOnCooldown then return end
        if not ownsFireflyTool(tool) then return end
        -- Activated was accepted while Enabled was true, even if the game's
        -- earlier handler has already disabled it for its own cooldown.
        state.originalEnabled=true
        startOriginalCycle()
    end))
    blockToolActivation(tool,state)
end

local function scanForFireflies()
    local backpack=player:FindFirstChildOfClass("Backpack")
    local character=player.Character

    local function scanContainer(container)
        if container then
            for _,child in ipairs(container:GetChildren()) do
                if child:IsA("Tool") and child.Name=="Fireflies" then
                    connectToTool(child)
                end
            end
        end
    end
    scanContainer(backpack)
    scanContainer(character)
end

local function hookTool()
    scanToken+=1
    local myScan=scanToken

    local function watchContainer(container)
        if not container then return end
        pcall(scanForFireflies)
        table.insert(watchConnections,container.ChildAdded:Connect(function(child)
            if child:IsA("Tool") and child.Name=="Fireflies" then
                -- Hook immediately so the first use after execution is not missed.
                connectToTool(child)
            end
        end))
    end

    watchContainer(player:FindFirstChildOfClass("Backpack"))
    watchContainer(player.Character)

    table.insert(watchConnections,player.ChildAdded:Connect(function(child)
        if child:IsA("Backpack") then
            watchContainer(child)
            task.defer(scanForFireflies)
        end
    end))

    table.insert(watchConnections,player.CharacterAdded:Connect(function(char)
        watchContainer(char)
        task.defer(function()
            if autoClutch and myScan==scanToken then
                buildTimer()
                scanForFireflies()
            end
        end)
    end))

    scanForFireflies()

    task.spawn(function()
        -- Fast startup window for tools inserted while the addon is loading.
        for _=1,12 do
            if not autoClutch or myScan~=scanToken then return end
            pcall(scanForFireflies)
            task.wait(0.05)
        end
        while autoClutch and myScan==scanToken do
            pcall(scanForFireflies)
            task.wait(0.5)
        end
    end)
end

local function unhookTool()
    scanToken+=1
    stopCycle()

    for _,conn in ipairs(watchConnections) do
        disconnect(conn)
    end
    table.clear(watchConnections)
    table.clear(hookedTools)
end

local autoToggle=addToggle(section,"Auto Firefly Clutch",autoClutch,function(state)
    autoClutch=state
    SetCfg("fireflyAutoClutch",state)
    if state then
        buildTimer()
        unhookTool()
        -- unhookTool clears stale tool hooks; restore the desired state and scan.
        autoClutch=true
        hookTool()
    else
        unhookTool()
    end
end)

local timerToggle=addToggle(section,"Enable Firefly Timer",timerEnabled,function(state)
    timerEnabled=state
    SetCfg("fireflyTimerEnabled",state)
    buildTimer()
    updateTimerDisplay()
end)

local timerColorToggle=addToggle(section,"Enable Statistic Colors",timerColors,function(state)
    timerColors=state
    SetCfg("fireflyTimerColors",state)
    updateTimerDisplay()
end)

section:AddSlider("Firefly Timer Size",1,10,timerSize,function(value)
    timerSize=math.clamp(tonumber(value) or 5,1,10)
    SetCfg("fireflyTimerSize",timerSize)
    applyTimerSize()
end)

local fireflyLockToggle=addToggle(section,"Lock Firefly Timer Position",timerLocked,function(state)
    timerLocked=state
    SetCfg("fireflyTimerLocked",state)
end)

section:AddButton("Reset Firefly Timer Position",function()
    saveStoredPosition("fireflyTimerPosition",DEFAULT_POS)
    if timerLabel then timerLabel.Position=DEFAULT_POS end
end)

local fireflyRemovingConnection=player.CharacterRemoving:Connect(function()
    stopCycle()
end)
local fireflyRespawnConnection=player.CharacterAdded:Connect(function()
    stopCycle()
end)

env.VisualsV2Runtime.RegisterReset(function()
    autoToggle:Set(false)
    timerToggle:Set(false)
    timerColorToggle:Set(false)
    fireflyLockToggle:Set(false)
    autoClutch=false
    timerEnabled=false
    timerColors=false
    timerLocked=false
    unhookTool()
    disconnect(fireflyRemovingConnection)
    disconnect(fireflyRespawnConnection)
    for _,connection in ipairs(timerDragConnections) do disconnect(connection) end
    table.clear(timerDragConnections)
    if gui then gui:Destroy(); gui=nil; timerLabel=nil end
end)

buildTimer()
if autoClutch then
    hookTool()
end
end)()

-- =========================================================
-- SCREEN
-- =========================================================

;(function()
local screenSection = mainTab:AddSection("Screen", "Visuals")
local stretchScreenEnabled = C("stretchScreenEnabled", false)
local STRETCH_FACTOR = 0.65

local stretchToggle = addToggle(screenSection, "Stretch Screen", stretchScreenEnabled, function(state)
    stretchScreenEnabled = state
    SetCfg("stretchScreenEnabled", state)
end)

RunService.RenderStepped:Connect(function()
    camera = workspace.CurrentCamera
    if camera and stretchScreenEnabled then
        camera.CFrame = camera.CFrame * CFrame.new(
            0, 0, 0,
            1, 0, 0,
            0, STRETCH_FACTOR, 0,
            0, 0, 1
        )
    end
end)

env.VisualsV2Runtime.RegisterReset(function()
    stretchToggle:Set(false)
    stretchScreenEnabled = false
end)

end)()

-- =========================================================
-- WORLD
-- =========================================================

;(function()
local worldSection=mainTab:AddSection("Environment","World")

-- Environment behavior restored from the attached Nexium source. The only UI
-- adaptation retained is the saved Time of Day preset dropdown requested earlier.
local savedFogStart=Lighting.FogStart
local savedFogEnd=Lighting.FogEnd
local savedFogColor=Lighting.FogColor
local fullbrightEnabled=C("fullbrightEnabled",false)
local ambientColor=C("ambientColor",Lighting.Ambient)
local exposure=C("exposure",Lighting.ExposureCompensation)
local fogEnabled=false
local applyFog=nil

local savedClockTime=Lighting.ClockTime

local function applyFullbright()
    Lighting.Brightness=2
    Lighting.ClockTime=14
    Lighting.FogEnd=100000
    Lighting.GlobalShadows=false
    Lighting.Ambient=Color3.fromRGB(255,255,255)
    Lighting.OutdoorAmbient=Color3.fromRGB(255,255,255)
end

local function disableFullbright()
    -- Match Nexium's working off-state, while preserving this add-on's selected
    -- ambient/exposure/preset values.
    Lighting.Brightness=1
    Lighting.GlobalShadows=true
    Lighting.FogEnd=savedFogEnd
    Lighting.Ambient=ambientColor
    Lighting.OutdoorAmbient=ambientColor
    Lighting.ExposureCompensation=exposure
    Lighting.ClockTime=savedClockTime
end

local fullbrightToggle=addToggle(worldSection,"Fullbright",fullbrightEnabled,function(state)
    fullbrightEnabled=state
    SetCfg("fullbrightEnabled",state)
    if state then
        applyFullbright()
    else
        disableFullbright()
        if fogEnabled and applyFog then applyFog() end
    end
end)

worldSection:AddColorpicker("Ambient Color",ambientColor,function(color)
    ambientColor=color
    SetCfg("ambientColor",color)
    if not fullbrightEnabled then
        Lighting.Ambient=color
        Lighting.OutdoorAmbient=color
    end
end)


worldSection:AddSlider("Exposure",-2,5,exposure,function(value)
    exposure=value
    SetCfg("exposure",value)
    Lighting.ExposureCompensation=value
end)

if fullbrightEnabled then applyFullbright() else disableFullbright() end

local fogSection=mainTab:AddSection("Fog","World")
fogEnabled=C("fogEnabled",false)
local fogRainbow=C("fogRainbow",false)
local fogColor=C("fogColor",Color3.fromRGB(200,200,255))
local fogStart=math.max(0,tonumber(C("fogStart",0)) or 0)
local fogEnd=math.max(50,tonumber(C("fogEnd",100)) or 100)

applyFog=function()
    Lighting.FogStart=fogStart
    Lighting.FogEnd=math.max(fogStart+1,fogEnd)
    Lighting.FogColor=fogRainbow and Color3.fromHSV((os.clock()%5)/5,1,1) or fogColor
end

local fogToggle=addToggle(fogSection,"Enable Beautiful Fog",fogEnabled,function(state)
    fogEnabled=state
    SetCfg("fogEnabled",state)
    if state then
        if not fullbrightEnabled then applyFog() end
    else
        Lighting.FogStart=savedFogStart
        Lighting.FogEnd=savedFogEnd
        Lighting.FogColor=savedFogColor
    end
end)

local rainbowFogToggle=addToggle(fogSection,"Rainbow Fog",fogRainbow,function(state)
    fogRainbow=state
    SetCfg("fogRainbow",state)
    if fogEnabled and not fullbrightEnabled then applyFog() end
end)

fogSection:AddSlider("Fog Distance",50,2000,fogEnd,function(value)
    fogEnd=value
    SetCfg("fogEnd",value)
    if fogEnabled and not fullbrightEnabled then applyFog() end
end)

fogSection:AddSlider("Fog Start",0,500,fogStart,function(value)
    fogStart=value
    SetCfg("fogStart",value)
    if fogEnabled and not fullbrightEnabled then applyFog() end
end)

fogSection:AddColorpicker("Fog Color",fogColor,function(color)
    fogColor=color
    SetCfg("fogColor",color)
    if fogEnabled and not fogRainbow and not fullbrightEnabled then applyFog() end
end)

RunService.RenderStepped:Connect(function()
    if fogEnabled and fogRainbow and not fullbrightEnabled then
        Lighting.FogColor=Color3.fromHSV((os.clock()%5)/5,1,1)
    end
end)

-- Skybox dropdown. Nexium entries retain their original asset IDs. Additional
-- six-face presets are kept only when they do not duplicate a Nexium name.
local skyboxSection=mainTab:AddSection("Skyboxes","Visuals")
local currentSky=Lighting:FindFirstChildOfClass("Sky")
env.VisualsV2OriginalSky=currentSky and currentSky:Clone() or false
local originalSky=env.VisualsV2OriginalSky

local skyCheckConnection
local selectedSkybox=C("selectedSkybox","Default")

local SKYBOX_PRESETS={
    ["Orange Skybox"]="627302570",
    ["FPS+ Skybox"]="582303304",
    ["Space Skybox"]="15619750970",
    ["Green Skybox"]="348361280",
    ["Blue Skybox"]="130093177270069",
    ["Purple Skybox"]="83555979203508",
    ["Red Skybox"]="401666131",
    ["HD Skybox"]="16823410580",
    ["Night Skybox"]="12064636",
    ["Galactic Skybox"]="10542194896",
    ["Winter Skybox"]="96628448286151",
    ["Saturn Skybox"]="1898754079",
    ["Outrun Skybox"]="3441770362",
    ["Cyan Space Skybox"]="367149630",
    ["City Skybox"]="117205995214134",
    ["Green Skybox 2.0"]="16823294549",
    ["Obama Skybox (Joke)"]="2362934358",
    ["SpongeBob Skybox"]="114523453023009",
    ["Purple Nebula Skybox"]="230057997",
    ["Bart Skybox"]="119891349513795",
    ["Sunless Blue Sky"]="591067775",
    ["Weirdcore Eye Skybox"]="11372740893",
    ["Minecraft Skybox"]="5087871978",
    ["Frutiger Aero Skybox"]="97046110924083",
    ["Cyberpunk Skybox"]="13689001090",
    ["Dark Red Castle Skybox"]="15832476802",
    ["Cartoon Skybox"]="107689530722429",
    ["Error Skybox"]="13710730784",
    ["Abyssal Blues Skybox"]="16269853692",
    ["Earth Skybox"]="266878339",
    ["Black & White Fade Skybox"]="6213224205",
    ["Purple Skybox 2"]="8107887936",
    ["Green Nebula Space"]="89018019804256",
    ["HD Rainbow Skybox"]="18915196644",
    ["Meadow Skybox"]="848241313",
    ["Pink Sky Skybox"]="107689530722174",
    ["Venus Skybox V2"]="110450592899174",

    ["Realistic Sky"]={"144933338","144931530","144933262","144933244","144933299","144931564"},
    ["Purple Nighty #1"]={"159454299","159454296","159454293","159454286","159454300","159454288"},
    ["Purple Nighty #2"]={"14543264135","14543358958","14543257810","14543275895","14543280890","14543371676"},
    ["Sunset"]={"15502525195","15502522797","15502524520","15502522129","15502523711","15502526102"},
    ["Nighty Sky"]={"168387023","168387089","168387054","168534432","168387190","168387135"},
    ["Sunset Sky"]={"458016711","458016826","458016532","458016655","458016782","458016792"},
    ["Night Fog"]={"1370717244","1370717336","1370717438","1370717567","1370717698","1370717782"},
    ["Blood Moon"]={"401664839","401664862","401664960","401664881","401664901","401664936"},
    ["Pink Blossom"]={"271042516","271077243","271042556","271042310","271042467","271077958"},
    ["Purple Sunset"]={"264908339","264907909","264909420","264909758","264908886","264907379"},
    ["Void Sky"]={"16262356578","16262358026","16262360469","16262362003","16262363873","16262366016"},
    ["Purple Night"]={"5084575798","5084575916","5103949679","5103948542","5103948784","5084576400"},
    ["Realistic Moon"]={"2670643994","2670643365","2670643214","2670643070","2670644173","2670644331"},
}

if selectedSkybox~="Default" and SKYBOX_PRESETS[selectedSkybox]==nil then
    selectedSkybox="Default"
    ConfigData["selectedSkybox"]="Default"
end

local SKYBOX_NAMES={
    "Default",
    "Orange Skybox","FPS+ Skybox","Space Skybox","Green Skybox","Blue Skybox",
    "Purple Skybox","Red Skybox","HD Skybox","Night Skybox","Galactic Skybox",
    "Winter Skybox","Saturn Skybox","Outrun Skybox","Cyan Space Skybox","City Skybox",
    "Green Skybox 2.0","Obama Skybox (Joke)","SpongeBob Skybox","Purple Nebula Skybox",
    "Bart Skybox","Sunless Blue Sky","Weirdcore Eye Skybox","Minecraft Skybox",
    "Frutiger Aero Skybox","Cyberpunk Skybox","Dark Red Castle Skybox","Cartoon Skybox",
    "Error Skybox","Abyssal Blues Skybox","Earth Skybox",
    "Black & White Fade Skybox","Purple Skybox 2","Green Nebula Space","HD Rainbow Skybox",
    "Meadow Skybox","Pink Sky Skybox","Venus Skybox V2",
    "Realistic Sky","Purple Nighty #1","Purple Nighty #2","Sunset","Nighty Sky",
    "Sunset Sky","Night Fog","Blood Moon","Pink Blossom","Purple Sunset",
    "Void Sky","Purple Night","Realistic Moon",
}

local function clearSky()
    for _,obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("Sky") then obj:Destroy() end
    end
end

local function restoreSky()
    clearSky()
    if typeof(originalSky)=="Instance" then
        originalSky:Clone().Parent=Lighting
    end
end

local function markSky(sky,name)
    if sky then pcall(function() sky:SetAttribute("VisualsV2SkyboxPreset",name) end) end
end

local function applySingleAsset(assetId,name)
    clearSky()

    local ok,asset=pcall(function()
        return game:GetObjects("rbxassetid://"..tostring(assetId))[1]
    end)

    if ok and asset then
        if asset:IsA("Sky") then
            markSky(asset,name)
            asset.Parent=Lighting
            return true
        end

        local nested=asset:FindFirstChildWhichIsA("Sky",true)
        if nested then
            local sky=nested:Clone()
            markSky(sky,name)
            sky.Parent=Lighting
            pcall(function() asset:Destroy() end)
            return true
        end

        pcall(function() asset:Destroy() end)
    end

    -- Original Nexium fallback.
    local sky=Instance.new("Sky")
    local id="rbxassetid://"..tostring(assetId)
    sky.SkyboxBk=id
    sky.SkyboxDn=id
    sky.SkyboxFt=id
    sky.SkyboxLf=id
    sky.SkyboxRt=id
    sky.SkyboxUp=id
    markSky(sky,name)
    sky.Parent=Lighting
    return true
end

local function applySixFace(ids,name)
    clearSky()
    local sky=Instance.new("Sky")
    sky.SkyboxBk="rbxassetid://"..ids[1]
    sky.SkyboxDn="rbxassetid://"..ids[2]
    sky.SkyboxFt="rbxassetid://"..ids[3]
    sky.SkyboxLf="rbxassetid://"..ids[4]
    sky.SkyboxRt="rbxassetid://"..ids[5]
    sky.SkyboxUp="rbxassetid://"..ids[6]
    markSky(sky,name)
    sky.Parent=Lighting
    return true
end

local function applySelectedSkybox()
    if selectedSkybox=="Default" or SKYBOX_PRESETS[selectedSkybox]==nil then
        restoreSky()
        return
    end

    local data=SKYBOX_PRESETS[selectedSkybox]
    if type(data)=="table" then
        applySixFace(data,selectedSkybox)
    else
        applySingleAsset(data,selectedSkybox)
    end
end

local function refreshSkyWatcher()
    if skyCheckConnection then
        skyCheckConnection:Disconnect()
        skyCheckConnection=nil
    end

    if selectedSkybox=="Default" then return end

    skyCheckConnection=Lighting.ChildAdded:Connect(function(child)
        if child:IsA("Sky") then
            task.defer(function()
                local current=Lighting:FindFirstChildOfClass("Sky")
                local tag
                pcall(function() tag=current and current:GetAttribute("VisualsV2SkyboxPreset") end)
                if tag~=selectedSkybox then
                    applySelectedSkybox()
                end
            end)
        end
    end)
end

addDropdown(skyboxSection,"Skybox",SKYBOX_NAMES,selectedSkybox,function(value)
    selectedSkybox=value
    SetCfg("selectedSkybox",value)
    applySelectedSkybox()
    refreshSkyWatcher()
end)

task.defer(function()
    applySelectedSkybox()
    refreshSkyWatcher()
end)

if fogEnabled and not fullbrightEnabled then applyFog() end

env.VisualsV2Runtime.RegisterReset(function()
    fullbrightToggle:Set(false)
    fogToggle:Set(false)
    rainbowFogToggle:Set(false)
    fullbrightEnabled=false
    fogEnabled=false
    fogRainbow=false
    if skyCheckConnection then skyCheckConnection:Disconnect(); skyCheckConnection=nil end
    restoreSky()
    fullbrightEnabled=false
    disableFullbright()
end)
end)()

-- =========================================================
-- UTILITIES: INVENTORY UNLIMITER + AUTO GET TOOLS
-- =========================================================

;(function()
local section=mainTab:AddSection("Inventory Unlimiter","Utilities")
section:AddParagraph(
    "Inventory Unlimiter",
    "Raises the local inventory display/equip limit from 3 to 10. The target functions are cached after discovery to reduce repeated scanning."
)

local inventoryEnabled=C("inventoryUnlimiterEnabled",false)
local inventoryLimit=math.clamp(tonumber(C("inventoryMaxItems",10)) or 10,3,10)
local autoGetTools=C("autoGetTools",false)
local selectedToys={
    C("autoToySlot1","None"), C("autoToySlot2","None"),
    C("autoToySlot3","None"), C("autoToySlot4","None"),
}
local getupvalues=(debug and debug.getupvalues) or getupvalues
local setupvalue=(debug and debug.setupvalue) or setupvalue
local getinfo=(debug and debug.getinfo) or getinfo
local getconstants=(debug and debug.getconstants) or getconstants
local targetFunctions={}
local targetsScanned=false
local alive=true
local recoveryToken=0
local recoveryRunning=false
local recoveryCharacter=nil
local removingCharacter=nil
local recoveryDeadline=0
local rescanRequested=false
local toyAttempts={}
local activeToyRequest=nil
local toyOrderDirty=true
local orderingBackpack=false
local observedBackpack=nil
local backpackConnections={}
local characterConnections={}
local toyConnections={}
local guiConnections={}
local lifecycleConnections={}
local dropdowns={}
local refreshingDropdowns=false
local guiRefreshToken=0
local requestRecovery,refreshToyDropdowns

local function disconnectAll(connections)
    for _,connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    table.clear(connections)
end

local function discoverTargets(force)
    if targetsScanned and not force then return end
    targetsScanned=false
    table.clear(targetFunctions)
    if not (type(getgc)=="function" and type(getupvalues)=="function"
        and type(setupvalue)=="function" and type(getinfo)=="function") then return end
    local okGc,objects=pcall(getgc)
    if not okGc or type(objects)~="table" then return end
    for _,f in ipairs(objects) do
        if type(f)=="function" then
            local success,info=pcall(getinfo,f)
            if success and type(info)=="table" then
                local isTarget=(info.name=="updateItemFrame" or info.name=="onItemEquipped")
                if not isTarget and type(getconstants)=="function" then
                    local cSuccess,constants=pcall(getconstants,f)
                    if cSuccess and type(constants)=="table" then
                        local hasTouch,hasEquip=false,false
                        for _,value in pairs(constants) do
                            if value=="TouchBinding" then hasTouch=true
                            elseif value=="EquipButton" then hasEquip=true end
                        end
                        isTarget=hasTouch and hasEquip
                    end
                end
                if isTarget then table.insert(targetFunctions,f) end
            end
        end
    end
    -- An empty/early discovery must remain eligible for the next retry.
    targetsScanned=#targetFunctions>0
end

local function applyInventoryLimit(force)
    if not inventoryEnabled then return end
    discoverTargets(force)
    for _,f in ipairs(targetFunctions) do
        local ok,upvalues=pcall(getupvalues,f)
        if ok and type(upvalues)=="table" then
            for index,value in pairs(upvalues) do
                if type(index)=="number" and type(value)=="number" and value>=2 and value<=10 then
                    pcall(setupvalue,f,index,inventoryLimit)
                end
            end
        end
    end
end

local function getBackpack()
    if observedBackpack and observedBackpack.Parent==player then return observedBackpack end
    return player:FindFirstChildOfClass("Backpack")
end

local function findToyFolder()
    local backpack=getBackpack()
    return backpack and backpack:FindFirstChild("Toys") or nil
end

local function getToyNames()
    local names={"None"}
    local folder=findToyFolder()
    if folder then
        for _,toy in ipairs(folder:GetChildren()) do
            if not table.find(names,toy.Name) then names[#names+1]=toy.Name end
        end
    end
    table.sort(names,function(a,b)
        if a==b then return false end
        if a=="None" then return true end
        if b=="None" then return false end
        return a:lower()<b:lower()
    end)
    return names
end

local function hasSelectedTool(name,char,backpack)
    local inCharacter=char and char:FindFirstChild(name)
    local inBackpack=backpack and backpack:FindFirstChild(name)
    return (inCharacter and inCharacter:IsA("Tool")) or (inBackpack and inBackpack:IsA("Tool")) or false
end

local function toyRemote()
    local rs=game:GetService("ReplicatedStorage")
    local remotes=rs:FindFirstChild("Remotes")
    local extras=remotes and remotes:FindFirstChild("Extras")
    local remote=extras and extras:FindFirstChild("ReplicateToy")
    if remote and remote:IsA("RemoteFunction") then return remote end
end

local function orderSelectedTools(char,backpack,token)
    if orderingBackpack or not backpack or char:FindFirstChildOfClass("Tool") then return false end
    local ordered,selected,selectedInstances={},{},{}
    local choices={}
    for slot=1,4 do
        local name=selectedToys[slot]
        choices[slot]=name
        if name and name~="None" and not selected[name] then
            local tool=backpack:FindFirstChild(name)
            if not tool or not tool:IsA("Tool") then return false end
            selected[name]=true
            selectedInstances[tool]=true
            ordered[#ordered+1]=tool
        end
    end
    if #ordered==0 then return true end

    local current={}
    for _,tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") then
            current[#current+1]=tool
            if not selectedInstances[tool] then ordered[#ordered+1]=tool end
        end
    end
    local matches=#current==#ordered
    for index,tool in ipairs(ordered) do
        if current[index]~=tool then matches=false; break end
    end
    if matches then return true end

    -- Backpack UI assigns slots on ChildAdded. Reinsert in the selected order,
    -- without unequipping a tool or requesting an already-owned toy again.
    orderingBackpack=true
    local detached={}
    local success=true
    for _,tool in ipairs(ordered) do
        if tool.Parent==backpack then
            local ok=pcall(function() tool.Parent=nil end)
            if ok then detached[tool]=true else success=false end
        else success=false end
    end
    -- Deferred ChildRemoved handlers must see the tools outside the Backpack
    -- before ChildAdded assigns the new slots. Always restore even if cancelled.
    task.wait()
    local valid=alive and runtimeAlive and autoGetTools and token==recoveryToken
        and player.Character==char and backpack.Parent==player
    for slot=1,4 do if choices[slot]~=selectedToys[slot] then valid=false end end
    for _,tool in ipairs(valid and ordered or current) do
        if detached[tool] and tool.Parent==nil then
            if not pcall(function() tool.Parent=backpack end) then success=false end
        elseif tool.Parent~=backpack then success=false end
    end
    if valid then
        local expected={}
        for _,tool in ipairs(ordered) do expected[tool]=true end
        for _,tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and not expected[tool] then success=false; break end
        end
    end
    orderingBackpack=false
    return success and valid
end

local function cancelToyRequests()
    for _,attempt in pairs(toyAttempts) do
        if attempt.thread and type(task.cancel)=="function" then pcall(task.cancel,attempt.thread) end
    end
    table.clear(toyAttempts)
    activeToyRequest=nil
end

local function cancelRecovery()
    recoveryToken=recoveryToken+1
    recoveryRunning=false
    recoveryCharacter=nil
    recoveryDeadline=0
    rescanRequested=false
    toyOrderDirty=true
    cancelToyRequests()
end

local function isCurrentRecovery(token,char)
    return alive and runtimeAlive and token==recoveryToken
        and player.Character==char and char~=removingCharacter
        and (inventoryEnabled or autoGetTools)
end

requestRecovery=function(forceScan)
    if not alive or not runtimeAlive or not (inventoryEnabled or autoGetTools) then return end
    local char=player.Character
    if not char or char==removingCharacter then return end
    if recoveryCharacter~=char then
        cancelRecovery()
        recoveryCharacter=char
        targetsScanned=false
        table.clear(targetFunctions)
    end
    if forceScan then rescanRequested=true end
    recoveryDeadline=math.max(recoveryDeadline,os.clock()+20)
    if recoveryRunning then return end
    recoveryRunning=true
    local token=recoveryToken
    task.spawn(function()
        local startedAt=os.clock()
        local scanTimes={0,1,3,6,10,15}
        local scanIndex=1
        local nextInventoryApply=0
        local nextToyRequest=0
        while isCurrentRecovery(token,char) and os.clock()<recoveryDeadline do
            local now=os.clock()
            local humanoid=char:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health>0 then
                local force=rescanRequested
                if scanTimes[scanIndex] and now-startedAt>=scanTimes[scanIndex] then
                    force=true
                    repeat scanIndex=scanIndex+1
                    until not scanTimes[scanIndex] or now-startedAt<scanTimes[scanIndex]
                end
                if inventoryEnabled and (force or (targetsScanned and now>=nextInventoryApply)) then
                    applyInventoryLimit(force)
                    nextInventoryApply=now+1
                end
                rescanRequested=false

                if autoGetTools then
                    local backpack=getBackpack()
                    if toyOrderDirty and backpack and orderSelectedTools(char,backpack,token) then
                        toyOrderDirty=false
                    end
                end
                if autoGetTools and not activeToyRequest and now>=nextToyRequest then
                    local backpack=getBackpack()
                    local folder=findToyFolder()
                    local remote=toyRemote()
                    if backpack and folder and remote then
                        local seen={}
                        for slot=1,4 do
                            local name=selectedToys[slot]
                            if name and name~="None" and not seen[name] then
                                seen[name]=true
                                if not hasSelectedTool(name,char,backpack) then
                                    local attempt=toyAttempts[name]
                                    if not attempt then
                                        attempt={count=0,nextAt=0,inFlight=false}
                                        toyAttempts[name]=attempt
                                    end
                                    if folder:FindFirstChild(name) and not attempt.inFlight and attempt.count<6 and now>=attempt.nextAt then
                                        attempt.count=attempt.count+1
                                        attempt.nextAt=now+math.min(3,0.75+attempt.count*0.5)
                                        attempt.inFlight=true
                                        activeToyRequest=attempt
                                        nextToyRequest=now+0.25
                                        attempt.thread=task.spawn(function()
                                            if isCurrentRecovery(token,char) and autoGetTools then
                                                pcall(function() remote:InvokeServer(name) end)
                                            end
                                            attempt.inFlight=false
                                            attempt.thread=nil
                                            attempt.nextAt=math.max(attempt.nextAt,os.clock()+math.min(3,0.75+attempt.count*0.5))
                                            if activeToyRequest==attempt then activeToyRequest=nil end
                                            if isCurrentRecovery(token,char) and autoGetTools then requestRecovery(false) end
                                        end)
                                    end
                                    -- Wait for this slot to actually arrive, including during
                                    -- retries or catalog loading, before requesting later slots.
                                    break
                                end
                            end
                        end
                    end
                end
            end
            task.wait(0.2)
        end
        if token==recoveryToken then recoveryRunning=false end
    end)
end

refreshToyDropdowns=function()
    local names=getToyNames()
    refreshingDropdowns=true
    for slot,dropdown in ipairs(dropdowns) do
        if dropdown then
            if type(dropdown.Change)=="function" then
                pcall(dropdown.Change,names)
            elseif type(dropdown.ChangeItems)=="function" then
                pcall(function() dropdown:ChangeItems(names) end)
            end
            if type(dropdown.Select)=="function" then
                local ok=pcall(dropdown.Select,selectedToys[slot])
                if not ok then pcall(function() dropdown:Select(selectedToys[slot]) end) end
            end
        end
    end
    refreshingDropdowns=false
end

local function watchToyFolder(folder)
    disconnectAll(toyConnections)
    if not folder then return end
    local function changed()
        refreshToyDropdowns()
        requestRecovery(false)
    end
    toyConnections[#toyConnections+1]=folder.ChildAdded:Connect(changed)
    toyConnections[#toyConnections+1]=folder.ChildRemoved:Connect(changed)
end

local function watchBackpack(backpack)
    disconnectAll(backpackConnections)
    disconnectAll(toyConnections)
    observedBackpack=backpack
    toyOrderDirty=true
    if not backpack then return end
    watchToyFolder(backpack:FindFirstChild("Toys"))
    backpackConnections[#backpackConnections+1]=backpack.ChildAdded:Connect(function(child)
        if child.Name=="Toys" then
            watchToyFolder(child)
            refreshToyDropdowns()
            requestRecovery(false)
        elseif child:IsA("Tool") and not orderingBackpack then
            toyOrderDirty=true
            requestRecovery(false)
        end
    end)
    backpackConnections[#backpackConnections+1]=backpack.ChildRemoved:Connect(function(child)
        if child.Name=="Toys" then watchToyFolder(nil)
        elseif child:IsA("Tool") and not orderingBackpack then
            toyOrderDirty=true
            requestRecovery(false)
        end
    end)
    refreshToyDropdowns()
end

local function watchCharacter(char)
    disconnectAll(characterConnections)
    if not char then return end
    local function changed(child)
        if child:IsA("Tool") then
            toyOrderDirty=true
            requestRecovery(false)
        end
    end
    characterConnections[1]=char.ChildAdded:Connect(changed)
    characterConnections[2]=char.ChildRemoved:Connect(changed)
end

local function queueGuiRecovery()
    guiRefreshToken=guiRefreshToken+1
    local token=guiRefreshToken
    task.delay(0.35,function()
        if alive and token==guiRefreshToken then requestRecovery(true) end
    end)
end

local function watchPlayerGui(gui)
    disconnectAll(guiConnections)
    if not gui then return end
    guiConnections[#guiConnections+1]=gui.ChildAdded:Connect(function(child)
        if child.Name=="MainGUI" or (child:IsA("ScreenGui") and child.Name:sub(1,10)~="VisualsV2_") then
            queueGuiRecovery()
        end
    end)
    guiConnections[#guiConnections+1]=gui.DescendantAdded:Connect(function(child)
        if child.Name=="EquipButton" or child.Name=="TouchBinding" then queueGuiRecovery() end
    end)
end

local inventoryToggle=addToggle(section,"Unlimit Inventory",inventoryEnabled,function(state)
    inventoryEnabled=state
    SetCfg("inventoryUnlimiterEnabled",state)
    if state then requestRecovery(true)
    elseif not autoGetTools then cancelRecovery() end
end)
section:AddSlider("Max Items",3,10,inventoryLimit,function(value)
    inventoryLimit=math.clamp(math.floor(tonumber(value) or 10),3,10)
    SetCfg("inventoryMaxItems",inventoryLimit)
    if inventoryEnabled then
        if targetsScanned then applyInventoryLimit(false) end
        requestRecovery(not targetsScanned)
    end
end)
local autoToggle=addToggle(section,"Auto Get Tools",autoGetTools,function(state)
    local wasEnabled=autoGetTools
    autoGetTools=state
    toyOrderDirty=true
    SetCfg("autoGetTools",state)
    if state then
        if not wasEnabled then cancelToyRequests() end
        requestRecovery(false)
    else
        cancelToyRequests()
        if not inventoryEnabled then cancelRecovery() end
    end
end)

local toyNames=getToyNames()
for slot=1,4 do
    dropdowns[slot]=addDropdown(section,"Select Toy Slot "..slot,toyNames,selectedToys[slot],function(selected)
        if refreshingDropdowns then return end
        selectedToys[slot]=selected
        SetCfg("autoToySlot"..slot,selected)
        toyOrderDirty=true
        if autoGetTools then
            local previous=toyAttempts[selected]
            if not previous or not previous.inFlight then toyAttempts[selected]=nil end
            requestRecovery(false)
        end
    end)
end
section:AddButton("Refresh Toy List",function() refreshToyDropdowns() end)

lifecycleConnections[#lifecycleConnections+1]=player.CharacterRemoving:Connect(function(char)
    removingCharacter=char
    disconnectAll(characterConnections)
    cancelRecovery()
    targetsScanned=false
    table.clear(targetFunctions)
end)
lifecycleConnections[#lifecycleConnections+1]=player.CharacterAdded:Connect(function(char)
    removingCharacter=nil
    watchCharacter(char)
    watchBackpack(player:FindFirstChildOfClass("Backpack"))
    requestRecovery(true)
end)
lifecycleConnections[#lifecycleConnections+1]=player.ChildAdded:Connect(function(child)
    if child:IsA("Backpack") then
        watchBackpack(child)
        requestRecovery(true)
    elseif child:IsA("PlayerGui") then
        watchPlayerGui(child)
        requestRecovery(true)
    end
end)
local replicatedStorage=game:GetService("ReplicatedStorage")
lifecycleConnections[#lifecycleConnections+1]=replicatedStorage.DescendantAdded:Connect(function(child)
    if child.Name=="Remotes" or child.Name=="Extras" or child.Name=="ReplicateToy" then requestRecovery(false) end
end)
watchBackpack(player:FindFirstChildOfClass("Backpack"))
watchCharacter(player.Character)
watchPlayerGui(player:FindFirstChildOfClass("PlayerGui"))
if inventoryEnabled or autoGetTools then task.defer(function() requestRecovery(false) end) end

env.VisualsV2Runtime.RegisterReset(function()
    alive=false
    guiRefreshToken=guiRefreshToken+1
    cancelRecovery()
    inventoryToggle:Set(false)
    autoToggle:Set(false)
    inventoryEnabled=false
    autoGetTools=false
    disconnectAll(lifecycleConnections)
    disconnectAll(backpackConnections)
    disconnectAll(characterConnections)
    disconnectAll(toyConnections)
    disconnectAll(guiConnections)
end)
end)()


-- =========================================================
-- MISCELLANEOUS
-- =========================================================

;(function()
local miscSection=mainTab:AddSection("Miscellaneous","Settings")
miscSection:AddButton("Reset Big/Bind Button Position",function()
    saveStoredPosition("speedButtonPosition",BIG_BUTTON_DEFAULT)
    saveStoredPosition("speedBindButtonPosition",BIND_BUTTON_DEFAULT)
    if speedButton then speedButton.Position=BIG_BUTTON_DEFAULT end
    BindableButtons:SetPosition("VisualsV2_SpeedBind",BIND_BUTTON_DEFAULT)
end)
addToggle(miscSection,"Lock Big Button POS",lockBigButtonPos,function(state)
    lockBigButtonPos=state
    SetCfg("lockBigButtonPos",state)
end)
addToggle(miscSection,"Lock Bind Button POS",lockBindButtonPos,function(state)
    lockBindButtonPos=state
    SetCfg("lockBindButtonPos",state)
    BindableButtons:SetLocked("VisualsV2_SpeedBind",state)
end)
end)()

-- Reapply local cosmetic state after respawn.
local function onCharacterAdded(char)
    characterOriginal=setmetatable({}, {__mode="k"})

    if headlessEnabled then
        task.spawn(function()
            char:WaitForChild("Head",2)
            if player.Character==char and headlessEnabled then
                applyCharacterVisuals()
            end
        end)
    end

    if KorbloxSystem.RightEnabled or KorbloxSystem.LeftEnabled then
        KorbloxSystem.Schedule(char)
    end

    task.delay(0.15,function()
        if player.Character~=char then return end
        if trailEnabled then createTrail() end
        if ffEnabled then applyForceField(); refreshForceFieldConnection() end
        if skinTrailEnabled then applySkinTrail(); refreshSkinTrailRainbowConnection() end
        if auraEnabled then applyAura() end
        if noInterruptionEmote then setupAutomaticEmoteProtection(char) end
        setupJumpCircles(char)
    end)

    task.delay(0.5,setupSpeedButtons)
end
if player.Character then task.defer(function() onCharacterAdded(player.Character) end) end
player.CharacterAdded:Connect(onCharacterAdded)

saveConfig()

-- =========================================================

-- =========================================================
-- VISUALSV2 PERFORMANCE & GRAPHICS
-- =========================================================
local performanceTab=mainTab

;(function()
local section=performanceTab:AddSection("FPS, Plyr, & Ping","Performance")
local Stats=game:GetService("Stats")
local enabled=C("vv2FpsPingEnabled",false)
local colors=C("vv2FpsPingColors",true)
local showFps=C("vv2FpsPingShowFps",true)
local showPing=C("vv2FpsPingShowPing",true)
local showPlayers=C("vv2FpsPingShowPlayers",true)
local legacyMonitorSize=tonumber(ConfigData["vv2FpsPingSize"])
local legacyMonitorScale=legacyMonitorSize and math.clamp(legacyMonitorSize,1,10)/5 or 1
if tonumber(ConfigData["vv2FpsPingSizeScaleVersion"])~=2 then
    -- Keep an existing display's physical size when migrating the old scale.
    ConfigData["vv2FpsPingSize"]=legacyMonitorSize
        and math.clamp(math.floor((legacyMonitorScale-0.5)*4+0.5),1,10) or 2
    ConfigData["vv2FpsPingSizeScaleVersion"]=2
end
local monitorSize=math.clamp(tonumber(C("vv2FpsPingSize",2)) or 2,1,10)
local locked=C("vv2FpsPingLocked",false)
local gui,holder,fps,ping,playersLabel,monitorScale,renderConn
local lastFps=0
local dragConnections={}
local POSITION_KEY="vv2FpsPingMonitorPosition"
local DEFAULT_POS=UDim2.new(0.5,0,0.05,0)
if tonumber(ConfigData["vv2FpsPingAnchorVersion"])~=2 then
    local saved=PositionData[POSITION_KEY]
    if type(saved)=="table" then
        local visibleCount=(showFps and 1 or 0)+(showPing and 1 or 0)+(showPlayers and 1 or 0)
        saved.xo=(tonumber(saved.xo or saved.XO) or 0)+(120*legacyMonitorScale/2)
        saved.yo=(tonumber(saved.yo or saved.YO) or 0)+(math.max(1,visibleCount*28-3)*legacyMonitorScale/2)
    end
    ConfigData["vv2FpsPingAnchorVersion"]=2
end
local BLACK=Color3.fromRGB(0,0,0)
local GREEN=Color3.fromRGB(0,255,0)
local YELLOW=Color3.fromRGB(255,200,0)
local RED=Color3.fromRGB(255,0,0)
local monitorToggle,fpsToggle,pingToggle,playersToggle

local function ensureMonitorStatistic()
    if configResetting or not enabled or showFps or showPing or showPlayers then return end
    showFps=true
    SetCfg("vv2FpsPingShowFps",true)
    pcall(function()
        shared.Notify("Error: Enable at least one statistic, or turn off Monitor UI. FPS has been enabled.",4)
    end)
    task.defer(function()
        if showFps and fpsToggle then fpsToggle:Set(true) end
    end)
end

local function root()
    if type(gethui)=="function" then
        local ok,r=pcall(gethui)
        if ok and typeof(r)=="Instance" then return r end
    end
    return player:WaitForChild("PlayerGui")
end

local function disconnectDragConnections()
    for _,connection in ipairs(dragConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(dragConnections)
end

local function decodeSavedPosition(fallback)
    return loadStoredPosition(POSITION_KEY,fallback)
end

local function saveMonitorPosition(position)
    saveStoredPosition(POSITION_KEY,position)
end

local function setMonitorPosition(position,saveIt)
    if holder then holder.Position=position end
    if saveIt then saveMonitorPosition(position) end
end

local function fpsColor(value,cap)
    if not colors then return BLACK end
    cap=math.max(tonumber(cap) or 60,1)
    if value>=cap*.85 then return GREEN end
    if value>=cap*.5 then return YELLOW end
    return RED
end

local function pingColor(value)
    if not colors then return BLACK end
    if value<=80 then return GREEN end
    if value<=150 then return YELLOW end
    return RED
end

local function playerCountColor(value)
    if not colors then return BLACK end
    -- MM2 servers are 1-12 players. Higher population is treated as better.
    value=math.clamp(tonumber(value) or 1,1,12)
    if value>=9 then return GREEN end
    if value>=5 then return YELLOW end
    return RED
end

local function makeLabel(name,y)
    local label=Instance.new("TextLabel")
    label.Name=name
    label.BackgroundTransparency=1
    label.Size=UDim2.new(1,0,0,25)
    label.Position=UDim2.fromOffset(0,y)
    label.Font=Enum.Font.SourceSansLight
    label.TextScaled=true
    label.TextColor3=BLACK
    label.TextStrokeTransparency=1
    label.Active=false
    label.Parent=holder
    return label
end

local function applyMonitorLayout()
    if not holder then return end
    local visible={showFps,showPing,showPlayers}
    local y=0
    for i,label in ipairs({fps,ping,playersLabel}) do
        label.Visible=visible[i]
        if visible[i] then
            label.Position=UDim2.fromOffset(0,y)
            y+=28
        end
    end
    holder.Size=UDim2.fromOffset(120,math.max(1,y-3))
    holder.Visible=showFps or showPing or showPlayers
    if monitorScale then monitorScale.Scale=0.4+((monitorSize-1)*(2.6/9)) end
end

local function updateMonitorStats(value)
    if not fps or not fps.Parent then return end
    if value~=nil then lastFps=value end
    local cap=workspace:GetAttribute("FPSCap") or 60
    fps.Text=tostring(lastFps)
    fps.TextColor3=fpsColor(lastFps,cap)

    local p=0
    pcall(function()
        p=tonumber(Stats.Network.ServerStatsItem["Data Ping"]:GetValueString():match("%-?%d+")) or 0
    end)
    ping.Text=tostring(p)
    ping.TextColor3=pingColor(p)

    local count=#Players:GetPlayers()
    playersLabel.Text=tostring(count)
    playersLabel.TextColor3=playerCountColor(count)
end

local function setupDragging()
    disconnectDragConnections()
    if not holder then return end

    local dragging=false
    local dragInput,dragStart,startPos

    local function beginDrag(input)
        if locked then return end
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        dragging=true
        dragInput=input
        dragStart=input.Position
        startPos=holder.Position
    end

    table.insert(dragConnections,holder.InputBegan:Connect(beginDrag))
    for _,label in ipairs({fps,ping,playersLabel}) do
        table.insert(dragConnections,label.InputBegan:Connect(beginDrag))
    end

    table.insert(dragConnections,UserInputService.InputChanged:Connect(function(input)
        if not dragging or locked then return end
        local matches=(input==dragInput)
            or (dragInput and dragInput.UserInputType==Enum.UserInputType.Touch and input.UserInputType==Enum.UserInputType.Touch)
            or (dragInput and dragInput.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement)
        if not matches then return end
        local delta=input.Position-dragStart
        holder.Position=UDim2.new(
            startPos.X.Scale,startPos.X.Offset+delta.X,
            startPos.Y.Scale,startPos.Y.Offset+delta.Y
        )
    end))

    table.insert(dragConnections,UserInputService.InputEnded:Connect(function(input)
        if not dragging then return end
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        dragging=false
        if holder then saveMonitorPosition(holder.Position) end
    end))
end

local function destroy()
    if renderConn then renderConn:Disconnect(); renderConn=nil end
    disconnectDragConnections()
    if gui then gui:Destroy(); gui=nil end
    holder=nil; fps=nil; ping=nil; playersLabel=nil; monitorScale=nil
end

local function create()
    ensureMonitorStatistic()
    destroy()

    gui=Instance.new("ScreenGui")
    gui.Name="VisualsV2_FpsPingMonitor"
    gui.ResetOnSpawn=false
    gui.IgnoreGuiInset=true
    gui.Parent=root()

    holder=Instance.new("Frame")
    holder.Name="VisualsV2_StatsHolder"
    holder.BackgroundTransparency=1
    holder.Size=UDim2.fromOffset(120,81)
    holder.AnchorPoint=Vector2.new(0.5,0.5)
    holder.Active=true
    holder.Position=decodeSavedPosition(DEFAULT_POS)
    holder.Parent=gui

    monitorScale=Instance.new("UIScale")
    monitorScale.Name="VisualsV2_MonitorScale"
    monitorScale.Parent=holder

    fps=makeLabel("VisualsV2_FPS",0)
    ping=makeLabel("VisualsV2_Ping",28)
    playersLabel=makeLabel("VisualsV2_Players",56)
    applyMonitorLayout()
    lastFps=0
    updateMonitorStats()
    setupDragging()

    local elapsed,frameCount=0,0
    renderConn=RunService.RenderStepped:Connect(function(dt)
        if not fps or not fps.Parent then return end
        elapsed+=math.max(dt,0)
        frameCount+=1
        if elapsed>=.5 then
            local averageFps=math.floor(frameCount/math.max(elapsed,1/1000)+.5)
            elapsed,frameCount=0,0
            updateMonitorStats(averageFps)
        end
    end)
end

monitorToggle=addToggle(section,"VV2 Enable Monitor UI",enabled,function(v)
    enabled=v
    SetCfg("vv2FpsPingEnabled",v)
    if v then create() else destroy() end
end)

local colorToggle=addToggle(section,"VV2 Enable Statistic Colors",colors,function(v)
    colors=v
    SetCfg("vv2FpsPingColors",v)
    updateMonitorStats()
end)

fpsToggle=addToggle(section,"Show FPS",showFps,function(v)
    showFps=v
    SetCfg("vv2FpsPingShowFps",v)
    ensureMonitorStatistic()
    applyMonitorLayout()
end)

pingToggle=addToggle(section,"Show Ping",showPing,function(v)
    showPing=v
    SetCfg("vv2FpsPingShowPing",v)
    ensureMonitorStatistic()
    applyMonitorLayout()
end)

playersToggle=addToggle(section,"Show Player Count",showPlayers,function(v)
    showPlayers=v
    SetCfg("vv2FpsPingShowPlayers",v)
    ensureMonitorStatistic()
    applyMonitorLayout()
end)

section:AddSlider("Monitor Size",1,10,monitorSize,function(value)
    monitorSize=math.clamp(tonumber(value) or 2,1,10)
    SetCfg("vv2FpsPingSize",monitorSize)
    applyMonitorLayout()
end)

local lockToggle=addToggle(section,"Lock Monitor Position",locked,function(v)
    locked=v
    SetCfg("vv2FpsPingLocked",v)
end)

section:AddButton("Reset Monitor Position",function()
    SetCfg("vv2FpsPingPosition","Top Center")
    setMonitorPosition(DEFAULT_POS,true)
end)

env.VisualsV2Runtime.RegisterReset(function()
    monitorToggle:Set(false)
    colorToggle:Set(false)
    fpsToggle:Set(false)
    pingToggle:Set(false)
    playersToggle:Set(false)
    lockToggle:Set(false)
    enabled=false
    colors=false
    showFps=false
    showPing=false
    showPlayers=false
    locked=false
    destroy()
end)

if enabled then task.defer(create) end
end)()

;(function()
local section=performanceTab:AddSection("Performance & Optimization","Performance")
local P=game:GetService("Players")
local originalMat,originalPart,originalTex,originalAcc,originalSky={},{},{},{},{}
local conns={}; local frameConn=nil
local state={
    smooth=C("perfSmooth",false), shadows=C("perfShadows",false), particles=C("perfParticles",false),
    meshes=C("perfMeshes",false), textures=C("perfTextures",false), accessories=C("perfAccessories",false),
    gray=C("perfGray",false), frame=C("perfFrame",false)
}
local originalShadows=Lighting.GlobalShadows
local function isPlayer(o) for _,p in ipairs(P:GetPlayers()) do if p.Character and o:IsDescendantOf(p.Character) then return true end end return false end
local function setSmooth(on)
    if conns.s then conns.s:Disconnect(); conns.s=nil end
    if on then
        for _,o in ipairs(workspace:GetDescendants()) do if o:IsA("BasePart") and not isPlayer(o) then if originalMat[o]==nil then originalMat[o]=o.Material end; o.Material=Enum.Material.SmoothPlastic end end
        conns.s=workspace.DescendantAdded:Connect(function(o) if o:IsA("BasePart") and not isPlayer(o) then if originalMat[o]==nil then originalMat[o]=o.Material end; o.Material=Enum.Material.SmoothPlastic end end)
    else for o,v in pairs(originalMat) do if o and o.Parent then pcall(function() o.Material=v end) end end; originalMat={} end
end
local function setParticles(on)
    if conns.p then conns.p:Disconnect(); conns.p=nil end
    local function one(o) if o:IsA("ParticleEmitter") or o:IsA("Trail") then if originalPart[o]==nil then originalPart[o]=o.Enabled end; o.Enabled=false end end
    if on then for _,o in ipairs(workspace:GetDescendants()) do one(o) end; conns.p=workspace.DescendantAdded:Connect(one)
    else for o,v in pairs(originalPart) do if o and o.Parent then pcall(function() o.Enabled=v end) end end; originalPart={} end
end
local function setMeshes(on)
    if conns.m then conns.m:Disconnect(); conns.m=nil end
    local function one(o)
        if isPlayer(o) then return end
        local p=(o:IsA("MeshPart") and o) or ((o:IsA("SpecialMesh") or o:IsA("BlockMesh") or o:IsA("CylinderMesh")) and o.Parent)
        if p and p:IsA("BasePart") and not isPlayer(p) then if originalPart[p]==nil then originalPart[p]=p.Transparency end; p.Transparency=1 end
    end
    if on then for _,o in ipairs(workspace:GetDescendants()) do one(o) end; conns.m=workspace.DescendantAdded:Connect(one)
    else for o,v in pairs(originalPart) do if o and o.Parent and o:IsA("BasePart") then pcall(function() o.Transparency=v end) end end end
end
local function setTextures(on)
    if conns.t then conns.t:Disconnect(); conns.t=nil end
    local function one(o) if o:IsA("Decal") or o:IsA("Texture") then if originalTex[o]==nil then originalTex[o]=o.Texture end; o.Texture="" end end
    if on then for _,o in ipairs(workspace:GetDescendants()) do one(o) end; conns.t=workspace.DescendantAdded:Connect(one)
    else for o,v in pairs(originalTex) do if o and o.Parent then pcall(function() o.Texture=v end) end end; originalTex={} end
end
local function setAccessories(on)
    if on then
        for _,p in ipairs(P:GetPlayers()) do if p.Character then for _,a in ipairs(p.Character:GetChildren()) do if a:IsA("Accessory") then originalAcc[a]=p; a.Parent=nil end end end end
    else for a,p in pairs(originalAcc) do if a and p and p.Character and not a.Parent then pcall(function() a.Parent=p.Character end) end end; originalAcc={} end
end
local function setGray(on)
    if on then
        for _,s in ipairs(Lighting:GetChildren()) do if s:IsA("Sky") and s.Name~="VisualsV2_GraySky" then originalSky[s]=s.Parent; s.Parent=nil end end
        local sky=Instance.new("Sky"); sky.Name="VisualsV2_GraySky"; local id="rbxassetid://99742693890881"; sky.SkyboxBk=id; sky.SkyboxDn=id; sky.SkyboxFt=id; sky.SkyboxLf=id; sky.SkyboxRt=id; sky.SkyboxUp=id; sky.Parent=Lighting
    else
        local s=Lighting:FindFirstChild("VisualsV2_GraySky"); if s then s:Destroy() end
        for sky,parent in pairs(originalSky) do if sky then sky.Parent=parent end end; originalSky={}
    end
end
local function setFrame(on)
    if frameConn then frameConn:Disconnect(); frameConn=nil end
    local function degrade(o)
        if o:IsA("BasePart") then o.CastShadow=false; pcall(function() o.RenderFidelity=Enum.RenderFidelity.Disabled end)
        elseif o:IsA("ParticleEmitter") or o:IsA("Trail") or o:IsA("Smoke") or o:IsA("Fire") or o:IsA("Sparkles") or o:IsA("PointLight") or o:IsA("SpotLight") or o:IsA("SurfaceLight") then o.Enabled=false end
    end
    if on then
        Lighting.GlobalShadows=false; Lighting.Brightness=1; Lighting.ClockTime=14
        pcall(function() settings().Rendering.QualityLevel=Enum.QualityLevel.Level01; settings().Rendering.MeshPartDetailLevel=Enum.MeshPartDetailLevel.Disabled end)
        pcall(function() workspace.Terrain.Decoration=false end)
        for _,o in ipairs(workspace:GetDescendants()) do degrade(o) end; frameConn=workspace.DescendantAdded:Connect(degrade)
    else
        pcall(function() settings().Rendering.QualityLevel=Enum.QualityLevel.Automatic; settings().Rendering.MeshPartDetailLevel=Enum.MeshPartDetailLevel.Full end)
        pcall(function() workspace.Terrain.Decoration=true end)
    end
end
local toggles={}
local function add(key,label,fn)
    toggles[#toggles+1]=addToggle(section,label,state[key],function(v) state[key]=v; SetCfg("perf"..key:sub(1,1):upper()..key:sub(2),v); fn(v) end)
end
add("smooth","VV2 No Textures (SmoothPlastic)",setSmooth)
add("shadows","VV2 Disable Shadows",function(v) Lighting.GlobalShadows=v and false or originalShadows end)
add("particles","VV2 Disable Particles/Trails",setParticles)
add("meshes","VV2 Hide Meshes (world only)",setMeshes)
add("textures","VV2 Remove Textures/Decals",setTextures)
add("accessories","VV2 Remove Accessories",setAccessories)
add("gray","VV2 Gray Skybox",setGray)
section:AddButton("VV2 Remove Weapon Displays",function() local wd=workspace:FindFirstChild("WeaponDisplays"); if wd then wd:Destroy() end end)
add("frame","VV2 Enable Frame Enhancement",setFrame)
env.VisualsV2Runtime.RegisterReset(function() for _,t in ipairs(toggles) do t:Set(false) end; setSmooth(false); setParticles(false); setMeshes(false); setTextures(false); setAccessories(false); setGray(false); setFrame(false) end)
end)()

;(function()
local section=performanceTab:AddSection("RTX & Graphics","Visuals")
local Terrain=workspace:FindFirstChildOfClass("Terrain")
local rtx=C("rtxEnabled",false); local timeOn=C("rtxTimeEnabled",false); local custom=C("rtxCustomEnabled",false)
local mode=C("rtxTimeMode","Default (Original Game Time)")
local br=tonumber(C("rtxBrightness",20)) or 20; local sat=tonumber(C("rtxSaturation",35)) or 35; local con=tonumber(C("rtxContrast",30)) or 30
local bloom=(tonumber(C("rtxBloom",45)) or 45)/100; local sun=(tonumber(C("rtxSunRays",35)) or 35)/100; local refl=(tonumber(C("rtxReflections",25)) or 25)/10
local d={Technology=Lighting.Technology,GlobalShadows=Lighting.GlobalShadows,Brightness=Lighting.Brightness,Ambient=Lighting.Ambient,OutdoorAmbient=Lighting.OutdoorAmbient,Bottom=Lighting.ColorShift_Bottom,Top=Lighting.ColorShift_Top,Diffuse=Lighting.EnvironmentDiffuseScale,Specular=Lighting.EnvironmentSpecularScale,Soft=Lighting.ShadowSoftness,Lat=Lighting.GeographicLatitude,Exposure=Lighting.ExposureCompensation,Clock=Lighting.ClockTime,WaterT=Terrain and Terrain.WaterTransparency or .3,WaterR=Terrain and Terrain.WaterReflectance or 0}
local rtxObjs={}; local atmo,timeSky,cc,bl,ray
local function clearList() for _,o in ipairs(rtxObjs) do if o and o.Parent then o:Destroy() end end; table.clear(rtxObjs) end
local function clearTime() if atmo then atmo:Destroy(); atmo=nil end; if timeSky then timeSky:Destroy(); timeSky=nil end end
local function restoreTime()
    clearTime(); Lighting.ClockTime=d.Clock; Lighting.GeographicLatitude=d.Lat; Lighting.Brightness=d.Brightness; Lighting.Ambient=d.Ambient; Lighting.OutdoorAmbient=d.OutdoorAmbient; Lighting.ColorShift_Bottom=d.Bottom; Lighting.ColorShift_Top=d.Top; Lighting.ExposureCompensation=d.Exposure
end
local presets={
["Morning (Clean Golden)"]={7,3.2,{55,50,45},{190,160,130},{20,15,10},{255,235,205},.3,-25,{255,225,185},{110,85,65},.3,.2,.4,2,false},
["Midday (Vibrant Sun)"]={13,4,{60,65,80},{180,200,230},{20,30,50},{255,255,245},.35,10,{200,220,255},{90,120,160},.2,0,.4,1,false},
["Afternoon (Golden Hour)"]={16.5,3.6,{70,45,35},{220,140,70},{70,30,15},{255,180,90},.38,-15,{255,150,60},{110,50,25},.35,.4,.7,3,false},
["Sunset (Natural Warmth)"]={18.2,3.4,{65,45,40},{210,130,85},{50,20,20},{255,170,110},.35,-50,{255,160,100},{90,50,40},.3,.4,.6,3,false},
["Night (Cool Moonlight)"]={0,2,{25,35,60},{40,70,120},{10,20,45},{130,190,255},.5,45,{30,50,90},{15,25,50},.4,0,.3,2,true},
["Midnight (Pitch Black & Stars)"]={1.5,1.2,{10,12,20},{15,25,45},{5,8,15},{80,120,200},.2,90,{10,20,40},{5,10,20},.6,0,.2,6,true}}
local function applyTime()
    if not timeOn then return end; clearTime()
    if mode=="Default (Original Game Time)" then restoreTime(); return end
    local p=presets[mode]; if not p then return end
    local function rgb(x) return Color3.fromRGB(x[1],x[2],x[3]) end
    Lighting.ClockTime=p[1]; Lighting.Brightness=p[2]; Lighting.Ambient=rgb(p[3]); Lighting.OutdoorAmbient=rgb(p[4]); Lighting.ColorShift_Bottom=rgb(p[5]); Lighting.ColorShift_Top=rgb(p[6]); Lighting.ExposureCompensation=p[7]; Lighting.GeographicLatitude=p[8]
    atmo=Instance.new("Atmosphere"); atmo.Name="VisualsV2_TimeAtmosphere"; atmo.Color=rgb(p[9]); atmo.Decay=rgb(p[10]); atmo.Density=p[11]; atmo.Offset=p[12]; atmo.Glare=p[13]; atmo.Haze=p[14]; atmo.Parent=Lighting
    if p[15] then timeSky=Instance.new("Sky"); timeSky.Name="VisualsV2_TimeSky"; timeSky.SkyboxBk="rbxassetid://826027103"; timeSky.SkyboxDn="rbxassetid://826027117"; timeSky.SkyboxFt="rbxassetid://826027137"; timeSky.SkyboxLf="rbxassetid://826027161"; timeSky.SkyboxRt="rbxassetid://826027189"; timeSky.SkyboxUp="rbxassetid://826027228"; timeSky.Parent=Lighting end
end
local function applyRTX()
    if not rtx then return end; clearList(); Lighting.Technology=Enum.Technology.Future; Lighting.GlobalShadows=true; Lighting.ShadowSoftness=.02; Lighting.EnvironmentDiffuseScale=1; Lighting.EnvironmentSpecularScale=refl
    if Terrain then Terrain.WaterTransparency=.01; Terrain.WaterReflectance=1; Terrain.WaterWaveSize=.25; Terrain.WaterWaveSpeed=16 end
    pcall(function() settings().Rendering.QualityLevel=Enum.QualityLevel.Level21 end)
    local o=Instance.new("BloomEffect"); o.Name="VisualsV2_RTX_Bloom"; o.Intensity=.4; o.Size=3500; o.Threshold=.65; o.Parent=Lighting; table.insert(rtxObjs,o)
    o=Instance.new("ColorCorrectionEffect"); o.Name="VisualsV2_RTX_Color"; o.Brightness=.15; o.Contrast=.45; o.Saturation=.35; o.TintColor=Color3.fromRGB(255,245,230); o.Parent=Lighting; table.insert(rtxObjs,o)
    o=Instance.new("DepthOfFieldEffect"); o.Name="VisualsV2_RTX_DOF"; o.FarIntensity=.08; o.FocusDistance=28; o.InFocusRadius=20; o.NearIntensity=.15; o.Parent=Lighting; table.insert(rtxObjs,o)
    o=Instance.new("SunRaysEffect"); o.Name="VisualsV2_RTX_Sun"; o.Intensity=.35; o.Spread=.85; o.Parent=Lighting; table.insert(rtxObjs,o)
end
local function stopRTX()
    clearList(); Lighting.Technology=d.Technology; Lighting.GlobalShadows=d.GlobalShadows; Lighting.Brightness=d.Brightness; Lighting.Ambient=d.Ambient; Lighting.OutdoorAmbient=d.OutdoorAmbient; Lighting.ColorShift_Bottom=d.Bottom; Lighting.ColorShift_Top=d.Top; Lighting.EnvironmentDiffuseScale=d.Diffuse; Lighting.EnvironmentSpecularScale=d.Specular; Lighting.ShadowSoftness=d.Soft; Lighting.GeographicLatitude=d.Lat; Lighting.ExposureCompensation=d.Exposure; Lighting.ClockTime=d.Clock
    if Terrain then Terrain.WaterTransparency=d.WaterT; Terrain.WaterReflectance=d.WaterR end
end
local function clearCustom() if cc then cc:Destroy(); cc=nil end; if bl then bl:Destroy(); bl=nil end; if ray then ray:Destroy(); ray=nil end end
local function applyCustom()
    if not custom then return end; Lighting.Brightness=br/10; Lighting.EnvironmentSpecularScale=refl
    if not cc or not cc.Parent then cc=Instance.new("ColorCorrectionEffect"); cc.Name="VisualsV2_CustomGraphics_Color"; cc.Parent=Lighting end; cc.Saturation=sat/100; cc.Contrast=con/100
    if not bl or not bl.Parent then bl=Instance.new("BloomEffect"); bl.Name="VisualsV2_CustomGraphics_Bloom"; bl.Parent=Lighting end; bl.Intensity=bloom; bl.Size=3500
    if not ray or not ray.Parent then ray=Instance.new("SunRaysEffect"); ray.Name="VisualsV2_CustomGraphics_Sun"; ray.Parent=Lighting end; ray.Intensity=sun; ray.Spread=.85
end
local rt=addToggle(section,"VV2 Enable RTX (Ultra Realistic)",rtx,function(v) rtx=v; SetCfg("rtxEnabled",v); if v then applyRTX() else stopRTX() end end)
local tt=addToggle(section,"VV2 Enable Custom Time of Day",timeOn,function(v) timeOn=v; SetCfg("rtxTimeEnabled",v); if v then applyTime() else restoreTime() end end)
addDropdown(section,"VV2 Time of Day Preset",{"Default (Original Game Time)","Morning (Clean Golden)","Midday (Vibrant Sun)","Afternoon (Golden Hour)","Sunset (Natural Warmth)","Night (Cool Moonlight)","Midnight (Pitch Black & Stars)"},mode,function(v) mode=v; SetCfg("rtxTimeMode",v); if timeOn then applyTime() end end)
local ct=addToggle(section,"VV2 Enable Custom Graphics",custom,function(v) custom=v; SetCfg("rtxCustomEnabled",v); if v then applyCustom() else clearCustom() end end)
section:AddSlider("VV2 Custom Brightness",5,40,br,function(v) br=v; SetCfg("rtxBrightness",v); if custom then applyCustom() end end)
section:AddSlider("VV2 Custom Saturation",0,100,sat,function(v) sat=v; SetCfg("rtxSaturation",v); if custom then applyCustom() end end)
section:AddSlider("VV2 Custom Contrast",0,100,con,function(v) con=v; SetCfg("rtxContrast",v); if custom then applyCustom() end end)
section:AddSlider("VV2 Bloom Intensity",0,100,math.floor(bloom*100),function(v) bloom=v/100; SetCfg("rtxBloom",v); if custom then applyCustom() end end)
section:AddSlider("VV2 SunRays Intensity",0,100,math.floor(sun*100),function(v) sun=v/100; SetCfg("rtxSunRays",v); if custom then applyCustom() end end)
section:AddSlider("VV2 Reflections Intensity",0,50,math.floor(refl*10),function(v) refl=v/10; SetCfg("rtxReflections",v); if custom or rtx then Lighting.EnvironmentSpecularScale=refl end end)
env.VisualsV2Runtime.RegisterReset(function() rt:Set(false); tt:Set(false); ct:Set(false); rtx=false; timeOn=false; custom=false; clearTime(); clearCustom(); stopRTX() end)
if rtx then task.defer(applyRTX) end; if timeOn then task.defer(applyTime) end; if custom then task.defer(applyCustom) end
end)()


-- =========================================================
-- SETTINGS FILE DELETION WATCH
-- =========================================================
-- If VisualsV2_settings.json is deleted while the add-on is running,
-- immediately turn off/reset active features and recreate a blank settings file.
-- Feature toggles reset; requested timer/statistic display defaults are restored
-- when the add-on next loads its settings.
;(function()
if type(exists)~="function" then return end

env.VisualsV2ConfigWatchToken=(tonumber(env.VisualsV2ConfigWatchToken) or 0)+1
local myWatchToken=env.VisualsV2ConfigWatchToken
local sawSettingsFile=false

local ok,present=pcall(exists,CFG_FILE)
if ok and present then sawSettingsFile=true end

task.spawn(function()
    while env.VisualsV2ConfigWatchToken==myWatchToken do
        local checkOk,filePresent=pcall(exists,CFG_FILE)

        if checkOk and filePresent then
            sawSettingsFile=true
        elseif checkOk and sawSettingsFile then
            sawSettingsFile=false

            -- Clear all saved state first so a later save cannot resurrect
            -- features that were enabled before the JSON was deleted.
            ConfigData={}
            PositionData={}

            -- Disable every registered feature without writing each old state
            -- back into the config while the reset is taking place.
            configResetting=true
            for _,resetter in ipairs(env.VisualsV2Runtime.Resetters or {}) do
                pcall(resetter)
            end
            configResetting=false

            -- Recreate an empty VisualsV2 schema; the next execution seeds the
            -- declared defaults without restoring the deleted settings.
            if type(write)=="function" then
                pcall(function()
                    write(CFG_FILE,HttpService:JSONEncode({
                        version=2,
                        settings={},
                        positions={},
                    }))
                end)
                sawSettingsFile=true
            end

            pcall(function()
                shared.Notify("VisualsV2 settings reset",2)
            end)
        end

        task.wait(1)
    end
end)
end)()

-- CREDITS — FINAL SECTION
-- =========================================================

;(function()
local creditsSection=mainTab:AddSection("Credits","")

creditsSection:AddLabel("Belfor — 1306953439238164551")
creditsSection:AddLabel("mrdaniel307228 — 1306953439238164551")
creditsSection:AddLabel("SANGUINE — 1190101169184460931")
creditsSection:AddLabel("NICOLAS — 1163360113092997120")
creditsSection:AddLabel("b6o6s, A — 718910264942002277")
creditsSection:AddLabel("Gato — 1333631679570645082")
creditsSection:AddLabel("lzzzx, 187 — 586568393801596928")
creditsSection:AddLabel("arkineku — 1418738338508308691")
creditsSection:AddLabel("anya_bts — 1067515726677684324")
end)()

saveConfig()
shared.Notify("Visions V2 loaded",2)
