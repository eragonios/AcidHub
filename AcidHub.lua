-- AcidHub: single-file distribution, including automatic reconnect reload support.
-- The source below is retained in memory; no second Lua file is required.
local source=[====[
-- AcidHub: standalone Egg ESP, display name, and walk speed.
-- Requires the game's ReplicatedStorage.Client.EggState module for egg positions.
local function BuildRenderer()
-- Renderer for normalized, verified field-egg snapshots.
-- Input records: {id: string, area: string, position: Vector3, text: string}.
-- Receives field-egg snapshots from the reader below.
local Renderer = {}
local AREAS = {"Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano",
    "AbyssOcean", "Prehistoric", "Cosmic", "CherryBlossom", "TitanTemple", "Angels & Demons"}

function Renderer.new(parent)
    local self = {markers = {}, areas = {}, enabled = false, destroyed = false}
    for _, area in ipairs(AREAS) do self.areas[area] = true end
    local folder = Instance.new("Folder")
    folder.Name = "EggESPMarkers"
    folder:SetAttribute("EggUITest", true)
    folder.Parent = parent

    function self:SetEnabled(enabled)
        self.enabled = enabled == true
        for _, marker in pairs(self.markers) do
            marker.gui.Enabled = self.enabled and self.areas[marker.area] == true
        end
    end

    function self:SetAreas(areas)
        self.areas = {}
        for _, area in ipairs(areas) do self.areas[area] = true end
        self:SetEnabled(self.enabled)
    end

    -- Call only with a complete, successful snapshot. A failed read must not be
    -- passed as an empty list. Removed IDs are despawned eggs, not stale labels.
    function self:SetSnapshot(records)
        if self.destroyed then return end
        local seen = {}
        for _, record in ipairs(records) do
            assert(type(record.id) == "string" and record.id ~= "", "Egg ID must be a nonempty string")
            assert(type(record.area) == "string", "Egg area must be a string")
            assert(typeof(record.position) == "Vector3", "Egg position must be a Vector3")
            assert(type(record.text) == "string", "Egg label must be a string")
            assert(not seen[record.id], "Duplicate egg ID in snapshot")
            seen[record.id] = true
        end
        for _, record in ipairs(records) do
            local marker = self.markers[record.id]
            if not marker then
                local anchor = Instance.new("Part")
                anchor.Name = "EggMarker"
                anchor.Size = Vector3.new(0.1, 0.1, 0.1)
                anchor.Transparency = 1
                anchor.Anchored = true
                anchor.CanCollide = false
                anchor.CanTouch = false
                anchor.CanQuery = false
                anchor.CastShadow = false
                anchor.Parent = folder
                local gui = Instance.new("BillboardGui")
                gui.Name = "EggLabel"
                gui.Adornee = anchor
                gui.AlwaysOnTop = true
                gui.Size = UDim2.fromOffset(250, 44)
                gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
                gui.Parent = anchor
                local label = Instance.new("TextLabel")
                label.Size = UDim2.fromScale(1, 1)
                label.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
                label.BackgroundTransparency = 1
                label.TextColor3 = Color3.fromRGB(255, 235, 150)
                label.TextStrokeTransparency = 0.15
                label.TextSize = 14
                label.TextWrapped = false
                label.RichText = true
                label.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold)
                label.Parent = gui
                local corner=Instance.new("UICorner")
                corner.CornerRadius=UDim.new(0,5)
                corner.Parent=label
                marker = {anchor = anchor, gui = gui, label = label}
                self.markers[record.id] = marker
            end
            marker.area = record.area
            marker.anchor.Position = record.position
            marker.label.Text = record.text
            local width=game:GetService("TextService"):GetTextSize(record.plainText or record.name or "",14,Enum.Font.BuilderSansBold,Vector2.new(10000,60)).X
            local _,lines=(record.plainText or ""):gsub("\n","")
            marker.gui.Size=UDim2.fromOffset(math.max(250,math.ceil(width)+20),math.max(44,24+(lines+1)*14))
            marker.label.BackgroundTransparency=record.background and 0.3 or 1
            marker.label.TextColor3 = record.color or Color3.fromRGB(255,255,255)
            marker.gui.Enabled = self.enabled and self.areas[record.area] == true
        end
        for id, marker in pairs(self.markers) do
            if not seen[id] then marker.anchor:Destroy(); self.markers[id] = nil end
        end
    end

    function self:Destroy()
        if self.destroyed then return end
        self.destroyed = true
        folder:Destroy()
        self.markers = {}
    end
    return self
end

return Renderer

end
local function BuildRarity()
-- Species, names, rarity and colors come exclusively from the current game directory.
local Rarity={Species={},Colors={Unknown=Color3.fromRGB(255,255,255)}}
local function key(name) return tostring(name):lower():gsub("[%s%-%_]","") end
local directory=require(game:GetService("ReplicatedStorage").Data.Assets).Directory
assert(type(directory)=="table","Live pet directory unavailable")
local byCategory,byName={},{}
for category,config in pairs(directory) do
    if type(category)=="string" and type(config)=="table" then
        local name=type(config.DisplayName)=="string" and config.DisplayName~="" and config.DisplayName or category
        local value=config.Rarity
        local rarity=type(value)=="table" and (value._id or value.DisplayName or value.Name) or value
        if type(rarity)~="string" or rarity=="" then rarity="Unknown" end
        local color=type(value)=="table" and value.Color or nil
        if typeof(color)~="Color3" then color=Rarity.Colors.Unknown end
        Rarity.Colors[rarity]=color
        local entry={name=name,category=category,rarity=rarity,color=color,source="Live game asset directory"}
        Rarity.Species[category]=entry
        byCategory[key(category)]=entry
        -- Ambiguous display names are not used to guess a category.
        local k=key(name)
        if byName[k]==nil then byName[k]=entry else byName[k]=false end
    end
end
function Rarity.Resolve(category,area)
    local entry=byCategory[key(category)] or byName[key(category)]
    if entry then return entry.name,entry.rarity,entry.color,entry.source end
    return tostring(category),"Unknown",Rarity.Colors.Unknown,"No live game match"
end
return Rarity
end

local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
assert(player, "Run on the Roblox client after joining Steal an Egg.")
local function movementHumanoid(character)
    if not character then return nil end
    local named=character:FindFirstChild("Humanoid")
    if named and named:IsA("Humanoid") then return named end
    for _,child in ipairs(character:GetChildren()) do
        if child:IsA("Humanoid") and child.Name~="AcidHubOriginalHumanoid" and child.Name~="AcidHubRespawnHumanoid" then return child end
    end
end
local lastTreadmillExitJump=0
local noSlowTreadmillExit
local treadmillExitBusy=false
local function requestTreadmillExitJump(character,humanoid,allowRestore)
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if player.Character~=character or not root or not root.Anchored or not humanoid or humanoid.Health<=0 then return false end
    local plots=workspace:FindFirstChild("Plots")
    local nearTreadmill=false
    for _,plot in ipairs(plots and plots:GetChildren() or {}) do
        local belt=plot:FindFirstChild("TreadmillBottom")
        if belt and belt:IsA("BasePart") and (root.Position-belt.Position).Magnitude<10 then nearTreadmill=true; break end
    end
    if not nearTreadmill then return false end
    if allowRestore and noSlowTreadmillExit and noSlowTreadmillExit(character) then return true end
    if os.clock()-lastTreadmillExitJump<0.2 then return true end
    lastTreadmillExitJump=os.clock()
    local storage=player:FindFirstChild("AcidHubRespawnStorage")
    local original=storage and storage:FindFirstChildOfClass("Humanoid")
    if original and original.Health>0 then
        original.Jump=false
        original.Jump=true
        original:ChangeState(Enum.HumanoidStateType.Jumping)
    end
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,true)
    humanoid.Jump=true
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    return true
end
local playerGui = player:WaitForChild("PlayerGui")
local previous = playerGui:FindFirstChild("AcidHubUI")
if previous and previous:GetAttribute("AcidHubUI") then previous:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AcidHubUI"
gui:SetAttribute("AcidHubUI", true)
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local Renderer, Rarity = BuildRenderer(), BuildRarity()
local renderer = Renderer.new(workspace)
local connections = {}
local cleanupActions = {}
local closed, enabled, busy, healthy = false, false, false, false
local worker, readToken, api = nil, 0, nil
local speedLocked, targetSpeed = false, 16
local speedHumanoid, originalSpeed, lastAppliedSpeed
local baseTravelActive,approachOverride=false,{}
local function releaseSpeed(preserveApproach)
    if not preserveApproach and approachOverride.humanoid then
        pcall(function() approachOverride.humanoid.WalkSpeed=approachOverride.base end)
        approachOverride.humanoid=nil
    end
    if speedHumanoid and originalSpeed ~= nil then
        pcall(function() speedHumanoid.WalkSpeed = originalSpeed end)
    end
    speedHumanoid, originalSpeed, lastAppliedSpeed = nil, nil, nil
end
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end
local function cleanup()
    if closed then return end
    closed = true
    readToken = readToken + 1
    if worker then pcall(task.cancel, worker) end
    releaseSpeed()
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for _, action in ipairs(cleanupActions) do pcall(action) end
    renderer:Destroy()
end
connect(gui.Destroying, cleanup)

local function make(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties) do object[key] = value end
    object.Parent = parent
    return object
end
local colors = {
    panel = Color3.fromRGB(20,24,32), card = Color3.fromRGB(31,37,48),
    text = Color3.fromRGB(235,240,247), muted = Color3.fromRGB(155,170,190),
    accent = Color3.fromRGB(74,213,180),
}
local panel = make("Frame", {
    Name = "Panel", Size = UDim2.fromOffset(540, 510), Position = UDim2.fromOffset(24,60),
    BackgroundColor3 = colors.panel, BorderSizePixel = 0,
}, gui)
make("UICorner", {CornerRadius = UDim.new(0,12)}, panel)
make("UIStroke", {Color = Color3.fromRGB(58,70,87), Thickness = 1}, panel)
local header = make("Frame", {Size = UDim2.new(1,-78,0,46), BackgroundTransparency = 1, Active = true}, panel)
local function label(text, position, size, parent, muted)
    return make("TextLabel", {
        Text = text, Position = position, Size = size,
        BackgroundTransparency = 1, FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),
        TextSize = 16, TextColor3 = muted and colors.muted or colors.text,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
    }, parent)
end
label("AcidHub", UDim2.fromOffset(16,0), UDim2.new(1,-16,1,0), header).TextSize=20
local function button(text, position, size, parent)
    local control = make("TextButton", {
        Text = text, Position = position, Size = size,
        BackgroundColor3 = colors.card, TextColor3 = colors.text,
        BorderSizePixel = 0, FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold), TextSize = 16,
        AutoButtonColor = true,
    }, parent)
    make("UICorner", {CornerRadius = UDim.new(0,7)}, control)
    return control
end
local minimize = button("-", UDim2.new(1,-72,0,10), UDim2.fromOffset(26,26), panel)
local close = button("X", UDim2.new(1,-40,0,10), UDim2.fromOffset(26,26), panel)
local reopen = button("AcidHub", UDim2.new(1,-140,0,24), UDim2.fromOffset(116,34), gui)
reopen.Visible = false
connect(minimize.Activated, function() panel.Visible = false; reopen.Visible = true end)
connect(reopen.Activated, function() panel.Visible = true; reopen.Visible = false end)
connect(close.Activated, function() gui:Destroy() end)

local sidebar=make("Frame",{Name="Sidebar",Position=UDim2.fromOffset(12,54),
    Size=UDim2.new(0,130,1,-68),BackgroundTransparency=1},panel)
make("Frame",{Position=UDim2.fromOffset(148,54),Size=UDim2.new(0,1,1,-68),
    BorderSizePixel=0,BackgroundColor3=colors.card},panel)
local infoTab = button("Info", UDim2.fromOffset(0,0), UDim2.new(1,0,0,36), sidebar)
local espTab = button("ESP", UDim2.fromOffset(0,132), UDim2.new(1,0,0,36), sidebar)
local othersTab = button("Others", UDim2.fromOffset(0,88), UDim2.new(1,0,0,36), sidebar)
local autoStealTab = button("Automations", UDim2.fromOffset(0,44), UDim2.new(1,0,0,36), sidebar)
local configTab = button("Config", UDim2.fromOffset(0,220), UDim2.new(1,0,0,36), sidebar)
local debugTab=button("Debug",UDim2.fromOffset(0,264),UDim2.new(1,0,0,36),sidebar)
local miscTab=button("Misc",UDim2.fromOffset(0,176),UDim2.new(1,0,0,36),sidebar)
local pageTitle=label("Info",UDim2.fromOffset(162,50),UDim2.new(1,-176,0,34),panel)
pageTitle.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold)
pageTitle.TextSize=20
local function page(name)
    local result = make("ScrollingFrame", {Name = name, Position = UDim2.fromOffset(162,94),
        Size = UDim2.new(1,-176,1,-108), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, CanvasSize = UDim2.fromOffset(0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y}, panel)
    make("UIListLayout", {Padding = UDim.new(0,8), SortOrder = Enum.SortOrder.LayoutOrder}, result)
    return result
end
local infoPage,espPage,othersPage,automationPage=page("InfoPage"),page("ESPPage"),page("OthersPage"),page("AutomationPage")
local automationSubtabs={}
local function automationSubpage(title,index)
    local section=make("Frame",{Name=title.."Section",Size=UDim2.new(1,-6,0,36),
        BackgroundTransparency=1,BorderSizePixel=0,LayoutOrder=index},automationPage)
    local control=button(title.."  >",UDim2.new(),UDim2.new(1,0,0,36),section)
    control.TextXAlignment=Enum.TextXAlignment.Left
    make("UIPadding",{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10)},control)
    local content=make("Frame",{Name=title,Position=UDim2.fromOffset(0,42),Size=UDim2.new(1,0,0,0),
        BackgroundTransparency=1,BorderSizePixel=0,Visible=false},section)
    local layout=make("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},content)
    local function resize()
        local height=layout.AbsoluteContentSize.Y
        content.Size=UDim2.new(1,0,0,height)
        section.Size=UDim2.new(1,-6,0,content.Visible and height+42 or 36)
        control.Text=title..(content.Visible and "  v" or "  >")
        -- Enabled color is updated independently of expansion.
    end
    control.TextColor3=Color3.fromRGB(255,160,160)
    table.insert(automationSubtabs,{page=content,resize=resize,button=control,name=title,key=title=="Auto Steal" and "AutoStealEnabled" or title})
    connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"),resize)
    connect(control.Activated,function()
        local expand=not content.Visible
        for _,tab in ipairs(automationSubtabs) do
            tab.page.Visible=tab.page==content and expand
            tab.resize()
        end
    end)
    return content
end
local autoStealPage=automationSubpage("Auto Steal",1)
local autoPlacePage=automationSubpage("Auto Place Eggs",2)
local autoTreadmillPage=automationSubpage("Auto Treadmill",3)
local autoHatchPage=automationSubpage("Auto Hatch",4)
automationSubpage("Auto Fuse",5)
automationSubpage("Auto Progress",6)
automationSubpage("Auto Sell",7)
local miscPage=page("MiscPage")
local configPage=page("ConfigPage")
local debugPage=page("DebugPage")
local tabs={
    {name="Debug",control=debugTab,page=debugPage},
    {name="Config",control=configTab,page=configPage},
    {name="Info",control=infoTab,page=infoPage},
    {name="ESP",control=espTab,page=espPage},
    {name="Others",control=othersTab,page=othersPage},
    {name="Automations",control=autoStealTab,page=automationPage},
    {name="Misc",control=miscTab,page=miscPage},
}
do
    local eventsPage=page("EventsPage")
    local eventsTab=button("Events",UDim2.fromOffset(0,88),UDim2.new(1,0,0,36),sidebar)
    othersTab.Position=UDim2.fromOffset(0,132); espTab.Position=UDim2.fromOffset(0,176)
    miscTab.Position=UDim2.fromOffset(0,220); configTab.Position=UDim2.fromOffset(0,264); debugTab.Position=UDim2.fromOffset(0,308)
    table.insert(tabs,{name="Events",control=eventsTab,page=eventsPage})
    local section=make("Frame",{Name="TheRiftSection",Size=UDim2.new(1,-6,0,36),BackgroundTransparency=1},eventsPage)
    local toggle=button("The Rift  >",UDim2.new(),UDim2.new(1,0,0,36),section)
    toggle.TextXAlignment=Enum.TextXAlignment.Left
    local body=make("Frame",{Name="RiftSettings",Position=UDim2.fromOffset(0,44),Size=UDim2.new(1,0,0,0),BackgroundTransparency=1,Visible=false},section)
    local layout=make("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},body)
    local function resize() body.Size=UDim2.new(1,0,0,layout.AbsoluteContentSize.Y); section.Size=UDim2.new(1,-6,0,body.Visible and layout.AbsoluteContentSize.Y+48 or 36) end
    connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"),resize)
    connect(toggle.Activated,function()
        body.Visible=not body.Visible; toggle.Text=body.Visible and "The Rift  v" or "The Rift  >"
        resize()
    end)
end
local function selectTab(name)
    for _,tab in ipairs(tabs) do
        local selected=tab.name==name
        tab.page.Visible=selected
        tab.control.TextColor3=selected and colors.accent or colors.muted
        tab.control.BackgroundTransparency=selected and 0 or 1
    end
    pageTitle.Text=name
end
for _,tab in ipairs(tabs) do
    connect(tab.control.Activated,function() selectTab(tab.name) end)
end
selectTab("Info")
local rowNumber = 0
local lastRows={}
local function row(parent, height)
    rowNumber = rowNumber + 1
    local result = make("Frame", {Size = UDim2.new(1,-6,0,height), BackgroundColor3 = colors.card,
        BorderSizePixel = 0, LayoutOrder = rowNumber}, parent)
    make("UICorner", {CornerRadius = UDim.new(0,8)}, result)
    lastRows[parent]=result
    return result
end
-- All future switches inherit persistence; optional descriptions follow Details.
local settingsBindings={}
local function copySetting(value)
    if type(value)~="table" then return value end
    local result={}
    for key,child in pairs(value) do result[key]=copySetting(child) end
    return result
end
local function registerSetting(key,default,get,set,validate)
    settingsBindings[key]={default=copySetting(default),get=get,set=set,validate=validate}
end
local function isBoolean(value) return type(value)=="boolean" end
local detailsEnabled=false
local detailFrames={}
local function detailRow(parent,height)
    local owner=assert(lastRows[parent],"Description requires a control row")
    local normalHeight=owner.Size.Y.Offset
    local frame=make("Frame",{Name="Details",Position=UDim2.new(1,8,0,0),
        Size=UDim2.new(0,272,1,0),BackgroundColor3=colors.card,
        BorderSizePixel=0,Visible=detailsEnabled},owner)
    make("UICorner",{CornerRadius=UDim.new(0,8)},frame)
    local function update(value)
        frame.Visible=value
        owner.Size=UDim2.new(1,value and -286 or -6,0,value and math.max(normalHeight,height) or normalHeight)
    end
    table.insert(detailFrames,update)
    update(detailsEnabled)
    return frame
end
local function switch(parent, title, initial, callback, description, settingKey)
    local frame = row(parent,42)
    label(title,UDim2.fromOffset(10,0),UDim2.new(1,-88,1,0),frame)
    local control = button(initial and "ON" or "OFF",UDim2.new(1,-74,0,6),UDim2.fromOffset(64,30),frame)
    control.Name = title
    local value = initial
    control.TextColor3 = value and colors.accent or colors.muted
    local function setValue(desired)
        if not isBoolean(desired) then return false end
        if desired~=value and callback(desired)==false then return false end
        value=desired
        control.Text=value and "ON" or "OFF"
        control.TextColor3=value and colors.accent or colors.muted
        return true
    end
    connect(control.Activated,function() setValue(not value) end)
    registerSetting(settingKey or title,initial,function() return value end,setValue,isBoolean)
    if description then
        label(description,UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(parent,76),true).TextSize=14
    end
    return control
end
local automationFlow={phase="idle",steal=false,place=false,placing=false,collecting=false,
    pendingDay=false,epoch=0,night=nil,nextReset=nil,cycleReady=false,placementRound=0}
local taskMessages={}
local currentTaskRow=row(infoPage,190)
currentTaskRow.LayoutOrder=2
label("Current Task",UDim2.fromOffset(12,6),UDim2.new(1,-24,0,26),currentTaskRow).TextSize=20
local currentTaskLabel=label("All automations OFF",UDim2.fromOffset(12,38),UDim2.new(1,-24,1,-46),currentTaskRow,true)
currentTaskLabel.TextYAlignment=Enum.TextYAlignment.Top
currentTaskLabel.TextSize=14
currentTaskLabel.Size=UDim2.new(1,-24,0,0)
currentTaskLabel.AutomaticSize=Enum.AutomaticSize.Y
connect(currentTaskLabel:GetPropertyChangedSignal("TextBounds"),function()
    currentTaskRow.Size=UDim2.new(1,-6,0,math.max(100,currentTaskLabel.TextBounds.Y+52))
end)
local function renderAutomationStatus()
    local lines={"Sequence: "..automationFlow.phase..(taskMessages.Sequence and (" — "..taskMessages.Sequence) or "")}
    local any=false
    for _,section in ipairs(automationSubtabs) do
        local binding=settingsBindings[section.key]
        local enabled=binding and binding.get()==true
        if section.key=="Auto Hatch" and settingsBindings["Auto Equip Best"] and settingsBindings["Auto Equip Best"].get() then enabled=true end
        if section.key=="Auto Sell" then enabled=(settingsBindings["Auto Sell Pets"] and settingsBindings["Auto Sell Pets"].get()) or (settingsBindings["Auto Sell Eggs"] and settingsBindings["Auto Sell Eggs"].get()) end
        if section.key=="Auto Progress" then
            for _,key in ipairs({"Auto Buy Trail","Auto Upgrade Base","Auto Upgrade Treadmill","Auto Claim"}) do if settingsBindings[key] and settingsBindings[key].get() then enabled=true end end
        end
        section.button.TextColor3=enabled and Color3.fromRGB(160,240,180) or Color3.fromRGB(255,160,160)
        if enabled then
            any=true
            table.insert(lines,section.name..": "..(taskMessages[section.name] or "Waiting"))
        end
    end
    if settingsBindings["Auto Equip Best"] and settingsBindings["Auto Equip Best"].get() then
        table.insert(lines,"Auto Equip Best: "..(taskMessages["Auto Equip Best"] or "Waiting for a hatch"))
    end
    if automationFlow.rift and automationFlow.rift.enabled then any=true; table.insert(lines,"The Rift: "..(taskMessages["The Rift"] or "Waiting")) end
    currentTaskLabel.Text=automationFlow.bossPauseRequested and "Automations paused for boss battle" or (any and table.concat(lines,"\n") or "All automations OFF")
end
local function reportTask(name,message)
    taskMessages[name]=tostring(message)
    renderAutomationStatus()
end
local function flowPhase(phase,reason)
    -- Collection -> Rift -> Fuse -> sequence sales -> placement -> idle training.
    -- Advance from the current stage; idle after placement must not restart it.
    local order={"rift","fusing","selling","placing"}
    local previous=automationFlow.phase
    local advance=phase=="processing" and 0 or nil
    if phase=="idle" and reason~="Stopped all automations" then
        for index,name in ipairs(order) do if previous==name and index<#order then advance=index; break end end
    end
    if advance~=nil then
        phase="idle"
        for index=advance+1,#order do
            local nextPhase=order[index]
            local enabled=nextPhase=="rift" and automationFlow.rift and automationFlow.rift.enabled
                or nextPhase=="fusing" and automationFlow.fuse
                or nextPhase=="selling" and automationFlow.sellSequence and automationFlow.sellSequence()
                or nextPhase=="placing" and automationFlow.place
            if enabled then phase=nextPhase; break end
        end
    end
    if phase=="placing" and previous~="placing" then automationFlow.placementRound=automationFlow.placementRound+1 end
    if phase~="idle" and automationFlow.stopTreadmill then automationFlow.stopTreadmill() end
    automationFlow.phase=phase
    taskMessages["Sequence"]=reason
    renderAutomationStatus()
end
local globalRow=row(automationPage,42)
globalRow.LayoutOrder=0
local startAll=button("Start All",UDim2.fromOffset(4,4),UDim2.new(0.5,-6,1,-8),globalRow)
local stopAll=button("Stop All",UDim2.new(0.5,2,0,4),UDim2.new(0.5,-6,1,-8),globalRow)
startAll.TextColor3=Color3.fromRGB(160,240,180)
stopAll.TextColor3=Color3.fromRGB(255,160,160)
local function setAllAutomations(value)
    local failures={}
    if settingsBindings["Auto Equip Best"] then
        local ok,result=pcall(settingsBindings["Auto Equip Best"].set,value)
        if not ok or result~=true then table.insert(failures,"Auto Equip Best") end
    end
    for _,section in ipairs(automationSubtabs) do
        local binding=settingsBindings[section.key]
        if binding then
            local ok,result=pcall(binding.set,value)
            if not ok or result~=true then table.insert(failures,section.name) end
        end
    end
    for _,key in ipairs({"Auto Buy Trail","Auto Upgrade Base","Auto Upgrade Treadmill","Auto Claim","Auto Sell Pets","Auto Sell Eggs"}) do
        if settingsBindings[key] then
            local ok,result=pcall(settingsBindings[key].set,value)
            if not ok or result~=true then failures[#failures+1]=key end
        end
    end
    if not value then flowPhase("idle","Stopped all automations") end
    renderAutomationStatus()
    if #failures>0 then currentTaskLabel.Text=currentTaskLabel.Text.."\nCould not change: "..table.concat(failures,", ") end
end
connect(startAll.Activated,function() setAllAutomations(true) end)
connect(stopAll.Activated,function() setAllAutomations(false) end)
task.spawn(function()
    while not closed do renderAutomationStatus(); task.wait(0.5) end
end)
local function flowPlace(reason)
    flowPhase("processing",reason)
end
local function flowNewDay()
    automationFlow.epoch=automationFlow.epoch+1
    if not automationFlow.steal then return end
    automationFlow.pendingDay=true
    if automationFlow.stopTreadmill then automationFlow.stopTreadmill() end
    if not automationFlow.collecting then flowPhase("preparing","Day started: check location and wait 4 seconds") end
end
-- Persistent JSONL audit records use live game rarity, never the static display catalog.
do
(function()
    local audit={error=nil,queue={},files={},enabled=false,mode="Full"}
    automationFlow.audit=audit
    local http=game:GetService("HttpService")
    local rarityNames={"Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret","Eternal","Divine"}
    local prefix="AcidHub_"
    if type(makefolder)=="function" then
        local ok=pcall(function() if type(isfolder)~="function" or not isfolder("AcidHub_Logs") then makefolder("AcidHub_Logs") end end)
        if ok then prefix="AcidHub_Logs/" end
    end
    local session=tostring(os.time()).."_"..tostring(game.JobId):sub(1,8)
    local function clean(value,depth,seen)
        local kind=typeof(value)
        if kind=="nil" or kind=="boolean" or kind=="string" then return value end
        if kind=="number" then return value==value and math.abs(value)<math.huge and value or tostring(value) end
        if kind~="table" then return tostring(value) end
        if depth>6 or seen[value] then return "[nested]" end
        seen[value]=true; local out={}; local count=0
        for k,v in pairs(value) do count=count+1; if count>150 then out._truncated=true; break end; out[tostring(k)]=clean(v,depth+1,seen) end
        seen[value]=nil; return out
    end
    function audit.rarity(category)
        local ok,rarity=pcall(function()
            local config=require(game:GetService("ReplicatedStorage").Data.Assets).Directory[category]
            local value=config and config.Rarity
            if type(value)=="table" then return {value._id or "",value.DisplayName or "",value.Name or ""} end
            return {value}
        end)
        if ok and type(rarity)=="table" then
            for _,candidate in ipairs(rarity) do
                if type(candidate)=="string" then
                    for rank,name in ipairs(rarityNames) do if candidate:lower()==name:lower() then return name,rank end end
                end
            end
        end
        return "Unknown",nil
    end
    function audit.inField(position)
        local objects=workspace:FindFirstChild("__OBJECTS")
        local areas=objects and objects:FindFirstChild("Areas")
        local line=areas and areas:FindFirstChild("SeparationLine")
        assert(line and line:IsA("BasePart"),"Gameplay boundary unavailable")
        return require(game:GetService("ReplicatedStorage").Shared.Util.GuardAreaGeometry).IsPastLine(line,position)
    end
    function audit.values(record)
        local category=record and (record.Category or record.AssetCategory)
        local rarity,rank=audit.rarity(category)
        return {category=category,rarity=rarity,rarityRank=rank,raw=record}
    end
    function audit.emit(channel,event,data)
        if not audit.enabled then return end
        if audit.mode=="Simple" then
            local values,success
            if channel=="Spawns" then
                if event~="first_observed" or not data.values or not data.values.rarityRank or data.values.rarityRank<8 then return end
                values=data.values
            elseif channel=="AutoSteal" then
                if event=="attempt_succeeded" then values=data.values; success=true
                elseif event=="attempt_not_confirmed" then values=data.attempt and data.attempt.values; success=false
                else return end
            elseif channel=="AutoFuse" then
                if event=="load_requested" then audit.simpleFuse=data.values; return end
                if event=="fuse_requested" then audit.simpleFuse=data.pets and data.pets[1] and data.pets[1].values; return end
                if event=="finish_result" or ((event=="load_result" or event=="fuse_result") and data.accepted~=true) then
                    values=audit.simpleFuse; success=data.accepted==true; audit.simpleFuse=nil
                elseif event=="status" and tostring(data.message):sub(1,7)=="Paused:" then
                    values=audit.simpleFuse; success=false; audit.simpleFuse=nil
                else return end
            end
            if not values then return end
            local fields={os.date("%Y-%m-%d %H:%M:%S"),values.category or "Unknown",values.rarity or "Unknown"}
            if channel=="AutoSteal" then
                local raw=values.raw or {}; local mutations={}
                local list=raw.Mutations or raw.AssetMutations
                if type(list)=="table" then for _,v in pairs(list) do mutations[#mutations+1]=tostring(v) end
                elseif type(list)=="string" and list~="" then mutations[1]=list end
                if #mutations==0 then local base=raw.BaseMutation or raw.AssetBaseMutation; if base and base~="None" and base~="" then mutations[1]=tostring(base) end end
                fields[#fields+1]=#mutations>0 and table.concat(mutations," + ") or "Normal"
                fields[#fields+1]=raw.AssetScale or raw.Scale or "Unknown"
                fields[#fields+1]=success and "Stolen" or "Not stolen"
            elseif channel=="AutoFuse" then fields[#fields+1]=success and "Succeeded" or "Failed" end
            for i,v in ipairs(fields) do fields[i]='"'..tostring(v):gsub('"','""'):gsub("[\r\n]"," ")..'"' end
            local file=(prefix=="AcidHub_" and "" or prefix).."AcidHub_"..channel.."_Simple.txt"
            audit.queue[file]=(audit.queue[file] or "")..table.concat(fields,",").."\n"
            audit.files[channel]=file
            return
        end
        local ok,encoded=pcall(function()
            return http:JSONEncode(clean({utc=os.date("!%Y-%m-%dT%H:%M:%SZ"),clock=os.clock(),session=session,
                gameDayEnd=automationFlow.nextReset,daySequence=automationFlow.epoch,placeId=game.PlaceId,serverId=game.JobId,
                event=event,data=data},0,{})).."\n"
        end)
        if not ok then audit.error=tostring(encoded); return end
        local file=prefix..os.date("!%Y-%m-%d").."_"..session.."_"..channel..".jsonl"
        audit.queue[file]=(audit.queue[file] or "")..encoded
        audit.files[channel]=file
    end
    function audit.flush()
        for file,data in pairs(audit.queue) do
            local ok,err=pcall(function()
                if type(appendfile)=="function" then appendfile(file,data)
                else
                    assert(type(writefile)=="function" and type(readfile)=="function","Executor file functions unavailable")
                    local old=""
                    if type(isfile)=="function" then
                        if isfile(file) then old=readfile(file) end
                    else
                        local readOK,existing=pcall(readfile,file)
                        if readOK then old=existing end
                    end
                    writefile(file,old..data)
                end
            end)
            if ok then audit.queue[file]=nil; audit.written=audit.written or {}; audit.written[file]=true
            else audit.error=tostring(err) end
        end
    end
    switch(miscPage,"Logging",false,function(value)
        audit.flush(); audit.enabled=value; audit.simpleFuse=nil
        if value then audit.emit("AutoSteal","logging_enabled",{}); audit.emit("AutoFuse","logging_enabled",{}) end
    end,"Write logs to AcidHub_Logs in the executor workspace. Simple logs append to three fixed AcidHub_<channel>_Simple.txt files across reloads and use local time; egg size is its internal scale multiplier. Full mode preserves detailed JSONL records and Secret+ spawn observations.")
    local modeButton=button("Logging Mode: Full",UDim2.new(),UDim2.new(1,0,1,0),row(miscPage,38))
    local function setMode(value)
        audit.flush(); audit.mode=value; audit.simpleFuse=nil
        modeButton.Text="Logging Mode: "..value
        return true
    end
    connect(modeButton.Activated,function() setMode(audit.mode=="Full" and "Simple" or "Full") end)
    registerSetting("LoggingMode","Full",function() return audit.mode end,setMode,function(v) return v=="Full" or v=="Simple" end)
    task.spawn(function()
        while not closed do
            audit.flush()
            if audit.error then warn("AcidHub logging: "..audit.error); audit.error=nil end
            task.wait(1)
        end
    end)
    task.spawn(function()
        local seen,day={},nil
        while not closed do
            local ok,err=pcall(function()
                if not audit.enabled then seen={}; day=nil; return end
                if not automationFlow.cycleReady then return end
                if day~=automationFlow.nextReset then
                    day=automationFlow.nextReset; seen={}; audit.emit("Spawns","day_observed",{dayEnd=day})
                end
                local snapshot=require(game:GetService("ReplicatedStorage").Client.EggState).ReadFieldEggs()
                assert(snapshot and type(snapshot.Records)=="table","Field snapshot unavailable")
                for _,record in pairs(snapshot.Records) do
                    if record.Uid and not seen[record.Uid] then
                        local values=audit.values(record)
                        if values.rarityRank then
                            seen[record.Uid]=true
                            if values.rarityRank>=8 then audit.emit("Spawns","first_observed",{uid=record.Uid,values=values}) end
                        end
                    end
                end
            end)
            if not ok then audit.error="Spawn scan: "..tostring(err) end
            task.wait(1)
        end
    end)
    table.insert(cleanupActions,function() audit.emit("AutoSteal","session_closed",{}); audit.emit("AutoFuse","session_closed",{}); audit.flush() end)
end)()
end

local function readAutomationDay()
    local cycle=require(game:GetService("ReplicatedStorage").Shared.Util.AreaEggCycle)
    local now=workspace:GetServerTimeNow()
    local night=cycle.IsNightPhase(now)
    local nextReset=cycle.NextResetTime(now)
    assert(type(night)=="boolean" and type(nextReset)=="number","Day/night data unavailable")
    local dawn=automationFlow.cycleReady and not night and
        (automationFlow.night or (automationFlow.nextReset and now>=automationFlow.nextReset))
    automationFlow.night=night; automationFlow.nextReset=nextReset; automationFlow.cycleReady=true
    if dawn then flowNewDay() end
    return night
end
task.spawn(function()
    while not closed do
        local ok=pcall(readAutomationDay)
        if not ok then automationFlow.cycleReady=false end
        task.wait(0.5)
    end
end)
local info = row(infoPage,334)
info.LayoutOrder=1
label(player.DisplayName,UDim2.fromOffset(12,8),UDim2.new(1,-24,0,24),info).TextSize=20
local gameNameLabel=label("Game: loading...",UDim2.fromOffset(12,40),UDim2.new(1,-24,0,24),info)
label("Server Ping: ...",UDim2.fromOffset(12,72),UDim2.new(1,-24,0,24),info,true).Name="ServerPing"
local speedLabel=label("Walk speed: ...",UDim2.fromOffset(12,104),UDim2.new(1,-24,0,24),info,true)
local currentSpeedLabel=label("Current speed: ...",UDim2.fromOffset(12,136),UDim2.new(1,-24,0,24),info,true)
local positionLabel=label("Player position XYZ: ...",UDim2.fromOffset(12,168),UDim2.new(1,-24,0,24),info,true)
positionLabel.TextSize=14
local plotInfo=label("Base plot: loading...",UDim2.fromOffset(12,232),UDim2.new(1,-24,0,24),info,true)
do (function()
    local moneyLabel=label("Current Money: ...",UDim2.fromOffset(12,200),UDim2.new(1,-24,0,24),info,true)
    moneyLabel.TextSize=14
    local inventoryLabel=label("Pets & Eggs: ?/?",UDim2.fromOffset(12,264),UDim2.new(1,-24,0,24),info,true)
    local growingLabel=label("Growing Eggs: ?",UDim2.fromOffset(12,296),UDim2.new(1,-24,0,24),info,true)
    task.spawn(function()
        while not closed do
            local moneyOK,money=pcall(function()
                local save=require(game:GetService("ReplicatedStorage").Shared.Save).Get()
                assert(save and type(save.Money)=="number","Money unavailable")
                return string.format("%.0f",save.Money):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
            end)
            moneyLabel.Text="Current Money: "..(moneyOK and money or "unavailable")
            local ok,total,placed,maximum=pcall(function()
                local storage=game:GetService("ReplicatedStorage")
                local save=assert(require(storage.Shared.Save).Get(),"Save unavailable")
                assert(type(save.Inventory)=="table","Inventory unavailable")
                local ownerEggs=require(storage.Client.EggState).ReadOwnerEggs(player.UserId)
                assert(type(ownerEggs)=="table","Egg records unavailable")
                local pets,unplaced,growing=0,0,0
                for _,item in pairs(save.Inventory) do if type(item)=="table" then pets=pets+1 end end
                for _,egg in pairs(ownerEggs) do
                    if egg.Placement~=nil then growing=growing+1 else unplaced=unplaced+1 end
                end
                return pets+unplaced,growing,require(storage.Shared.Globals.Constants).BACKPACK.LIMIT
            end)
            inventoryLabel.Text="Pets & Eggs: "..tostring(ok and total or "?").."/"..tostring(ok and maximum or "?")
            growingLabel.Text="Growing Eggs: "..tostring(ok and placed or "?")
            task.wait(1)
        end
    end)
end)() end

do
    local originalZoom
    local function restoreZoom()
        if originalZoom~=nil then
            player.CameraMaxZoomDistance=originalZoom
            originalZoom=nil
        end
    end
    switch(miscPage,"Max Zoom",false,function(value)
        if value then
            if originalZoom==nil then originalZoom=player.CameraMaxZoomDistance end
            player.CameraMaxZoomDistance=originalZoom*2
        else restoreZoom() end
    end,"Double the maximum camera zoom-out distance. OFF restores the previous limit.")
    table.insert(cleanupActions,restoreZoom)
end

do
    local currentServer=row(miscPage,78)
    label("Current server ID",UDim2.fromOffset(10,5),UDim2.new(1,-20,0,22),currentServer,true)
    make("TextBox",{Name="CurrentServerId",Text=game.JobId~="" and game.JobId or "Unavailable (local/Studio session)",
        Position=UDim2.fromOffset(10,30),Size=UDim2.new(1,-126,0,38),BackgroundTransparency=1,
        TextColor3=colors.text,TextSize=14,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextWrapped=true,
        TextEditable=false,ClearTextOnFocus=false,TextXAlignment=Enum.TextXAlignment.Left},currentServer)
    local reconnect=button("Reconnect",UDim2.new(1,-112,0,30),UDim2.fromOffset(102,36),currentServer)
    reconnect.TextSize=16
    local serverInfo=row(miscPage,120)
    label("Join another server",UDim2.fromOffset(10,5),UDim2.new(1,-20,0,22),serverInfo,true)
    local serverBox=make("TextBox",{Name="ServerId",Text="",
        PlaceholderText="Paste server ID",Position=UDim2.fromOffset(10,30),Size=UDim2.new(1,-98,0,36),
        BackgroundColor3=colors.panel,BorderSizePixel=0,TextColor3=colors.text,TextSize=14,
        FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextWrapped=true,TextEditable=true,ClearTextOnFocus=false},serverInfo)
    make("UICorner",{CornerRadius=UDim.new(0,6)},serverBox)
    local join=button("Join",UDim2.new(1,-78,0,30),UDim2.fromOffset(68,36),serverInfo)
    local feedback=label("Paste a server ID for this place, then press Join.",UDim2.fromOffset(10,72),UDim2.new(1,-20,0,40),serverInfo,true)
    feedback.TextSize=14
    local teleport=game:GetService("TeleportService")
    local joining=false
    local autoReconnect,autoExecute=false,false
    local reconnectAttempt,nextReconnect,joinDeadline=0,0,0
    local queued=false
    local leaving=false
    local gateFile="AcidHub_AutoExecute.enabled"
    if type(writefile)=="function" then pcall(writefile,gateFile,"false") end
    local function queueFunction()
        return queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
    end
    local function reloadSource()
        local env=type(getgenv)=="function" and getgenv() or _G
        if type(env.AcidHubReloadSource)=="string" then return env.AcidHubReloadSource end
        if type(readfile)=="function" then
            local ok,source=pcall(readfile,"AcidHub.lua")
            if ok and type(source)=="string" and source:find("local function BuildRenderer()",1,true) then return source end
        end
    end
    local function prepareExecute()
        if not autoExecute or queued then return true end
        local source=reloadSource()
        local queue=queueFunction()
        if not source or type(queue)~="function" then return false,"Run the updated AcidHub.lua; teleport queuing must be supported by your executor." end
        local payload="local ok,on=pcall(readfile,"..string.format("%q",gateFile).."); if not ok or on~='true' then return end; "
            .."repeat task.wait() until game:IsLoaded(); local source="..string.format("%q",source)
            .."; local env=type(getgenv)==\"function\" and getgenv() or _G; env.AcidHubReloadSource=source; local run,err=loadstring(source); if not run then error(err) end; run()"
        local ok,err=pcall(queue,payload)
        if ok then queued=true end
        return ok,tostring(err)
    end
    switch(miscPage,"Auto Reconnect",false,function(value)
        autoReconnect=value; reconnectAttempt=0; nextReconnect=0
        feedback.Text=value and "Auto Reconnect ON; waits for a disconnect, then retries up to five times." or "Auto Reconnect OFF."
    end,"Reconnect after a disconnect. Tries this server first, then another server in this place. Stops after five failed attempts.")
    switch(miscPage,"Auto Execute Script",false,function(value)
        if value and (type(queueFunction())~="function" or type(writefile)~="function" or type(readfile)~="function" or not reloadSource()) then
            feedback.Text="Auto Execute unavailable. Run the updated AcidHub.lua with an executor supporting queue_on_teleport, readfile and writefile."
            return false
        end
        if type(writefile)=="function" then
            local ok,err=pcall(writefile,gateFile,value and "true" or "false")
            if not ok then feedback.Text="Auto Execute setting failed: "..tostring(err); return false end
        end
        autoExecute=value
        feedback.Text=value and "Auto Execute ON for reconnects and server joins. Save settings to keep it enabled next load." or "Auto Execute OFF."
    end,"Reload AcidHub after reconnecting or joining another server. Use the bundled local launcher. Requires executor teleport queuing. Save settings to retain your switches.")
    pcall(function()
        connect(player.OnTeleport,function(state)
            if state==Enum.TeleportState.Started or state==Enum.TeleportState.InProgress then
                leaving=true
                local ok,err=prepareExecute()
                if not ok then feedback.Text="Auto Execute failed: "..tostring(err) end
            end
        end)
    end)
    local function disconnected()
        local message=""
        pcall(function() message=game:GetService("GuiService"):GetErrorMessage() end)
        if message=="" then
            pcall(function()
                local prompts=game:GetService("CoreGui"):FindFirstChild("RobloxPromptGui")
                local overlay=prompts and prompts:FindFirstChild("promptOverlay")
                local prompt=overlay and overlay:FindFirstChild("ErrorPrompt")
                if prompt and prompt.Visible then
                    for _,item in ipairs(prompt:GetDescendants()) do
                        if item:IsA("TextLabel") then message=message.." "..item.Text end
                    end
                end
            end)
        end
        message=tostring(message):lower()
        return message:find("disconnected",1,true) or message:find("lost connection",1,true)
            or message:find("kicked",1,true) or message:find("shut down",1,true)
            or message:find("error code: 277",1,true) or message:find("error code: 279",1,true)
    end
    local function failed(message)
        leaving=false
        joining=false; join.Text="Join"; reconnect.Text="Reconnect"; feedback.Text=message
    end
    connect(teleport.TeleportInitFailed,function(who,result,message)
        if who==player and joining then failed("Join failed: "..tostring(message)) end
    end)
    connect(reconnect.Activated,function()
        if joining then return end
        if not game.JobId or game.JobId=="" then feedback.Text="Current server ID unavailable."; return end
        joining=true; reconnect.Text="Connecting"; feedback.Text="Reconnecting to the current server..."
        joinDeadline=os.clock()+30
        local queuedOK,queueError=prepareExecute()
        if not queuedOK then failed("Auto Execute failed: "..tostring(queueError)); return end
        local ok,err=pcall(function() teleport:TeleportToPlaceInstance(game.PlaceId,game.JobId,player) end)
        if not ok and not closed then failed("Reconnect failed: "..tostring(err)) end
    end)
    connect(join.Activated,function()
        if joining then return end
        local serverId=serverBox.Text:match("^%s*(.-)%s*$")
        if serverId=="" then feedback.Text="Enter a server ID first."; return end
        if serverId==game.JobId then feedback.Text="You are already in this server."; return end
        serverBox.Text=serverId
        joining=true; join.Text="Joining"; feedback.Text="Connecting to the entered server..."
        joinDeadline=os.clock()+30
        local queuedOK,queueError=prepareExecute()
        if not queuedOK then failed("Auto Execute failed: "..tostring(queueError)); return end
        local ok,err=pcall(function() teleport:TeleportToPlaceInstance(game.PlaceId,serverId,player) end)
        if not ok and not closed then failed("Join failed: "..tostring(err)) end
    end)
    task.spawn(function()
        while not closed do
            if joining and os.clock()>=joinDeadline then failed("Join timed out.") end
            if autoReconnect and not joining and reconnectAttempt<5 and os.clock()>=nextReconnect and disconnected() then
                reconnectAttempt=reconnectAttempt+1
                nextReconnect=os.clock()+math.min(30,3*2^(reconnectAttempt-1))
                joining=true; joinDeadline=os.clock()+30
                feedback.Text="Auto Reconnect attempt "..reconnectAttempt.."/5"
                local ok,err=prepareExecute()
                if ok then
                    ok,err=pcall(function()
                        if reconnectAttempt==1 and game.JobId~="" then teleport:TeleportToPlaceInstance(game.PlaceId,game.JobId,player)
                        else teleport:Teleport(game.PlaceId,player) end
                    end)
                end
                if not ok then failed("Auto Reconnect failed: "..tostring(err)) end
            end
            task.wait(1)
        end
    end)
    table.insert(cleanupActions,function()
        autoReconnect=false; autoExecute=false
        if not leaving and type(writefile)=="function" then pcall(writefile,gateFile,"false") end
    end)
end
task.spawn(function()
    local ok,product=pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    end)
    if closed then return end
    gameNameLabel.Text="Game: "..(ok and type(product)=="table" and type(product.Name)=="string" and product.Name or "name unavailable")
end)
local speedRow = row(othersPage,116)
label("Movement speed (studs/s)",UDim2.fromOffset(10,4),UDim2.new(1,-20,0,25),speedRow,true)
local speedBox=make("TextBox",{Name="TargetSpeed",Position=UDim2.fromOffset(10,34),Size=UDim2.new(1,-106,0,32),
    Text="Loading...",TextEditable=false,ClearTextOnFocus=false,PlaceholderText="0–1000",BackgroundColor3=colors.panel,
    TextColor3=colors.text,TextSize=14,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),BorderSizePixel=0},speedRow)
make("UICorner",{CornerRadius=UDim.new(0,6)},speedBox)
local speedToggle=button("Edit",UDim2.new(1,-86,0,34),UDim2.fromOffset(76,32),speedRow)
local gameSpeedButton=button("Using Game Speed",UDim2.fromOffset(10,74),UDim2.new(1,-20,0,32),speedRow)
local speedStatus=label("Live WalkSpeed. Edit and Apply to override it for all movement. Use Game Speed removes the override.",
    UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(othersPage,100),true)
speedStatus.TextSize=14
local speedEditing=false
local function validateSpeed()
    local value=tonumber(speedBox.Text)
    if not value or value~=value or value<0 or value>1000 then
        speedStatus.Text="Enter a number from 0 to 1000."
        return false
    end
    return true
end
local function refreshSpeedDisplay()
    speedBox.TextEditable=speedEditing
    speedToggle.Text=speedEditing and "Apply" or "Edit"
    gameSpeedButton.Text=(speedLocked or speedEditing) and "Use Game Speed" or "Using Game Speed"
    gameSpeedButton.TextColor3=speedLocked and colors.accent or colors.muted
    if not speedEditing then
        local humanoid=movementHumanoid(player.Character)
        speedBox.Text=speedLocked and tostring(targetSpeed) or (humanoid and string.format("%.2f",humanoid.WalkSpeed) or "Loading...")
        speedStatus.Text=speedLocked and ("Custom speed: "..targetSpeed.." studs/s for all movement.") or "Live game WalkSpeed. Click Edit to choose a custom speed."
    end
end
local function applyEffectiveSpeed(humanoid)
    local temporary=humanoid and approachOverride.humanoid==humanoid
    if not speedLocked and not temporary then return end
    local effectiveTarget=temporary and approachOverride.speed or targetSpeed
    if humanoid~=speedHumanoid then
        releaseSpeed(true)
        speedHumanoid=humanoid
        originalSpeed=temporary and approachOverride.base or (humanoid and humanoid.WalkSpeed or nil)
    end
    if humanoid and humanoid.Health>0 and humanoid.WalkSpeed~=effectiveTarget then
        -- Remember game updates received during an override for Use Game Speed.
        -- Changes observed during a temporary boost may be the game's echo of
        -- that boost. Never adopt them as the unboosted restoration speed.
        if not temporary and humanoid.WalkSpeed~=lastAppliedSpeed then originalSpeed=humanoid.WalkSpeed end
        humanoid.WalkSpeed=effectiveTarget
    end
    if humanoid then lastAppliedSpeed=effectiveTarget end
end
local function setSpeedEnabled(desired)
    speedLocked=desired
    speedEditing=false
    if not desired then releaseSpeed() else applyEffectiveSpeed(movementHumanoid(player.Character)) end
    refreshSpeedDisplay()
    return true
end
connect(speedToggle.Activated,function()
    if not speedEditing then
        speedEditing=true
        refreshSpeedDisplay()
        speedBox:CaptureFocus()
    elseif validateSpeed() then
        targetSpeed=tonumber(speedBox.Text)
        setSpeedEnabled(true)
    end
end)
connect(gameSpeedButton.Activated,function() setSpeedEnabled(false) end)
registerSetting("TargetSpeed",16,function() return targetSpeed end,function(value)
    targetSpeed=value; refreshSpeedDisplay(); return true
end,function(value) return type(value)=="number" and value==value and value>=0 and value<=1000 end)
registerSetting("KeepSpeed",false,function() return speedLocked end,setSpeedEnabled,isBoolean)
local speedElapsed=0
connect(game:GetService("RunService").Heartbeat,function(delta)
    speedElapsed=speedElapsed+delta
    if speedElapsed<0.1 then return end
    speedElapsed=0
    applyEffectiveSpeed(movementHumanoid(player.Character))
    refreshSpeedDisplay()
end)
refreshSpeedDisplay()

-- No Slow retains the working Animator and grounded jump handling.
do
    local noSlowRow=row(othersPage,42)
    local noSlowButton=button("No Slow",UDim2.fromOffset(6,6),UDim2.new(1,-12,0,30),noSlowRow)
    noSlowButton.Name="NoSlow"
    local noSlowStatus=label("ON enables No Slow and reapplies it after respawn. OFF restores the original Humanoid.",UDim2.fromOffset(10,6),UDim2.new(1,-20,1,-12),detailRow(othersPage,76),true)
    noSlowStatus.TextSize=14
    local replacementForInput,replacementCharacter
    local noSlowDesired=false
    local disableNoSlow
    local animationReport="No Slow animation diagnostics: not started"
    local animationStatus=label(animationReport,UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,140),true)
    local copyAnimation=button("Copy No Slow Animation Report",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    connect(copyAnimation.Activated,function()
        if type(setclipboard)=="function" then pcall(setclipboard,animationReport) end
    end)
    local function adoptCharacter(character)
        replacementForInput,replacementCharacter=nil,nil
        if character and (character:GetAttribute("AcidHubNoSlow") or character:GetAttribute("AcidHubHumanoidTest")) then
            replacementForInput=movementHumanoid(character)
            replacementCharacter=character
        end
        noSlowButton.Text=replacementForInput and "No Slow: ON" or (noSlowDesired and "No Slow: waiting for respawn" or "No Slow: OFF")
        noSlowButton.TextColor3=replacementForInput and colors.accent or colors.text
        noSlowStatus.Text=replacementForInput and "No Slow active; reapplies after respawn. Keep AcidHub open for movement and animations." or "Enable while empty-handed. No Slow will reapply after respawn while AcidHub stays open."
    end
    adoptCharacter(player.Character)
    connect(player.CharacterAdded,adoptCharacter)
    local lastJumpRequest=0
    local function requestReplacementJump()
        local humanoid=replacementForInput
        if not humanoid or player.Character~=replacementCharacter or humanoid.Parent~=replacementCharacter then return end
        if Input:GetFocusedTextBox() then return end
        local now=os.clock()
        if now-lastJumpRequest<0.2 then return end
        lastJumpRequest=now
        if requestTreadmillExitJump(replacementCharacter,humanoid,true) then
            noSlowStatus.Text="Treadmill exit jump requested."
            return
        end
        if humanoid.Health<=0 or humanoid.Sit or humanoid.PlatformStand then
            noSlowStatus.Text="Jump input received, but character is dead, seated, or in PlatformStand."
            return
        end
        if humanoid.FloorMaterial==Enum.Material.Air then
            noSlowStatus.Text="Jump input received; waiting for ground. State: "..humanoid:GetState().Name
            return
        end
        local strength=humanoid.UseJumpPower and humanoid.JumpPower or humanoid.JumpHeight
        if strength<=0 then
            noSlowStatus.Text="Jump input received, but "..(humanoid.UseJumpPower and "JumpPower" or "JumpHeight").." is zero."
            return
        end
        -- The cloned state permissions or default controls can suppress Jump=true.
        -- Request the jump state directly, only on grounded user input.
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,true)
        humanoid.Jump=true
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
    connect(Input.JumpRequest,requestReplacementJump)
    connect(Input.InputBegan,function(input,processed)
        if not processed and input.KeyCode==Enum.KeyCode.Space then requestReplacementJump() end
    end)
    local testButton=button("Animation Sync Test",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    label("Fresh character required, with No Slow and speed OFF. Preserves the original animation rig; another player must verify visibility. Rejoin to undo the rig test.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,110),true).TextSize=14
    local stopTestButton=button("Stop Animation Sync",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local testStatus=label("Animation test not started.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,90),true)
    testStatus.TextSize=14
    local syncConnection,walkTrack,runTrack,currentTrack
    local inputHumanoid
    local function stopSync()
        if syncConnection then syncConnection:Disconnect(); syncConnection=nil end
        if inputHumanoid then pcall(function() inputHumanoid:Move(Vector3.zero,false) end); inputHumanoid=nil end
        for _,track in ipairs({walkTrack,runTrack}) do
            pcall(function() track:Stop(0.1); track:Destroy() end)
        end
        walkTrack,runTrack,currentTrack=nil,nil,nil
    end
    connect(stopTestButton.Activated,function()
        stopSync(); testStatus.Text="Animation playback stopped. Rejoin to restore the original rig."
    end)
    connect(player.CharacterRemoving,stopSync)
    table.insert(cleanupActions,stopSync)
    local function prepareTracks(animator,animate)
        stopSync()
        local function animationIn(name)
            local folder=animate and animate:FindFirstChild(name)
            return folder and folder:FindFirstChildWhichIsA("Animation",true)
        end
        local walk,run=animationIn("walk"),animationIn("run")
        walk=walk or run; run=run or walk
        if not animator or not walk or not run then return false,"Original Animator or walk/run animations unavailable." end
        local ok,err=pcall(function()
            walkTrack=animator:LoadAnimation(walk)
            runTrack=animator:LoadAnimation(run)
            for _,track in ipairs({walkTrack,runTrack}) do
                track.Looped=true; track.Priority=Enum.AnimationPriority.Movement
            end
        end)
        if not ok then stopSync(); return false,tostring(err) end
        return true
    end
    local function startSync(character,replacement,controls)
        inputHumanoid=replacement
        local elapsed=0
        -- Playback at 1x corresponds to our 16 studs/s reference speed.
        local animationReferenceSpeed=16
        syncConnection=game:GetService("RunService").Heartbeat:Connect(function(delta)
            if closed or player.Character~=character or replacement.Parent~=character then stopSync(); return end
            local ok,err=pcall(function()
                -- Default controls may still target the preserved Humanoid.
                -- Forward user input to the movement Humanoid on every frame.
                local direction=controls:GetMoveVector()
                if Input:GetFocusedTextBox() or replacement.Health<=0 or replacement.Sit then direction=Vector3.zero end
                replacement:Move(direction,true)
                elapsed=elapsed+delta
                if elapsed<0.1 then return end
                elapsed=0
                local root=replacement.RootPart
                local state=replacement:GetState()
                local grounded=replacement.FloorMaterial~=Enum.Material.Air
                local velocity=root and root.AssemblyLinearVelocity or Vector3.zero
                local speed=Vector3.new(velocity.X,0,velocity.Z).Magnitude
                local moving=root and not root.Anchored and replacement.Health>0 and not replacement.Sit
                    and grounded and (state==Enum.HumanoidStateType.Running or state==Enum.HumanoidStateType.RunningNoPhysics)
                    and replacement.MoveDirection.Magnitude>0.05 and speed>0.5
                local walkSpeed=math.max(replacement.WalkSpeed,0)
                local desired=moving and (speed<walkSpeed*0.5 and walkTrack or runTrack) or nil
                if currentTrack~=desired then
                    if currentTrack then currentTrack:Stop(0.15) end
                    currentTrack=desired
                end
                if currentTrack then
                    if not currentTrack.IsPlaying then currentTrack:Play(0.15) end
                    currentTrack:AdjustSpeed(walkSpeed/animationReferenceSpeed)
                end
            end)
            if not ok then stopSync(); testStatus.Text="Animation test stopped: "..tostring(err) end
        end)
        testStatus.Text="Test active. Ask another player to watch walking/running, then check jumping and attacks. Rejoin to undo."
    end
    noSlowDesired=replacementForInput~=nil
    local function enableNoSlow(animationTest,reapply)
        if replacementForInput and replacementCharacter==player.Character then
            noSlowStatus.Text="No Slow is already active. Click its button to turn it OFF."
            return true
        end
        if speedLocked and not reapply then
            noSlowStatus.Text="Turn the speed control OFF before enabling No Slow."
            return
        end
        local character=player.Character
        local old=character and movementHumanoid(character)
        if not old or old.Health<=0 then noSlowStatus.Text="Wait for your character, then try again.";return end
        local animate=character:FindFirstChild("Animate")
        local animateEnabled=animate and animate:IsA("LocalScript") and animate.Enabled
        local originalAnimator=old:FindFirstChildOfClass("Animator")
        local originalName,originalEvaluation=old.Name,old.EvaluateStateMachine
        local testControls
        local movementControls
        if not animationTest then
            local controlsOK,result=pcall(function()
                local scripts=player:FindFirstChild("PlayerScripts")
                local module=scripts and scripts:FindFirstChild("PlayerModule")
                assert(module,"PlayerModule unavailable")
                local controls=require(module):GetControls()
                assert(controls and type(controls.GetMoveVector)=="function","Movement input unavailable")
                return controls
            end)
            if not controlsOK then noSlowStatus.Text="No Slow not enabled: "..tostring(result); return false end
            if player.Character~=character or old.Parent~=character or closed then return false end
            if reapply and not noSlowDesired then return false end
            movementControls=result
        end
        if animationTest then
            local controlsOK,controlsResult=pcall(function()
                local scripts=player:FindFirstChild("PlayerScripts")
                local module=scripts and scripts:FindFirstChild("PlayerModule")
                assert(module and module:IsA("ModuleScript"),"PlayerModule is unavailable")
                local controls=require(module):GetControls()
                assert(controls and type(controls.GetMoveVector)=="function","Movement input is unavailable")
                return controls
            end)
            if not controlsOK then testStatus.Text="Cannot start movement test: "..tostring(controlsResult); return false end
            if closed or player.Character~=character or old.Parent~=character then return false end
            testControls=controlsResult
            local ready,message=prepareTracks(originalAnimator,animate)
            if not ready then testStatus.Text=message; return false end
        end
        local camera=workspace.CurrentCamera
        local cameraSubject=camera and camera.CameraSubject
        local archivable=old.Archivable
        local cloneOK,replacement=pcall(function()
            old.Archivable=true
            return old:Clone()
        end)
        old.Archivable=archivable
        if not cloneOK or not replacement then
            if animationTest then stopSync() end
            noSlowStatus.Text="Could not clone Humanoid; original retained."
            return
        end
        replacement.Archivable=archivable
        if not animationTest then replacement.BreakJointsOnDeath=false end
        -- Preserve the existing Animator and its loaded tracks/references.
        -- Cloning an Animator does not preserve its live AnimationTracks.
        local clonedAnimator=replacement:FindFirstChildOfClass("Animator")
        if clonedAnimator and not animationTest then clonedAnimator:Destroy() end
        local respawnStorage
        if not animationTest then
            respawnStorage=Instance.new("Folder")
            respawnStorage.Name="AcidHubRespawnStorage"
            respawnStorage.Parent=player
        end
        local ok,err=pcall(function()
            for _,state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
                if state~=Enum.HumanoidStateType.None then
                    replacement:SetStateEnabled(state,old:GetStateEnabled(state))
                end
            end
            if animateEnabled then animate.Enabled=false end
            if animationTest then
                -- Retain the original server-created animation hierarchy for this experiment.
                old.Name="AcidHubOriginalHumanoid"
                old.EvaluateStateMachine=false
                replacement.Name="Humanoid"
            else
                -- Preserve the original outside the animated model until reset/death.
                old.Name="AcidHubRespawnHumanoid"
                old.EvaluateStateMachine=false
                replacement.Name="Humanoid"
            end
            replacement.Parent=character
            if not animationTest then
                old.Parent=respawnStorage
                replacement.EvaluateStateMachine=true
                if originalAnimator then
                    originalAnimator.Parent=replacement
                else
                    local animator=Instance.new("Animator")
                    animator.Parent=replacement
                end
            end
            if camera and cameraSubject==old then camera.CameraSubject=replacement end
        end)
        if not ok then
            pcall(function() if originalAnimator then originalAnimator.Parent=old end end)
            pcall(function() replacement:Destroy() end)
            pcall(function() old.Name=originalName; old.EvaluateStateMachine=originalEvaluation; old.Parent=character end)
            if respawnStorage then respawnStorage:Destroy() end
            if animationTest then stopSync() end
            pcall(function() if camera then camera.CameraSubject=cameraSubject end end)
            pcall(function() if animateEnabled then animate.Enabled=true end end)
            noSlowStatus.Text="Replacement failed; attempted to restore original: "..tostring(err)
            return
        end
        if not animationTest then
            local restored=false
            local movementConnection
            local wasManual=false
            local animationElapsed=0
            local liveAnimator=replacement:FindFirstChildOfClass("Animator")
            local function animateMovement(delta)
                -- Observe native playback; do not replace holding/attack tracks or weights.
                animationElapsed=animationElapsed+delta
                if animationElapsed<0.5 then return end
                animationElapsed=0
                local lines={"No Slow Native Animation Report",
                    "Animator="..(liveAnimator and liveAnimator:GetFullName() or "missing"),
                    "Animate enabled="..tostring(animate and animate.Enabled),
                    "State="..replacement:GetState().Name}
                local held=character:FindFirstChildOfClass("Tool")
                table.insert(lines,"Held tool="..(held and held.Name or "none"))
                local tracks=liveAnimator and liveAnimator:GetPlayingAnimationTracks() or {}
                table.insert(lines,"Playing tracks="..#tracks)
                for _,track in ipairs(tracks) do
                    table.insert(lines,tostring(track.Animation and track.Animation.AnimationId)
                        .." | Priority="..track.Priority.Name.." | Weight="..string.format("%.2f",track.WeightCurrent)
                        .." | Time="..string.format("%.2f",track.TimePosition).." | Speed="..string.format("%.2f",track.Speed))
                end
                animationReport=table.concat(lines,"\n")
                animationStatus.Text=animationReport
            end
            local function stopMovementBridge()
                if movementConnection then movementConnection:Disconnect(); movementConnection=nil end
                wasManual=false
            end
            local function restoreOriginal(dying)
                if restored then return end
                restored=true
                if approachOverride.resetOwner==character then approachOverride.resetOwner=nil; approachOverride.resetCharacter=nil end
                disableNoSlow=nil
                stopMovementBridge()
                pcall(function() game:GetService("StarterGui"):SetCore("ResetButtonCallback",true) end)
                if player.Character~=character or not character.Parent then
                    if respawnStorage then respawnStorage:Destroy(); respawnStorage=nil end
                    return
                end
                replacementForInput,replacementCharacter=nil,nil
                if animateEnabled and animate.Parent then animate.Enabled=false end
                if originalAnimator and originalAnimator.Parent then originalAnimator.Parent=old end
                replacement.Parent=nil
                old.Name=originalName
                old.EvaluateStateMachine=originalEvaluation
                old.Parent=character
                if respawnStorage then respawnStorage:Destroy(); respawnStorage=nil end
                character:SetAttribute("AcidHubNoSlow",nil)
                if camera and camera.CameraSubject==replacement then camera.CameraSubject=old end
                replacement:Destroy()
                if dying then
                    -- Hand death back to the original Humanoid, not a locally broken model.
                    old.EvaluateStateMachine=true
                    old:SetStateEnabled(Enum.HumanoidStateType.Dead,true)
                    old.Health=0
                    old:ChangeState(Enum.HumanoidStateType.Dead)
                elseif animateEnabled and animate.Parent then
                    animate.Enabled=true
                end
                adoptCharacter(character)
                if dying then
                    noSlowStatus.Text="No Slow released. Waiting for the game to spawn a new character."
                    task.delay(10,function()
                        if not closed and player.Character==character then
                            noSlowStatus.Text="The game has not created a new character. Rejoin to recover; local restoration did not complete respawn."
                        end
                    end)
                end
            end
            approachOverride.resetOwner=character
            approachOverride.resetCharacter=function(expectedCharacter)
                if restored or expectedCharacter~=character or player.Character~=character then return false end
                restoreOriginal(true)
                return true
            end
            connect(replacement.Died,function() restoreOriginal(true) end)
            connect(old.HealthChanged,function(health)
                if health<=0 then restoreOriginal(true) end
            end)
            -- PlayerModule can still address the preserved original Humanoid.
            -- Forward manual input only; idle frames must not cancel automation MoveTo.
            movementConnection=game:GetService("RunService").RenderStepped:Connect(function(delta)
                if restored or closed or player.Character~=character or replacement.Parent~=character then
                    stopMovementBridge(); return
                end
                local direction=movementControls:GetMoveVector()
                if Input:GetFocusedTextBox() or replacement.Health<=0 or replacement.Sit then direction=Vector3.zero end
                local manual=direction.Magnitude>0.001
                if manual then replacement:Move(direction,true)
                elseif wasManual then replacement:Move(Vector3.zero,false) end
                wasManual=manual
                local animationOK,animationError=pcall(animateMovement,delta)
                if not animationOK then
                    animationReport="No Slow animation report error: "..tostring(animationError)
                    animationStatus.Text=animationReport
                end
            end)
            local resetEvent=Instance.new("BindableEvent")
            connect(resetEvent.Event,function() restoreOriginal(true) end)
            local starterGui=game:GetService("StarterGui")
            local resetBound=false
            task.spawn(function()
                for attempt=1,10 do
                    if closed or restored then return end
                    if pcall(function() starterGui:SetCore("ResetButtonCallback",resetEvent) end) then resetBound=true; return end
                    task.wait(0.5)
                end
            end)
            local function releaseReset()
                if resetBound then pcall(function() starterGui:SetCore("ResetButtonCallback",true) end); resetBound=false end
            end
            connect(player.CharacterRemoving,function(leaving)
                if leaving==character then
                    stopMovementBridge()
                    releaseReset()
                    restored=true
                    if respawnStorage then respawnStorage:Destroy(); respawnStorage=nil end
                    resetEvent:Destroy()
                end
            end)
            connect(resetEvent.Event,releaseReset)
            connect(replacement.Died,releaseReset)
            disableNoSlow=function()
                releaseReset()
                restoreOriginal(false)
                resetEvent:Destroy()
            end
            table.insert(cleanupActions,function()
                releaseReset()
                restoreOriginal(false)
                resetEvent:Destroy()
            end)
        end
        replacementForInput,replacementCharacter=replacement,character
        character:SetAttribute("AcidHubNoSlow",true)
        if animateEnabled then
            task.spawn(function()
                game:GetService("RunService").Heartbeat:Wait()
                if not closed and player.Character==character and replacement.Parent==character and replacement.Health>0 and animate.Parent==character then animate.Enabled=true end
            end)
        end
        adoptCharacter(character)
        if animationTest then startSync(character,replacement,testControls) end
        return true
    end
    do
    local exitRetryAfter=0
    local recoveryCharacter
    noSlowTreadmillExit=function(character)
        if treadmillExitBusy then return true end
        if not noSlowDesired or player.Character~=character then return false end
        if os.clock()<exitRetryAfter or recoveryCharacter==character then return true end
        treadmillExitBusy=true
        task.spawn(function()
            local ok,err=pcall(function()
                if disableNoSlow then disableNoSlow() end
                noSlowButton.Text="No Slow: exiting treadmill"
                game:GetService("RunService").Heartbeat:Wait()
                local function live()
                    if closed or not noSlowDesired or player.Character~=character then return end
                    local humanoid=movementHumanoid(character)
                    local root=character:FindFirstChild("HumanoidRootPart")
                    if root and root.Parent and humanoid and humanoid.Health>0 then return root,humanoid end
                end
                local function note(message)
                    noSlowStatus.Text=message
                    reportTask("Treadmill",message)
                end
                for attempt=1,5 do
                    local root,humanoid=live()
                    if not root then return end
                    if root.Anchored then
                        note("Leaving treadmill: attempt "..attempt.."/5")
                        requestTreadmillExitJump(character,humanoid,false)
                    end
                    local deadline=os.clock()+2
                    local releasedAt
                    repeat
                        root,humanoid=live()
                        if not root then return end
                        if root.Anchored then releasedAt=nil
                        else
                            releasedAt=releasedAt or os.clock()
                            if os.clock()-releasedAt>=0.2 then
                                note("Treadmill exit confirmed; restoring No Slow")
                                enableNoSlow(false,true)
                                return
                            end
                        end
                        task.wait(0.1)
                    until os.clock()>=deadline
                end
                local root,humanoid=live()
                if not root or not root.Anchored then return end
                -- Match path recovery: never reset when carrying, or when the read is uncertain.
                local reader=require(game:GetService("ReplicatedStorage").Client.EggState)
                local snapshot=reader.ReadFieldEggs()
                assert(type(snapshot)=="table" and type(snapshot.Records)=="table","Cannot verify empty hands for treadmill recovery")
                for _,egg in pairs(snapshot.Records) do
                    assert(type(egg)=="table" and type(egg.State)=="string","Invalid field snapshot for treadmill recovery")
                    if tonumber(egg.CarrierUserId)==player.UserId then
                        note("Treadmill recovery withheld: carrying a field egg")
                        return
                    end
                end
                root,humanoid=live()
                if not root or not root.Anchored then return end
                assert(character:GetAttribute("AcidHubNoSlow")~=true,"Original Humanoid was not restored; reset withheld")
                note("Five treadmill exit attempts failed; respawning empty-handed")
                humanoid.Health=0
                recoveryCharacter=character
                humanoid:ChangeState(Enum.HumanoidStateType.Dead)
                -- Movement remains gated by the dead/anchored rig until a living character exists.
            end)
            treadmillExitBusy=false
            exitRetryAfter=os.clock()+5
            if not ok and not closed then
                local message="Treadmill exit error: "..tostring(err).."; retrying after cooldown"
                noSlowStatus.Text=message
                reportTask("Treadmill",message)
            end
        end)
        return true
    end
    end
    table.insert(cleanupActions,function() noSlowTreadmillExit=nil end)
    connect(player.CharacterAdded,function(character)
        task.spawn(function()
            -- Wait for this new rig's controls and animation assets before replacing it.
            while not closed and noSlowDesired and player.Character==character do
                local humanoid=movementHumanoid(character)
                if humanoid and humanoid.Health>0 and character:FindFirstChild("HumanoidRootPart")
                    and character:FindFirstChild("Animate") and humanoid:FindFirstChildOfClass("Animator") then
                    task.wait(0.5)
                    if closed or not noSlowDesired or player.Character~=character then return end
                    if enableNoSlow(false,true) then return end
                end
                task.wait(0.5)
            end
        end)
    end)
    connect(testButton.Activated,function()
        local character=player.Character
        if character and (character:GetAttribute("AcidHubNoSlow") or character:GetAttribute("AcidHubHumanoidTest") or character:FindFirstChild("AcidHubOriginalHumanoid")) then
            testStatus.Text="Fresh character required. Disable saved No Slow, rejoin, then run this test first."; return
        end
        if speedLocked then testStatus.Text="Turn speed OFF before running the test."; return end
        testStatus.Text="Preparing animation test..."
        if enableNoSlow(true) then noSlowDesired=true
        elseif testStatus.Text=="Preparing animation test..." then testStatus.Text=noSlowStatus.Text end
    end)
    local function setNoSlow(value)
        if not value then
            if replacementForInput and not disableNoSlow then
                noSlowStatus.Text="The separate Animation Sync Test needs a rejoin to undo."
                return false
            end
            noSlowDesired=false
            if disableNoSlow then disableNoSlow() end
            adoptCharacter(player.Character)
            noSlowStatus.Text="No Slow OFF. Original Humanoid restored; automatic reapplication disabled."
            return true
        end
        if not enableNoSlow() then return false end
        noSlowDesired=true
        adoptCharacter(player.Character)
        return true
    end
    connect(noSlowButton.Activated,function() setNoSlow(not (noSlowDesired or replacementForInput~=nil)) end)
    registerSetting("NoSlow",false,function() return noSlowDesired end,setNoSlow,isBoolean)
    settingsBindings.NoSlow.restore=function(value)
        if not value then return setNoSlow(false) end
        -- Saved settings can load before the game's character controllers bind.
        -- Finish a fresh OFF/ON cycle before starting saved automations.
        local deadline=os.clock()+30
        local stableCharacter,stableHumanoid,readySince
        noSlowStatus.Text="Restoring No Slow: waiting for character controllers..."
        while not closed and os.clock()<deadline do
            local character=player.Character
            local humanoid=movementHumanoid(character)
            local scripts=player:FindFirstChild("PlayerScripts")
            local ready=game:IsLoaded() and player:GetAttribute("__LOADED")~=false
                and character and humanoid and humanoid.Health>0
                and character:FindFirstChild("HumanoidRootPart") and character:FindFirstChild("Animate")
                and humanoid:FindFirstChildOfClass("Animator") and scripts and scripts:FindFirstChild("PlayerModule")
            if ready then
                if stableCharacter~=character or stableHumanoid~=humanoid then
                    stableCharacter,stableHumanoid,readySince=character,humanoid,os.clock()
                end
                if os.clock()-readySince>=2 then
                    if not setNoSlow(true) then return false end
                    task.wait(1)
                    if closed or not noSlowDesired or player.Character~=character then return false end
                    if disableNoSlow then disableNoSlow() end
                    task.wait(0.5)
                    if closed or not noSlowDesired or player.Character~=character then return false end
                    local ok=enableNoSlow(false,true)
                    adoptCharacter(character)
                    if ok then noSlowStatus.Text="No Slow refreshed after load. Ready for automations." end
                    return ok==true
                end
            else stableCharacter,stableHumanoid,readySince=nil,nil,nil end
            task.wait(0.25)
        end
        noSlowStatus.Text="No Slow restore timed out waiting for character controllers. Reload when the character is ready."
        return false
    end
end

-- Instant Prompt changes hold duration only; interaction still requires input.
do
    local instant=false
    local originals=setmetatable({},{__mode="k"})
    local function shorten(prompt)
        if not instant or not prompt:IsA("ProximityPrompt") then return end
        if originals[prompt]==nil then originals[prompt]=prompt.HoldDuration end
        prompt.HoldDuration=0
    end
    local function restore()
        for prompt,duration in pairs(originals) do
            pcall(function() prompt.HoldDuration=duration end)
        end
        originals=setmetatable({},{__mode="k"})
    end
    table.insert(cleanupActions,restore)
    switch(othersPage,"Instant Grab",false,function(value)
        instant=value
        if value then
            for _,object in ipairs(workspace:GetDescendants()) do
                if object:IsA("ProximityPrompt") then shorten(object) end
            end
        else restore() end
    end)
    connect(workspace.DescendantAdded,shorten)
    connect(game:GetService("ProximityPromptService").PromptShown,shorten)
    label("Removes hold time from interaction prompts. You still press E; game-side timing may still apply.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(othersPage,58),true).TextSize=14
end

-- No Traps applies the observed CanTouch change to the current character.
do
    local active=false
    local originals={}
    local addedConnection,removingConnection
    local function restorePart(part)
        local original=originals[part]
        if original==nil then return end
        pcall(function() part.CanTouch=original end)
        originals[part]=nil
    end
    local function detach()
        if addedConnection then addedConnection:Disconnect(); addedConnection=nil end
        if removingConnection then removingConnection:Disconnect(); removingConnection=nil end
        for part in pairs(originals) do restorePart(part) end
    end
    local function disableTouch(part)
        if not active or not part:IsA("BasePart") then return end
        if originals[part]==nil then originals[part]=part.CanTouch end
        part.CanTouch=false
    end
    local function attach(character)
        detach()
        if not active or not character then return end
        addedConnection=character.DescendantAdded:Connect(disableTouch)
        removingConnection=character.DescendantRemoving:Connect(restorePart)
        for _,part in ipairs(character:GetDescendants()) do disableTouch(part) end
    end
    switch(othersPage,"No Traps",false,function(value)
        active=value
        if active then attach(player.Character) else detach() end
    end,"Disables CanTouch on character parts, including accessories and equipped tool parts. Covers new parts and respawns. OFF restores captured values; other touch interactions may also be affected.")
    connect(player.CharacterAdded,attach)
    connect(player.CharacterRemoving,function() detach() end)
    table.insert(cleanupActions,function() active=false; detach() end)
end

-- Experimental early state recovery observed in the protected hit capture.
do
    local active=false
    local characterConnections={}
    local stateConnection,humanoid
    local pending=false
    local generation=0
    local function clearBinding()
        generation=generation+1; pending=false
        if stateConnection then stateConnection:Disconnect(); stateConnection=nil end
        humanoid=nil
    end
    local function detach()
        clearBinding()
        for _,connection in ipairs(characterConnections) do connection:Disconnect() end
        characterConnections={}
    end
    local function requestRecovery()
        if not active or pending or not humanoid then return end
        local target=humanoid
        local token=generation
        local state=target:GetState()
        if state~=Enum.HumanoidStateType.Physics and state~=Enum.HumanoidStateType.Ragdoll then return end
        pending=true
        task.defer(function()
            if token~=generation then return end
            pending=false
            if closed or not active or humanoid~=target or target.Parent~=player.Character then return end
            if target.Health<=0 or target.Sit then return end
            local root=target.RootPart
            if root and root.Anchored then return end
            local current=target:GetState()
            if current==Enum.HumanoidStateType.Physics or current==Enum.HumanoidStateType.Ragdoll then
                pcall(function() target:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            end
        end)
    end
    local function bind(target)
        clearBinding()
        humanoid=target
        if not target then return end
        stateConnection=target.StateChanged:Connect(requestRecovery)
        requestRecovery()
    end
    local function attach(character)
        detach()
        if not active or not character then return end
        table.insert(characterConnections,character.ChildAdded:Connect(function(child)
            if child:IsA("Humanoid") then bind(child) end
        end))
        table.insert(characterConnections,character.ChildRemoved:Connect(function(child)
            if child==humanoid then bind(movementHumanoid(character)) end
        end))
        bind(movementHumanoid(character))
    end
    switch(othersPage,"No Ragdoll",false,function(value)
        active=value
        if value then attach(player.Character) else detach() end
    end,"Experimental: requests GettingUp when Physics or Ragdoll begins. Does not prevent the initial push or change joints. OFF stops recovery requests. Handles respawns and No Slow replacement.")
    connect(player.CharacterAdded,attach)
    connect(player.CharacterRemoving,detach)
    table.insert(cleanupActions,function() active=false; detach() end)
end

local showMutations=false
local mutatedOnly=false
Rarity.ESP={colors=false,rarity=false,size=false,income=false,background=false}
function Rarity.ESP.compact(value)
    if type(value)~="number" or value~=value or value<0 or value==math.huge then return nil end
    local suffixes={"","K","M","B","T","QA","QI","SX","SP","OC","NO","DC"}
    local tier=1
    while value>=1000 and tier<#suffixes do value=value/1000; tier=tier+1 end
    value=math.floor(value*10+0.5)/10
    if value>=1000 and tier<#suffixes then value=value/1000; tier=tier+1 end
    return string.format("%.1f",value):gsub("%.0$","").." "..suffixes[tier]
end
function Rarity.ESP.escape(value)
    return tostring(value):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;"):gsub('"',"&quot;"):gsub("'","&apos;")
end
function Rarity.ESP.text(marker,mutations,settings)
    settings=settings or Rarity.ESP
    local plain=(settings.rarity and ("["..marker.rarity.."] ") or "")..marker.name
    local text=Rarity.ESP.escape(plain)
    local details,plainDetails={},{}
    local function detail(value,color)
        plainDetails[#plainDetails+1]=value
        local escaped=Rarity.ESP.escape(value)
        details[#details+1]=settings.colors and ('<font color="'..color..'">'..escaped..'</font>') or escaped
    end
    if settings.size and marker.scale then detail(string.format("%.0f%%",marker.scale*100),"#FFDB4D") end
    if settings.income then
        local income=Rarity.ESP.compact(marker.income)
        if income then detail(income.."/s","#00FF80") end
    end
    if #details>0 then
        text=text.." ("..table.concat(details," ")..")"
        plain=plain.." ("..table.concat(plainDetails," ")..")"
    end
    if mutations and marker.mutation and marker.mutation~="" then
        text=text.."\n["..Rarity.ESP.escape(marker.mutation).."]"
        plain=plain.."\n["..marker.mutation.."]"
    end
    return text,plain
end
function Rarity.ESP.metrics(record)
    local scale=tonumber(record.AssetScale)
    if not scale or scale~=scale or scale<=0 or scale==math.huge then scale=nil end
    local ok,income=pcall(function()
        local util=game:GetService("ReplicatedStorage").Shared.Util
        local records=require(util.EggRecords)
        -- ReadOwnedEggs already decodes placed eggs; Decode expects serialized CFrame components.
        local egg=record
        if not record.Placement or typeof(record.Placement.LocalCFrame)~="CFrame" then egg=records.Decode(record) end
        return require(util.AssetEarnings).RatePerSecond(records.ToAssetItemData(egg))
    end)
    return scale,ok and income or nil
end
local allMarkers,selectedAreas,selectedRarities={},{},{}
local areaOptions={"Forest","Lake","Desert","Jungle","Snow","Volcano","AbyssOcean","Prehistoric","Cosmic","CherryBlossom","TitanTemple","Angels & Demons"}
local rarityOptions={"Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret","Eternal","Divine","Unknown"}
for _,name in ipairs(areaOptions) do selectedAreas[name]=true end
for _,name in ipairs(rarityOptions) do selectedRarities[name]=true end
local status,refresh,redraw
switch(espPage,"Egg ESP",false,function(value)
    enabled=value
    if value then if refresh then refresh() end
    else
        readToken=readToken+1
        if busy and worker then pcall(task.cancel,worker) end
        busy,healthy=false,false
        if status then status.Text="ESP off" end
    end
    renderer:SetEnabled(enabled and healthy)
end)
local statusRow=detailRow(espPage,64)
status=label("Connecting to egg data...",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),statusRow,true)
status.TextSize=14
local function displaySwitch(title, initial, setter)
    switch(espPage,title,initial,function(value) setter(value); if redraw then redraw() end end)
end
displaySwitch("Show Mutations",false,function(value) showMutations=value end)
displaySwitch("Show Colors",false,function(value) Rarity.ESP.colors=value end)
displaySwitch("Show Background",false,function(value) Rarity.ESP.background=value end)
displaySwitch("Show Rarity",false,function(value) Rarity.ESP.rarity=value end)
displaySwitch("Show Size Percentage",false,function(value) Rarity.ESP.size=value end)
displaySwitch("Estimated Income",false,function(value) Rarity.ESP.income=value end)
displaySwitch("Only Mutated Eggs",false,function(value) mutatedOnly=value end)
local function multiSelect(title,options,selection,parent,settingKey,defaultSelected,onChange)
    parent=parent or espPage
    if defaultSelected==nil then defaultSelected=true end
    local frame=row(parent,42)
    local heading=button(title,UDim2.fromOffset(6,6),UDim2.new(1,-12,0,30),frame)
    local choices=make("Frame",{Position=UDim2.fromOffset(6,44),Size=UDim2.new(1,-12,0,38+math.ceil(#options/2)*34),
        BackgroundTransparency=1,Visible=false},frame)
    local all=button("All",UDim2.fromOffset(0,0),UDim2.new(0.5,-3,0,28),choices)
    local none=button("None",UDim2.new(0.5,3,0,0),UDim2.new(0.5,-3,0,28),choices)
    local controls={}
    local function update()
        local count=0
        for _,name in ipairs(options) do
            if selection[name] then count=count+1 end
            controls[name].Text=(selection[name] and "[x] " or "[ ] ")..name
            controls[name].TextColor3=selection[name] and colors.accent or colors.muted
        end
        heading.Text=title.." ("..count.."/"..#options..") "..(choices.Visible and "-" or "+")
        if onChange then onChange() elseif redraw then redraw() end
    end
    for index,name in ipairs(options) do
        local col=(index-1)%2
        controls[name]=button(name,UDim2.new(col*0.5,col==0 and 0 or 3,0,34+math.floor((index-1)/2)*34),UDim2.new(0.5,-3,0,28),choices)
        controls[name].TextSize=14
        connect(controls[name].Activated,function() selection[name]=not selection[name]; update() end)
    end
    connect(all.Activated,function() for _,name in ipairs(options) do selection[name]=true end; update() end)
    connect(none.Activated,function() for _,name in ipairs(options) do selection[name]=false end; update() end)
    connect(heading.Activated,function()
        choices.Visible=not choices.Visible
        frame.Size=UDim2.new(1,-6,0,choices.Visible and (86+math.ceil(#options/2)*34) or 42)
        update()
    end)
    update()
    local defaults={}
    for _,name in ipairs(options) do defaults[name]=defaultSelected end
    registerSetting(settingKey or title,defaults,function() return copySetting(selection) end,function(value)
        for _,name in ipairs(options) do selection[name]=value[name] end
        update(); return true
    end,function(value)
        if type(value)~="table" then return false end
        for _,name in ipairs(options) do if not isBoolean(value[name]) then return false end end
        return true
    end)
end
multiSelect("Areas",areaOptions,selectedAreas)
do
    local espRarities={}
    for _,rarity in ipairs(rarityOptions) do
        if rarity~="Unknown" then espRarities[#espRarities+1]=rarity end
    end
    selectedRarities.Unknown=nil
    multiSelect("Rarities",espRarities,selectedRarities)
end
local refreshButton=button("Refresh Now",UDim2.fromOffset(0,0),UDim2.new(1,0,1,0),row(espPage,34))
connect(refreshButton.Activated,function() if refresh then refresh() end end)
redraw=function()
    local visible={}
    for _,marker in ipairs(allMarkers) do
        if selectedAreas[marker.area] and selectedRarities[marker.rarity] and (not mutatedOnly or marker.mutation~="") then
            marker.text,marker.plainText=Rarity.ESP.text(marker,showMutations)
            marker.background=Rarity.ESP.background
            marker.color=Rarity.ESP.colors and marker.rarityColor or Color3.fromRGB(255,255,255)
            table.insert(visible,marker)
        end
    end
    renderer:SetSnapshot(visible)
    renderer:SetEnabled(enabled and healthy)
    if healthy then
        status.Text=#visible.." shown / "..#allMarkers.." located eggs | Live"
    end
end

local resizeHandle=button("◢",UDim2.new(1,-24,1,-24),UDim2.fromOffset(22,22),panel)
resizeHandle.Name="ResizeHandle"; resizeHandle.ZIndex=20; resizeHandle.BackgroundTransparency=1
local resizing,resizeInput,resizeOrigin,resizeSize
connect(resizeHandle.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        resizing=true; resizeInput=input; resizeOrigin=input.Position; resizeSize=panel.AbsoluteSize
    end
end)
connect(Input.InputChanged,function(input)
    if resizing and (input.UserInputType==Enum.UserInputType.MouseMovement or input==resizeInput) then
        local delta=input.Position-resizeOrigin
        local viewport=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
        local minimumWidth=detailsEnabled and 820 or 540
        local maxWidth=math.max(minimumWidth,viewport.X-panel.AbsolutePosition.X-8)
        local maxHeight=math.max(450,viewport.Y-panel.AbsolutePosition.Y-8)
        panel.Size=UDim2.fromOffset(math.clamp(resizeSize.X+delta.X,minimumWidth,maxWidth),math.clamp(resizeSize.Y+delta.Y,450,maxHeight))
    end
end)
connect(Input.InputEnded,function(input)
    if input==resizeInput or input.UserInputType==Enum.UserInputType.MouseButton1 then resizing=false end
end)

local dragging, dragOrigin, panelOrigin, dragInput
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragInput = true, input
        dragOrigin, panelOrigin = input.Position, panel.Position
    end
end)
connect(Input.InputChanged, function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput) then
        local delta = input.Position - dragOrigin
        panel.Position = UDim2.new(panelOrigin.X.Scale, panelOrigin.X.Offset + delta.X,
            panelOrigin.Y.Scale, panelOrigin.Y.Offset + delta.Y)
    end
end)
connect(Input.InputEnded, function(input)
    if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

local areas = {}
for _, area in ipairs(areaOptions) do areas[string.lower(area):gsub("[^%w]","")] = area end
areas.angelsanddemons="Angels & Demons"
areas.angelsdemons="Angels & Demons"
-- Captured Data.Areas.Configs["Light Dark"] is the Angels & Demons biome.
areas.lightdark="Angels & Demons"
local function mutationNames(value,baseMutation)
    local result, seen = {}, {}
    local function add(name)
        if type(name) ~= "string" then return end
        name = name:match("^%s*(.-)%s*$")
        if name == "" or string.lower(name) == "none" or seen[name] then return end
        seen[name] = true
        table.insert(result, name)
    end
    if type(value) == "string" then add(value)
    elseif type(value) == "table" then
        for key, child in next, value do
            if type(child) == "string" then add(child)
            elseif type(key) == "string" and (child == true or (type(child) == "number" and child > 0)) then add(key) end
        end
    end
    add(baseMutation)
    table.sort(result)
    return table.concat(result, ", ")
end
local stealDroppedEggs=false
local function stealableFieldState(state)
    return state=="Slot" or (stealDroppedEggs and state=="Dropped")
end
refresh=function()
    if closed or busy or not enabled then return end
    busy = true
    readToken = readToken + 1
    local token = readToken
    worker = task.spawn(function()
        local ok, result = pcall(function()
            if not api then
                local client = game:GetService("ReplicatedStorage"):FindFirstChild("Client")
                local module = client and client:FindFirstChild("EggState")
                assert(module and module:IsA("ModuleScript"), "EggState is unavailable in this game.")
                api = require(module)
            end
            assert(type(api) == "table" and type(api.ReadFieldEggs) == "function", "Egg reader unavailable.")
            local snapshot = api.ReadFieldEggs()
            assert(type(snapshot) == "table" and type(snapshot.Records) == "table", "Unexpected egg data format.")
            local markers, seen, missing = {}, {}, 0
            for _, record in next, snapshot.Records do
                assert(type(record) == "table" and type(record.Uid) == "string", "Invalid egg record.")
                assert(not seen[record.Uid], "Duplicate egg ID.")
                seen[record.Uid] = true
                local rawArea = tostring(record.AreaId or "Unknown")
                local area = areas[string.lower(rawArea):gsub("[^%w]", "")] or rawArea
                local name, rarity, color = Rarity.Resolve(tostring(record.AssetCategory or "Unknown egg"), area)
                local frame = typeof(record.BoundsCFrame) == "CFrame" and record.BoundsCFrame or record.BottomCFrame
                if typeof(frame) == "CFrame" then
                    local mutation = mutationNames(record.Mutations,record.BaseMutation)
                    local scale,income=Rarity.ESP.metrics(record)
                    table.insert(markers, {id = record.Uid, area = area, position = frame.Position,
                        text = name, name=name, mutation=mutation, rarity=rarity,
                        rarityColor=color,scale=scale,income=income})
                else missing = missing + 1 end
            end
            return {markers = markers, missing = missing}
        end)
        if closed or token ~= readToken then return end
        busy = false
        if not ok then
            healthy = false
            renderer:SetEnabled(false)
            status.Text = "Egg data unavailable: " .. tostring(result)
            return
        end
        allMarkers=result.markers
        healthy=true
        local rendered, renderError = pcall(redraw)
        healthy = rendered
        renderer:SetEnabled(enabled and healthy)
        if not rendered then status.Text = "ESP update failed: " .. tostring(renderError); return end
        if result.missing>0 then status.Text=status.Text.."\n"..result.missing.." eggs without positions" end
    end)
    task.delay(12, function()
        if closed or token ~= readToken or not busy then return end
        readToken = readToken + 1
        if worker then pcall(task.cancel, worker) end
        busy, healthy = false, false
        renderer:SetEnabled(false)
        status.Text = "Egg data timed out. Toggle ESP to retry."
    end)
end
-- User-provided destination; proximity alone does not confirm delivery.
do
(function()
    local pen={enabled=false,colors=false,rarity=false,size=false,income=false,background=false,mutations=false,onlyMutated=false,status=false}
    local penRenderer=Renderer.new(workspace)
    penRenderer:SetAreas({"Pen"})
    local choices,selected={},{}
    for _,rarity in ipairs(rarityOptions) do if rarity~="Unknown" then choices[#choices+1]=rarity; selected[rarity]=true end end
    label("Pen Eggs ESP",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),row(espPage,38)).TextSize=20
    local update
    local function option(title,key)
        switch(espPage,title,false,function(value)
            pen[key]=value
            if not pen.enabled then penRenderer:SetEnabled(false) end
            if update then task.spawn(update) end
        end,nil,"PenESP."..key)
    end
    option("Pen Eggs ESP","enabled")
    option("Show Mutations","mutations")
    option("Show Colors","colors")
    option("Show Background","background")
    option("Show Rarity","rarity")
    option("Show Size Percentage","size")
    option("Estimated Income","income")
    option("Only Mutated Eggs","onlyMutated")
    option("Show Status","status")
    multiSelect("Pen Rarities",choices,selected,espPage,"PenESP.Rarities",true,function() if update then task.spawn(update) end end)
    local busy=false
    local function countdown(seconds)
        seconds=math.ceil(math.max(0,seconds))
        if seconds<=0 then return "Ready" end
        local h=math.floor(seconds/3600)
        local m=math.floor(seconds%3600/60)
        local sec=seconds%60
        return h>0 and string.format("%dh %dm %ds",h,m,sec) or (m>0 and string.format("%dm %ds",m,sec) or (sec.."s"))
    end
    update=function()
        if busy or closed or not pen.enabled then return end
        busy=true
        local ok,markers=pcall(function()
            local storage=game:GetService("ReplicatedStorage")
            local reader=require(storage.Client.EggState)
            local plots=require(storage.Client.PlotState)
            local records=require(storage.Shared.Util.EggRecords)
            local groups=reader.ReadOwnedEggs()
            assert(type(groups)=="table","Owned egg snapshot unavailable")
            local result={}
            local now=workspace:GetServerTimeNow()
            for _,group in pairs(groups) do
                local owner=Players:GetPlayerByUserId(tonumber(group.OwnerUserId) or 0)
                local plot=owner and plots.ResolvePlot(owner)
                if plot and plot.CenterPoint and type(group.Records)=="table" then
                    for uid,egg in pairs(group.Records) do
                        if egg.Placement and typeof(egg.Placement.LocalCFrame)=="CFrame" then
                            local name,rarity,color=Rarity.Resolve(egg.AssetCategory)
                            local mutation=mutationNames(egg.Mutations,egg.BaseMutation)
                            if selected[rarity] and (not pen.onlyMutated or mutation~="") then
                                local scale,income=Rarity.ESP.metrics(egg)
                                local marker={id=tostring(group.OwnerUserId)..":"..tostring(uid),area="Pen",
                                    position=(plot.CenterPoint.CFrame*egg.Placement.LocalCFrame).Position,
                                    name=name,rarity=rarity,mutation=mutation,scale=scale,income=income,
                                    color=pen.colors and color or Color3.fromRGB(255,255,255),background=pen.background}
                                marker.text,marker.plainText=Rarity.ESP.text(marker,pen.mutations,pen)
                                if pen.status then
                                    local timed,status=pcall(function()
                                        local speed=egg.GrowthSpeedMultiplier
                                        assert(type(speed)=="number" and speed>0,"Growth speed unavailable")
                                        local credit=records.CurrentNightCredit(egg,now,speed)
                                        local remaining=records.GrowthSecondsRemaining(egg,now,speed,credit,owner)/speed
                                        assert(remaining==remaining and remaining<math.huge,"Invalid growth time")
                                        return countdown(remaining)
                                    end)
                                    status=timed and status or "Time unavailable"
                                    marker.text=marker.text.."\nStatus: "..Rarity.ESP.escape(status)
                                    marker.plainText=marker.plainText.."\nStatus: "..status
                                end
                                result[#result+1]=marker
                            end
                        end
                    end
                end
            end
            return result
        end)
        busy=false
        if closed or not pen.enabled then return end
        if not ok then penRenderer:SetEnabled(false); reportTask("Pen ESP",tostring(markers)); return end
        local rendered,err=pcall(function() penRenderer:SetSnapshot(markers); penRenderer:SetEnabled(true) end)
        if not rendered then penRenderer:SetEnabled(false); reportTask("Pen ESP",tostring(err)) end
    end
    task.spawn(function() while not closed do update(); task.wait(1) end end)
    table.insert(cleanupActions,function() pen.enabled=false; penRenderer:Destroy() end)
end)()
end

local autoStealSafeZone=Vector3.new(527,71,-365)
local lastPreviewEggId
-- Auto Steal milestone 1: manual, read-only target selection, independent of ESP.
do
    local previewAreas={}
    for _,name in ipairs(areaOptions) do previewAreas[name]=false end
    local minimum,priority,speciesText="All","Best Rarity",""
    local approachSpeed="Current Speed"
    local previewReport=""
    local previewStatus,previewBox,previewButton
    local previewWorker,previewBusy=nil,false
    local generation=0
    local function invalidate()
        generation=generation+1
        if previewWorker then pcall(task.cancel,previewWorker); previewWorker=nil end
        previewBusy=false; previewReport=""
        if previewButton then previewButton.Text="Preview Target" end
        if previewBox then previewBox.Text="" end
        if previewStatus then previewStatus.Text="Settings changed. Press Preview Target for a fresh selection." end
    end
    local heading=label("Auto Steal — Selection Preview",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),row(debugPage,44))
    do
        local index={enabled=false,secured={}}
        automationFlow.indexCompletion=index
        switch(autoStealPage,"Index Completion",false,function(value) index.enabled=value; invalidate() end,
            "Adds missing World Index species beyond normal target filters. One secured egg per missing species; owned/growing eggs and pets count. Uses normal priority, progression and daily limits.")
        function index.needs()
            if not index.enabled then return {} end
            local storage=game:GetService("ReplicatedStorage")
            local save=require(storage.Shared.Save).Get()
            assert(save and type(save.Index)=="table" and type(save.Inventory)=="table","Index completion data unavailable")
            local assets=require(storage.Data.Assets).Directory
            local areaData=require(storage.Data.Areas).Directory
            local needs={}
            for _,area in pairs(areaData) do
                for _,drop in ipairs(area.DropTable or {}) do
                    local category=drop[1]
                    local config=assets[category]
                    if type(drop[2])=="number" and drop[2]>0 and config and config.DontRoll~=true
                        and save.Index[category]~=true and not index.secured[category] then needs[category]=true end
                end
            end
            for _,pet in pairs(save.Inventory) do
                assert(type(pet)=="table" and type(pet.Category)=="string","Invalid pet inventory for index completion")
                needs[pet.Category]=nil
            end
            local groups=require(storage.Client.EggState).ReadOwnedEggs()
            assert(type(groups)=="table","Owned eggs unavailable for index completion")
            local found=false
            for _,group in pairs(groups) do
                if type(group)=="table" and tonumber(group.OwnerUserId)==player.UserId then
                    assert(type(group.Records)=="table","Invalid owned eggs for index completion")
                    found=true
                    for _,egg in pairs(group.Records) do
                        assert(type(egg)=="table" and type(egg.AssetCategory)=="string","Invalid egg for index completion")
                        needs[egg.AssetCategory]=nil
                    end
                end
            end
            assert(found,"Local owned eggs unavailable for index completion")
            return needs
        end
    end
    heading.TextSize=20
    label("Read-only milestone: ranks field eggs without moving or grabbing. Empty areas/species means all. Delivery will end at the safe zone; placement is a separate future feature.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,110),true).TextSize=14
    switch(autoStealPage,"Dropped Eggs",false,function(value)
        stealDroppedEggs=value; invalidate()
    end,"OFF selects only eggs in slots. ON also includes dropped field eggs that match your filters.")
    do (function()
    local state={enabled=false}
    automationFlow.progression=state
    switch(autoStealPage,"Steal Progression",false,function(value) state.enabled=value; invalidate() end,
        "Re-read normal carrying speed before every target. Exclude areas below the game's escape requirement, including Rift targets. Unknown requirements are excluded. Temporary approach boosts do not count.")
    local function progressionSnapshot(humanoid)
        local speed=humanoid and humanoid.WalkSpeed or 0
        if approachOverride and approachOverride.humanoid==humanoid and approachOverride.base then speed=approachOverride.base end
        local result={speed=speed,allowed={},details={}}
        local function key(name) return tostring(name):lower():gsub("[^%w]",""):gsub("angelsanddemons","angelsdemons"):gsub("lightdark","angelsdemons") end
        local ok,err=pcall(function()
            local storage=game:GetService("ReplicatedStorage")
            local requirement=require(storage.Shared.Modules.GuardAreas.GuardEscapeRequirement)
            local util=require(storage.Shared.Util.TreadmillUtil)
            local areaData=require(storage.Data.Areas).Directory
            local guards=require(storage.Data.Guards).Directory
            local objects=workspace:FindFirstChild("__OBJECTS")
            local areas=objects and objects:FindFirstChild("Areas")
            local line=areas and areas:FindFirstChild("SeparationLine")
            assert(areas and line,"Area boundary unavailable")
            local models={}
            for _,model in ipairs(areas:GetDescendants()) do
                if model:IsA("Model") and model:FindFirstChild("Bounds") and model:FindFirstChild("ClosestExitPoint") then models[key(model.Name)]=model end
            end
            for _,area in ipairs(areaOptions) do
                local found,detail=pcall(function()
                    local model=assert(models[key(area)],"Area model missing")
                    local config=assert(areaData[model.Name],"Area config missing")
                    local guardConfig=assert(guards[config.GuardId],"Guard config missing")
                    local guard=model:FindFirstChild("Guard")
                    local root=guard and guard:FindFirstChild("HumanoidRootPart")
                    assert(root and root:IsA("BasePart"),"Guard position missing")
                    local power=requirement.ResolveSpeedPower(model,root.Position,line)
                    local threshold=math.max(guardConfig.WalkSpeed*1.05,util.SpeedPowerToWalkSpeed(power))
                    assert(type(threshold)=="number" and threshold>0 and threshold<math.huge,"Invalid escape requirement")
                    result.allowed[area]=speed==speed and speed>=threshold
                    return string.format("%s: guard %.1f | escape %.1f | %s",area,guardConfig.WalkSpeed,threshold,result.allowed[area] and "ELIGIBLE" or "TOO SLOW")
                end)
                result.details[#result.details+1]=found and detail or (area..": UNKNOWN — "..tostring(detail))
            end
        end)
        if not ok then result.details[#result.details+1]="Requirements unavailable: "..tostring(err) end
        return result
    end
    local progressionReport=""
    local progressionRead=button("Preview Steal Progression",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,36))
    local progressionCopy=button("Copy Steal Progression",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,36))
    local progressionStatus=label("Preview compares freshly read carrying speed with live area escape requirements.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,230),true)
    progressionStatus.TextSize=14
    connect(progressionRead.Activated,function()
        local snapshot=progressionSnapshot(movementHumanoid(player.Character))
        progressionReport=string.format("AcidHub Steal Progression | Normal speed %.2f\n",snapshot.speed)..table.concat(snapshot.details,"\n")
        progressionStatus.Text=progressionReport
    end)
    connect(progressionCopy.Activated,function() if type(setclipboard)=="function" then pcall(setclipboard,progressionReport) end end)
    state.snapshot=progressionSnapshot
    state.show=function(snapshot)
        progressionReport=string.format("AcidHub Steal Progression | Normal speed %.2f\n",snapshot.speed)..table.concat(snapshot.details,"\n")
        progressionStatus.Text=progressionReport
    end
    end)() end
    -- Bounded, searchable dropdowns expand inside the scrolling accordion.
    local openDropdown
    local function dropdown(title,options,multiple,get,set,caption)
        local frame=row(autoStealPage,42)
        label(title,UDim2.fromOffset(10,0),UDim2.new(0.48,-10,0,42),frame).TextSize=14
        local control=button("",UDim2.new(0.48,0,0,6),UDim2.new(0.52,-8,0,30),frame)
        control.TextSize=16
        local body=make("Frame",{Position=UDim2.fromOffset(8,44),Size=UDim2.new(1,-16,0,224),
            BackgroundColor3=colors.panel,BorderSizePixel=0,Visible=false},frame)
        local search=make("TextBox",{Text="",PlaceholderText="Search",ClearTextOnFocus=false,
            Position=UDim2.fromOffset(6,4),Size=UDim2.new(1,-12,0,28),BackgroundColor3=colors.card,
            TextColor3=colors.text,BorderSizePixel=0,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextSize=14},body)
        local list=make("ScrollingFrame",{Position=UDim2.fromOffset(6,36),Size=UDim2.new(1,-12,1,-42),
            BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.new(),
            AutomaticCanvasSize=Enum.AutomaticSize.Y},body)
        make("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,3)},list)
        local entries={}
        local function refresh()
            local value=get()
            local selected={}
            if multiple then for name,enabled in pairs(value) do if enabled then table.insert(selected,name) end end; table.sort(selected) end
            control.Text=(multiple and (#selected==0 and "All" or #selected==1 and selected[1] or tostring(#selected).." selected") or value).."  v"
            local query=string.lower(search.Text)
            for _,entry in ipairs(entries) do
                local active=multiple and value[entry.value] or value==entry.value
                entry.button.Text=(active and "✓ " or "")..entry.caption
                entry.button.TextColor3=active and colors.accent or colors.text
                entry.button.Visible=query=="" or string.find(string.lower(entry.caption),query,1,true)~=nil
            end
        end
        local function close() body.Visible=false; frame.Size=UDim2.new(1,0,0,42) end
        if multiple then
            local clear=button("Clear selection (All)",UDim2.new(),UDim2.new(1,-4,0,28),list)
            clear.LayoutOrder=0
            connect(clear.Activated,function() set({}); invalidate(); refresh() end)
        end
        for index,value in ipairs(options) do
            local option=button("",UDim2.new(),UDim2.new(1,-4,0,28),list)
            option.LayoutOrder=index; option.TextSize=16
            table.insert(entries,{value=value,caption=caption and caption(value) or value,button=option})
            connect(option.Activated,function()
                if multiple then local nextValue=copySetting(get()); nextValue[value]=not nextValue[value]; set(nextValue)
                else set(value); close() end
                invalidate(); refresh()
            end)
        end
        connect(search:GetPropertyChangedSignal("Text"),refresh)
        connect(control.Activated,function()
            if body.Visible then close(); return end
            if openDropdown then openDropdown() end
            openDropdown=close; body.Visible=true; frame.Size=UDim2.new(1,0,0,276); refresh()
        end)
        refresh()
        return refresh
    end
    do (function()
        local limits={maximum="No Limit",cutoff="Off",day=nil,count=0,delivered={}}
        automationFlow.stealLimits=limits
        local refreshMax=dropdown("Max Eggs per Day",{"No Limit","5 Eggs","10 Eggs"},false,function() return limits.maximum end,function(value) limits.maximum=value end)
        registerSetting("Steal.MaxEggsPerDay","No Limit",function() return limits.maximum end,function(value) limits.maximum=value; refreshMax(); return true end,
            function(value) return value=="No Limit" or value=="5 Eggs" or value=="10 Eggs" end)
        local refreshCutoff=dropdown("Stop Before Night",{"Off","1 min","2 min"},false,function() return limits.cutoff end,function(value) limits.cutoff=value end)
        registerSetting("Steal.StopBeforeNight","Off",function() return limits.cutoff end,function(value) limits.cutoff=value; refreshCutoff(); return true end,
            function(value) return value=="Off" or value=="1 min" or value=="2 min" end)
        function limits.sync()
            local cycle=require(game:GetService("ReplicatedStorage").Shared.Util.AreaEggCycle)
            local now=workspace:GetServerTimeNow()
            local day=cycle.PeriodIndexAt(now)
            if limits.day~=day then limits.day=day; limits.count=0; limits.delivered={} end
            return cycle,now
        end
        function limits.record(uid)
            limits.sync()
            if not limits.delivered[uid] then limits.delivered[uid]=true; limits.count=limits.count+1 end
        end
        function limits.reason()
            local cycle,now=limits.sync()
            local maximum=limits.maximum=="5 Eggs" and 5 or limits.maximum=="10 Eggs" and 10 or nil
            if maximum and limits.count>=maximum then return "Daily egg limit reached: "..limits.count.."/"..maximum end
            local seconds=limits.cutoff=="1 min" and 60 or limits.cutoff=="2 min" and 120 or nil
            if seconds and cycle.IsRunning() and cycle.NightStartTime(now)-now<=seconds then
                return "Stop Before Night reached: "..limits.cutoff
            end
        end
    end)() end
    do
    local approachOptions={"Current Speed","10%","20%","30%","40%","50%","60%","70%","80%","90%","100%"}
    local refreshApproach=dropdown("Approach Speed",approachOptions,false,function() return approachSpeed end,function(value) approachSpeed=value end)
    registerSetting("Steal.ApproachSpeed","Current Speed",function() return approachSpeed end,function(value)
        approachSpeed=(value=="Instant" or value=="Teleport") and "Current Speed" or value; refreshApproach(); invalidate(); return true
    end,function(value) return value=="Instant" or value=="Teleport" or table.find(approachOptions,value)~=nil end)
    end
    local refreshAreas=dropdown("Target Areas",areaOptions,true,function() return previewAreas end,function(value) previewAreas=value end)
    registerSetting("StealPreview.Areas",copySetting(previewAreas),function() return copySetting(previewAreas) end,function(value)
        previewAreas=copySetting(value); refreshAreas(); invalidate(); return true
    end,function(value)
        if type(value)~="table" then return false end
        for name,enabled in pairs(value) do if not table.find(areaOptions,name) or type(enabled)~="boolean" then return false end end
        return true
    end)
    local minimumOptions={"All"}
    for _,name in ipairs(rarityOptions) do if name~="Unknown" then table.insert(minimumOptions,name) end end
    local refreshMinimum=dropdown("Minimum Rarity",minimumOptions,false,function() return minimum end,function(value) minimum=value end)
    registerSetting("StealPreview.Minimum","All",function() return minimum end,function(value)
        minimum=value; refreshMinimum(); invalidate(); return true
    end,function(value) return table.find(minimumOptions,value)~=nil end)
    local speciesOptions,speciesRarities={},{}
    for _,entry in pairs(Rarity.Species) do
        if not speciesRarities[entry.name] then table.insert(speciesOptions,entry.name); speciesRarities[entry.name]=entry.rarity end
    end
    table.sort(speciesOptions,function(a,b)
        local ar,br=table.find(rarityOptions,speciesRarities[a]) or 0,table.find(rarityOptions,speciesRarities[b]) or 0
        if ar~=br then return ar<br end
        return a<b
    end)
    local function speciesSelection()
        local selected={}
        for name in speciesText:gmatch("[^,]+") do
            name=name:match("^%s*(.-)%s*$")
            if name~="" then local resolved=Rarity.Resolve(name); selected[resolved]=true end
        end
        return selected
    end
    local refreshSpecies=dropdown("Target Specific Eggs",speciesOptions,true,speciesSelection,function(value)
        local selected={}
        for name,enabled in pairs(value) do if enabled then table.insert(selected,name) end end
        table.sort(selected); speciesText=table.concat(selected,", ")
    end,function(name) return name.." ["..speciesRarities[name].."]" end)
    registerSetting("StealPreview.Species","",function() return speciesText end,function(value)
        speciesText=value; refreshSpecies(); invalidate(); return true
    end,function(value) return type(value)=="string" and #value<=20000 end)
    local priorities={"Best Rarity","Best Weight","Mutation","Highest Money/Sec"}
    local refreshPriority=dropdown("Steal Priority",priorities,false,function() return priority end,function(value) priority=value end)
    registerSetting("StealPreview.Priority","Best Rarity",function() return priority end,function(value)
        priority=value=="Nearest" and "Best Rarity" or value; refreshPriority(); invalidate(); return true
    end,function(value) return value=="Nearest" or table.find(priorities,value)~=nil end)
    previewButton=button("Preview Target",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local copyButton=button("Copy Selection Report",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local saveButton=button("Save Selection Report",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    previewStatus=label("Ready. Set filters and press Preview Target. No movement or pickup.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,90),true)
    previewStatus.TextSize=14
    previewBox=make("TextBox",{Name="StealSelectionReport",Text="",TextEditable=false,ClearTextOnFocus=false,
        MultiLine=true,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
        BackgroundTransparency=1,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextSize=14,TextColor3=colors.text,
        Position=UDim2.fromOffset(10,6),Size=UDim2.new(1,-20,1,-12)},row(debugPage,320))
    local function nameKey(value) return string.lower(value):gsub("[%s%-%_]","") end
    local ranks={}
    for index,name in ipairs(rarityOptions) do if name~="Unknown" then ranks[name]=index end end
    -- Use the same decoded-egg conversions as the game's sell inventory UI.
    local function eggMetrics(record)
        local ok,records,egg=pcall(function()
            local module=require(game:GetService("ReplicatedStorage").Shared.Util.EggRecords)
            return module,module.Decode(record)
        end)
        if not ok then return nil,nil end
        local function metric(callback)
            local valid,value=pcall(callback)
            if valid and type(value)=="number" and value==value and value>=0 and value<math.huge then return value end
        end
        local weight=metric(function() return records.WeightKg(egg) end)
        local income=metric(function()
            local earnings=require(game:GetService("ReplicatedStorage").Shared.Util.AssetEarnings)
            return earnings.RatePerSecond(records.ToAssetItemData(egg))
        end)
        return weight,income
    end
    local function mutationRank(value,baseMutation)
        local names=string.lower(mutationNames(value,baseMutation))
        if names:find("rainbow",1,true) then return 3 end
        if names:find("golden",1,true) then return 2 end
        if names:find("silver",1,true) then return 1 end
        return 0
    end
    local function priorityValue(candidate,selectedPriority)
        if selectedPriority=="Best Weight" then return candidate.weight end
        if selectedPriority=="Highest Money/Sec" then return candidate.income end
        if selectedPriority=="Mutation" then return candidate.mutationRank end
        return candidate.rank
    end
    local function metricFields(record)
        local fields={}
        for key,value in pairs(record) do
            if type(key)=="string" and (type(value)=="number" or type(value)=="table") then
                table.insert(fields,key.."="..(type(value)=="table" and "<table>" or tostring(value)))
            end
        end
        table.sort(fields)
        return table.concat(fields,", ")
    end
    local function evaluate(records,origin,filters)
        local candidates,excluded,states,seen={},{},{},{}
        local wanted,matched={},{}
        local anyArea=true
        for _,value in pairs(filters.areas) do if value then anyArea=false; break end end
        for name in filters.species:gmatch("[^,]+") do
            local trimmed=name:match("^%s*(.-)%s*$")
            if trimmed~="" then wanted[nameKey(trimmed)]=trimmed end
        end
        local total=0
        local function reject(reason) excluded[reason]=(excluded[reason] or 0)+1 end
        for _,record in pairs(records) do
            total=total+1
            assert(total<=5000,"Egg snapshot exceeds preview limit (5000); no selection made.")
            assert(type(record)=="table" and type(record.Uid)=="string" and record.Uid~="","Invalid egg record; no selection made.")
            assert(not seen[record.Uid],"Duplicate egg ID; no selection made."); seen[record.Uid]=true
            local rawArea=tostring(record.AreaId or "Unknown")
            local area=areas[string.lower(rawArea):gsub("[^%w]","")] or rawArea
            local rawName=tostring(record.AssetCategory or "Unknown egg")
            local name=Rarity.Resolve(rawName,area)
            local rarity=automationFlow.audit.rarity(rawName)
            local rawKey,displayKey=nameKey(rawName),nameKey(name)
            if wanted[rawKey] then matched[rawKey]=true end
            if wanted[displayKey] then matched[displayKey]=true end
            local state=tostring(record.State or "Unknown")
            states[state]=(states[state] or 0)+1
            local frame=typeof(record.BoundsCFrame)=="CFrame" and record.BoundsCFrame or record.BottomCFrame
            local reason
            if not table.find(areaOptions,area) then reason="Unknown field area: "..rawArea
            elseif not stealableFieldState(state) then reason="State is not stealable: "..state
            elseif not (filters.indexNeeds and filters.indexNeeds[rawName]) and not anyArea and not filters.areas[area] then reason="Area filter"
            elseif not (filters.indexNeeds and filters.indexNeeds[rawName]) and filters.minimum~="All" and (ranks[rarity] or 0)<ranks[filters.minimum] then reason="Minimum rarity"
            elseif not (filters.indexNeeds and filters.indexNeeds[rawName]) and next(wanted) and not wanted[rawKey] and not wanted[displayKey] then reason="Species filter"
            elseif typeof(frame)~="CFrame" then reason="Missing position"
            end
            if reason then reject(reason)
            else
                local distance=(frame.Position-origin).Magnitude
                if distance~=distance or distance==math.huge then reject("Invalid distance")
                else
                    local weight,income=eggMetrics(record)
                    table.insert(candidates,{id=record.Uid,name=name,rawName=rawName,area=area,rarity=rarity,
                    rank=ranks[rarity] or 0,distance=distance,state=state,mutation=mutationNames(record.Mutations,record.BaseMutation),position=frame.Position,
                    mutationRank=mutationRank(record.Mutations,record.BaseMutation),
                    metricFields=metricFields(record),weight=weight,income=income}) end
            end
        end
        table.sort(candidates,function(a,b)
            local av,bv=priorityValue(a,filters.priority),priorityValue(b,filters.priority)
            if av~=bv then
                if av==nil then return false end
                if bv==nil then return true end
                return av>bv
            end
            if av==nil and a.rank~=b.rank then return a.rank>b.rank end
            if a.distance~=b.distance then return a.distance<b.distance end
            return a.id<b.id
        end)
        local unmatched={}
        for key,name in pairs(wanted) do if not matched[key] then table.insert(unmatched,name) end end
        table.sort(unmatched)
        return {candidates=candidates,excluded=excluded,states=states,total=total,unmatched=unmatched}
    end
    -- First automated collection test. Configuration reuses the preview filters.
    do
        local running=false
        local cycleJob
        local runId=0
        local job
        local heldPrompt,movingHumanoid
        local ignored={}
        local completed=0
        local returnedHome=false
        local log={}
        local masterRow=row(autoStealPage,42)
        label("Auto Steal",UDim2.fromOffset(10,0),UDim2.new(1,-88,1,0),masterRow)
        local control=button("OFF",UDim2.new(1,-74,0,6),UDim2.fromOffset(64,30),masterRow)
        control.Parent.LayoutOrder=-1
        label("Uses your filters and the daily automation sequence. Remains ON while idle or recovering after respawn. Defaults to OFF; Save settings remembers your ON/OFF choice.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(autoStealPage,130),true).TextSize=14
        local autoStatus=label("Auto Steal is OFF.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,110),true)
        autoStatus.TextSize=14
        local copyLog=button("Copy Auto Steal Log",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,36))
        local function note(message)
            reportTask("Auto Steal",message)
            automationFlow.audit.stealReason=message
            automationFlow.audit.emit("AutoSteal","status",{message=message})
            autoStatus.Text=message.." | Delivered: "..completed
            table.insert(log,string.format("[%.2f] %s",os.clock(),message))
            if #log>150 then table.remove(log,1) end
        end
        local function stopMotion()
            if approachOverride.humanoid then
                local boostedHumanoid=approachOverride.humanoid
                local restoreTarget=speedLocked and targetSpeed or approachOverride.base
                approachOverride.humanoid=nil
                boostedHumanoid.WalkSpeed=restoreTarget
                if speedHumanoid==boostedHumanoid then
                    if speedLocked then lastAppliedSpeed=restoreTarget
                    else speedHumanoid,originalSpeed,lastAppliedSpeed=nil,nil,nil end
                end
                note(string.format("Approach boost ended | restored WalkSpeed %.2f",restoreTarget))
            end
            if heldPrompt then pcall(function() heldPrompt:InputHoldEnd() end); heldPrompt=nil end
            if movingHumanoid then
                pcall(function()
                    movingHumanoid:Move(Vector3.zero,false)
                    local root=movingHumanoid.RootPart
                    if root then
                        movingHumanoid:MoveTo(root.Position)
                        if not root.Anchored then
                            root.AssemblyLinearVelocity=Vector3.zero
                            root.AssemblyAngularVelocity=Vector3.zero
                        end
                    end
                end)
                movingHumanoid=nil
            end
        end
        local function leaveTreadmill(character,humanoid)
            if treadmillExitBusy then return false,"Waiting for treadmill exit and No Slow reapplication" end
            local root=character and character:FindFirstChild("HumanoidRootPart")
            if not humanoid or not root or player.Character~=character then return false,"Character unavailable" end
            if movementHumanoid(character)~=humanoid then return false,"Movement Humanoid changed; retrying with the current one" end
            if root.Anchored then
                local requested=requestTreadmillExitJump(character,humanoid,true)
                -- Exit can restore/destroy this Humanoid. Reacquire it on the next cycle.
                return false,requested and "Treadmill exit requested; waiting for release" or "Anchored outside a recognized treadmill"
            end
            if humanoid.Sit or humanoid.PlatformStand then
                humanoid.Sit=false
                humanoid.PlatformStand=false
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                return false,"Waiting for character recovery"
            end
            return true
        end
        local function stop(message)
            running=false; runId=runId+1
            if automationFlow.audit.stealAttempt then
                automationFlow.audit.emit("AutoSteal","attempt_not_confirmed",{attempt=automationFlow.audit.stealAttempt,success=false,reason=message or "Stopped"})
                automationFlow.audit.stealAttempt=nil
            end
            automationFlow.steal=false; automationFlow.collecting=false; automationFlow.pendingDay=false
            if automationFlow.phase=="stealing" or automationFlow.phase=="preparing" then flowPlace("Auto Steal stopped") end
            if cycleJob then pcall(task.cancel,cycleJob); cycleJob=nil end
            if job then pcall(task.cancel,job); job=nil end
            stopMotion(); control.Text="OFF"; control.TextColor3=colors.muted
            if message then note(message) end
        end
        local function fields()
            local client=game:GetService("ReplicatedStorage"):FindFirstChild("Client")
            local module=client and client:FindFirstChild("EggState")
            assert(module,"EggState unavailable")
            local reader=require(module)
            local result=reader.ReadFieldEggs()
            assert(type(result)=="table" and type(result.Records)=="table","Field data unavailable")
            local byId={}
            for _,record in pairs(result.Records) do
                assert(type(record)=="table" and type(record.Uid)=="string" and not byId[record.Uid],"Invalid or duplicate field UID")
                byId[record.Uid]=record
            end
            return reader,result.Records,byId
        end
        local function owned(reader)
            local result=reader.ReadOwnedEggs()
            assert(type(result)=="table","Owned data unavailable")
            local records
            for _,group in pairs(result) do
                if type(group)=="table" and tonumber(group.OwnerUserId)==player.UserId then
                    assert(not records and type(group.Records)=="table","Invalid owned group")
                    records=group.Records
                end
            end
            assert(records,"Local owned inventory unavailable")
            return copySetting(records)
        end
        local function matching(a,b)
            for _,key in ipairs({"AssetCategory","AssetColorIndex","AssetColorSeed","AssetEyeColor","AssetScale"}) do
                if a[key]==nil or b[key]==nil then return false end
                if key=="AssetScale" then
                    local x,y=tonumber(a[key]),tonumber(b[key])
                    if not x or not y or x~=x or y~=y or math.abs(x-y)>0.000001 then return false end
                elseif tostring(a[key])~=tostring(b[key]) then return false end
            end
            return true
        end
        local function equipFreeHands(character,humanoid)
            if not character or not humanoid then return false,"character unavailable" end
            local backpack=player:FindFirstChildOfClass("Backpack")
            local function isFreeHands(tool)
                if not tool or not tool:IsA("Tool") then return false end
                local name=string.lower(tool.Name)
                return name=="free hands" or name=="freehands" or name:find("free",1,true) and name:find("hand",1,true)
            end
            local freeHands
            for _,container in ipairs({character,backpack}) do
                if container then
                    for _,child in ipairs(container:GetChildren()) do
                        if isFreeHands(child) then freeHands=child; break end
                    end
                end
                if freeHands then break end
            end
            pcall(function() humanoid:UnequipTools() end)
            if freeHands then
                local ok=pcall(function() humanoid:EquipTool(freeHands) end)
                return ok,ok and "equipped" or "equip failed"
            end
            return false,"Free Hands tool not found; unequipped current tool"
        end
        local function directMove(character,humanoid,destination,check,arrivalRadius,timeout,outboundMode)
            arrivalRadius=arrivalRadius or 3
            timeout=timeout or 60
            local root=character:FindFirstChild("HumanoidRootPart")
            if not root or root.Anchored then
                local ready,reason=leaveTreadmill(character,humanoid)
                if not ready then return false,reason end
                root=character:FindFirstChild("HumanoidRootPart")
            end
            local deadline=os.clock()+timeout
            local lastCommand=-math.huge
            local lastCheck=0
            local bonus=(tonumber((outboundMode or ""):match("^(%d+)%%$")) or 0)/100
            movingHumanoid=humanoid
            if bonus>0 then
                applyEffectiveSpeed(humanoid)
                approachOverride.base=humanoid.WalkSpeed
                approachOverride.speed=approachOverride.base*(1+bonus)
                approachOverride.humanoid=humanoid
                applyEffectiveSpeed(humanoid)
                note(string.format("Outbound speed %.1f -> %.1f (+%.0f%%); restore before pickup",approachOverride.base,approachOverride.speed,bonus*100))
            end
            while running and os.clock()<deadline do
                assert(player.Character==character and humanoid.Parent==character and humanoid.Health>0,"Character changed or died")
                if root.Anchored then
                    local ready,reason=leaveTreadmill(character,humanoid)
                    if not ready then stopMotion(); return false,reason end
                end
                local delta=destination-root.Position
                local flatDistance=Vector3.new(delta.X,0,delta.Z).Magnitude
                local verticalClose=math.abs(delta.Y)<=humanoid.HipHeight+root.Size.Y/2+2
                local distance=verticalClose and flatDistance or delta.Magnitude
                if distance<=arrivalRadius then stopMotion(); return true end
                if check and os.clock()-lastCheck>=0.2 then
                    lastCheck=os.clock()
                    local proceed,done=check()
                    if done then stopMotion(); return true end
                    if not proceed then stopMotion(); return false end
                end
                if os.clock()-lastCommand>=2 then
                    lastCommand=os.clock()
                    humanoid:MoveTo(destination)
                end
                game:GetService("RunService").Heartbeat:Wait()
            end
            stopMotion(); return false
        end
        local function pickupPrompt(record)
            local exact,nearby,diagnostics={},{},{}
            local frame=typeof(record.BottomCFrame)=="CFrame" and record.BottomCFrame or record.BoundsCFrame
            assert(typeof(frame)=="CFrame","Egg position unavailable")
            local scanned=0
            for _,object in ipairs(workspace:GetDescendants()) do
                scanned=scanned+1
                assert(scanned<=60000,"Prompt scan limit reached; cannot identify target confidently")
                if object:IsA("ProximityPrompt") and object.Enabled then
                    local node=object.Parent
                    local anchor=node and (node:IsA("Attachment") and node.WorldPosition or node:IsA("BasePart") and node.Position or node:IsA("Model") and node:GetPivot().Position)
                    local identified=false
                    for _=1,6 do
                        if not node or node==workspace then break end
                        if node.Name==record.Uid or node:GetAttribute("Uid")==record.Uid or node:GetAttribute("UID")==record.Uid or node:GetAttribute("EggUid")==record.Uid then identified=true end
                        node=node.Parent
                    end
                    local distance=anchor and (anchor-frame.Position).Magnitude
                    if #diagnostics<12 and (identified or (distance and distance<=5)) then
                        table.insert(diagnostics,string.format("%s | Action=%s | Object=%s | egg distance=%s | range=%.1f | UID match=%s",
                            object:GetFullName(),object.ActionText,object.ObjectText,distance and string.format("%.2f",distance) or "unavailable",object.MaxActivationDistance,tostring(identified)))
                    end
                    if identified then table.insert(exact,object)
                    elseif anchor and (anchor-frame.Position).Magnitude<=5 then
                        local action=string.lower(object.ActionText)
                        if action:find("pick",1,true) or action:find("grab",1,true) or action:find("steal",1,true) then table.insert(nearby,{prompt=object,distance=distance or math.huge}) end
                    end
                end
            end
            if #exact==1 then return exact[1] end
            if #exact==0 and #nearby==1 then return nearby[1].prompt end
            if #exact==0 and #nearby>1 then
                table.sort(nearby,function(a,b) return a.distance<b.distance end)
                if nearby[1].distance+1<nearby[2].distance then return nearby[1].prompt end
            end
            return nil,"Pickup prompt unresolved (UID matches="..#exact..", nearby pickup matches="..#nearby.."). No interaction sent. Candidates (up to 12): "..(#diagnostics>0 and table.concat(diagnostics," ; ") or "none")
        end
        local function cycle()
        local function requestFieldCarry(reader,record)
            assert(type(reader.CarryFieldEgg)=="function","EggState.CarryFieldEgg unavailable")
            -- Match the game's prompt callback, including tutorial slot identity.
            local identity=require(game:GetService("ReplicatedStorage").Shared.Util.AreaEggSlotIdentity)
            local slotKey
            if identity.LooksLikeFirstAreaUid(record.Uid) then
                slotKey=identity.SlotKey(record.AreaId,record.NestId)
            end
            return reader.CarryFieldEgg(record.Uid,slotKey)
        end
            if automationFlow.bossPauseRequested or treadmillExitBusy or (automationFlow.rift and automationFlow.rift.busy) then task.wait(0.1); return end
            if automationFlow.pendingDay then flowPhase("preparing","Starting the new day's collection") end
            if automationFlow.phase~="stealing" and automationFlow.phase~="preparing" then task.wait(0.25); return end
            if automationFlow.placing or not automationFlow.cycleReady then task.wait(0.25); return end
            local character=player.Character
            local humanoid=movementHumanoid(character)
            assert(character and humanoid and humanoid.Health>0,"Wait for a living character")
            assert(not character:FindFirstChild("AcidHubOriginalHumanoid"),"Animation Sync Test conflicts with automatic movement. Rejoin and use normal No Slow for this test.")
            local root=character:FindFirstChild("HumanoidRootPart")
            assert(root,"Root part unavailable")
            if automationFlow.phase=="preparing" then
                local epoch=automationFlow.epoch
                local ready,reason=leaveTreadmill(character,humanoid)
                if not ready then note("Waiting to leave treadmill: "..tostring(reason)); task.wait(1); return end
                local inField=automationFlow.audit.inField(root.Position)
                if not inField and not directMove(character,humanoid,autoStealSafeZone,nil,4,60) then task.wait(1); return end
                note(inField and "Already in gameplay field; waiting 4 seconds, no safe-zone return" or "At safe zone; waiting 4 seconds before stealing")
                local waitUntil=os.clock()+4
                while running and os.clock()<waitUntil do
                    if not root.Parent or (not inField and (root.Position-autoStealSafeZone).Magnitude>8) then return end
                    task.wait(0.1)
                end
                if not running or epoch~=automationFlow.epoch then return end
                automationFlow.pendingDay=false; returnedHome=true; ignored={}
                flowPhase("stealing","Startup wait complete")
            end
            local limitReason=automationFlow.stealLimits.reason()
            if limitReason then note(limitReason); flowPlace(limitReason); return end
            local reader,records,byId=fields()
            for _,record in pairs(records) do
                assert(not (record.State=="Carried" and tonumber(record.CarrierUserId)==player.UserId),"Already carrying a field egg. Deliver it manually before starting.")
            end
            local filters={areas=copySetting(previewAreas),minimum=minimum,priority=priority,species=speciesText}
            filters.indexNeeds=automationFlow.indexCompletion.needs()
            local ranked=evaluate(records,root.Position,filters)
            if automationFlow.rift and automationFlow.rift.enabled then
                local names={}
                for category,count in pairs(automationFlow.rift.needs()) do if count>0 then names[#names+1]=category end end
                if #names>0 then
                    local extras=evaluate(records,root.Position,{areas={},minimum="All",priority=priority,species=table.concat(names,",")})
                    local seen={}; for _,candidate in ipairs(ranked.candidates) do seen[candidate.id]=true end
                    for _,candidate in ipairs(extras.candidates) do if not seen[candidate.id] then candidate.rift=true; candidate.riftKey=automationFlow.rift.recipeKey; ranked.candidates[#ranked.candidates+1]=candidate end end
                end
            end
            if automationFlow.progression.enabled then
                local snapshot=automationFlow.progression.snapshot(humanoid)
                local reachable={}
                for _,candidate in ipairs(ranked.candidates) do if snapshot.allowed[candidate.area] then reachable[#reachable+1]=candidate end end
                ranked.candidates=reachable
                automationFlow.progression.show(snapshot)
            end
            local target
            for _,candidate in ipairs(ranked.candidates) do if not ignored[candidate.id] or ignored[candidate.id]<os.clock() then target=candidate; break end end
            if not target then
                note("No eligible targets remain; collection finished for this day")
                flowPlace("Collection finished")
                task.wait(0.25)
                return
            end
            local ready,reason=leaveTreadmill(character,humanoid)
            if not ready then note("Target found, but movement is locked. Leave treadmill or wait for character release | "..tostring(reason)); task.wait(1); return end
            root=character:FindFirstChild("HumanoidRootPart")
            assert(root,"Root part unavailable")
            if not returnedHome and not automationFlow.audit.inField(root.Position) and (root.Position-autoStealSafeZone).Magnitude>8 then
                note("Target found; returning to safe zone before stealing")
                if not directMove(character,humanoid,autoStealSafeZone,nil,4,60) then note("Could not reach safe zone before target selection"); task.wait(1); return end
                returnedHome=true
                task.wait(0.2)
                return
            end
            returnedHome=true
            local record=copySetting(byId[target.id])
            automationFlow.audit.stealAttempt={uid=target.id,values=automationFlow.audit.values(record),filters=filters}
            automationFlow.audit.stealReason="Approaching target"
            automationFlow.audit.emit("AutoSteal","attempt_started",automationFlow.audit.stealAttempt)
            local inventoryBefore=owned(reader)
            local filterGeneration=generation
            local outboundMode=approachSpeed
            note("Approaching "..target.name.." | UID "..target.id.." | WalkSpeed "..string.format("%.1f",humanoid.WalkSpeed).." | Approach "..outboundMode)
            local approachStarted=os.clock()
            local frame=typeof(record.BottomCFrame)=="CFrame" and record.BottomCFrame or record.BoundsCFrame
            assert(typeof(frame)=="CFrame","Target has no usable position")
            local destination=frame.Position+Vector3.new(0,humanoid.HipHeight+root.Size.Y/2,0)
            local function approachCheck()
                if automationFlow.stealLimits.reason() then return false,false end
                if target.rift and (not automationFlow.rift or not automationFlow.rift.enabled or automationFlow.rift.paused or not automationFlow.rift.bannerMatches() or target.riftKey~=automationFlow.rift.recipeKey) then return false,false end
                return generation==filterGeneration,false
            end
            local approached=directMove(character,humanoid,destination,approachCheck,3,45,outboundMode)
            if not approached then ignored[target.id]=os.clock()+20; note("Direct move did not reach target; moving to next target"); task.wait(0.5); return end
            local _,_,current=fields()
            if generation~=filterGeneration or not current[target.id] or not stealableFieldState(current[target.id].State) then return end
            note(string.format("Approach completed in %.2fs | WalkSpeed %.1f",os.clock()-approachStarted,humanoid.WalkSpeed))
            -- Stop and restore the approach boost before issuing the exact-UID request.
            local stopDeadline=os.clock()+0.12
            repeat
                movingHumanoid=humanoid
                stopMotion()
                game:GetService("RunService").Heartbeat:Wait()
            until not running or os.clock()>=stopDeadline
            if target.rift and (not automationFlow.rift.enabled or (automationFlow.rift.needs()[target.rawName] or 0)<=0) then return end
            if not target.rift then
                filters.indexNeeds=automationFlow.indexCompletion.needs()
                if #evaluate({record},root.Position,filters).candidates==0 then
                    note("Target no longer needed by index or normal filters; rescanning"); return
                end
            end
            if automationFlow.progression.enabled and not automationFlow.progression.snapshot(humanoid).allowed[target.area] then
                note("Steal Progression: carrying speed/requirement changed; skipping "..target.name); return
            end
            local carrying=false
            for attempt=1,2 do
                if not running or generation~=filterGeneration then return end
                local limitReason=automationFlow.stealLimits.reason()
                if limitReason then note(limitReason); flowPlace(limitReason); return end
                assert(player.Character==character and humanoid.Parent==character and humanoid.Health>0,"Character changed before pickup")
                local _,_,latest=fields()
                local pickupRecord=latest[target.id]
                if not pickupRecord or not stealableFieldState(pickupRecord.State) then
                    note("Target changed before UID pickup; moving to next target")
                    return
                end
                note("CarryFieldEgg request | UID "..target.id.." | attempt "..attempt.." | WalkSpeed "..string.format("%.2f",humanoid.WalkSpeed))
                local accepted,message=requestFieldCarry(reader,pickupRecord)
                note("CarryFieldEgg returned "..tostring(accepted).." | message="..tostring(message))
                automationFlow.audit.emit("AutoSteal","pickup_result",{uid=target.id,accepted=accepted,message=message,attempt=attempt})
                if not running then return end
                if accepted==true then
                    local confirmUntil=os.clock()+3
                    repeat
                        if not running then return end
                        local _,_,now=fields(); local egg=now[target.id]
                        carrying=egg and egg.State=="Carried" and tonumber(egg.CarrierUserId)==player.UserId
                        if carrying then break end
                        assert(player.Character==character and humanoid.Parent==character and humanoid.Health>0,"Character changed while confirming pickup")
                        task.wait(0.1)
                    until os.clock()>=confirmUntil
                    -- An accepted request may still be replicating. Do not send it twice.
                    break
                elseif attempt==1 and message=="Get closer to the egg" then
                    local _,_,fresh=fields(); local live=fresh[target.id]
                    if not live or not stealableFieldState(live.State) then break end
                    local liveFrame=typeof(live.BottomCFrame)=="CFrame" and live.BottomCFrame or live.BoundsCFrame
                    if typeof(liveFrame)~="CFrame" then break end
                    note("Server requested closer approach; retrying the same UID once at normal speed")
                    if not directMove(character,humanoid,liveFrame.Position+Vector3.new(0,humanoid.HipHeight+root.Size.Y/2,0),approachCheck,1,10) then break end
                else break end
            end
            if not carrying then
                ignored[target.id]=os.clock()+60
                note("UID pickup not confirmed; moving to next target: "..target.name)
                return
            end
            note("Carrying "..target.name.."; returning to safe zone")
            local deliveredUid
            local lostCarry=false
            local function checkDelivery()
                local _,_,now=fields(); local egg=now[target.id]
                if not egg then
                    local count=0
                    for id,value in pairs(owned(reader)) do
                        if not inventoryBefore[id] and matching(record,value) then deliveredUid=id; count=count+1 end
                    end
                    assert(count<=1,"Delivery ambiguous: multiple matching new inventory eggs")
                    if count==1 then return true,true end
                    return true,false
                end
                if not (egg.State=="Carried" and tonumber(egg.CarrierUserId)==player.UserId) then
                    ignored[target.id]=os.clock()+60
                    if not lostCarry then note("No longer carrying "..target.name.."; moving to next target | State="..tostring(egg.State).." | CarrierUserId="..tostring(egg.CarrierUserId)) end
                    lostCarry=true
                    return false,false
                end
                return true,false
            end
            if not directMove(character,humanoid,autoStealSafeZone,checkDelivery,4,60) then return end
            if lostCarry then return end
            untilTime=os.clock()+8
            while running and not deliveredUid and not lostCarry and os.clock()<untilTime do checkDelivery(); task.wait(0.25) end
            if lostCarry then return end
            if not deliveredUid then ignored[target.id]=os.clock()+60; note("No matching owned egg confirmed at safe zone; moving to next target"); return end
            automationFlow.stealLimits.record(deliveredUid)
            automationFlow.indexCompletion.secured[target.rawName]=true
            completed=completed+1; ignored[target.id]=os.clock()+60
            note("Delivered "..target.name.." | inventory UID "..deliveredUid)
            automationFlow.audit.emit("AutoSteal","attempt_succeeded",{uid=target.id,inventoryUid=deliveredUid,success=true,values=automationFlow.audit.values(record)})
            automationFlow.audit.stealAttempt=nil
            local ok,reason=equipFreeHands(character,humanoid)
            note("Free Hands after delivery: "..tostring(reason))
            local limitReason=automationFlow.stealLimits.reason()
            if limitReason then note(limitReason); flowPlace(limitReason) end
            task.wait(0.75)
        end
        local function start()
            if running or closed then return end
            running=true; runId=runId+1; local token=runId
            automationFlow.steal=true
            local dayOK,isNight=pcall(readAutomationDay)
            automationFlow.pendingDay=true
            if dayOK and isNight then
                automationFlow.pendingDay=false; flowPhase("idle","Waiting for the next day")
            else
                if automationFlow.stopTreadmill then automationFlow.stopTreadmill() end
                flowPhase("preparing","Starting daytime collection; checking current zone")
            end
            returnedHome=false
            control.Text="ON"; control.TextColor3=colors.accent
            note("Auto Steal ON")
            job=task.spawn(function()
                local failures=0
                while running and token==runId and not closed do
                    local finished,ok,err=false,nil,nil
                    automationFlow.collecting=not automationFlow.bossPauseRequested and (automationFlow.phase=="stealing" or automationFlow.phase=="preparing")
                    cycleJob=task.spawn(function()
                        ok,err=pcall(cycle)
                        finished=true
                    end)
                    local deadline=os.clock()+180
                    while not finished and running and token==runId and not closed and os.clock()<deadline do task.wait(0.1) end
                    if not finished then
                        if cycleJob then pcall(task.cancel,cycleJob) end
                        ok=false; err="Cycle timed out; movement paused before retry"
                    end
                    cycleJob=nil
                    if automationFlow.audit.stealAttempt then
                        automationFlow.audit.emit("AutoSteal","attempt_not_confirmed",{attempt=automationFlow.audit.stealAttempt,success=false,reason=err or automationFlow.audit.stealReason or "Stopped"})
                        automationFlow.audit.stealAttempt=nil
                    end
                    automationFlow.collecting=false
                    if not running or token~=runId or closed then return end
                    if not ok then
                        stopMotion()
                        failures=failures+1
                        note("Auto Steal remains ON; waiting/retrying: "..tostring(err))
                        task.wait(math.min(10,failures*2))
                    else failures=0 end
                end
            end)
        end
        connect(control.Activated,function()
            if running then stop("Stopped by user") else start() end
        end)
        connect(copyLog.Activated,function()
            if type(setclipboard)~="function" then note("Clipboard unavailable"); return end
            local ok=pcall(setclipboard,"AcidHub Auto Steal\n"..table.concat(log,"\n"))
            if ok then autoStatus.Text="Auto Steal log copied." end
        end)
        connect(player.CharacterRemoving,function()
            if not running then return end
            stopMotion(); returnedHome=false
            if automationFlow.phase=="stealing" or automationFlow.phase=="preparing" then automationFlow.pendingDay=true end
            note("Auto Steal remains ON; waiting for respawn")
        end)
        table.insert(cleanupActions,function() stop() end)
        -- The legacy AutoStealTest value was always saved false; use a real setting.
        registerSetting("AutoStealEnabled",false,function() return running end,function(value)
            automationFlow.stealConfigured=true
            if value then start() else stop("Auto Steal OFF from settings") end
            return true
        end,isBoolean)

        -- Isolated, manually triggered experiment. No Auto Steal movement calls use teleport.
        ;(function()
            local test={active=false,selected=nil,log={}}
            local targetRow=row(debugPage,112); targetRow.LayoutOrder=-103
            local targetBox=label("Teleport Test - Titan Temple\nReading field eggs...",UDim2.fromOffset(10,6),UDim2.new(1,-20,1,-12),targetRow,true)
            targetBox.TextSize=14
            local stateRow=row(debugPage,38); stateRow.LayoutOrder=-102
            local stateButton=button("Change State to Freefall",UDim2.new(),UDim2.new(1,0,1,0),stateRow)
            local hoverRow=row(debugPage,38); hoverRow.LayoutOrder=-101
            local hoverButton=button("Fly/Hover Test: OFF",UDim2.new(),UDim2.new(1,0,1,0),hoverRow)
            local tryRow=row(debugPage,38); tryRow.LayoutOrder=-100
            local tryButton=button("Try Teleport and Grab",UDim2.new(),UDim2.new(1,0,1,0),tryRow)
            local uidRow=row(debugPage,38); uidRow.LayoutOrder=-99
            local uidButton=button("Try UID Grab (No Teleport)",UDim2.new(),UDim2.new(1,0,1,0),uidRow)
            local actions=row(debugPage,38); actions.LayoutOrder=-98
            local refreshButton=button("New Random Egg",UDim2.new(),UDim2.new(0.5,-3,1,0),actions)
            local stopButton=button("Stop Test",UDim2.new(0.5,3,0,0),UDim2.new(0.5,-3,1,0),actions)
            local statusRow=row(debugPage,82); statusRow.LayoutOrder=-97
            local status=label("One attempt per click. Turn automations OFF for this test. Confirmed pickup starts normal-speed return to the safe zone.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),statusRow,true)
            status.TextSize=14
            local copyRow=row(debugPage,36); copyRow.LayoutOrder=-96
            local copy=button("Copy Teleport Test Log",UDim2.new(),UDim2.new(1,0,1,0),copyRow)
            local function logTest(message)
                status.Text=message
                table.insert(test.log,string.format("[%.2f] %s",os.clock(),message))
                if #test.log>150 then table.remove(test.log,1) end
            end
            local function automationOn()
                for _,key in ipairs({"AutoStealEnabled","Auto Treadmill","Auto Place Eggs","Auto Hatch"}) do
                    local binding=settingsBindings[key]
                    if binding and binding.get() then return true end
                end
                return false
            end
            local function eligible(egg)
                return egg and tostring(egg.AreaId):lower():gsub("[%s_%-]","")=="titantemple"
                    and (egg.State=="Slot" or egg.State=="Dropped")
            end
            local function selectEgg(force)
                local _,records,byId=fields()
                if not force and test.selected and eligible(byId[test.selected]) then return end
                local candidates={}
                for _,egg in pairs(records) do
                    if eligible(egg) and (typeof(egg.BottomCFrame)=="CFrame" or typeof(egg.BoundsCFrame)=="CFrame") then
                        table.insert(candidates,egg)
                    end
                end
                test.selected=nil
                if #candidates==0 then targetBox.Text="Teleport Test - Titan Temple\nNo available Slot/Dropped eggs. Waiting for a spawn."; return end
                local egg=candidates[math.random(1,#candidates)]
                test.selected=egg.Uid
                local frame=typeof(egg.BottomCFrame)=="CFrame" and egg.BottomCFrame or egg.BoundsCFrame
                local name,rarity=Rarity.Resolve(tostring(egg.AssetCategory),"TitanTemple")
                targetBox.Text="Teleport Test - Titan Temple\n"..name.." ["..rarity.."] | "..egg.State.."\nUID: "..egg.Uid.."\nXYZ: "..tostring(frame.Position)
            end
            local function stopHover()
                local hover=test.hover
                test.hover=nil
                if hover then
                    if hover.connection then hover.connection:Disconnect() end
                    if hover.velocity then hover.velocity:Destroy() end
                    if hover.attachment then hover.attachment:Destroy() end
                end
                hoverButton.Text="Fly/Hover Test: OFF"
                hoverButton.TextColor3=colors.muted
            end
            connect(hoverButton.Activated,function()
                if test.active then logTest("Use Stop Test before changing hover."); return end
                if test.hover then stopHover(); logTest("Hover OFF; normal physics restored."); return end
                if automationOn() or baseTravelActive or treadmillExitBusy then logTest("Stop automations and leave the treadmill before enabling hover."); return end
                local character=player.Character
                local humanoid=movementHumanoid(character)
                local root=character and character:FindFirstChild("HumanoidRootPart")
                if not root or not humanoid or humanoid.Health<=0 or root.Anchored then logTest("Hover requires a living, unanchored character."); return end
                local hover={character=character,humanoid=humanoid,root=root,targetY=root.Position.Y+4,started=os.clock(),stable=0,ready=false}
                test.hover=hover
                local ok,err=pcall(function()
                    humanoid:Move(Vector3.zero,false); humanoid:MoveTo(root.Position)
                    hover.attachment=Instance.new("Attachment")
                    hover.attachment.Name="AcidHubDebugHoverAttachment"; hover.attachment.Parent=root
                    hover.velocity=Instance.new("LinearVelocity")
                    hover.velocity.Name="AcidHubDebugHoverVelocity"
                    hover.velocity.Attachment0=hover.attachment
                    hover.velocity.RelativeTo=Enum.ActuatorRelativeTo.World
                    hover.velocity.VelocityConstraintMode=Enum.VelocityConstraintMode.Vector
                    hover.velocity.ForceLimitsEnabled=true
                    hover.velocity.ForceLimitMode=Enum.ForceLimitMode.Magnitude
                    hover.velocity.MaxForce=math.max(root.AssemblyMass*workspace.Gravity*4,10000)
                    hover.velocity.VectorVelocity=Vector3.new(0,12,0)
                    hover.velocity.Parent=root
                    hoverButton.Text="Fly/Hover Test: Lifting..."; hoverButton.TextColor3=colors.accent
                    logTest("Hover ON: lifting 4 studs, then holding airborne. No WalkSpeed or Humanoid state override.")
                    hover.connection=game:GetService("RunService").Heartbeat:Connect(function(dt)
                        if test.hover~=hover then return end
                        local stepped,stepError=pcall(function()
                            if closed or player.Character~=character or humanoid.Parent~=character or humanoid.Health<=0 or root.Parent~=character or root.Anchored or automationOn() then
                                stopHover(); logTest("Hover stopped: character or automation changed."); return
                            end
                            local errorY=hover.targetY-root.Position.Y
                            hover.velocity.VectorVelocity=Vector3.new(0,math.clamp(errorY*6,-12,12),0)
                            local airborne=humanoid.FloorMaterial==Enum.Material.Air
                            if airborne and math.abs(errorY)<0.5 then hover.stable=hover.stable+dt else hover.stable=0 end
                            if hover.stable>=0.3 and not hover.ready then
                                hover.ready=true
                                hoverButton.Text="Fly/Hover Test: ON (Airborne)"
                                logTest("Hover ready | State "..humanoid:GetState().Name.." | Floor "..humanoid.FloorMaterial.Name.." | XYZ "..tostring(root.Position))
                            end
                            if not hover.ready and os.clock()-hover.started>5 then
                                stopHover(); logTest("Hover could not establish stable airborne position; stopped.")
                            end
                        end)
                        if not stepped then stopHover(); logTest("Hover stopped: "..tostring(stepError)) end
                    end)
                end)
                if not ok then stopHover(); logTest("Hover setup failed: "..tostring(err)) end
            end)
            local function cleanupTest()
                stopHover()
                local humanoid=test.humanoid
                test.humanoid=nil
                if humanoid then pcall(function()
                    if humanoid.Parent==player.Character and humanoid.Health>0 then
                        humanoid:Move(Vector3.zero,false)
                        local root=humanoid.RootPart
                        if root then
                            humanoid:MoveTo(root.Position)
                            if not root.Anchored then root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero end
                        end
                    end
                end) end
                if test.prompt then pcall(function() test.prompt:InputHoldEnd() end); test.prompt=nil end
                test.active=false; tryButton.Text="Try Teleport and Grab"
            end
            local function stopTest(message)
                test.active=false
                if test.job then pcall(task.cancel,test.job); test.job=nil end
                cleanupTest()
                if message then logTest(message) end
            end
            local function runTest(mode)
                assert(not automationOn() and not baseTravelActive and not treadmillExitBusy,"Stop automations and wait for movement to finish before testing")
                local reader,records,byId=fields()
                local egg=byId[test.selected]
                assert(eligible(egg),"Selected egg is no longer available; choose a new random egg")
                for _,record in pairs(records) do
                    assert(not(record.State=="Carried" and tonumber(record.CarrierUserId)==player.UserId),"Already carrying an egg; deliver it first")
                end
                egg=copySetting(egg)
                local before=owned(reader)
                local character=player.Character
                local humanoid=movementHumanoid(character)
                local root=character and character:FindFirstChild("HumanoidRootPart")
                assert(root and humanoid and humanoid.Health>0 and not root.Anchored,"Living, unanchored character required; leave the treadmill first")
                test.humanoid=humanoid
                local function check()
                    assert(test.active and not closed and not automationOn(),"Test cancelled or automation enabled")
                    assert(player.Character==character and humanoid.Parent==character and humanoid.Health>0 and root.Parent==character and not root.Anchored,"Character changed, died or became anchored")
                end
                applyEffectiveSpeed(humanoid)
                logTest("Target "..tostring(egg.AssetCategory).." | UID "..egg.Uid.." | WalkSpeed "..humanoid.WalkSpeed)
                local frame=typeof(egg.BottomCFrame)=="CFrame" and egg.BottomCFrame or egg.BoundsCFrame
                local destination=frame.Position+Vector3.new(0,humanoid.HipHeight+root.Size.Y/2,0)
                if mode=="teleport" and test.hover then
                    assert(test.hover.humanoid==humanoid and test.hover.ready and humanoid.FloorMaterial==Enum.Material.Air,"Wait for Hover ON (Airborne) before teleporting")
                    destination=destination+Vector3.new(0,4,0)
                    logTest("Airborne teleport preparation | State "..humanoid:GetState().Name.." | Floor "..humanoid.FloorMaterial.Name)
                end
                local deadline
                assert(type(reader.CarryFieldEgg)=="function","EggState.CarryFieldEgg unavailable")
                check()
                if mode=="uid" then
                    logTest("UID-only pickup request | UID "..egg.Uid.." | distance "..string.format("%.2f",(root.Position-destination).Magnitude).." | no teleport")
                else
                    humanoid:Move(Vector3.zero,false); humanoid:MoveTo(root.Position)
                    logTest("Teleport + UID pickup | UID "..egg.Uid.." | State "..humanoid:GetState().Name.." | From "..tostring(root.Position).." | To "..tostring(destination))
                    if test.hover then test.hover.targetY=destination.Y end
                    root.CFrame=root.CFrame+(destination-root.Position)
                    root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero
                    humanoid:Move(Vector3.zero,false)
                    stopHover()
                    logTest("Hover released; waiting for stable landing before one UID pickup request")
                    local landingUntil=os.clock()+5
                    local groundedSince
                    local landed=false
                    repeat
                        game:GetService("RunService").Heartbeat:Wait()
                        check()
                        humanoid:Move(Vector3.zero,false)
                        if humanoid.FloorMaterial~=Enum.Material.Air and math.abs(root.AssemblyLinearVelocity.Y)<2 then
                            groundedSince=groundedSince or os.clock()
                            if os.clock()-groundedSince>=0.25 then landed=true; break end
                        else groundedSince=nil end
                    until os.clock()>=landingUntil
                    local _,_,afterLanding=fields()
                    local live=afterLanding[egg.Uid]
                    assert(eligible(live),"Selected egg changed before pickup; no request sent")
                    local liveFrame=typeof(live.BottomCFrame)=="CFrame" and live.BottomCFrame or live.BoundsCFrame
                    assert(typeof(liveFrame)=="CFrame","Live egg position unavailable; no request sent")
                    frame=liveFrame
                    local delta=root.Position-frame.Position
                    logTest(string.format("Landing result | landed=%s | State %s | Floor %s | XYZ %s | egg distance 3D=%.2f | horizontal=%.2f | vertical=%.2f",
                        tostring(landed),humanoid:GetState().Name,humanoid.FloorMaterial.Name,tostring(root.Position),delta.Magnitude,Vector3.new(delta.X,0,delta.Z).Magnitude,math.abs(delta.Y)))
                    assert(landed,"Landing not confirmed within 5 seconds; no pickup request sent")
                end
                -- Teleport tests request pickup only after landing; UID-only tests remain stationary.
                check()
                logTest("Sending one CarryFieldEgg request | UID "..egg.Uid.." | egg distance "..string.format("%.2f",(root.Position-frame.Position).Magnitude))
                local accepted,message=reader.CarryFieldEgg(egg.Uid,nil)
                logTest("CarryFieldEgg returned "..tostring(accepted).." | message="..tostring(message).." | State "..humanoid:GetState().Name.." | egg distance "..string.format("%.2f",(root.Position-frame.Position).Magnitude))
                check()
                assert(accepted==true,"UID pickup denied: "..tostring(message))
                local carrying=false
                deadline=os.clock()+3
                repeat
                    check()
                    local _,_,latest=fields(); local current=latest[egg.Uid]
                    carrying=current and current.State=="Carried" and tonumber(current.CarrierUserId)==player.UserId
                    if carrying then break end
                    task.wait(0.1)
                until os.clock()>=deadline
                assert(carrying,"Pickup not confirmed; no return started")
                stopHover()
                logTest("Carrying confirmed; walking to safe zone | WalkSpeed "..humanoid.WalkSpeed)
                deadline=os.clock()+120
                local commanded=-math.huge
                repeat
                    check()
                    local _,_,latest=fields(); local current=latest[egg.Uid]
                    if current then
                        assert(current.State=="Carried" and tonumber(current.CarrierUserId)==player.UserId,"Egg dropped or carrier changed; return stopped")
                    else
                        local matches,delivered=0,nil
                        for uid,value in pairs(owned(reader)) do
                            if not before[uid] and matching(egg,value) then matches=matches+1; delivered=uid end
                        end
                        assert(matches<=1,"Delivery ambiguous: multiple matching eggs")
                        if matches==1 then logTest("DELIVERED | inventory UID "..delivered); return end
                    end
                    if os.clock()-commanded>=1 then
                        humanoid:MoveTo(autoStealSafeZone); commanded=os.clock()
                    end
                    task.wait(0.1)
                until os.clock()>=deadline
                error("Return timed out; inventory delivery was not confirmed")
            end
            local function launchTest(mode)
                if test.active then return end
                if automationOn() or baseTravelActive or treadmillExitBusy then logTest("Turn automations OFF and wait for movement to finish before testing."); return end
                if not test.selected then logTest("No Titan Temple egg selected yet."); return end
                test.active=true; tryButton.Text="Test running..."
                logTest("Starting "..mode.." test; no Humanoid state changes requested by this test")
                test.job=task.spawn(function()
                    local ok,err=pcall(runTest,mode)
                    cleanupTest(); test.job=nil
                    if not ok then logTest("Test stopped: "..tostring(err)) end
                end)
            end
            connect(tryButton.Activated,function() launchTest("teleport") end)
            connect(uidButton.Activated,function() launchTest("uid") end)
            connect(stateButton.Activated,function()
                if test.active or automationOn() then logTest("Stop the active test and automations before changing state."); return end
                local humanoid=movementHumanoid(player.Character)
                if not humanoid or humanoid.Health<=0 then logTest("Freefall: living character required."); return end
                local ok,err=pcall(function()
                    logTest("Manual Freefall request | before "..humanoid:GetState().Name.." | Humanoid "..humanoid:GetFullName())
                    if not humanoid:GetStateEnabled(Enum.HumanoidStateType.Freefall) then logTest("Freefall is disabled on this Humanoid; no change requested."); return end
                    humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
                    logTest("Manual Freefall request | immediate state "..humanoid:GetState().Name)
                    task.delay(0.25,function()
                        if not closed and humanoid.Parent==player.Character and humanoid.Health>0 then
                            logTest("Manual Freefall observation after 0.25s | State "..humanoid:GetState().Name)
                        end
                    end)
                end)
                if not ok then logTest("Freefall request failed: "..tostring(err)) end
            end)
            connect(refreshButton.Activated,function()
                if test.active then return end
                local ok,err=pcall(selectEgg,true)
                if not ok then logTest("Target read failed: "..tostring(err)) end
            end)
            connect(stopButton.Activated,function() stopTest("Stopped by user") end)
            connect(copy.Activated,function()
                if type(setclipboard)=="function" then
                    local ok=pcall(setclipboard,"AcidHub Debug Teleport + Grab\n"..table.concat(test.log,"\n"))
                    if ok then status.Text="Teleport test log copied." end
                else status.Text="Clipboard unavailable." end
            end)
            connect(player.CharacterRemoving,function() if test.active or test.hover then stopTest("Character removed; test stopped") end end)
            table.insert(cleanupActions,function() stopTest() end)
            test.readerJob=task.spawn(function()
                while not closed do
                    if not test.active then
                        local ok,err=pcall(selectEgg,false)
                        if not ok then test.selected=nil; targetBox.Text="Teleport Test - Titan Temple\nWaiting for field data: "..tostring(err) end
                    end
                    task.wait(2)
                end
            end)
            table.insert(cleanupActions,function() if test.readerJob then pcall(task.cancel,test.readerJob) end end)
        end)()
    end

    local function reportFor(result,filters)
        local selected={}
        for _,name in ipairs(areaOptions) do if filters.areas[name] then table.insert(selected,name) end end
        local lines={"AcidHub Auto Steal Selection Preview", "Game ID: "..game.GameId.." | Place ID: "..game.PlaceId,
            "Captured UTC: "..os.date("!%Y-%m-%d %H:%M:%S"),
            "Read-only. No movement, pickup, delivery, or placement was attempted.",
            string.format("Safe-zone destination XYZ: %.1f, %.1f, %.1f (user provided)",autoStealSafeZone.X,autoStealSafeZone.Y,autoStealSafeZone.Z),
            "Eligibility: State="..(stealDroppedEggs and "Slot or Dropped" or "Slot").." in supported field areas, including Angels & Demons. This does not prove a pickup will succeed.",
            "Distances are straight-line 3D distances, not route lengths. Rarity comes from live game asset data; unknown rarity qualifies only with All.",
            "Areas: "..(#selected==0 and "All" or table.concat(selected,", ")),
            "Minimum rarity: "..filters.minimum.." | Priority: "..filters.priority,
            "Specific eggs: "..(filters.species:match("^%s*$") and "Any" or filters.species),
            "Records: "..result.total.." | Eligible candidates: "..#result.candidates,""}
        local target=result.candidates[1]
        if target then
            table.insert(lines,"WOULD SELECT: "..target.name.." ["..target.rarity.."]")
            table.insert(lines,"UID: "..target.id.." | Area: "..target.area.." | State: "..target.state)
            table.insert(lines,"Game species: "..target.rawName.." | Mutations: "..(target.mutation~="" and target.mutation or "None"))
            table.insert(lines,"Metric discovery (record fields): "..target.metricFields)
            table.insert(lines,string.format("Distance: %.1f studs | XYZ: %.1f, %.1f, %.1f",target.distance,target.position.X,target.position.Y,target.position.Z))
            table.insert(lines,"Reason: "..filters.priority..", then nearest distance; UID breaks exact ties.")
            if filters.priority=="Mutation" then table.insert(lines,"Mutation order: Rainbow > Golden > Silver > None/other.") end
        else table.insert(lines,"NO ELIGIBLE TARGET") end
        table.insert(lines,"\nTOP CANDIDATES (up to 10)")
        for index=1,math.min(10,#result.candidates) do
            local item=result.candidates[index]
            table.insert(lines,string.format("%d. %s [%s] | %s | %.1f studs | Weight=%s | Money/sec=%s | Mutations=%s | UID %s",index,item.name,item.rarity,item.area,item.distance,tostring(item.weight or "unavailable"),tostring(item.income or "unavailable"),item.mutation,item.id))
        end
        if filters.priority=="Best Weight" or filters.priority=="Highest Money/Sec" then
            local missing=0
            for _,item in ipairs(result.candidates) do if priorityValue(item,filters.priority)==nil then missing=missing+1 end end
            table.insert(lines,"Weight/income use the game's EggRecords and AssetEarnings calculations. Missing priority metric: "..missing..". Known values rank first; failed conversions fall back to live rarity, then distance.")
        end
        local function counts(title,values)
            table.insert(lines,"\n"..title)
            local keys={}; for key in pairs(values) do table.insert(keys,key) end; table.sort(keys)
            for _,key in ipairs(keys) do table.insert(lines,key..": "..values[key]) end
            if #keys==0 then table.insert(lines,"None") end
        end
        counts("EXCLUDED (first failing rule)",result.excluded)
        counts("OBSERVED STATES",result.states)
        if #result.unmatched>0 then table.insert(lines,"\nNames not matched in this snapshot (may be absent or misspelled): "..table.concat(result.unmatched,", ")) end
        table.insert(lines,"\nNext milestone: confirm carried egg identity, pickup interaction, and arrival at the safe zone. Placement remains separate.")
        return table.concat(lines,"\n")
    end
    connect(previewButton.Activated,function()
        if previewBusy then return end
        invalidate()
        if #speciesText>20000 then previewStatus.Text="Species filter is too long (maximum 20000 characters)."; return end
        local character=player.Character
        local humanoid=movementHumanoid(character)
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if not humanoid or humanoid.Health<=0 or not root or not root:IsA("BasePart") then
            previewStatus.Text="Wait for a living character before previewing."; return
        end
        local filters={areas=copySetting(previewAreas),minimum=minimum,priority=priority,species=speciesText}
        local token=generation
        previewBusy=true; previewButton.Text="Reading..."; previewStatus.Text="Reading a fresh egg snapshot..."
        previewWorker=task.spawn(function()
            local ok,result=pcall(function()
                assert(game.GameId==10563114921,"Preview is intended for Steal an Egg.")
                local client=game:GetService("ReplicatedStorage"):FindFirstChild("Client")
                local module=client and client:FindFirstChild("EggState")
                assert(module and module:IsA("ModuleScript"),"EggState is unavailable.")
                local reader=require(module)
                assert(type(reader)=="table" and type(reader.ReadFieldEggs)=="function","Egg reader unavailable.")
                local snapshot=reader.ReadFieldEggs()
                assert(type(snapshot)=="table" and type(snapshot.Records)=="table","Unexpected egg snapshot.")
                assert(player.Character==character and root.Parent==character and humanoid.Health>0,"Character changed during read; preview again.")
                filters.indexNeeds=automationFlow.indexCompletion.needs()
                return evaluate(snapshot.Records,root.Position,filters)
            end)
            if closed or generation~=token then return end
            previewBusy=false; previewWorker=nil; previewButton.Text="Preview Target"
            if not ok then previewStatus.Text="Preview failed: "..tostring(result); return end
            local reportOK,text=pcall(reportFor,result,filters)
            if not reportOK then previewStatus.Text="Report failed: "..tostring(text); return end
            previewReport=text; previewBox.Text=text
            lastPreviewEggId=result.candidates[1] and result.candidates[1].id or nil
            local target=result.candidates[1]
            previewStatus.Text=target and ("Would select "..target.name.." ["..target.rarity.."]. Snapshot only—press Preview Target to refresh.") or "No eligible target. See exclusions in the report."
        end)
        task.delay(12,function()
            if closed or generation~=token or not previewBusy then return end
            invalidate(); previewStatus.Text="Preview timed out. Try again when egg data is available."
        end)
    end)
    connect(copyButton.Activated,function()
        if previewReport=="" then previewStatus.Text="Create a fresh preview first."; return end
        if type(setclipboard)~="function" then previewStatus.Text="Clipboard unavailable. Use Save Selection Report."; return end
        local ok=pcall(setclipboard,previewReport)
        previewStatus.Text=ok and "Selection report copied." or "Copy failed. Use Save Selection Report."
    end)
    connect(saveButton.Activated,function()
        if previewReport=="" then previewStatus.Text="Create a fresh preview first."; return end
        if type(writefile)~="function" then previewStatus.Text="File saving unavailable. Use Copy Selection Report."; return end
        local path="AcidHub_StealPreview_"..os.time()..".txt"
        local ok,err=pcall(writefile,path,previewReport)
        previewStatus.Text=ok and ("Saved to executor workspace: "..path) or ("Save failed: "..tostring(err))
    end)
    connect(player.CharacterRemoving,invalidate)
    table.insert(cleanupActions,function()
        generation=generation+1
        if previewWorker then pcall(task.cancel,previewWorker); previewWorker=nil end
    end)
end

-- Inventory journey diagnostics: explicit stage captures, no inventory mutations.
do
    label("Inventory Journey Capture",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),row(debugPage,42)).TextSize=20
    label("Preview an egg or paste its UID. Start Capture before pickup; Stop Capture in the safe zone without placing it. State and owned-inventory checks run every 0.75 seconds, for up to 5 minutes.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,120),true).TextSize=14
    local uidRow=row(debugPage,80)
    label("Target egg UID",UDim2.fromOffset(10,4),UDim2.new(1,-20,0,22),uidRow,true)
    local uidBox=make("TextBox",{Name="JourneyEggUid",Text="",PlaceholderText="Blank = last preview target",
        Position=UDim2.fromOffset(10,30),Size=UDim2.new(1,-20,0,40),BackgroundColor3=colors.panel,
        BorderSizePixel=0,TextColor3=colors.text,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextSize=14,TextWrapped=true,ClearTextOnFocus=false},uidRow)
    local beforeButton=button("Start Capture",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local safeButton=button("Stop Capture",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local copyButton=button("Copy Inventory Journey",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local saveButton=button("Save Inventory Journey",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local clearButton=button("Clear Inventory Journey",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local journeyStatus=label("Ready. Preview a target, then capture Before Pickup.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,90),true)
    journeyStatus.TextSize=14
    local journeyBox=make("TextBox",{Name="InventoryJourneyReport",Text="",TextEditable=false,ClearTextOnFocus=false,
        MultiLine=true,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
        Position=UDim2.fromOffset(10,6),Size=UDim2.new(1,-20,1,-12),BackgroundTransparency=1,
        TextColor3=colors.text,TextSize=14,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold)},row(debugPage,260))
    local captures,events,eventConnections={},{},{}
    local targetUid,journeyCharacter,report
    local readWorker,reading=nil,false
    local continuous=false
    local runToken=0
    local latest,lastTransition
    local generation,started=0,0
    local eventLimited=false
    local stageNames={"Start Capture","Carrying (automatically observed)","Stop Capture (location not automatically verified)"}
    local function stopEvents()
        for _,connection in ipairs(eventConnections) do connection:Disconnect() end
        eventConnections={}
    end
    local function cancelRead()
        generation=generation+1
        if readWorker then pcall(task.cancel,readWorker); readWorker=nil end
        reading=false
    end
    local function scalar(value)
        local kind=typeof(value)
        if kind=="Instance" then return value:GetFullName() end
        local text=tostring(value)
        return #text>800 and (text:sub(1,800).." [truncated]") or text
    end
    local function startEvents(character)
        stopEvents(); events={}; eventLimited=false; started=os.clock()
        for _,object in ipairs({player,character}) do
            table.insert(eventConnections,object.AttributeChanged:Connect(function(name)
                if #events>=300 then eventLimited=true; stopEvents(); return end
                table.insert(events,string.format("[%.3fs] %s Attribute:%s = %s",os.clock()-started,object.Name,name,scalar(object:GetAttribute(name))))
            end))
        end
        local token=started
        task.delay(300,function()
            if closed or token~=started then return end
            if #eventConnections>0 then
                table.insert(events,"Attribute trace stopped after 300 seconds.")
                stopEvents()
            end
        end)
    end
    local function relevant(name)
        name=string.lower(name)
        for _,word in ipairs({"inventory","backpack","unplaced","egg","carry","carried","profile","replica","playerdata","trapped","safezone"}) do
            if name:find(word,1,true) then return true end
        end
        return false
    end
    local fingerprintFields={"AssetCategory","AssetColorIndex","AssetColorSeed","AssetEyeColor","AssetScale"}
    local function eggIdentity(record)
        local result={}
        for _,key in ipairs(fingerprintFields) do result[key]=record[key] end
        result.State=record.State; result.CarrierUserId=record.CarrierUserId
        return result
    end
    local function sameEgg(a,b)
        for _,key in ipairs(fingerprintFields) do
            if a[key]==nil or b[key]==nil then return false end
            if key=="AssetScale" then
                local x,y=tonumber(a[key]),tonumber(b[key])
                if not x or not y or x~=x or y~=y or math.abs(x-y)>0.000001 then return false end
            elseif tostring(a[key])~=tostring(b[key]) then return false end
        end
        return true
    end
    local function deliverySummary(before,carrying,after)
        if not before or not carrying or not after then return "Delivery comparison pending: baseline, observed pickup, and final sample are required." end
        if not carrying.target or carrying.target.State~="Carried" or tonumber(carrying.target.CarrierUserId)~=player.UserId then
            return "NOT CONFIRMED: carrying stage did not identify this egg as carried by you."
        end
        if not after.fieldOK or after.targetPresent~=false then return "NOT CONFIRMED: field removal not established." end
        if not before.ownedReliable or not carrying.ownedReliable or not after.ownedReliable then
            return "NOT CONFIRMED: owned-egg reader data was unavailable, incomplete, or had an unrecognized structure. Inspect OwnedReaderRaw and notes."
        end
        local matches={}
        for id,record in pairs(after.owned) do
            if not before.owned[id] and not carrying.owned[id] and sameEgg(carrying.target,record) then table.insert(matches,id) end
        end
        table.sort(matches)
        if #matches==1 then
            return "DELIVERY CANDIDATE: field egg "..tostring(targetUid).." was carried by you, left field data, and matches new owned UID "..matches[1].." across species, color index, color seed, eye color, and scale. Strong correlation; no explicit server receipt was observed."
        elseif #matches>1 then return "AMBIGUOUS: multiple new owned eggs match: "..table.concat(matches,", ") end
        return "NOT CONFIRMED: no new owned egg matched the carried egg's full fingerprint."
    end
    local function snapshot(uid,character,quick)
        local data,notes={},{}
        local count=0
        local function put(key,value)
            if count>=8000 then return end
            if data[key]==nil then count=count+1 end
            data[key]=scalar(value)
        end
        local function flatten(value,path,depth,seen)
            if type(value)~="table" then
                if type(value)~="function" and type(value)~="thread" then put(path,value) end
                return
            end
            if seen[value] then put(path,"[shared/cyclic table]"); return end
            if depth>6 then put(path,"[depth limit]"); return end
            seen[value]=true
            local entries=0
            for key,child in next,value do
                entries=entries+1
                if entries>350 then put(path..".[limit]","350 entries reached"); break end
                if type(key)=="string" or type(key)=="number" then
                    flatten(child,path.."["..scalar(key).."]",depth+1,seen)
                end
            end
            if entries==0 then put(path,"{}") end
        end
        local function attributes(object,path)
            for name,value in pairs(object:GetAttributes()) do put(path..".Attribute:"..name,value) end
        end
        put("Context.TargetUID",uid); put("Context.GameId",game.GameId); put("Context.PlaceId",game.PlaceId)
        put("Context.ServerId",game.JobId); put("Context.PlayerUserId",player.UserId)
        local root=character:FindFirstChild("HumanoidRootPart")
        put("Context.SafeZoneDestination",autoStealSafeZone)
        if root and root:IsA("BasePart") then
            put("Context.Position",root.Position)
            put("Context.DistanceToSafeZone",(root.Position-autoStealSafeZone).Magnitude)
        end
        attributes(player,"Player"); attributes(character,"Character")
        local function inspect(scope,path)
            if not scope then put(path,"[unavailable]"); return end
            local scanned=0
            local function visit(object,prefix)
                scanned=scanned+1
                if scanned>1800 then return end
                put(prefix..".Class",object.ClassName); attributes(object,prefix)
                if object:IsA("ValueBase") then pcall(function() put(prefix..".Value",object.Value) end) end
                if object:IsA("Tool") then
                    put(prefix..".ToolTip",object.ToolTip); put(prefix..".TextureId",object.TextureId)
                end
                local counts={}
                for _,child in ipairs(object:GetChildren()) do
                    if scanned>=1800 then break end
                    counts[child.Name]=(counts[child.Name] or 0)+1
                    visit(child,prefix.."/"..child.Name.."#"..counts[child.Name])
                end
            end
            visit(scope,path)
            if scanned>=1800 then table.insert(notes,path.." reached 1800-object scan limit.") end
        end
        inspect(player:FindFirstChildOfClass("Backpack"),"Backpack")
        for _,child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then inspect(child,"EquippedTool/"..child.Name) end
        end
        for _,child in ipairs(player:GetChildren()) do
            if child~=playerGui and child.Name~="PlayerScripts" and not child:IsA("Backpack") then inspect(child,"PlayerData/"..child.Name) end
        end
        local client=game:GetService("ReplicatedStorage"):FindFirstChild("Client")
        local eggReader,targetRecord,targetPresent
        local owned,ownedReliable={},false
        local fieldOK,fieldError=pcall(function()
            local module=client and client:FindFirstChild("EggState")
            assert(module and module:IsA("ModuleScript"),"EggState unavailable")
            local reader=require(module)
            eggReader=reader
            assert(type(reader)=="table" and type(reader.ReadFieldEggs)=="function","Field reader unavailable")
            local field=reader.ReadFieldEggs()
            assert(type(field)=="table" and type(field.Records)=="table","Invalid field snapshot")
            local found,total=false,0
            for _,record in pairs(field.Records) do
                total=total+1
                assert(total<=5000,"Field record limit exceeded")
                if type(record)=="table" then
                    if record.Uid==uid then found=true; targetRecord=eggIdentity(record); flatten(record,"TargetFieldRecord",0,{}) end
                    if record.State=="Carried" then flatten(record,"CarriedFieldRecord/"..tostring(record.Uid),0,{}) end
                end
            end
            targetPresent=found
            put("Field.TargetPresent",found); put("Field.RecordCount",total)
        end)
        if not fieldOK then table.insert(notes,"Field capture failed: "..tostring(fieldError)) end
        local ownedOK,ownedError=pcall(function()
            assert(type(eggReader)=="table" and type(eggReader.ReadOwnedEggs)=="function","ReadOwnedEggs unavailable")
            -- Probe the plural reader without arguments; retain its actual return shape.
            local result=eggReader.ReadOwnedEggs()
            assert(type(result)=="table","ReadOwnedEggs did not return a table")
            -- Observed schema: array of {OwnerUserId, Records = {[UID] = record}}.
            local group
            local groupCount=0
            for _,entry in pairs(result) do
                groupCount=groupCount+1
                assert(groupCount<=200,"Owned owner-group limit exceeded")
                if type(entry)=="table" and tonumber(entry.OwnerUserId)==player.UserId then
                    assert(not group,"Duplicate local owner groups")
                    group=entry
                end
            end
            assert(group and type(group.Records)=="table","Local player's owned Records group unavailable")
            put("OwnedReader.OwnerUserId",group.OwnerUserId)
            flatten(group,"OwnedReaderRaw",0,{})
            local parsed=0
            for id,record in pairs(group.Records) do
                assert(type(id)=="string" and id~="" and type(record)=="table" and record.AssetCategory~=nil,"Invalid local owned record")
                assert(parsed<5000,"Owned record limit exceeded")
                owned[id]=eggIdentity(record); parsed=parsed+1
            end
            ownedReliable=true
            put("OwnedReader.ParsedCount",parsed); put("OwnedReader.ReliableForComparison",true)

        end)
        if not ownedOK then ownedReliable=false; table.insert(notes,"Owned reader failed: "..tostring(ownedError)) end
        if quick then
            assert(player.Character==character,"Character changed during capture")
            if count>=8000 then table.insert(notes,"Snapshot reached 8000-field display limit.") end
            return {data=data,notes=notes,time=os.date("!%Y-%m-%d %H:%M:%S"),fields=count,
                target=targetRecord,targetPresent=targetPresent,fieldOK=fieldOK,owned=owned,ownedReliable=ownedReliable}
        end
        -- Discover module names without starting unfamiliar module initializers.
        local scripts=player:FindFirstChild("PlayerScripts")
        local candidates={}
        for _,scope in ipairs({client or false,scripts or false}) do
            if scope then
                local scanned=0
                for _,object in ipairs(scope:GetDescendants()) do
                    scanned=scanned+1
                    if scanned>6000 then table.insert(notes,"Module discovery truncated: "..scope.Name); break end
                    if object:IsA("ModuleScript") and relevant(object.Name) then candidates[object]=object:GetFullName() end
                    if object:IsA("ValueBase") then pcall(function() put("ClientValues/"..object:GetFullName(),object.Value) end) end
                    if relevant(object.Name) then attributes(object,"ClientAttributes/"..object:GetFullName()) end
                end
            end
        end
        local paths={}; for _,path in pairs(candidates) do table.insert(paths,path) end; table.sort(paths)
        for index,path in ipairs(paths) do put("ModuleCandidates/"..index,path) end
        if type(getloadedmodules)=="function" then
            local ok,loaded=pcall(getloadedmodules)
            if ok and type(loaded)=="table" then
                local ordered={}
                for _,module in pairs(loaded) do if candidates[module] then table.insert(ordered,module) end end
                table.sort(ordered,function(a,b) return candidates[a]<candidates[b] end)
                for index,module in ipairs(ordered) do
                    if index>30 then table.insert(notes,"Loaded-module export inspection limited to 30 modules."); break end
                    -- Only require already-loaded modules; never call their exported functions.
                    local exportOK,export=pcall(require,module)
                    if exportOK then
                        flatten(export,"LoadedExport/"..candidates[module],0,{})
                        if type(export)=="table" then
                            for name,member in next,export do
                                if type(name)=="string" and type(member)=="function" then put("AvailableFunction/"..candidates[module].."/"..name,"not called") end
                            end
                        end
                    else table.insert(notes,"Could not inspect loaded export: "..candidates[module]) end
                end
            else table.insert(notes,"Loaded-module enumeration failed; module names and Instances only.") end
        else table.insert(notes,"getloadedmodules unavailable; no unfamiliar modules were required.") end
        local uiCount,uiScanned=0,0
        for _,object in ipairs(playerGui:GetDescendants()) do
            uiScanned=uiScanned+1
            if uiScanned>12000 then table.insert(notes,"Inventory UI search reached scan limit."); break end
            if not object:IsDescendantOf(gui) and (object:IsA("TextLabel") or object:IsA("TextButton")) then
                local path=object:GetFullName()
                if relevant(path) and object.Text~="" then
                    uiCount=uiCount+1
                    if uiCount>180 then table.insert(notes,"Inventory UI text limited to 180 entries."); break end
                    put("UIText/"..path,object.Text)
                end
            end
        end
        if count>=8000 then table.insert(notes,"Snapshot reached 8000-field limit.") end
        assert(player.Character==character,"Character changed during capture")
        return {data=data,notes=notes,time=os.date("!%Y-%m-%d %H:%M:%S"),fields=count,
            target=targetRecord,targetPresent=targetPresent,fieldOK=fieldOK,owned=owned,ownedReliable=ownedReliable}
    end
    local function keys(values)
        local result={}; for key in pairs(values) do table.insert(result,key) end; table.sort(result); return result
    end
    local function buildReport()
        local lines={"AcidHub Inventory Journey | Target UID: "..tostring(targetUid),
            "Read-only. Carrying is observed from State and CarrierUserId. Stop location is user-chosen, not verified as a safe zone.",
            "Field disappearance does not prove delivery. Compare UID-bearing data and inventory changes.",
            "Client data may be incomplete. UI text may be hidden/stale. Duplicate-name sibling indices can shift.",
            "Readers: ReadFieldEggs() and ReadOwnedEggs(); inventory is restricted to LocalPlayer.UserId. No mutation functions called.","",
            deliverySummary(captures[1],captures[2],captures[3]),""}
        for index=1,3 do
            local capture=captures[index]
            if capture then
                table.insert(lines,"=== "..stageNames[index].." | "..capture.time.." UTC ===")
                table.insert(lines,"Captured fields: "..capture.fields)
                for _,note in ipairs(capture.notes) do table.insert(lines,"NOTE: "..note) end
                table.insert(lines,"TARGET UID MATCHES")
                local matches=0
                for _,key in ipairs(keys(capture.data)) do
                    local value=capture.data[key]
                    if key~="Context.TargetUID" and (key:find(targetUid,1,true) or value:find(targetUid,1,true)) then
                        matches=matches+1; table.insert(lines,key.." = "..value)
                    end
                end
                if matches==0 then table.insert(lines,"None in captured data.") end
                if index==1 then
                    table.insert(lines,"BASELINE DATA")
                    for _,key in ipairs(keys(capture.data)) do table.insert(lines,key.." = "..capture.data[key]) end
                else
                    table.insert(lines,"CHANGES FROM PREVIOUS STAGE")
                    local previous=(captures[index-1] or captures[1]).data
                    local all={};for key in pairs(previous) do all[key]=true end;for key in pairs(capture.data) do all[key]=true end
                    for _,key in ipairs(keys(all)) do
                        if previous[key]~=capture.data[key] then table.insert(lines,key..": "..tostring(previous[key]).." -> "..tostring(capture.data[key])) end
                    end
                end
                table.insert(lines,"")
            end
        end
        table.insert(lines,"PLAYER / CHARACTER ATTRIBUTE EVENTS (limit reached: "..tostring(eventLimited)..")")
        for _,entry in ipairs(events) do table.insert(lines,entry) end
        return table.concat(lines,"\n")
    end
    local function showReport()
        report=buildReport()
        journeyBox.Text=#report>14000 and (report:sub(1,14000).."\n[Preview shortened. Copy/Save includes the full report.]") or report
    end
    local function transition(sample)
        latest=sample
        if not captures[2] and sample.target and sample.target.State=="Carried" and tonumber(sample.target.CarrierUserId)==player.UserId then
            captures[2]=sample
            table.insert(events,string.format("[%.3fs] Target first observed carried by LocalPlayer.",os.clock()-started))
        end
        local state=sample.fieldOK and (sample.target and sample.target.State or "Absent from field") or "Field read failed"
        local match=deliverySummary(captures[1],captures[2],sample)
        local key=tostring(state).." | "..tostring(sample.target and sample.target.CarrierUserId).." | "..match
        if key~=lastTransition then
            lastTransition=key
            if #events<600 then table.insert(events,string.format("[%.3fs] %s",os.clock()-started,key)) end
        end
        journeyStatus.Text="Capturing: "..tostring(state)..". "..(captures[2] and "Your pickup was observed. Stop in the safe zone." or "Waiting to observe your pickup.")
    end
    local function readSample(done)
        cancelRead(); reading=true
        local token=generation
        readWorker=task.spawn(function()
            local ok,result=pcall(snapshot,targetUid,journeyCharacter,true)
            if closed or generation~=token then return end
            reading=false; readWorker=nil
            done(ok,result)
        end)
        task.delay(15,function()
            if closed or generation~=token or not reading then return end
            cancelRead(); done(false,"Inventory read timed out.")
        end)
    end
    local function finish(message)
        continuous=false; runToken=runToken+1; stopEvents()
        beforeButton.Text="Start Capture"; safeButton.Text="Stop Capture"
        if latest and captures[1] then
            captures[3]=latest
            local ok,err=pcall(showReport)
            journeyStatus.Text=ok and message or ("Report failed: "..tostring(err))
        else journeyStatus.Text=message end
    end
    local function stopCapture()
        if not continuous then journeyStatus.Text="No active capture. Press Start Capture first."; return end
        continuous=false; runToken=runToken+1
        if not captures[1] then cancelRead(); finish("Stopped before baseline was ready. No journey was captured."); return end
        safeButton.Text="Stopping..."
        readSample(function(ok,result)
            if ok then transition(result)
            else table.insert(events,"Final read failed; final snapshot is the last successful sample: "..tostring(result)) end
            finish(ok and "Capture stopped. Copy or save Inventory Journey." or "Stopped with an incomplete final read. Copy report for details.")
        end)
    end
    local function poll(token)
        if closed or not continuous or token~=runToken then return end
        if player.Character~=journeyCharacter then finish("Character changed. Capture ended; start a new journey."); return end
        if os.clock()-started>=300 then stopCapture(); return end
        readSample(function(ok,result)
            if not continuous or token~=runToken then return end
            if not ok then
                table.insert(events,"Capture read failed: "..tostring(result))
                finish("Capture stopped after a read failure. Copy the partial report."); return
            end
            transition(result)
            task.delay(0.75,function() poll(token) end)
        end)
    end
    connect(beforeButton.Activated,function()
        if continuous or reading then journeyStatus.Text="Capture already active. Stop it before starting again."; return end
        local character=player.Character
        if not character then journeyStatus.Text="Wait for your character."; return end
        local uid=uidBox.Text:match("^%s*(.-)%s*$")
        if uid=="" then uid=lastPreviewEggId end
        if not uid or uid=="" or #uid>200 then journeyStatus.Text="Preview a target first or paste its exact UID."; return end
        cancelRead(); stopEvents(); captures={}; report=nil; journeyBox.Text=""; latest=nil; lastTransition=nil
        targetUid=uid; uidBox.Text=uid; journeyCharacter=character
        startEvents(character); continuous=true; runToken=runToken+1
        local token=runToken
        beforeButton.Text="Capturing..."; journeyStatus.Text="Reading baseline; wait before picking up the egg."
        readSample(function(ok,result)
            if not continuous or token~=runToken then return end
            if not ok then finish("Could not start capture: "..tostring(result)); return end
            if not result.fieldOK or not result.target or result.target.State~="Slot" then
                finish("Start before pickup with a target still in Slot state. Refresh Preview Target if needed."); return
            end
            captures[1]=result; transition(result)
            journeyStatus.Text="Baseline ready. Pick up your egg, return to the safe zone, then Stop Capture."
            task.delay(0.75,function() poll(token) end)
        end)
    end)
    connect(safeButton.Activated,stopCapture)
    connect(copyButton.Activated,function()
        if not report then journeyStatus.Text="Capture a stage first."; return end
        if type(setclipboard)~="function" then journeyStatus.Text="Clipboard unavailable. Use Save Inventory Journey."; return end
        local ok=pcall(setclipboard,report); journeyStatus.Text=ok and "Full journey report copied." or "Copy failed."
    end)
    connect(saveButton.Activated,function()
        if not report then journeyStatus.Text="Capture a stage first."; return end
        if type(writefile)~="function" then journeyStatus.Text="File saving unavailable."; return end
        local path="AcidHub_InventoryJourney_"..os.time()..".txt"
        local ok,err=pcall(writefile,path,report)
        journeyStatus.Text=ok and ("Saved in executor workspace: "..path) or ("Save failed: "..tostring(err))
    end)
    connect(clearButton.Activated,function()
        continuous=false; runToken=runToken+1; beforeButton.Text="Start Capture"; safeButton.Text="Stop Capture"
        cancelRead(); stopEvents(); captures={}; events={}; report=nil; targetUid=nil; journeyCharacter=nil; latest=nil
        journeyBox.Text=""; uidBox.Text=""; journeyStatus.Text="Cleared. Ready for a new journey."
    end)
    connect(player.CharacterRemoving,function()
        cancelRead(); finish("Character changed. Capture ended. Start a new capture with a fresh target.")
    end)
    table.insert(cleanupActions,function() continuous=false; runToken=runToken+1; cancelRead(); stopEvents(); captures={}; events={}; latest=nil end)
end

-- Session-only plot selection and cancellable treadmill route test.
-- Discover exposed interfaces only; never require unknown modules or call remotes.
do
    label("Client Interface Discovery",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),row(debugPage,42)).TextSize=20
    label("Open the game's inventory, equip an egg, then scan. Lists client scripts and network objects; tries ordinary Source reads on relevant scripts. No remote calls, hooks, or module initialization. This does not capture outgoing calls.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,125),true).TextSize=14
    local scan=button("Scan Client Interfaces",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local save=button("Save Client Interfaces",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local copy=button("Copy Client Interfaces",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local status=label("Ready for read-only discovery.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,90),true)
    local report,busy,cancelled="",false,false
    local function relevant(name)
        name=string.lower(name)
        for _,word in ipairs({"egg","equip","inventory","backpack","place","plot","pen","asset","network","remote","packet"}) do
            if string.find(name,word,1,true) then return true end
        end
        return false
    end
    connect(scan.Activated,function()
        if busy then return end
        busy=true; status.Text="Scanning client interfaces..."
        task.spawn(function()
            local ok,result=pcall(function()
                local lines={"AcidHub Client Interface Discovery", "Game ID: "..game.GameId.." | Place ID: "..game.PlaceId,
                    "UTC: "..os.date("!%Y-%m-%d %H:%M:%S"),
                    "Read-only names/metadata. Names are candidates, not verified functions or argument schemas.",
                    "Ordinary Source access only. No decompilation, unknown require(), interception or remote invocation."}
                local scopes={game:GetService("ReplicatedStorage"),player,workspace}
                local seen,entries,visited={},0,0
                local sourceAttempts,sourceReadable,sourceCharacters=0,0,0
                local limited=false
                for _,scope in ipairs(scopes) do
                    for _,object in ipairs(scope:GetDescendants()) do
                        if cancelled then return nil end
                        visited=visited+1
                        if visited>120000 or entries>=2500 then limited=true; break end
                        if not seen[object] and not object:IsDescendantOf(gui) then
                            seen[object]=true
                            local network=object:IsA("RemoteEvent") or object:IsA("RemoteFunction") or object:IsA("UnreliableRemoteEvent")
                            local scriptObject=object:IsA("ModuleScript") or object:IsA("LocalScript")
                            local binding=(object:IsA("BindableEvent") or object:IsA("BindableFunction")) and relevant(object.Name)
                            if network or scriptObject or binding then
                                entries=entries+1
                                table.insert(lines,"\n"..object.ClassName.." | "..object:GetFullName())
                                local attributes={}
                                for key,value in pairs(object:GetAttributes()) do table.insert(attributes,key.."="..tostring(value)) end
                                table.sort(attributes)
                                if #attributes>0 then table.insert(lines,"Attributes: "..table.concat(attributes,"; ")) end
                                if scriptObject and relevant(object.Name) and sourceAttempts<80 and sourceCharacters<100000 then
                                    sourceAttempts=sourceAttempts+1
                                    local accessible,source=pcall(function() return object.Source end)
                                    if accessible and type(source)=="string" and #source>0 then
                                        sourceReadable=sourceReadable+1
                                        local length=math.min(#source,12000,100000-sourceCharacters)
                                        sourceCharacters=sourceCharacters+length
                                        table.insert(lines,"SOURCE (untrusted code, not executed):\n"..source:sub(1,length))
                                        if length<#source then table.insert(lines,"[Source truncated]") end
                                    else table.insert(lines,"Source unavailable or empty through ordinary client access.") end
                                end
                            end
                        end
                        if visited%300==0 then task.wait() end
                    end
                    if limited then break end
                end
                table.insert(lines,string.format("\nInspected=%d | Entries=%d | Scan limited=%s | Source attempts=%d | Readable sources=%d | Source budget=%d/100000",visited,entries,tostring(limited),sourceAttempts,sourceReadable,sourceCharacters))
                table.insert(lines,"Absence from this report does not establish absence from the game. Unnamed/dynamically created interfaces may need separate investigation.")
                return table.concat(lines,"\n")
            end)
            busy=false
            if cancelled then return end
            if ok and result then report=result; status.Text="Discovery ready. Save or copy Client Interfaces." else status.Text="Discovery failed: "..tostring(result) end
        end)
    end)
    connect(save.Activated,function()
        if report=="" then status.Text="Scan Client Interfaces first."; return end
        if type(writefile)~="function" then status.Text="File saving unavailable. Use Copy Client Interfaces."; return end
        local filename="AcidHub_Client_Interfaces_"..os.time()..".txt"
        local ok,err=pcall(writefile,filename,report)
        status.Text=ok and ("Saved "..filename) or tostring(err)
    end)
    connect(copy.Activated,function()
        if report=="" then status.Text="Scan Client Interfaces first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        status.Text=ok and "Client interfaces copied." or "Clipboard unavailable. Use Save Client Interfaces."
    end)
    table.insert(cleanupActions,function() cancelled=true end)
end

do
    local scanRow=row(debugPage,38); scanRow.LayoutOrder=-95
    local scan=button("Inspect Egg Pickup Interfaces",UDim2.new(),UDim2.new(1,0,1,0),scanRow)
    local actionRow=row(debugPage,38); actionRow.LayoutOrder=-94
    local stopScan=button("Stop Pickup Inspection",UDim2.new(),UDim2.new(0.5,-3,1,0),actionRow)
    local copyScan=button("Copy Pickup Inspection",UDim2.new(0.5,3,0,0),UDim2.new(0.5,-3,1,0),actionRow)
    local statusRow=row(debugPage,80); statusRow.LayoutOrder=-93
    local status=label("Read-only pickup source discovery. Finds UID arguments and distance checks if exposed in client code. Sends no pickup or teleport requests.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),statusRow,true)
    status.TextSize=14
    local state={token=0,busy=false,report=""}
    local function cancel()
        state.token=state.token+1; state.busy=false
        if state.worker then pcall(task.cancel,state.worker); state.worker=nil end
        if state.job then pcall(task.cancel,state.job); state.job=nil end
    end
    local function relevant(name)
        name=name:lower()
        return name:find("egg",1,true) or name:find("carry",1,true) or name:find("pickup",1,true) or name:find("steal",1,true)
    end
    connect(scan.Activated,function()
        if state.busy then return end
        state.busy=true; state.token=state.token+1
        local token=state.token
        state.report="AcidHub Egg Pickup Interface Inspection\nPlace ID: "..game.PlaceId.."\nUTC: "..os.date("!%Y-%m-%d %H:%M:%S").."\nRead-only. Source/decompiler text was not executed. No remote calls. Client code cannot establish server acceptance.\n"
        state.job=task.spawn(function()
            local ok,err=pcall(function()
                local candidates={}
                local storage=game:GetService("ReplicatedStorage")
                for _,scope in ipairs({storage,player:FindFirstChild("PlayerScripts"),player.Character}) do
                    if scope then
                        for _,object in ipairs(scope:GetDescendants()) do
                            if relevant(object.Name) then
                                if object:IsA("RemoteEvent") or object:IsA("RemoteFunction") then
                                    state.report=state.report.."\nREMOTE CANDIDATE: "..object:GetFullName().." ["..object.ClassName.."] (name only; signature unknown)\n"
                                elseif object:IsA("ModuleScript") or object:IsA("LocalScript") then
                                    local name=object.Name:lower()
                                    local score=(name:find("carry",1,true) or name:find("pickup",1,true) or name:find("steal",1,true)) and 100
                                        or name=="eggstate" and 90 or name:find("areaegg",1,true) and 80 or 10
                                    table.insert(candidates,{object=object,score=score})
                                end
                            end
                        end
                    end
                end
                table.sort(candidates,function(a,b)
                    if a.score~=b.score then return a.score>b.score end
                    return a.object:GetFullName()<b.object:GetFullName()
                end)
                state.report=state.report.."\nSCRIPT CANDIDATES ("..#candidates.."):\n"
                for _,candidate in ipairs(candidates) do state.report=state.report..candidate.object:GetFullName().."\n" end
                for index=1,math.min(12,#candidates) do
                    if token~=state.token or closed then return end
                    local object=candidates[index].object
                    status.Text="Inspecting "..index.."/"..math.min(12,#candidates)..": "..object.Name
                    state.report=state.report.."\nSOURCE: "..object:GetFullName().."\n"
                    local finished,output=false,nil
                    state.worker=task.spawn(function()
                        local accessible,source=pcall(function() return object.Source end)
                        if accessible and type(source)=="string" and #source>0 then output="METHOD: Source\n"..source
                        elseif type(decompile)=="function" then
                            local recovered,text=pcall(decompile,object)
                            output=recovered and type(text)=="string" and ("METHOD: decompile; may be incomplete\n"..text) or "Source unavailable; decompile failed."
                        else output="Source and decompile unavailable." end
                        finished=true
                    end)
                    local deadline=os.clock()+10
                    while not finished and token==state.token and not closed and os.clock()<deadline do task.wait(0.1) end
                    if token~=state.token or closed then return end
                    if not finished then
                        if state.worker then pcall(task.cancel,state.worker) end
                        output="Source inspection timed out."
                    end
                    state.worker=nil
                    output=output or "No output"
                    state.report=state.report..output:sub(1,30000)..(#output>30000 and "\n[Truncated at 30000 characters]" or "").."\n"
                end
            end)
            if token~=state.token or closed then return end
            state.busy=false; state.job=nil
            if not ok then state.report=state.report.."\nInspection error: "..tostring(err) end
            status.Text=ok and "Pickup inspection complete. Copy Pickup Inspection and send the report." or "Inspection failed; partial report can be copied."
        end)
    end)
    connect(stopScan.Activated,function() cancel(); status.Text="Stopped. Partial pickup report can be copied." end)
    connect(copyScan.Activated,function()
        if state.report=="" then status.Text="Inspect Egg Pickup Interfaces first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,state.report)
        status.Text=ok and "Pickup inspection copied." or "Clipboard unavailable."
    end)
    table.insert(cleanupActions,cancel)
end

do
    local order=-230
    local function testRow(height)
        local frame=row(debugPage,height); frame.LayoutOrder=order; order=order+1; return frame
    end
    label("Fuse — One-cycle Debug Test",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),testRow(38)).TextSize=20
    local status=label("Load three chosen pets through the game's fuse UI, then Preview. Test consumes those pets and charges the displayed fuse cost.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),testRow(150),true)
    status.TextSize=14
    local previewButton=button("Preview Loaded Fuse",UDim2.new(),UDim2.new(1,0,1,0),testRow(38))
    local runButton=button("Test Fuse Once (consumes 3 pets)",UDim2.new(),UDim2.new(1,0,1,0),testRow(38))
    local finishButton=button("Finish Pending Fuse Reward",UDim2.new(),UDim2.new(1,0,1,0),testRow(38))
    local copy=button("Copy Fuse Test Report",UDim2.new(),UDim2.new(1,0,1,0),testRow(38))
    local preview,busy=nil,false
    local lines={"AcidHub Fuse One-cycle Test"}
    local function note(message)
        status.Text=message
        if #lines>=100 then table.remove(lines,2) end
        table.insert(lines,string.format("[%.2f] %s",os.clock(),message))
    end
    local function snapshot()
        local storage=game:GetService("ReplicatedStorage")
        local save=require(storage.Shared.Save).Get()
        assert(type(save)=="table" and type(save.FusionSlots)=="table" and type(save.Inventory)=="table","Fuse save data unavailable")
        assert(not save.FusionLocked and save.FusionEggReward==false,"Machine is busy or has a pending reward; finish it in the game first")
        assert(save.FusionInfoAcknowledged,"Read and accept the game's fuse briefing first")
        local kernel=require(storage.Shared.Util.FuseKernel)
        local items=require(storage.Shared.Util.AssetItems)
        local ids,decoded,seen={},{},{}
        local category
        for i=1,3 do
            local uid=save.FusionSlots[i]
            local item=uid and save.Inventory[uid]
            assert(type(uid)=="string" and item and not seen[uid],"Load exactly three pets through the game UI first")
            local allowed,reason=kernel.MayEnterFuse(uid,item,category,true)
            assert(allowed,reason or "Pet cannot be fused")
            category=category or item.Category; seen[uid]=true
            ids[i]=uid; decoded[i]=items.Decode(item)
        end
        local count=0
        assert(type(save.EggInventory)=="table","Egg inventory unavailable")
        for _ in pairs(save.EggInventory) do count=count+1 end
        assert(count<require(storage.Shared.Types.Eggs).MAX_INVENTORY,"Egg inventory full")
        local price=kernel.PriceFor(decoded)
        local signature=game:GetService("HttpService"):JSONEncode(decoded)
        return {ids=ids,price=price,signature=signature,category=category}
    end
    connect(previewButton.Activated,function()
        if busy then return end
        preview=nil
        local ok,result=pcall(snapshot)
        if not ok then note("Preview stopped: "..tostring(result)); return end
        preview=result
        note("Selected category: "..tostring(result.category).." | Cost: "..tostring(result.price).."\nPet UIDs: "..table.concat(result.ids,", ").."\nTest Fuse Once will consume these three pets.")
    end)
    connect(runButton.Activated,function()
        if busy then return end
        if not preview then note("Preview Loaded Fuse first."); return end
        for _,key in ipairs({"AutoStealEnabled","Auto Place Eggs","Auto Treadmill","Auto Hatch","Auto Equip Best","Auto Fuse","Steal Rift Pets","Auto Buy Trail","Auto Upgrade Base","Auto Upgrade Treadmill","Auto Claim","Auto Sell Pets","Auto Sell Eggs"}) do
            if settingsBindings[key] and settingsBindings[key].get() then note("Turn automations OFF before the fuse test."); return end
        end
        local selected=preview; preview=nil; busy=true
        task.spawn(function()
            local ok,err=pcall(function()
                local current=snapshot()
                assert(current.signature==selected.signature and current.price==selected.price and table.concat(current.ids,"|")==table.concat(selected.ids,"|"),"Selection or cost changed; preview again")
                local storage=game:GetService("ReplicatedStorage")
                local remotes=require(storage.Shared.Remotes)
                local types=require(storage.Shared.Types.FuseMachine)
                if closed then return end
                note("Calling BeginFuse once | cost="..tostring(current.price).." | UIDs="..table.concat(current.ids,", "))
                local accepted,message,reward=remotes.Fusery.BeginFuse:InvokeServer()
                assert(accepted==true,"BeginFuse denied: "..tostring(message))
                assert(types.FuseResult(reward),"Server accepted fuse but returned an invalid reward. Check the machine manually; no retry.")
                -- Complete directly; do not also fire the native handler and duplicate its request.
                note("BeginFuse accepted; calling FinishReveal once.")
                local finished,finishReason=remotes.Fusery.FinishReveal:InvokeServer()
                assert(finished==true,"FinishReveal denied: "..tostring(finishReason)..". Use Finish Pending Fuse Reward after checking the machine.")
                if closed then return end
                note("FinishReveal accepted by server. Waiting for replicated inventory update.")
                local deadline=os.clock()+60
                repeat
                    task.wait(0.5)
                    if closed then return end
                    local save=require(storage.Shared.Save).Get()
                    if save and not save.FusionLocked and save.FusionEggReward==false then
                        local consumed=true
                        for _,uid in ipairs(selected.ids) do if save.Inventory[uid] then consumed=false end end
                        if consumed then note("Fuse completed: FinishReveal accepted, inputs consumed and reward state cleared. Check your egg inventory."); return end
                    end
                until os.clock()>deadline
                note("Completion unconfirmed after 60s. Check the game's machine/reveal; no automatic retry.")
            end)
            busy=false
            if not ok and not closed then note("Fuse test stopped: "..tostring(err).." | No automatic retry.") end
        end)
    end)
    connect(finishButton.Activated,function()
        if busy then return end
        for _,key in ipairs({"AutoStealEnabled","Auto Place Eggs","Auto Treadmill","Auto Hatch","Auto Equip Best","Auto Fuse","Steal Rift Pets","Auto Buy Trail","Auto Upgrade Base","Auto Upgrade Treadmill","Auto Claim","Auto Sell Pets","Auto Sell Eggs"}) do
            if settingsBindings[key] and settingsBindings[key].get() then note("Turn automations OFF before finishing the pending reward."); return end
        end
        busy=true; preview=nil
        task.spawn(function()
            local ok,err=pcall(function()
                local storage=game:GetService("ReplicatedStorage")
                local save=require(storage.Shared.Save).Get()
                local types=require(storage.Shared.Types.FuseMachine)
                assert(save and types.PendingEggReward(save.FusionEggReward),"No valid pending fuse reward found. No request sent.")
                if closed then return end
                note("Calling FinishReveal once for existing reward; no BeginFuse or pet loading.")
                local accepted,message=require(storage.Shared.Remotes).Fusery.FinishReveal:InvokeServer()
                assert(accepted==true,"FinishReveal denied: "..tostring(message))
                if not closed then note("Pending reward: FinishReveal accepted by server. Check your egg inventory.") end
            end)
            busy=false
            if not ok and not closed then note("Finish pending reward stopped: "..tostring(err).." | No automatic retry.") end
        end)
    end)
    connect(copy.Activated,function()
        local ok=type(setclipboard)=="function" and pcall(setclipboard,table.concat(lines,"\n"))
        if not ok then status.Text="Clipboard unavailable." end
    end)
end

do
(function()
    local order=-270
    local function r(height) local f=row(debugPage,height); f.LayoutOrder=order; order=order+1; return f end
    label("The Rift — Live Debug Test",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),r(38)).TextSize=20
    local status=label("Read requirements to preview three pets. No stealing or trade-in happens until you press Test Rift Trade Once.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),r(210),true)
    status.TextSize=14
    local readButton=button("Read Rift Requirements + Preview Pets",UDim2.new(),UDim2.new(1,0,1,0),r(38))
    local tradeButton=button("Test Rift Trade Once (consumes 3 pets)",UDim2.new(),UDim2.new(1,0,1,0),r(38))
    local copy=button("Copy Rift Test Report",UDim2.new(),UDim2.new(1,0,1,0),r(38))
    local busy,preview=false,nil
    local lines={"AcidHub Rift Live Test"}
    local function note(message)
        if #lines>=100 then table.remove(lines,2) end
        lines[#lines+1]=os.date("%Y-%m-%d %H:%M:%S").." | "..message
        status.Text=message
    end
    local function snapshot()
        local storage=game:GetService("ReplicatedStorage")
        local remotes=require(storage.Shared.Remotes).Rift
        local state=remotes.AskState:InvokeServer()
        assert(type(state)=="table" and type(state.Requirements)=="table" and #state.Requirements==3,"Rift state did not return three requirements")
        local save=require(storage.Shared.Save).Get()
        assert(save and type(save.Inventory)=="table" and type(save.EquippedAssets)=="table","Inventory unavailable")
        local data=require(storage.Data.Rift)
        local kernel=require(storage.Shared.Util.FuseKernel)
        local items=require(storage.Shared.Util.AssetItems)
        local used,selected,missing={},{},{}
        for slot,category in ipairs(state.Requirements) do
            assert(type(category)=="string","Invalid Rift category")
            local candidates={}
            for uid,item in pairs(save.Inventory) do
                if not used[uid] and item.Category==category and not table.find(save.EquippedAssets,uid) then
                    local ok,allowed=pcall(kernel.MayEnterRift,uid,item)
                    if ok and allowed then
                        local decoded=items.Decode(item)
                        candidates[#candidates+1]={uid=uid,weight=items.WeightKg(decoded),item=copySetting(item)}
                    end
                end
            end
            table.sort(candidates,function(a,b) return a.weight==b.weight and a.uid<b.uid or a.weight<b.weight end)
            if candidates[1] then selected[slot]=candidates[1]; used[candidates[1].uid]=true
            else missing[#missing+1]=category end
        end
        return {state=state,selected=selected,missing=missing,rotation=math.floor(workspace:GetServerTimeNow()/data.RotationSeconds()),seconds=data.SecondsUntilRotation()}
    end
    connect(readButton.Activated,function()
        if busy then return end
        busy=true; preview=nil
        task.spawn(function()
            local ok,result=pcall(snapshot)
            busy=false
            if closed then return end
            if not ok then note("Read failed: "..tostring(result)); return end
            preview=result
            local text={"Banner: "..tostring(result.state.BannerId).." | rotates in "..math.floor(result.seconds).."s"}
            for i,category in ipairs(result.state.Requirements) do
                local pet=result.selected[i]
                text[#text+1]=category..(pet and string.format(" | UID %s | %.2f kg",pet.uid,pet.weight) or " | MISSING")
            end
            text[#text+1]=#result.missing==0 and "Trade test will consume these exact pets." or "Missing pets must be collected and hatched before trading."
            text[#text+1]="Normal Auto Steal filters are unchanged."
            note(table.concat(text,"\n"))
        end)
    end)
    connect(tradeButton.Activated,function()
        if busy then return end
        if not preview or #preview.missing>0 then note("Preview a complete set of three pets first."); return end
        for _,key in ipairs({"AutoStealEnabled","Auto Place Eggs","Auto Treadmill","Auto Hatch","Auto Equip Best","Auto Fuse","Steal Rift Pets","Auto Buy Trail","Auto Upgrade Base","Auto Upgrade Treadmill","Auto Claim","Auto Sell Pets","Auto Sell Eggs"}) do
            if settingsBindings[key] and settingsBindings[key].get() then note("Turn automations OFF for this trade test."); return end
        end
        local selected=preview; preview=nil; busy=true
        task.spawn(function()
            local ok,err=pcall(function()
                local current=snapshot()
                assert(current.rotation==selected.rotation and current.state.BannerId==selected.state.BannerId,"Rift rotated; preview again")
                local storage=game:GetService("ReplicatedStorage")
                local save=require(storage.Shared.Save).Get()
                local kernel=require(storage.Shared.Util.FuseKernel)
                local ids={}
                local before={}; for uid in pairs(save.EggInventory) do before[uid]=true end
                local count=0; for _ in pairs(before) do count=count+1 end
                assert(count<require(storage.Shared.Types.Eggs).MAX_INVENTORY,"Egg inventory full")
                for i,pet in ipairs(selected.selected) do
                    assert(current.state.Requirements[i]==selected.state.Requirements[i],"Recipe changed; preview again")
                    local item=save.Inventory[pet.uid]
                    assert(item and item.Category==current.state.Requirements[i] and not table.find(save.EquippedAssets,pet.uid),"Selected pet changed or became equipped")
                    assert(kernel.MayEnterRift(pet.uid,item),"Selected pet is no longer eligible")
                    ids[i]=pet.uid
                end
                if closed then return end
                note("AskTradeIn once | UIDs="..table.concat(ids,", "))
                local remotes=require(storage.Shared.Remotes).Rift
                local accepted,message=remotes.AskTradeIn:InvokeServer(ids)
                assert(accepted==true,"Trade denied: "..tostring(message))
                note("Trade accepted; calling AskFinishReveal once without animation")
                local result,reason=remotes.AskFinishReveal:InvokeServer()
                note("AskFinishReveal returned "..tostring(result).." | "..tostring(reason).."; checking inventory")
                local deadline=os.clock()+15
                repeat
                    local state=require(storage.Shared.Save).Get()
                    local consumed=true
                    for _,uid in ipairs(ids) do if state.Inventory[uid] then consumed=false end end
                    if consumed then
                        for uid in pairs(state.EggInventory) do if not before[uid] then note("Trade completed: inputs consumed; new egg observed | UID "..uid); return end end
                    end
                    task.wait(0.25)
                until closed or os.clock()>deadline
                error("Reward unconfirmed; check Rift and inventory manually. No retry sent.")
            end)
            busy=false
            if not ok and not closed then note("Rift test stopped: "..tostring(err)) end
        end)
    end)
    connect(copy.Activated,function()
        if type(setclipboard)=="function" then pcall(setclipboard,table.concat(lines,"\n")) end
    end)
end)()
end

do
(function()
    local order=-380
    local function testRow(height)
        local frame=row(debugPage,height); frame.LayoutOrder=order; order=order+1; return frame
    end
    label("Auto Progress — One-shot Tests",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),testRow(38)).TextSize=20
    label("Preview first, then test one action. Purchase tests spend game money. Stop automations before testing. No automatic retries; no trail equip or Robux purchase calls.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),testRow(85),true).TextSize=14
    local status=label("Preview Progress to read affordable upgrades and available claims.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),testRow(155),true)
    status.TextSize=14
    local busy=false; local previews={}; local lines={"AcidHub Progress One-shot Tests"}
    local function note(message)
        lines[#lines+1]=os.date("%Y-%m-%d %H:%M:%S").." | "..message
        status.Text=message; reportTask("Auto Progress",message)
    end
    local function idle()
        assert(not closed,"Hub closed")
        for _,key in ipairs({"AutoStealEnabled","Auto Place Eggs","Auto Treadmill","Auto Hatch","Auto Equip Best","Auto Fuse","Steal Rift Pets","Auto Buy Trail","Auto Upgrade Base","Auto Upgrade Treadmill","Auto Claim","Auto Sell Pets","Auto Sell Eggs"}) do
            local binding=settingsBindings[key]
            assert(not binding or not binding.get(),"Turn OFF "..key.." before testing")
        end
        assert(not automationFlow.collecting and not automationFlow.placing and not automationFlow.fusing and not (automationFlow.rift and automationFlow.rift.busy) and not treadmillExitBusy,"Wait for current work to finish")
    end
    local function progressTrailCandidate(save,directory)
        local best=1; local chosen,cost
        for id,owned in pairs(save.TrailInventory) do
            if owned==true and directory[id] then best=math.max(best,tonumber(directory[id].SpeedMultiplier) or 1) end
        end
        for id,config in pairs(directory) do
            local price=tonumber(config.Price)
            if config.DisplayInShop==true and not save.TrailInventory[id] and price and price>=0 and price<=save.Money and (tonumber(config.SpeedMultiplier) or 1)>best then
                if not chosen or price<cost or (price==cost and id<chosen) then chosen=id; cost=price end
            end
        end
        return chosen,cost
    end
    -- END progressTrailCandidate
    local function plan(kind,offlineSummary)
        local storage=game:GetService("ReplicatedStorage")
        local save=assert(require(storage.Shared.Save).Get(),"Save not loaded")
        local remotes=require(storage.Shared.Remotes)
        if kind=="Trail" then
            local directory=require(storage.Data.Trails).Directory
            local id,cost=progressTrailCandidate(save,directory)
            if not id then return nil,"No affordable trail stronger than your owned trails" end
            return {key=id,cost=cost,text=tostring(directory[id].DisplayName or id).." | cost "..cost}
        elseif kind=="Base" then
            local level=assert(tonumber(save.BaseUpgradeLevel),"Base level unavailable")
            local config=require(storage.Data.Bases).BASES[level+1]
            if not config then return nil,"Base maxed" end
            if save.Money<config.Cost then return nil,"Base unaffordable | cost "..config.Cost end
            return {key=level+1,before=level,cost=config.Cost,text="Base level "..level.." -> "..(level+1).." | cost "..config.Cost}
        elseif kind=="Treadmill" then
            local level=assert(tonumber(save.TreadmillUpgradeLevel),"Treadmill level unavailable")
            local config=require(storage.Data.Treadmills).GetByUpgradeLevel(level+1)
            if not config then return nil,"Treadmill maxed" end
            if save.Money<config.Price then return nil,"Treadmill unaffordable | cost "..config.Price end
            return {key=config._id,before=level,cost=config.Price,text="Treadmill "..config._id.." | cost "..config.Price}
        elseif kind=="Offline" then
            local summary=offlineSummary or remotes.AwayEarnings.FetchSummary:InvokeServer()
            assert(type(summary)=="table","Offline summary unavailable")
            if summary.IsMultiplierPurchasePending then return nil,"Offline multiplier purchase pending" end
            local amount=tonumber(summary.ClaimableAmount) or 0
            if amount<=0 then return nil,"No offline earnings available" end
            return {key="Claim",text="Offline earnings available: "..amount}
        elseif kind=="Index" then
            local categories={}
            for category,discovered in pairs(save.Index or {}) do
                if discovered==true and not (save.IndexClaimedCategories or {})[category] then categories[#categories+1]=category end
            end
            table.sort(categories)
            if #categories==0 then return nil,"No unclaimed index rewards" end
            return {key=table.concat(categories,"|"),text="Claim all index rewards: "..#categories.." categories"}
        end
    end
    local function execute(kind,current,emit)
        local note=emit
            local storage=game:GetService("ReplicatedStorage")
            local remotes=require(storage.Shared.Remotes)
            note("Sending "..kind.." once | "..current.text)
            local accepted,message,result
            if kind=="Trail" then accepted,message=remotes.Trailwear.AskPurchase:InvokeServer(current.key)
            elseif kind=="Base" then remotes.Homestead.AskBaseTierRaise:FireServer()
            elseif kind=="Treadmill" then accepted,message=remotes.Treadmill.AskTierRaise:InvokeServer(current.key)
            elseif kind=="Offline" then accepted,message,result=remotes.AwayEarnings.AskCollect:InvokeServer({Kind="Claim"})
            else accepted,message,result=remotes.Codex.AskRedeemAll:InvokeServer() end
            if kind~="Base" then
                note(kind.." returned "..tostring(accepted).." | "..tostring(message))
                assert(accepted==true,"Request rejected: "..tostring(message))
            end
            if kind=="Offline" then
                assert(type(result)=="table" and type(result.AwardedAmount)=="number","Accepted; reward result unconfirmed")
                note("Offline completed | awarded "..result.AwardedAmount); return
            elseif kind=="Index" then
                assert(type(result)=="table","Accepted; index result unconfirmed")
                -- The native index controller applies this response to its local save cache.
                for _,entry in ipairs(result) do
                    if type(entry.Category)=="string" then require(storage.Shared.Save).ApplyLocalFieldEntry("IndexClaimedCategories",entry.Category,true) end
                end
                note("Index completed | server returned "..#result.." claimed rewards"); return
            end
            local deadline=os.clock()+12
            repeat
                local save=require(storage.Shared.Save).Get()
                local confirmed=save and ((kind=="Trail" and save.TrailInventory[current.key]==true)
                    or (kind=="Base" and save.BaseUpgradeLevel>=current.key)
                    or (kind=="Treadmill" and save.TreadmillUpgradeLevel>current.before))
                if confirmed then note(kind.." completed; saved ownership/level change observed"); return end
                task.wait(0.25)
            until closed or os.clock()>deadline
            error("Result unconfirmed after 12 seconds; inspect the game before another test")
    end
    local function launch(action)
        if busy then return end
        busy=true
        task.spawn(function()
            local ok,err=pcall(action)
            busy=false
            if not ok then note("Stopped: "..tostring(err).." | no automatic retry") end
        end)
    end
    local preview=button("Preview Progress",UDim2.new(),UDim2.new(1,0,1,0),testRow(36))
    connect(preview.Activated,function() launch(function()
        idle(); previews={}; local summary={}
        for _,kind in ipairs({"Trail","Base","Treadmill","Offline","Index"}) do
            local ok,result,reason=pcall(plan,kind)
            if ok then previews[kind]=result end
            local message=kind..": "..(ok and (result and result.text or reason) or tostring(result))
            summary[#summary+1]=message; note(message)
        end
        status.Text=table.concat(summary,"\n")
    end) end)
    for _,kind in ipairs({"Trail","Base","Treadmill","Offline","Index"}) do
        local control=button("Test "..kind.." Once",UDim2.new(),UDim2.new(1,0,1,0),testRow(36))
        connect(control.Activated,function() launch(function()
            idle()
            local approved=assert(previews[kind],"Preview an eligible "..kind.." action first")
            previews[kind]=nil
            local current,reason=plan(kind)
            assert(current,reason)
            assert(current.key==approved.key and current.cost==approved.cost,"Target/cost changed; preview again")
            idle()
            execute(kind,current,note)
        end) end)
    end
    local progressPage
    for _,section in ipairs(automationSubtabs) do if section.name=="Auto Progress" then progressPage=section.page end end
    local enabled,paused,pending={},{},{}
    local offlineSummary
    local controls={{"Auto Buy Trail","Trail"},{"Auto Upgrade Base","Base"},{"Auto Upgrade Treadmill","Treadmill"},{"Auto Claim","Claims"}}
    local actions={{"Auto Claim","Offline"},{"Auto Claim","Index"},{"Auto Buy Trail","Trail"},{"Auto Upgrade Base","Base"},{"Auto Upgrade Treadmill","Treadmill"}}
    local updates={}
    local function progressNote(key,message)
        updates[key]=message
        local summary={}
        for _,entry in ipairs(controls) do if enabled[entry[1]] then summary[#summary+1]=entry[1]..": "..(updates[entry[1]] or "Watching for changes") end end
        reportTask("Auto Progress",table.concat(summary," | "))
    end
    local function schedule(kind)
        for _,entry in ipairs(actions) do
            if entry[2]==kind and enabled[entry[1]] and not paused[entry[1]] and not pending[kind] then
                -- Keep the first deadline so a constantly changing balance cannot starve checks.
                pending[kind]=os.clock()+1.5
            end
        end
    end
    for _,entry in ipairs(controls) do
        local key=entry[1]
        switch(progressPage,key,false,function(value)
            enabled[key]=value; paused[key]=nil
            for _,action in ipairs(actions) do if action[1]==key then
                pending[action[2]]=nil
                if value then schedule(action[2]) end
            end end
            progressNote(key,value and "Initial check queued; watching for changes" or "OFF")
        end,key=="Auto Claim" and "Check on enable and on index/offline reward changes. Updates are combined for 1.5 seconds; requests run sequentially."
            or "Check on enable and when money or ownership/levels change. Buy affordable upgrades with game money, sequentially, after a 1.5-second debounce.")
    end
    task.spawn(function()
        local ok,err=pcall(function()
            local storage=game:GetService("ReplicatedStorage")
            local save=require(storage.Shared.Save)
            local remotes=require(storage.Shared.Remotes)
            connect(save.FieldSignal("Money"),function() schedule("Trail"); schedule("Base"); schedule("Treadmill") end)
            for _,entry in ipairs({{"TrailInventory","Trail"},{"BaseUpgradeLevel","Base"},{"TreadmillUpgradeLevel","Treadmill"},{"Index","Index"},{"IndexClaimedCategories","Index"}}) do
                local field,kind=entry[1],entry[2]
                connect(save.FieldSignal(field),function() schedule(kind) end)
            end
            connect(remotes.AwayEarnings.SummaryRefreshed.OnClientEvent,function(summary)
                if type(summary)~="table" or type(summary.ClaimableAmount)~="number" then return end
                local changed=not offlineSummary or offlineSummary.ClaimableAmount~=summary.ClaimableAmount
                    or offlineSummary.IsMultiplierPurchasePending~=summary.IsMultiplierPurchasePending
                offlineSummary={ClaimableAmount=summary.ClaimableAmount,IsMultiplierPurchasePending=summary.IsMultiplierPurchasePending}
                if changed and summary.ClaimableAmount>0 and not summary.IsMultiplierPurchasePending then schedule("Offline") end
            end)
        end)
        if not ok then
            for _,entry in ipairs(controls) do progressNote(entry[1],"Change listeners unavailable: "..tostring(err)) end
        end
    end)
    task.spawn(function()
        while not closed do
            if not busy then
                for _,entry in ipairs(actions) do
                    local key,kind=entry[1],entry[2]
                    if pending[kind] and os.clock()>=pending[kind] then
                        pending[kind]=nil
                        if not closed and enabled[key] and not paused[key] then
                            busy=true
                            local ok,err=pcall(function()
                                local candidate,reason=plan(kind,kind=="Offline" and offlineSummary or nil)
                                if closed or not enabled[key] then return end
                                if not candidate then progressNote(key,kind..": "..tostring(reason)); return end
                                execute(kind,candidate,function(message) progressNote(key,message) end)
                                -- A confirmed purchase permits checking the next upgrade, even if
                                -- the corresponding save signal arrived before confirmation.
                                if kind=="Trail" or kind=="Base" or kind=="Treadmill" then schedule(kind) end
                            end)
                            busy=false
                            if not ok then paused[key]=true; progressNote(key,"Paused: "..tostring(err).."; toggle OFF/ON after checking the result") end
                        end
                    end
                end
            end
            -- Only pending timestamps are inspected here; no availability reads or requests.
            task.wait(0.25)
        end
    end)
    table.insert(cleanupActions,function() for key in pairs(enabled) do enabled[key]=false end; pending={} end)
    local copy=button("Copy Progress Test Log",UDim2.new(),UDim2.new(1,0,1,0),testRow(36))
    connect(copy.Activated,function() if type(setclipboard)=="function" then pcall(setclipboard,table.concat(lines,"\n")) end end)
    local save=button("Save Progress Test Log",UDim2.new(),UDim2.new(1,0,1,0),testRow(36))
    connect(save.Activated,function()
        if type(writefile)~="function" then note("File saving unavailable"); return end
        local ok,err=pcall(writefile,"AcidHub_Progress_Test.txt",table.concat(lines,"\n"))
        status.Text=ok and "Saved AcidHub_Progress_Test.txt" or tostring(err)
    end)
end)()
end

do
    local order=-400
    local function guardRow(height)
        local frame=row(debugPage,height)
        frame.LayoutOrder=order; order=order+1
        return frame
    end
    label("Steal Progression — Guard Inspection",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),guardRow(42)).TextSize=20
    label("Reads guard chase, escape requirements, area configuration, and speed conversion sources. No movement or remote calls. A guard’s observed WalkSpeed may differ from its chase speed.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,120),true).TextSize=14
    local scan=button("Inspect Guard Speed Scripts",UDim2.new(),UDim2.new(1,0,1,0),guardRow(38))
    local stop=button("Stop Guard Speed Inspection",UDim2.new(),UDim2.new(1,0,1,0),guardRow(38))
    local save=button("Save Guard Speed Inspection",UDim2.new(),UDim2.new(1,0,1,0),guardRow(38))
    local copy=button("Copy Guard Speed Inspection",UDim2.new(),UDim2.new(1,0,1,0),guardRow(38))
    local status=label("Inspect Guard Speed Scripts, then save or copy the report. Each inspection reads your current normal speed again.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),guardRow(90),true)
    local generation,busy=0,false
    local worker,report=nil,""
    local function cancel()
        generation=generation+1; busy=false
        if worker then pcall(task.cancel,worker); worker=nil end
    end
    connect(scan.Activated,function()
        if busy then return end
        busy=true; generation=generation+1; local run=generation
        report="AcidHub Guard Speed Source Inspection\nUTC: "..os.date("!%Y-%m-%d %H:%M:%S").."\nPlace ID: "..game.PlaceId.."\nRead-only inspection. Recovered text is untrusted and was not executed. Decompiler output is not guaranteed accurate.\n"
        local storage=game:GetService("ReplicatedStorage")
        local targets={
            {storage,{"Shared","Modules","GuardAreas","GuardEscapeRequirement"}},
            {storage,{"Shared","Modules","GuardAreas","GuardEscapePrediction"}},
            {storage,{"Shared","Modules","GuardAreas","GuardChasePolicy"}},
            {storage,{"Shared","Utils","GuardEscape"}},
            {storage,{"Shared","Util","TreadmillUtil"}},
            {storage,{"Shared","Globals","Constants"}},
            {storage,{"Data","Areas"}},
            {player,{"PlayerScripts","Game","GuardAreas","GuardComponent"}},
            {player,{"PlayerScripts","Game","GuardAreas","ForestGuardRuntime"}},
            {player,{"PlayerScripts","Game","GuardAreas","GuardEscapeSignController"}},
            {player,{"PlayerScripts","GUI","GuardAreas","RequiredSpeedSign"}},
        }
        local seen={}
        for _,target in ipairs(targets) do seen[target[1]:GetFullName().."."..table.concat(target[2],".")]=true end
        for _,root in ipairs({storage,player}) do
            for _,object in ipairs(root:GetDescendants()) do
                if object:IsA("LocalScript") or object:IsA("ModuleScript") then
                    local path=object:GetFullName()
                    local relevant=path:find(".Data.Areas.Configs.",1,true) or path:find(".Shared.Modules.GuardAreas.",1,true)
                        or object.Name:lower():find("walkspeed",1,true)
                    if relevant and not seen[path] and #targets<45 then seen[path]=true; targets[#targets+1]={object,{}} end
                end
            end
        end
        local humanoid=movementHumanoid(player.Character)
        local normal=humanoid and humanoid.WalkSpeed
        if approachOverride and approachOverride.humanoid==humanoid and approachOverride.base then normal=approachOverride.base end
        report=report.."Current normal WalkSpeed: "..tostring(normal).." | current Humanoid WalkSpeed: "..tostring(humanoid and humanoid.WalkSpeed).."\n"
        local objects=workspace:FindFirstChild("__OBJECTS")
        local areas=objects and objects:FindFirstChild("Areas")
        report=report.."\nLIVE AREA GUARD OBSERVATIONS (not confirmed chase speeds):\n"
        if areas then
            for _,area in ipairs(areas:GetChildren()) do
                local guard=area:FindFirstChild("Guard")
                local h=guard and guard:FindFirstChildWhichIsA("Humanoid",true)
                local root=guard and guard:FindFirstChild("HumanoidRootPart")
                report=report..area.Name.." | WalkSpeed="..tostring(h and h.WalkSpeed).." | position="..tostring(root and root.Position).."\n"
                if guard then
                    for key,value in pairs(guard:GetAttributes()) do report=report.."  Guard attribute "..key.."="..tostring(value).."\n" end
                end
            end
        else report=report.."Area folder unavailable\n" end
        report=report.."Executor capabilities: getconnections="..type(getconnections).." | firesignal="..type(firesignal).." | decompile="..type(decompile).."\n"
        task.spawn(function()
            for _,target in ipairs(targets) do
                if run~=generation then return end
                local object=target[1]
                local path=object:GetFullName()..(#target[2]>0 and ("."..table.concat(target[2],".")) or "")
                for _,name in ipairs(target[2]) do object=object and object:FindFirstChild(name) end
                report=report.."\nTARGET: "..path.."\n"
                if not object or not (object:IsA("LocalScript") or object:IsA("ModuleScript")) then
                    report=report.."Missing script at observed path.\n"
                else
                    status.Text="Inspecting "..object.Name.." (up to 20 seconds)..."
                    local finished,output=false,nil
                    worker=task.spawn(function()
                        local ok,source=pcall(function() return object.Source end)
                        if ok and type(source)=="string" and #source>0 then
                            output="METHOD: Source\n"..source
                        elseif type(decompile)=="function" then
                            local success,recovered=pcall(decompile,object)
                            output=success and type(recovered)=="string" and ("METHOD: decompile (verify before use)\n"..recovered) or ("Decompiler failed: "..tostring(recovered))
                        else output="Source unavailable; executor decompile function unavailable." end
                        finished=true
                    end)
                    local deadline=os.clock()+20
                    while not finished and run==generation and os.clock()<deadline do task.wait(0.1) end
                    if run~=generation then return end
                    if not finished then
                        if worker then pcall(task.cancel,worker) end
                        output="Inspection timed out after 20 seconds."
                    end
                    worker=nil
                    output=output or "No output"
                    report=report..output:sub(1,80000)..(#output>80000 and "\n[Truncated at 80000 characters]" or "").."\n"
                end
            end
            if run==generation then busy=false; status.Text="Inspection finished. Save or copy the report." end
        end)
    end)
    connect(stop.Activated,function() cancel(); report=report.."\nStopped by user; report may be partial.\n"; status.Text="Stopped. Partial report available." end)
    connect(copy.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        status.Text=ok and "Inspection copied." or "Clipboard unavailable. Save the report."
    end)
    connect(save.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        if type(writefile)~="function" then status.Text="File saving unavailable."; return end
        local filename="AcidHub_Guard_Speed_Source_"..os.time()..".txt"
        local ok,err=pcall(writefile,filename,report)
        status.Text=ok and ("Saved "..filename) or tostring(err)
    end)
    table.insert(cleanupActions,cancel)
end



do (function()
    local order=-440
    local function sellTestRow(height)
        local frame=row(debugPage,height); frame.LayoutOrder=order; order=order+1; return frame
    end
    label("Auto Sell — One-shot Tests",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),sellTestRow(38)).TextSize=20
    label("Preview first. Each test permanently sells ONE displayed UID, Rare or below. Equipped, favorite and fusing pets are excluded; eggs must be unplaced. No automatic selling or retries.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),sellTestRow(95),true).TextSize=14
    local status=label("Preview Auto Sell to choose one low-rarity pet and one unplaced egg.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),sellTestRow(145),true)
    status.TextSize=14
    local busy=false; local previews={}; local lines={"AcidHub Auto Sell One-shot Tests"}
    local function note(message)
        lines[#lines+1]=os.date("%Y-%m-%d %H:%M:%S").." | "..message
        status.Text=message; reportTask("Auto Sell",message)
    end
    local function idle()
        assert(not closed,"Hub closed")
        for _,key in ipairs({"AutoStealEnabled","Auto Place Eggs","Auto Treadmill","Auto Hatch","Auto Equip Best","Auto Fuse","Steal Rift Pets","Auto Buy Trail","Auto Upgrade Base","Auto Upgrade Treadmill","Auto Claim","Auto Sell Pets","Auto Sell Eggs"}) do
            local binding=settingsBindings[key]; assert(not binding or not binding.get(),"Turn OFF "..key.." before testing")
        end
        assert(not automationFlow.collecting and not automationFlow.placing and not automationFlow.fusing and not (automationFlow.rift and automationFlow.rift.busy),"Wait for current automation work to finish")
    end
    local function candidates(kind)
        local storage=game:GetService("ReplicatedStorage")
        local save=assert(require(storage.Shared.Save).Get(),"Save unavailable")
        assert(type(save.EquippedAssets)=="table" and type(save.Inventory)=="table" and type(save.EggInventory)=="table","Inventory not ready")
        local items=require(storage.Shared.Util.AssetItems)
        local eggs=require(storage.Shared.Util.EggRecords)
        local source=kind=="Pets" and save.Inventory or save.EggInventory
        local result={}
        for uid,raw in pairs(source) do
            local ok,item=pcall(function()
                if kind=="Pets" then
                    local decoded=items.Decode(raw)
                    if decoded.IsFavorite==true or decoded.InFuse==true or table.find(save.EquippedAssets,uid) then return end
                    local rarity,rank=automationFlow.audit.rarity(decoded.Category)
                    if not rank or rank>3 then return end
                    return {uid=uid,category=decoded.Category,rarity=rarity,rank=rank,price=items.SalePrice(decoded),weight=items.WeightKg(decoded)}
                else
                    if raw.Placement~=nil then return end
                    local decoded=eggs.Decode(raw)
                    local rarity,rank=automationFlow.audit.rarity(decoded.AssetCategory)
                    if not rank or rank>3 then return end
                    return {uid=uid,category=decoded.AssetCategory,rarity=rarity,rank=rank,price=eggs.SellPrice(decoded),weight=eggs.WeightKg(decoded)}
                end
            end)
            if ok and item and type(item.price)=="number" and item.price>=0 then result[#result+1]=item end
        end
        table.sort(result,function(a,b)
            if a.rank~=b.rank then return a.rank<b.rank end
            if a.price~=b.price then return a.price<b.price end
            return a.uid<b.uid
        end)
        return result
    end
    local preview=button("Preview Auto Sell",UDim2.new(),UDim2.new(1,0,1,0),sellTestRow(36))
    connect(preview.Activated,function()
        if busy then return end
        local ok,err=pcall(function()
            idle(); previews={}; local summary={}
            for _,kind in ipairs({"Pets","Eggs"}) do
                local item=candidates(kind)[1]; previews[kind]=item
                local text=kind..": "..(item and (item.category.." | "..item.rarity.." | "..tostring(item.weight).." kg | base sale value "..item.price.." | UID "..item.uid) or "No eligible Rare-or-below candidate")
                note(text); summary[#summary+1]=text
            end
            status.Text=table.concat(summary,"\n")
        end)
        if not ok then note("Preview stopped: "..tostring(err)) end
    end)
    for _,kind in ipairs({"Pets","Eggs"}) do
        local control=button(kind=="Pets" and "Test Sell One Pet" or "Test Sell One Egg",UDim2.new(),UDim2.new(1,0,1,0),sellTestRow(36))
        connect(control.Activated,function()
            if busy then return end
            busy=true
            task.spawn(function()
                local ok,err=pcall(function()
                    idle()
                    local selected=assert(previews[kind],"Preview an eligible item first")
                    previews[kind]=nil
                    local fresh
                    for _,item in ipairs(candidates(kind)) do if item.uid==selected.uid then fresh=item end end
                    assert(fresh and fresh.category==selected.category and fresh.price==selected.price,"Previewed item changed or is now protected; preview again")
                    idle()
                    local storage=game:GetService("ReplicatedStorage")
                    local request={Assets={},Eggs={}}
                    if kind=="Pets" then request.Assets={selected.uid} else request.Eggs={selected.uid} end
                    note("Sending SellSelection once | "..kind.." | "..selected.category.." | UID "..selected.uid)
                    require(storage.Shared.Remotes).PetSatchel.SellSelection:FireServer(request)
                    local deadline=os.clock()+12
                    repeat
                        local save=require(storage.Shared.Save).Get()
                        local inventory=save and (kind=="Pets" and save.Inventory or save.EggInventory)
                        if inventory and inventory[selected.uid]==nil then note("Sale completed: exact UID removed from "..kind.." | "..selected.uid); return end
                        task.wait(0.25)
                    until closed or os.clock()>deadline
                    error("Sale unconfirmed after 12 seconds; check inventory. No retry sent")
                end)
                busy=false
                if not ok then note("Test stopped: "..tostring(err)) end
            end)
        end)
    end
    local duplicatePreview
    local pickDuplicate=button("Preview Repeated UID Sale Pet",UDim2.new(),UDim2.new(1,0,1,0),sellTestRow(36))
    local sellDuplicate=button("Test Sell Same UID x3",UDim2.new(),UDim2.new(1,0,1,0),sellTestRow(36))
    connect(pickDuplicate.Activated,function()
        if busy then return end
        duplicatePreview=nil
        local ok,err=pcall(function()
            idle()
            local pool=candidates("Pets")
            assert(#pool>0,"No eligible Common–Rare pet; equipped, favorite and fusing pets are excluded")
            duplicatePreview=pool[math.random(1,#pool)]
            local pet=duplicatePreview
            note("Repeated UID preview: "..Rarity.Resolve(pet.category).." | "..pet.rarity.." | UID "..pet.uid.." | single sale value "..pet.price..". Test may permanently sell this pet.")
        end)
        if not ok then note("Preview stopped: "..tostring(err)) end
    end)
    connect(sellDuplicate.Activated,function()
        if busy then return end
        if not duplicatePreview then note("Preview Repeated UID Sale Pet first"); return end
        local selected=duplicatePreview; duplicatePreview=nil; busy=true
        task.spawn(function()
            local ok,err=pcall(function()
                idle()
                local fresh
                for _,pet in ipairs(candidates("Pets")) do if pet.uid==selected.uid then fresh=pet; break end end
                assert(fresh and fresh.category==selected.category and fresh.price==selected.price,"Pet changed or is protected; preview again")
                local storage=game:GetService("ReplicatedStorage")
                local saveModule=require(storage.Shared.Save)
                local before=saveModule.Get()
                local moneyBefore=before and before.Money
                local request={Assets={selected.uid,selected.uid,selected.uid},Eggs={}}
                idle()
                note("Sending ONE SellSelection | Assets="..table.concat(request.Assets,", ").." | single sale value="..selected.price)
                require(storage.Shared.Remotes).PetSatchel.SellSelection:FireServer(request)
                local removed=false
                local deadline=os.clock()+12
                repeat
                    if closed then return end
                    local current=saveModule.Get()
                    if current and current.Inventory and current.Inventory[selected.uid]==nil and not removed then
                        removed=true; note("Selected pet UID removed from inventory")
                    end
                    task.wait(0.25)
                until os.clock()>=deadline
                local current=saveModule.Get()
                local delta=type(moneyBefore)=="number" and current and type(current.Money)=="number" and (current.Money-moneyBefore) or nil
                note("Result: UID removal="..tostring(removed).." | observed money change="..tostring(delta)..". Other income may affect this amount; RemoteEvent has no return response. No retry sent.")
            end)
            busy=false
            if not ok and not closed then note("Repeated UID sale stopped: "..tostring(err).." | No automatic retry") end
        end)
    end)
    local fieldPreview
    local previewField=button("Preview Random Field Egg Sale",UDim2.new(),UDim2.new(1,0,1,0),sellTestRow(36))
    local sellField=button("Test Sell Field Egg UID Once",UDim2.new(),UDim2.new(1,0,1,0),sellTestRow(36))
    local function fieldSaleRecords()
        local storage=game:GetService("ReplicatedStorage")
        local snapshot=require(storage.Client.EggState).ReadFieldEggs()
        local save=require(storage.Shared.Save).Get()
        assert(snapshot and type(snapshot.Records)=="table" and save and type(save.EggInventory)=="table","Field/inventory data unavailable")
        local eligible={}
        for _,egg in pairs(snapshot.Records) do
            if type(egg)=="table" and type(egg.Uid)=="string" and egg.State=="Slot"
                and (not tonumber(egg.CarrierUserId) or tonumber(egg.CarrierUserId)==0) and not save.EggInventory[egg.Uid] then
                eligible[#eligible+1]=egg
            end
        end
        return storage,save,eligible,snapshot.Records
    end
    connect(previewField.Activated,function()
        if busy then return end
        fieldPreview=nil
        local ok,err=pcall(function()
            idle()
            local _,_,pool=fieldSaleRecords()
            assert(#pool>0,"No uncarried field slot eggs available")
            fieldPreview=copySetting(pool[math.random(1,#pool)])
            local egg=fieldPreview
            note("Field sale preview: "..Rarity.Resolve(egg.AssetCategory).." | area="..tostring(egg.AreaId).." | UID="..egg.Uid.." | State=Slot | not in your egg inventory")
        end)
        if not ok then note("Field preview stopped: "..tostring(err)) end
    end)
    connect(sellField.Activated,function()
        if busy then return end
        if not fieldPreview then note("Preview Random Field Egg Sale first"); return end
        local selected=fieldPreview; fieldPreview=nil; busy=true
        task.spawn(function()
            local ok,err=pcall(function()
                idle()
                local storage,save,pool=fieldSaleRecords()
                local valid=false
                for _,egg in ipairs(pool) do if egg.Uid==selected.Uid and egg.AssetCategory==selected.AssetCategory and egg.AreaId==selected.AreaId then valid=true; break end end
                assert(valid,"Selected field egg changed, disappeared, or entered inventory; preview again")
                local moneyBefore=save.Money
                idle()
                note("Sending ONE SellSelection | Eggs={"..selected.Uid.."} | Assets={} | no pickup")
                require(storage.Shared.Remotes).PetSatchel.SellSelection:FireServer({Assets={},Eggs={selected.Uid}})
                task.wait(3)
                if closed then return end
                local _,current,_,records=fieldSaleRecords()
                local observed
                for _,egg in pairs(records) do if egg.Uid==selected.Uid then observed=egg; break end end
                local delta=type(moneyBefore)=="number" and type(current.Money)=="number" and current.Money-moneyBefore or nil
                note("Field egg after request: "..(observed and tostring(observed.State) or "not observed").." | in your inventory="..tostring(current.EggInventory[selected.Uid]~=nil).." | observed money change="..tostring(delta))
                note("No server return value (RemoteEvent). Despawns, pickups and other income can change these observations; they do not confirm a sale. No retry sent.")
            end)
            busy=false
            if not ok and not closed then note("Field sale test stopped: "..tostring(err).." | No automatic retry") end
        end)
    end)
    local copy=button("Copy Auto Sell Test Log",UDim2.new(),UDim2.new(1,0,1,0),sellTestRow(36))
    connect(copy.Activated,function() if type(setclipboard)=="function" then pcall(setclipboard,table.concat(lines,"\n")) end end)
end)() end

do
    local order=-420
    local function sellRow(height)
        local frame=row(debugPage,height)
        frame.LayoutOrder=order; order=order+1
        return frame
    end
    label("Auto Sell — Debug Inspection",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),sellRow(42)).TextSize=20
    label("Reads seller, selection, egg-sale, income, and backpack capacity rules. No sales or remote calls.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,120),true).TextSize=14
    local scan=button("Inspect Auto Sell Scripts",UDim2.new(),UDim2.new(1,0,1,0),sellRow(38))
    local stop=button("Stop Auto Sell Inspection",UDim2.new(),UDim2.new(1,0,1,0),sellRow(38))
    local save=button("Save Auto Sell Inspection",UDim2.new(),UDim2.new(1,0,1,0),sellRow(38))
    local copy=button("Copy Auto Sell Inspection",UDim2.new(),UDim2.new(1,0,1,0),sellRow(38))
    local status=label("Inspect Auto Sell Scripts, then save or copy the report. Needed to verify exact sale arguments and near-full capacity checks.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),sellRow(90),true)
    local generation,busy=0,false
    local worker,report=nil,""
    local function cancel()
        generation=generation+1; busy=false
        if worker then pcall(task.cancel,worker); worker=nil end
    end
    connect(scan.Activated,function()
        if busy then return end
        busy=true; generation=generation+1; local run=generation
        report="AcidHub Auto Sell Source Inspection\nUTC: "..os.date("!%Y-%m-%d %H:%M:%S").."\nPlace ID: "..game.PlaceId.."\nRead-only inspection. Recovered text is untrusted and was not executed. Decompiler output is not guaranteed accurate.\n"
        local storage=game:GetService("ReplicatedStorage")
        local targets={
            {player,{"PlayerScripts","Game","Npcs","AssetSellerNpc"}},
            {player,{"PlayerScripts","GUI","SellPrompt"}},
            {player,{"PlayerScripts","GUI","PetList"}},
            {storage,{"Shared","Util","AssetItems"}},
            {storage,{"Shared","Globals","Constants"}},
            {storage,{"Shared","Types","Eggs"}},
        }
        local seen={}
        for _,target in ipairs(targets) do seen[target[1]:GetFullName().."."..table.concat(target[2],".")]=true end
        for _,root in ipairs({storage,player}) do
            for _,object in ipairs(root:GetDescendants()) do
                if object:IsA("LocalScript") or object:IsA("ModuleScript") then
                    local name=object.Name:lower(); local path=object:GetFullName()
                    if (name:find("sell",1,true) or name:find("capacity",1,true) or name:find("inventorylimit",1,true))
                        and not path:find("Packages",1,true) and not seen[path] and #targets<25 then
                        seen[path]=true; targets[#targets+1]={object,{}}
                    end
                end
            end
        end
        report=report.."Executor capabilities: getconnections="..type(getconnections).." | firesignal="..type(firesignal).." | decompile="..type(decompile).."\n"
        task.spawn(function()
            for _,target in ipairs(targets) do
                if run~=generation then return end
                local object=target[1]
                local path=object:GetFullName()..(#target[2]>0 and ("."..table.concat(target[2],".")) or "")
                for _,name in ipairs(target[2]) do object=object and object:FindFirstChild(name) end
                report=report.."\nTARGET: "..path.."\n"
                if not object or not (object:IsA("LocalScript") or object:IsA("ModuleScript")) then
                    report=report.."Missing script at observed path.\n"
                else
                    status.Text="Inspecting "..object.Name.." (up to 20 seconds)..."
                    local finished,output=false,nil
                    worker=task.spawn(function()
                        local ok,source=pcall(function() return object.Source end)
                        if ok and type(source)=="string" and #source>0 then
                            output="METHOD: Source\n"..source
                        elseif type(decompile)=="function" then
                            local success,recovered=pcall(decompile,object)
                            output=success and type(recovered)=="string" and ("METHOD: decompile (verify before use)\n"..recovered) or ("Decompiler failed: "..tostring(recovered))
                        else output="Source unavailable; executor decompile function unavailable." end
                        finished=true
                    end)
                    local deadline=os.clock()+20
                    while not finished and run==generation and os.clock()<deadline do task.wait(0.1) end
                    if run~=generation then return end
                    if not finished then
                        if worker then pcall(task.cancel,worker) end
                        output="Inspection timed out after 20 seconds."
                    end
                    worker=nil
                    output=output or "No output"
                    report=report..output:sub(1,80000)..(#output>80000 and "\n[Truncated at 80000 characters]" or "").."\n"
                end
            end
            if run==generation then busy=false; status.Text="Inspection finished. Save or copy the report." end
        end)
    end)
    connect(stop.Activated,function() cancel(); report=report.."\nStopped by user; report may be partial.\n"; status.Text="Stopped. Partial report available." end)
    connect(copy.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        status.Text=ok and "Inspection copied." or "Clipboard unavailable. Save the report."
    end)
    connect(save.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        if type(writefile)~="function" then status.Text="File saving unavailable."; return end
        local filename="AcidHub_AutoSell_Source_"..os.time()..".txt"
        local ok,err=pcall(writefile,filename,report)
        status.Text=ok and ("Saved "..filename) or tostring(err)
    end)
    table.insert(cleanupActions,cancel)
end

do
    local order=-410
    local function capacityRow(height)
        local frame=row(debugPage,height)
        frame.LayoutOrder=order; order=order+1
        return frame
    end
    label("Auto Pen Capacity — Debug Inspection",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),capacityRow(42)).TextSize=20
    label("Reads egg placement and pet-pen capacity rules. No purchases, placement, or remote calls.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,120),true).TextSize=14
    local scan=button("Inspect Pen Capacity Scripts",UDim2.new(),UDim2.new(1,0,1,0),capacityRow(38))
    local stop=button("Stop Pen Capacity Inspection",UDim2.new(),UDim2.new(1,0,1,0),capacityRow(38))
    local save=button("Save Pen Capacity Inspection",UDim2.new(),UDim2.new(1,0,1,0),capacityRow(38))
    local copy=button("Copy Pen Capacity Inspection",UDim2.new(),UDim2.new(1,0,1,0),capacityRow(38))
    local status=label("Inspect Pen Capacity Scripts, then save or copy the report to verify the placed-egg limit.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),capacityRow(90),true)
    local generation,busy=0,false
    local worker,report=nil,""
    local function cancel()
        generation=generation+1; busy=false
        if worker then pcall(task.cancel,worker); worker=nil end
    end
    connect(scan.Activated,function()
        if busy then return end
        busy=true; generation=generation+1; local run=generation
        report="AcidHub Pen Capacity Source Inspection\nUTC: "..os.date("!%Y-%m-%d %H:%M:%S").."\nPlace ID: "..game.PlaceId.."\nRead-only inspection. Recovered text is untrusted and was not executed. Decompiler output is not guaranteed accurate.\n"
        local storage=game:GetService("ReplicatedStorage")
        local targets={
            {storage,{"Shared","Types","Eggs"}},
            {storage,{"Data","Bases"}},
            {storage,{"Client","EggState"}},
            {player,{"PlayerScripts","GUI","PetList","PetPenCapacityGuidanceController"}},
            {player,{"PlayerScripts","GUI","PetList"}},
        }
        report=report.."Executor capabilities: getconnections="..type(getconnections).." | firesignal="..type(firesignal).." | decompile="..type(decompile).."\n"
        task.spawn(function()
            for _,target in ipairs(targets) do
                if run~=generation then return end
                local object=target[1]
                local path=object:GetFullName()..(#target[2]>0 and ("."..table.concat(target[2],".")) or "")
                for _,name in ipairs(target[2]) do object=object and object:FindFirstChild(name) end
                report=report.."\nTARGET: "..path.."\n"
                if not object or not (object:IsA("LocalScript") or object:IsA("ModuleScript")) then
                    report=report.."Missing script at observed path.\n"
                else
                    status.Text="Inspecting "..object.Name.." (up to 20 seconds)..."
                    local finished,output=false,nil
                    worker=task.spawn(function()
                        local ok,source=pcall(function() return object.Source end)
                        if ok and type(source)=="string" and #source>0 then
                            output="METHOD: Source\n"..source
                        elseif type(decompile)=="function" then
                            local success,recovered=pcall(decompile,object)
                            output=success and type(recovered)=="string" and ("METHOD: decompile (verify before use)\n"..recovered) or ("Decompiler failed: "..tostring(recovered))
                        else output="Source unavailable; executor decompile function unavailable." end
                        finished=true
                    end)
                    local deadline=os.clock()+20
                    while not finished and run==generation and os.clock()<deadline do task.wait(0.1) end
                    if run~=generation then return end
                    if not finished then
                        if worker then pcall(task.cancel,worker) end
                        output="Inspection timed out after 20 seconds."
                    end
                    worker=nil
                    output=output or "No output"
                    report=report..output:sub(1,80000)..(#output>80000 and "\n[Truncated at 80000 characters]" or "").."\n"
                end
            end
            if run==generation then busy=false; status.Text="Inspection finished. Save or copy the report." end
        end)
    end)
    connect(stop.Activated,function() cancel(); report=report.."\nStopped by user; report may be partial.\n"; status.Text="Stopped. Partial report available." end)
    connect(copy.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        status.Text=ok and "Inspection copied." or "Clipboard unavailable. Save the report."
    end)
    connect(save.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        if type(writefile)~="function" then status.Text="File saving unavailable."; return end
        local filename="AcidHub_Pen_Capacity_Source_"..os.time()..".txt"
        local ok,err=pcall(writefile,filename,report)
        status.Text=ok and ("Saved "..filename) or tostring(err)
    end)
    table.insert(cleanupActions,cancel)
end

do
    local order=-350
    local function progressRow(height)
        local frame=row(debugPage,height)
        frame.LayoutOrder=order; order=order+1
        return frame
    end
    label("Auto Progress — Debug Inspection",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),progressRow(42)).TextSize=20
    label("Reads trail, base/treadmill upgrade, and reward controller sources. No purchases, upgrades, claims, or recovered code execution.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,120),true).TextSize=14
    local scan=button("Inspect Progress Scripts",UDim2.new(),UDim2.new(1,0,1,0),progressRow(38))
    local stop=button("Stop Progress Inspection",UDim2.new(),UDim2.new(1,0,1,0),progressRow(38))
    local save=button("Save Progress Inspection",UDim2.new(),UDim2.new(1,0,1,0),progressRow(38))
    local copy=button("Copy Progress Inspection",UDim2.new(),UDim2.new(1,0,1,0),progressRow(38))
    local status=label("Open the game’s trail shop, upgrade menus and index once, then Inspect Progress Scripts. Save or copy the finished report.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),progressRow(90),true)
    local generation,busy=0,false
    local worker,report=nil,""
    local function cancel()
        generation=generation+1; busy=false
        if worker then pcall(task.cancel,worker); worker=nil end
    end
    connect(scan.Activated,function()
        if busy then return end
        busy=true; generation=generation+1; local run=generation
        report="AcidHub Progress Source Inspection\nUTC: "..os.date("!%Y-%m-%d %H:%M:%S").."\nPlace ID: "..game.PlaceId.."\nRead-only inspection. Recovered text is untrusted and was not executed. Decompiler output is not guaranteed accurate.\n"
        local storage=game:GetService("ReplicatedStorage")
        local targets={
            {player,{"PlayerScripts","GUI","Shops","TrailShop"}},
            {player,{"PlayerScripts","GUI","PlotUpgradeController"}},
            {player,{"PlayerScripts","GUI","TreadmillUpgrade"}},
            {player,{"PlayerScripts","GUI","TreadmillUpgrade","Client"}},
            {player,{"PlayerScripts","GUI","Index"}},
            {player,{"PlayerScripts","GUI","Index","ClaimRewardPanel"}},
            {storage,{"Client","BaseUpgrade"}},
            {storage,{"Client","Types","OfflineAssets"}},
            {storage,{"Shared","Types","Index"}},
        }
        -- Discover additional relevant scripts by their actual live paths, without requiring them.
        local seen={}
        for _,target in ipairs(targets) do seen[target[1]:GetFullName().."."..table.concat(target[2],".")]=true end
        for _,root in ipairs({storage,player}) do
            for _,object in ipairs(root:GetDescendants()) do
                if object:IsA("LocalScript") or object:IsA("ModuleScript") then
                    local path=object:GetFullName()
                    local name=object.Name:lower()
                    local relevant=name:find("offline",1,true) or name:find("trail",1,true)
                        or name:find("treadmillupgrade",1,true) or name:find("baseupgrade",1,true)
                        or name:find("plotupgrade",1,true) or name:find("claimreward",1,true)
                    if relevant and not path:find("Packages",1,true) and not seen[path] and #targets<40 then
                        seen[path]=true; targets[#targets+1]={object,{}}
                    end
                end
            end
        end
        report=report.."Executor capabilities: getconnections="..type(getconnections).." | firesignal="..type(firesignal).." | decompile="..type(decompile).."\n"
        task.spawn(function()
            for _,target in ipairs(targets) do
                if run~=generation then return end
                local object=target[1]
                local path=object:GetFullName()..(#target[2]>0 and ("."..table.concat(target[2],".")) or "")
                for _,name in ipairs(target[2]) do object=object and object:FindFirstChild(name) end
                report=report.."\nTARGET: "..path.."\n"
                if not object or not (object:IsA("LocalScript") or object:IsA("ModuleScript")) then
                    report=report.."Missing script at observed path.\n"
                else
                    status.Text="Inspecting "..object.Name.." (up to 20 seconds)..."
                    local finished,output=false,nil
                    worker=task.spawn(function()
                        local ok,source=pcall(function() return object.Source end)
                        if ok and type(source)=="string" and #source>0 then
                            output="METHOD: Source\n"..source
                        elseif type(decompile)=="function" then
                            local success,recovered=pcall(decompile,object)
                            output=success and type(recovered)=="string" and ("METHOD: decompile (verify before use)\n"..recovered) or ("Decompiler failed: "..tostring(recovered))
                        else output="Source unavailable; executor decompile function unavailable." end
                        finished=true
                    end)
                    local deadline=os.clock()+20
                    while not finished and run==generation and os.clock()<deadline do task.wait(0.1) end
                    if run~=generation then return end
                    if not finished then
                        if worker then pcall(task.cancel,worker) end
                        output="Inspection timed out after 20 seconds."
                    end
                    worker=nil
                    output=output or "No output"
                    report=report..output:sub(1,80000)..(#output>80000 and "\n[Truncated at 80000 characters]" or "").."\n"
                end
            end
            if run==generation then busy=false; status.Text="Inspection finished. Save or copy the report." end
        end)
    end)
    connect(stop.Activated,function() cancel(); report=report.."\nStopped by user; report may be partial.\n"; status.Text="Stopped. Partial report available." end)
    connect(copy.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        status.Text=ok and "Inspection copied." or "Clipboard unavailable. Save the report."
    end)
    connect(save.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        if type(writefile)~="function" then status.Text="File saving unavailable."; return end
        local filename="AcidHub_Progress_Source_"..os.time()..".txt"
        local ok,err=pcall(writefile,filename,report)
        status.Text=ok and ("Saved "..filename) or tostring(err)
    end)
    table.insert(cleanupActions,cancel)
end

do
    local order=-250
    local function riftRow(height)
        local frame=row(debugPage,height)
        frame.LayoutOrder=order; order=order+1
        return frame
    end
    label("The Rift — Debug Inspection",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),riftRow(42)).TextSize=20
    label("Reads the Rift interface and controller source. No stealing, trade-in, reroll, or reward requests are sent. Normal Auto Steal filters are unchanged during inspection.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,120),true).TextSize=14
    local scan=button("Inspect Rift Scripts",UDim2.new(),UDim2.new(1,0,1,0),riftRow(38))
    local stop=button("Stop Rift Inspection",UDim2.new(),UDim2.new(1,0,1,0),riftRow(38))
    local save=button("Save Rift Inspection",UDim2.new(),UDim2.new(1,0,1,0),riftRow(38))
    local copy=button("Copy Rift Inspection",UDim2.new(),UDim2.new(1,0,1,0),riftRow(38))
    local status=label("Open the game’s Rift UI, then Read Rift Requirements. Inspect Rift Scripts to capture recipe, rotation and trade-in handling.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),riftRow(90),true)
    local generation,busy=0,false
    local worker,report=nil,""
    local function cancel()
        generation=generation+1; busy=false
        if worker then pcall(task.cancel,worker); worker=nil end
    end
    connect(scan.Activated,function()
        if busy then return end
        busy=true; generation=generation+1; local run=generation
        report="AcidHub Rift Source Inspection\nUTC: "..os.date("!%Y-%m-%d %H:%M:%S").."\nPlace ID: "..game.PlaceId.."\nRead-only inspection. Recovered text is untrusted and was not executed. Decompiler output is not guaranteed accurate.\n"
        local targets={
            {player,{"PlayerScripts","GUI","RiftTradeIn"}},
            {player,{"PlayerScripts","GUI","RiftTradeIn","RiftSequence"}},
            {player,{"PlayerScripts","Game","RiftMachine"}},
            {game:GetService("ReplicatedStorage"),{"Shared","Modules","RiftRecipes"}},
            {game:GetService("ReplicatedStorage"),{"Shared","Modules","RiftZoneLadder"}},
            {game:GetService("ReplicatedStorage"),{"Shared","Util","RiftEligibility"}},
            {game:GetService("ReplicatedStorage"),{"Shared","Types","Rift"}},
            {game:GetService("ReplicatedStorage"),{"Data","Rift"}},
        }
        report=report.."Executor capabilities: getconnections="..type(getconnections).." | firesignal="..type(firesignal).." | decompile="..type(decompile).."\n"
        task.spawn(function()
            for _,target in ipairs(targets) do
                if run~=generation then return end
                local object=target[1]
                local path=object:GetFullName().."."..table.concat(target[2],".")
                for _,name in ipairs(target[2]) do object=object and object:FindFirstChild(name) end
                report=report.."\nTARGET: "..path.."\n"
                if not object or not (object:IsA("LocalScript") or object:IsA("ModuleScript")) then
                    report=report.."Missing script at observed path.\n"
                else
                    status.Text="Inspecting "..object.Name.." (up to 20 seconds)..."
                    local finished,output=false,nil
                    worker=task.spawn(function()
                        local ok,source=pcall(function() return object.Source end)
                        if ok and type(source)=="string" and #source>0 then
                            output="METHOD: Source\n"..source
                        elseif type(decompile)=="function" then
                            local success,recovered=pcall(decompile,object)
                            output=success and type(recovered)=="string" and ("METHOD: decompile (verify before use)\n"..recovered) or ("Decompiler failed: "..tostring(recovered))
                        else output="Source unavailable; executor decompile function unavailable." end
                        finished=true
                    end)
                    local deadline=os.clock()+20
                    while not finished and run==generation and os.clock()<deadline do task.wait(0.1) end
                    if run~=generation then return end
                    if not finished then
                        if worker then pcall(task.cancel,worker) end
                        output="Inspection timed out after 20 seconds."
                    end
                    worker=nil
                    output=output or "No output"
                    report=report..output:sub(1,80000)..(#output>80000 and "\n[Truncated at 80000 characters]" or "").."\n"
                end
            end
            if run==generation then busy=false; status.Text="Inspection finished. Save or copy the report." end
        end)
    end)
    connect(stop.Activated,function() cancel(); report=report.."\nStopped by user; report may be partial.\n"; status.Text="Stopped. Partial report available." end)
    connect(copy.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        status.Text=ok and "Inspection copied." or "Clipboard unavailable. Save the report."
    end)
    connect(save.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        if type(writefile)~="function" then status.Text="File saving unavailable."; return end
        local filename="AcidHub_Rift_Source_"..os.time()..".txt"
        local ok,err=pcall(writefile,filename,report)
        status.Text=ok and ("Saved "..filename) or tostring(err)
    end)
    local read=button("Read Rift Requirements (UI)",UDim2.new(),UDim2.new(1,0,1,0),riftRow(38))
    connect(read.Activated,function()
        if busy then status.Text="Wait for the inspection to finish or stop it first."; return end
        local screen=player.PlayerGui:FindFirstChild("RiftTradeIn")
        if not screen then status.Text="Open the game's Rift UI first, then read again."; return end
        local main=screen:FindFirstChild("RiftTradeInMain")
        if not main or not main.Visible or (screen:IsA("ScreenGui") and not screen.Enabled) then status.Text="Open the game's Rift UI first to avoid reading stale hidden labels."; return end
        local lines={"AcidHub Rift UI Snapshot",os.date("!%Y-%m-%dT%H:%M:%SZ"),"Displayed UI text only; recipe and rotation fields await source verification."}
        for _,object in ipairs(main:GetDescendants()) do
            if (object:IsA("TextLabel") or object:IsA("TextButton")) and object.Text~="" then
                local visible=true; local node=object
                while node and node~=screen do if node:IsA("GuiObject") and not node.Visible then visible=false; break end; node=node.Parent end
                if visible then lines[#lines+1]=object:GetFullName().." = "..object.Text end
            end
        end
        report=table.concat(lines,"\n")
        status.Text="Rift UI read: "..tostring(#lines-3).." visible text fields. Copy Rift Inspection to share the current recipe and rotation display."
    end)
    table.insert(cleanupActions,cancel)
end

do
    local order=-220
    local function fuseRow(height)
        local frame=row(debugPage,height)
        frame.LayoutOrder=order; order=order+1
        return frame
    end
    label("Auto Fuse — Debug Inspection",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),fuseRow(42)).TextSize=20
    label("Reads the fuse controller, selection rules, and remote definitions. Does not load, eject, or fuse pets, and does not execute recovered code.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,120),true).TextSize=14
    local scan=button("Inspect Fuse Scripts",UDim2.new(),UDim2.new(1,0,1,0),fuseRow(38))
    local stop=button("Stop Fuse Inspection",UDim2.new(),UDim2.new(1,0,1,0),fuseRow(38))
    local save=button("Save Fuse Inspection",UDim2.new(),UDim2.new(1,0,1,0),fuseRow(38))
    local copy=button("Copy Fuse Inspection",UDim2.new(),UDim2.new(1,0,1,0),fuseRow(38))
    local status=label("Fuse remote names are known; arguments and sequence need verification. Inspect and send the report before the first fuse test.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),fuseRow(90),true)
    local generation,busy=0,false
    local worker,report=nil,""
    local function cancel()
        generation=generation+1; busy=false
        if worker then pcall(task.cancel,worker); worker=nil end
    end
    connect(scan.Activated,function()
        if busy then return end
        busy=true; generation=generation+1; local run=generation
        report="AcidHub Fuse Source Inspection\nUTC: "..os.date("!%Y-%m-%d %H:%M:%S").."\nPlace ID: "..game.PlaceId.."\nRead-only inspection. Recovered text is untrusted and was not executed. Decompiler output is not guaranteed accurate.\n"
        local targets={
            {player,{"PlayerScripts","GUI","FuseMachine"}},
            {player,{"PlayerScripts","Game","FuseMachine"}},
            {player,{"PlayerScripts","GUI","FuseMachine","FuseMachineBackpackSelection"}},
            {player,{"PlayerScripts","GUI","FuseMachine","FuseMachineProgressPresentation"}},
            {game:GetService("ReplicatedStorage"),{"Shared","Util","FuseKernel"}},
            {game:GetService("ReplicatedStorage"),{"Shared","Util","EggRecords"}},
            {game:GetService("ReplicatedStorage"),{"Shared","Util","AssetItems"}},
            {game:GetService("ReplicatedStorage"),{"Shared","Util","AssetEarnings"}},
            {game:GetService("ReplicatedStorage"),{"Data","Assets"}},
            {game:GetService("ReplicatedStorage"),{"Shared","Types","FuseMachine"}},
            {game:GetService("ReplicatedStorage"),{"Shared","Remotes"}},
        }
        report=report.."Executor capabilities: getconnections="..type(getconnections).." | firesignal="..type(firesignal).." | decompile="..type(decompile).."\n"
        task.spawn(function()
            for _,target in ipairs(targets) do
                if run~=generation then return end
                local object=target[1]
                local path=object:GetFullName().."."..table.concat(target[2],".")
                for _,name in ipairs(target[2]) do object=object and object:FindFirstChild(name) end
                report=report.."\nTARGET: "..path.."\n"
                if not object or not (object:IsA("LocalScript") or object:IsA("ModuleScript")) then
                    report=report.."Missing script at observed path.\n"
                else
                    status.Text="Inspecting "..object.Name.." (up to 20 seconds)..."
                    local finished,output=false,nil
                    worker=task.spawn(function()
                        local ok,source=pcall(function() return object.Source end)
                        if ok and type(source)=="string" and #source>0 then
                            output="METHOD: Source\n"..source
                        elseif type(decompile)=="function" then
                            local success,recovered=pcall(decompile,object)
                            output=success and type(recovered)=="string" and ("METHOD: decompile (verify before use)\n"..recovered) or ("Decompiler failed: "..tostring(recovered))
                        else output="Source unavailable; executor decompile function unavailable." end
                        finished=true
                    end)
                    local deadline=os.clock()+20
                    while not finished and run==generation and os.clock()<deadline do task.wait(0.1) end
                    if run~=generation then return end
                    if not finished then
                        if worker then pcall(task.cancel,worker) end
                        output="Inspection timed out after 20 seconds."
                    end
                    worker=nil
                    output=output or "No output"
                    report=report..output:sub(1,80000)..(#output>80000 and "\n[Truncated at 80000 characters]" or "").."\n"
                end
            end
            if run==generation then busy=false; status.Text="Inspection finished. Save or copy the report." end
        end)
    end)
    connect(stop.Activated,function() cancel(); report=report.."\nStopped by user; report may be partial.\n"; status.Text="Stopped. Partial report available." end)
    connect(copy.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        status.Text=ok and "Inspection copied." or "Clipboard unavailable. Save the report."
    end)
    connect(save.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        if type(writefile)~="function" then status.Text="File saving unavailable."; return end
        local filename="AcidHub_Fuse_Source_"..os.time()..".txt"
        local ok,err=pcall(writefile,filename,report)
        status.Text=ok and ("Saved "..filename) or tostring(err)
    end)
    table.insert(cleanupActions,cancel)
end

do
    label("Equip / Placement Source Inspection",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),row(debugPage,42)).TextSize=20
    label("Inspects PlacedEggRenderer and EggHatchAnimation to verify the BeginHatch/FinishHatch sequence. Tries Source, then executor decompile if available. Recovered code may be incomplete. No hatch requests or recovered code execution.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,120),true).TextSize=14
    local scan=button("Inspect Equip Best + Hatch Scripts",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local stop=button("Stop Script Inspection",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local save=button("Save Hatch Inspection",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local copy=button("Copy Equip + Placement Inspection",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local status=label("Ready. Inspects the backpack Equip Best controller and hatch scripts.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,90),true)
    local generation,busy=0,false
    local worker,report=nil,""
    local function cancel()
        generation=generation+1; busy=false
        if worker then pcall(task.cancel,worker); worker=nil end
    end
    connect(scan.Activated,function()
        if busy then return end
        busy=true; generation=generation+1; local run=generation
        report="AcidHub Equip + Placement Source Inspection\nUTC: "..os.date("!%Y-%m-%d %H:%M:%S").."\nPlace ID: "..game.PlaceId.."\nRead-only inspection. Recovered text is untrusted and was not executed. Decompiler output is not guaranteed accurate.\n"
        local targets={
            {player,{"PlayerScripts","GUI","BackpackController"}},
            {player,{"PlayerScripts","GUI","BackpackController","Main"}},
            {game:GetService("ReplicatedStorage"),{"Shared","Eggs","PlacedEggRenderer"}},
            {game:GetService("ReplicatedStorage"),{"Shared","Eggs","EggHatchAnimation"}},
        }
        report=report.."Executor capabilities: getconnections="..type(getconnections).." | firesignal="..type(firesignal).." | decompile="..type(decompile).."\n"
        task.spawn(function()
            for _,target in ipairs(targets) do
                if run~=generation then return end
                local object=target[1]
                local path=object:GetFullName().."."..table.concat(target[2],".")
                for _,name in ipairs(target[2]) do object=object and object:FindFirstChild(name) end
                report=report.."\nTARGET: "..path.."\n"
                if not object or not (object:IsA("LocalScript") or object:IsA("ModuleScript")) then
                    report=report.."Missing script at observed path.\n"
                else
                    status.Text="Inspecting "..object.Name.." (up to 20 seconds)..."
                    local finished,output=false,nil
                    worker=task.spawn(function()
                        local ok,source=pcall(function() return object.Source end)
                        if ok and type(source)=="string" and #source>0 then
                            output="METHOD: Source\n"..source
                        elseif type(decompile)=="function" then
                            local success,recovered=pcall(decompile,object)
                            output=success and type(recovered)=="string" and ("METHOD: decompile (verify before use)\n"..recovered) or ("Decompiler failed: "..tostring(recovered))
                        else output="Source unavailable; executor decompile function unavailable." end
                        finished=true
                    end)
                    local deadline=os.clock()+20
                    while not finished and run==generation and os.clock()<deadline do task.wait(0.1) end
                    if run~=generation then return end
                    if not finished then
                        if worker then pcall(task.cancel,worker) end
                        output="Inspection timed out after 20 seconds."
                    end
                    worker=nil
                    output=output or "No output"
                    report=report..output:sub(1,80000)..(#output>80000 and "\n[Truncated at 80000 characters]" or "").."\n"
                end
            end
            if run==generation then busy=false; status.Text="Inspection finished. Save or copy the report." end
        end)
    end)
    connect(stop.Activated,function() cancel(); report=report.."\nStopped by user; report may be partial.\n"; status.Text="Stopped. Partial report available." end)
    connect(copy.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        status.Text=ok and "Inspection copied." or "Clipboard unavailable. Save the report."
    end)
    connect(save.Activated,function()
        if report=="" then status.Text="Inspect scripts first."; return end
        if type(writefile)~="function" then status.Text="File saving unavailable."; return end
        local filename="AcidHub_Hatch_Source_"..os.time()..".txt"
        local ok,err=pcall(writefile,filename,report)
        status.Text=ok and ("Saved "..filename) or tostring(err)
    end)
    table.insert(cleanupActions,cancel)
end

do
    local check=button("Check Ready Eggs",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local copy=button("Copy Hatch Readiness",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local status=label("Read-only hatch readiness check. No eggs are hatched by this button.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,85),true)
    local report=""
    connect(check.Activated,function()
        local ok,result=pcall(function()
            local client=game:GetService("ReplicatedStorage"):FindFirstChild("Client")
            local module=client and client:FindFirstChild("EggState")
            assert(module,"EggState unavailable")
            local reader=require(module)
            local records=reader.ReadOwnerEggs(player.UserId)
            local ids={}; for uid in pairs(records) do table.insert(ids,uid) end; table.sort(ids)
            local ready,growing,unplaced=0,0,0
            local lines={"AcidHub Hatch Readiness", "UTC: "..os.date("!%Y-%m-%d %H:%M:%S"),"Uses EggState.IsReadyToHatch. No hatch requests sent."}
            for _,uid in ipairs(ids) do
                local record=records[uid]
                if record.Placement==nil then unplaced=unplaced+1
                elseif reader.IsReadyToHatch(uid) then
                    ready=ready+1; table.insert(lines,"READY | "..uid.." | "..tostring(record.AssetCategory))
                else growing=growing+1 end
            end
            table.insert(lines,string.format("Ready=%d | Growing=%d | Unplaced=%d",ready,growing,unplaced))
            return table.concat(lines,"\n")
        end)
        if ok then report=result; status.Text=result:match("[^\n]+$") else status.Text="Readiness check failed: "..tostring(result) end
    end)
    connect(copy.Activated,function()
        if report=="" then status.Text="Check Ready Eggs first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        status.Text=ok and "Hatch readiness copied." or "Clipboard unavailable."
    end)
end

local hatchAutomationOn,hatchOperationBusy=false,false
do
    label("Auto Hatch",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),row(debugPage,42)).TextSize=20
    local status=label("OFF. Hatches ready owned eggs one at a time.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,100),true)
    local active,working=false,false
    local equipEnabled,equipPending=false,false
    local lastEquip=-math.huge
    local function equipBest()
        -- Observed in BackpackController.Main: both remotes take no arguments.
        local remotes=require(game:GetService("ReplicatedStorage").Shared.Remotes)
        local haul=remotes and remotes.Haul
        if not haul or not haul.FetchWearBestStatus or not haul.WearBest then
            error("Game Equip Best interface unavailable (Haul.FetchWearBestStatus / WearBest).")
        end
        local needed,reason=haul.FetchWearBestStatus:InvokeServer()
        if closed or not equipEnabled then return "Cancelled" end
        if needed==false then return "Best pets already equipped; no equip request needed." end
        if needed~=true then error("Equip Best status unavailable: "..tostring(reason)) end
        lastEquip=os.clock()
        local accepted,message=haul.WearBest:InvokeServer()
        if accepted~=true then error("WearBest denied: "..tostring(message or accepted)) end
        return "Best pets equipped (server confirmed)."
    end
    local attempted,lines={}, {"AcidHub Auto Hatch Test"}
    local retryAfter={}
    local function note(message)
        reportTask("Auto Hatch",message)
        if #lines>=200 then table.remove(lines,2) end
        table.insert(lines,string.format("[%.2f] %s",os.clock(),message)); status.Text=message
    end
    switch(autoHatchPage,"Auto Hatch",false,function(value)
        if value and hatchOperationBusy then note("Wait for the current hatch test to finish."); return false end
        active=value
        hatchAutomationOn=value
        note(value and "Auto Hatch ON" or (working and "OFF; current hatch may finish, no next egg will start." or "Auto Hatch OFF"))
    end,"Hatches ready owned eggs sequentially without animations. Explicit rejections retry after 30 seconds; rejected completion retries only FinishHatch. Unknown outcomes are not automatically repeated. OFF stops new hatches; special upgrade results are not handled.")
    switch(autoHatchPage,"Auto Equip Best",false,function(value)
        equipEnabled=value
        if not value then equipPending=false end
        reportTask("Auto Equip Best",value and "Waiting for a successful Auto Hatch" or "OFF")
    end,"After a successful Auto Hatch, checks the game's Equip Best status and requests WearBest when needed. Checks and equip calls are at least five seconds apart; multiple hatches during the cooldown share one request.")
    task.spawn(function()
        while not closed do
            if equipEnabled and equipPending and not automationFlow.selling and os.clock()-lastEquip>=5 and not (settingsBindings["Auto Fuse"] and settingsBindings["Auto Fuse"].busy()) and not (automationFlow.rift and automationFlow.rift.holdEquip()) then
                equipPending=false
                lastEquip=os.clock()
                local ok,err=pcall(equipBest)
                if not closed then
                    local message=ok and tostring(err) or ("Equip Best failed: "..tostring(err))
                    reportTask("Auto Equip Best",message)
                end
            end
            task.wait(0.25)
        end
    end)
    local copy=button("Copy Auto Hatch Report",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    connect(copy.Activated,function()
        local ok=type(setclipboard)=="function" and pcall(setclipboard,table.concat(lines,"\n"))
        if not ok then status.Text="Clipboard unavailable." end
    end)
    task.spawn(function()
        while not closed do
            if active and not working and not hatchOperationBusy and not automationFlow.selling then
                working=true
                hatchOperationBusy=true
                local ok,err=pcall(function()
                    local storage=game:GetService("ReplicatedStorage")
                    local reader=require(storage.Client.EggState)
                    local ids={}
                    for uid,record in pairs(reader.ReadOwnerEggs(player.UserId)) do
                        local retryFinish=attempted[uid]=="finish"
                        if record.Placement~=nil and (not attempted[uid] or retryFinish) and os.clock()>=(retryAfter[uid] or 0)
                            and (retryFinish or reader.IsReadyToHatch(uid)) then table.insert(ids,uid) end
                    end
                    table.sort(ids)
                    if not active or closed then return end
                    if #ids==0 then status.Text="Waiting for ready eggs or rejection cooldowns; uncertain requests remain excluded."; return end
                    local uid=ids[1]
                    local retryFinish=attempted[uid]=="finish"
                    local record=reader.ReadOwnedEgg(player.UserId,uid)
                    if not record or record.Placement==nil or (not retryFinish and not reader.IsReadyToHatch(uid)) then return end
                    local character=player.Character
                    local humanoid=movementHumanoid(character)
                    if not humanoid or humanoid.Health<=0 then return end
                    attempted[uid]=true
                    retryAfter[uid]=nil
                    if not retryFinish then
                        note("Starting "..tostring(record.AssetCategory).." | UID="..uid)
                        local accepted,message,outcome=reader.BeginHatch(uid)
                        if closed then return end
                        note("BeginHatch returned "..tostring(accepted).." | "..tostring(message))
                        if accepted~=true then
                            if accepted==false then
                                attempted[uid]=nil; retryAfter[uid]=os.clock()+30
                                note("BeginHatch rejected; retry eligible in 30 seconds | UID="..uid)
                            end
                            return
                        end
                        local types=require(storage.Shared.Types.Eggs)
                        if outcome~=nil and outcome==types.HATCH_RESULT_MECHA_UPGRADED then
                            note("Special upgrade result skipped; normal hatch flow required for "..uid); return
                        end
                    else
                        note("Retrying FinishHatch only | UID="..uid)
                    end
                    local finished,reason,assetUid=reader.FinishHatch(uid)
                    if closed then return end
                    note("FinishHatch returned "..tostring(finished).." | asset UID="..tostring(assetUid).." | "..tostring(reason))
                    if finished~=true then
                        -- This wrapper message can follow a server success with a malformed
                        -- asset UID. It is an unknown outcome, not a safe rejection to retry.
                        if finished==false and reason~="Invalid granted asset UID" then
                            attempted[uid]="finish"; retryAfter[uid]=os.clock()+30
                            note("FinishHatch rejected; completion retry eligible in 30 seconds | UID="..uid)
                        end
                        return
                    end
                    if equipEnabled then equipPending=true end
                    local deadline=os.clock()+15
                    repeat
                        if closed then return end
                        if reader.ReadOwnedEgg(player.UserId,uid)==nil then
                            note("Hatch flow returned; egg UID removed from owned eggs: "..uid); return
                        end
                        task.wait(0.2)
                    until os.clock()>deadline
                    note("Hatch completion unconfirmed for "..uid.."; no retry this load.")
                end)
                working=false
                hatchOperationBusy=false
                if not ok and not closed then note("Hatch test error: "..tostring(err)) end
            end
            task.wait(2)
        end
    end)
    table.insert(cleanupActions,function() active=false; hatchAutomationOn=false; equipEnabled=false; equipPending=false end)
end

do
    local test=button("Test Hatch One Without Animation",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local copy=button("Copy Direct Hatch Report",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local status=label("Auto Hatch must be OFF. Tests BeginHatch then FinishHatch on one ready egg.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,95),true)
    local lines={"AcidHub Direct Hatch Test"}
    local function note(message)
        table.insert(lines,string.format("[%.2f] %s",os.clock(),message)); status.Text=message
    end
    connect(copy.Activated,function() if type(setclipboard)=="function" then pcall(setclipboard,table.concat(lines,"\n")) end end)
    connect(test.Activated,function()
        if hatchAutomationOn or hatchOperationBusy then note("Turn Auto Hatch OFF and wait for the current hatch to finish."); return end
        hatchOperationBusy=true
        lines={"AcidHub Direct Hatch Test", "One ready egg. No local hatch animation; no automatic retries."}
        task.spawn(function()
            local done=false
            task.delay(20,function() if not done and not closed then note("Request still pending; additional hatch tests remain blocked.") end end)
            local ok,err=pcall(function()
                local storage=game:GetService("ReplicatedStorage")
                local reader=require(storage.Client.EggState)
                local types=require(storage.Shared.Types.Eggs)
                local ids={}
                for uid,record in pairs(reader.ReadOwnerEggs(player.UserId)) do
                    if record.Placement~=nil and reader.IsReadyToHatch(uid) then table.insert(ids,uid) end
                end
                table.sort(ids)
                if #ids==0 then note("No ready owned eggs."); return end
                local uid=ids[1]
                if closed or not reader.IsReadyToHatch(uid) then return end
                note("BeginHatch UID="..uid)
                local accepted,message,outcome=reader.BeginHatch(uid)
                if closed then return end
                note("BeginHatch returned "..tostring(accepted).." | message="..tostring(message).." | result="..tostring(outcome))
                if accepted~=true then return end
                note("Immediately after BeginHatch: owned record present="..tostring(reader.ReadOwnedEgg(player.UserId,uid)~=nil).." (replication may lag)")
                if outcome==types.HATCH_RESULT_MECHA_UPGRADED and outcome~=nil then
                    note("Special Mecha-upgrade result. Direct completion not tested; resume through the normal hatch flow."); return
                end
                note("Calling FinishHatch without animation")
                local finished,reason,assetUid=reader.FinishHatch(uid)
                if closed then return end
                note("FinishHatch returned "..tostring(finished).." | message="..tostring(reason).." | granted asset UID="..tostring(assetUid))
                if finished~=true then note("Completion rejected; no retry sent."); return end
                local deadline=os.clock()+5
                repeat
                    if closed then return end
                    if reader.ReadOwnedEgg(player.UserId,uid)==nil then note("HATCH CONFIRMED | egg removed | granted asset UID="..tostring(assetUid)); return end
                    task.wait(0.1)
                until os.clock()>deadline
                note("Finish accepted; owned egg removal not yet observed. Do not retry this UID.")
            end)
            done=true; hatchOperationBusy=false
            if not ok and not closed then note("Direct hatch error: "..tostring(err).."; no automatic retry.") end
        end)
    end)
end

local placementTestPlot
-- Approximate the base district from the live plot floors and spawn/belt locations.
local function inBaseDistrict(position)
    local minX,maxX,minZ,maxZ=autoStealSafeZone.X,autoStealSafeZone.X,autoStealSafeZone.Z,autoStealSafeZone.Z
    local function include(p)
        minX=math.min(minX,p.X); maxX=math.max(maxX,p.X)
        minZ=math.min(minZ,p.Z); maxZ=math.max(maxZ,p.Z)
    end
    local plots=workspace:FindFirstChild("Plots")
    for _,plot in ipairs(plots and plots:GetChildren() or {}) do
        for _,name in ipairs({"SpawnPoint","TreadmillBottom"}) do
            local part=plot:FindFirstChild(name)
            if part and part:IsA("BasePart") then include(part.Position) end
        end
        local update=plot:FindFirstChild("ToUpdate")
        local area=update and update:FindFirstChild("PetArea")
        if area and area:IsA("BasePart") then
            for _,x in ipairs({-1,1}) do for _,z in ipairs({-1,1}) do
                include(area.CFrame:PointToWorldSpace(Vector3.new(x*area.Size.X/2,0,z*area.Size.Z/2)))
            end end
        end
    end
    return position.X>=minX-8 and position.X<=maxX+8 and position.Z>=minZ-8 and position.Z<=maxZ+8 and math.abs(position.Y-autoStealSafeZone.Y)<20
end
local function directBaseTravel(character,destination,keepGoing,note,belt)
    if baseTravelActive then return false,"Another base movement is active" end
    baseTravelActive=true
    local movedHumanoid,path,blockedConnection,computeJob
    local function clearPath()
        if blockedConnection then blockedConnection:Disconnect(); blockedConnection=nil end
        if computeJob then pcall(task.cancel,computeJob); computeJob=nil end
        if path then path:Destroy(); path=nil end
    end
    local function halt()
        if movedHumanoid and movedHumanoid.Parent==character then
            movedHumanoid:Move(Vector3.zero,false)
            local root=character:FindFirstChild("HumanoidRootPart")
            if root and not root.Anchored then
                local v=root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity=Vector3.new(0,v.Y,0)
            end
        end
    end
    local function live()
        if closed or not keepGoing() then return nil,nil,"Movement cancelled" end
        if player.Character~=character then return nil,nil,"Character changed" end
        local root=character:FindFirstChild("HumanoidRootPart")
        local humanoid=movementHumanoid(character)
        if not root or not humanoid or humanoid.Health<=0 then return nil,nil,"Character unavailable" end
        if movedHumanoid~=humanoid then movedHumanoid=humanoid; applyEffectiveSpeed(humanoid) end
        return root,humanoid
    end
    local function walk(point,seconds,from,isBlocked)
        local deadline=os.clock()+seconds
        local commanded,best,progressed=-math.huge,math.huge,os.clock()
        while os.clock()<deadline do
            local root,humanoid,why=live()
            if not root then return false,why,false end
            if root.Anchored then
                if belt and (root.Position-belt.Position).Magnitude<10 then return true,"Training anchor detected" end
                requestTreadmillExitJump(character,humanoid,true)
                return false,"Waiting for treadmill release",false
            end
            if isBlocked and isBlocked() then halt(); return false,"Path blocked ahead",true end
            local delta=point-root.Position
            local distance=Vector3.new(delta.X,0,delta.Z).Magnitude
            local reached=distance<=3 and math.abs(delta.Y)<6
            -- Crossing a waypoint between frames must not send a fast character backwards.
            if not reached and from and math.abs(delta.Y)<6 then
                local line=Vector3.new(point.X-from.X,0,point.Z-from.Z)
                local offset=Vector3.new(root.Position.X-from.X,0,root.Position.Z-from.Z)
                if line.Magnitude>0.01 then
                    local along=offset:Dot(line.Unit)
                    reached=along>=line.Magnitude and (offset-line.Unit*along).Magnitude<=4
                end
            end
            if reached then return true,"Waypoint reached" end
            if distance<best-0.5 then best=distance; progressed=os.clock() end
            if os.clock()-progressed>5 then halt(); return false,"No progress for 5 seconds",true end
            if os.clock()-commanded>=1 then humanoid:MoveTo(point); commanded=os.clock() end
            game:GetService("RunService").Heartbeat:Wait()
        end
        halt(); return false,"Route timed out",true
    end
    local function recoverRespawn()
        local root,humanoid,why=live()
        if not root then return false,why end
        local readOK,carrying=pcall(function()
            local reader=require(game:GetService("ReplicatedStorage").Client.EggState)
            local snapshot=reader.ReadFieldEggs()
            assert(type(snapshot)=="table" and type(snapshot.Records)=="table","Field snapshot unavailable")
            for _,egg in pairs(snapshot.Records) do
                assert(type(egg)=="table" and type(egg.State)=="string","Invalid field snapshot")
                if tonumber(egg.CarrierUserId)==player.UserId then return true end
            end
            return false
        end)
        if not readOK then return false,"Respawn withheld: cannot verify empty hands" end
        if carrying then return false,"Respawn withheld: carrying a field egg" end
        -- Recheck cancellation and character identity after the inventory read.
        root,humanoid,why=live()
        if not root then return false,why end
        if approachOverride.recoveryCharacter==character then return false,"Respawn already requested for this character; waiting" end
        halt()
        note("Five path recovery attempts failed; respawning with no carried field egg. Automation will resume with the assigned plot.")
        placementTestPlot=nil
        approachOverride.recoveryCharacter=character
        if character:GetAttribute("AcidHubNoSlow")==true then
            if approachOverride.resetOwner~=character or type(approachOverride.resetCharacter)~="function" then
                approachOverride.recoveryCharacter=nil
                return false,"No Slow reset handler unavailable; respawn withheld"
            end
            if not approachOverride.resetCharacter(character) then
                approachOverride.recoveryCharacter=nil
                return false,"No Slow reset handler declined"
            end
        else
            humanoid.Health=0
            humanoid:ChangeState(Enum.HumanoidStateType.Dead)
        end
        return false,"Recovery respawn requested; waiting for the new character"
    end
    local ok,result,reason=pcall(function()
        local root,humanoid,why=live()
        if not root then return false,why end
        note(string.format("Direct movement | current WalkSpeed %.1f | XYZ %s",humanoid.WalkSpeed,tostring(destination)))
        local reached,message,retry=walk(destination,60)
        if reached then return true,"Destination reached" end
        if not retry then return false,message end
        note("Direct route blocked; switching to pathfinding at normal movement speed")
        local failures=0
        local recoveryDeadline=os.clock()+240
        while failures<5 and os.clock()<recoveryDeadline do
            root,humanoid,why=live()
            if not root then return false,why end
            local remaining=destination-root.Position
            if Vector3.new(remaining.X,0,remaining.Z).Magnitude<=3 and math.abs(remaining.Y)<6 then return true,"Destination reached" end
            clearPath(); halt()
            -- Keep path requests short enough for distant zones and streaming.
            local goal=remaining.Magnitude>512 and root.Position+remaining.Unit*512 or destination
            path=game:GetService("PathfindingService"):CreatePath({
                AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=8,
            })
            local computed,computeOK,computeError=false,nil,nil
            local currentPath=path
            local origin=root.Position
            note("Computing recovery path | consecutive failures "..failures.."/5")
            computeJob=task.spawn(function()
                computeOK,computeError=pcall(function() currentPath:ComputeAsync(origin,goal) end)
                computed=true
            end)
            local computeDeadline=os.clock()+10
            while not computed and os.clock()<computeDeadline do
                if not live() then return false,"Movement cancelled or character changed" end
                task.wait(0.1)
            end
            local completedPath=false
            message=not computed and "Path computation timed out" or not computeOK and tostring(computeError) or "No path found"
            if computed and computeOK and path.Status==Enum.PathStatus.Success then
                local points=path:GetWaypoints()
                local index,blocked=1,false
                blockedConnection=path.Blocked:Connect(function(blockedIndex) if blockedIndex>=index then blocked=true end end)
                completedPath=#points>0
                for waypointIndex,waypoint in ipairs(points) do
                    index=waypointIndex
                    root,humanoid,why=live()
                    if not root then return false,why end
                    if waypoint.Action==Enum.PathWaypointAction.Jump then humanoid.Jump=true end
                    local point=waypoint.Position+Vector3.new(0,humanoid.HipHeight+root.Size.Y/2,0)
                    local from=waypointIndex>1 and points[waypointIndex-1].Position or nil
                    local walked,walkReason,walkRetry=walk(point,math.min(30,math.max(8,(root.Position-point).Magnitude/math.max(humanoid.WalkSpeed,1)+5)),from,function() return blocked end)
                    if not walked then
                        if not walkRetry then return false,walkReason end
                        completedPath=false; message=walkReason; break
                    end
                    if root.Anchored and belt and (root.Position-belt.Position).Magnitude<10 then return true,"Training anchor detected" end
                end
                if completedPath and (root.Position-origin).Magnitude<1 then completedPath=false; message="Path made no progress" end
            end
            clearPath()
            if completedPath then
                failures=0
                note("Recovery path segment reached; continuing toward destination")
            else
                failures=failures+1
                note("Path recovery failed "..failures.."/5: "..tostring(message))
                task.wait(0.5)
            end
        end
        if failures>=5 then return recoverRespawn() end
        return false,"Recovery travel timed out; retrying on the next automation pass"
    end)
    pcall(clearPath); pcall(halt)
    baseTravelActive=false
    if not ok then return false,tostring(result) end
    return result,reason
end
local function resolveOwnedPlot()
    local ok,resolved=pcall(function()
        local client=game:GetService("ReplicatedStorage"):FindFirstChild("Client")
        local module=client and client:FindFirstChild("PlotState")
        assert(module,"PlotState unavailable")
        return require(module).ResolvePlot()
    end)
    local plot=ok and resolved and resolved.PlotFolder
    if plot and plot.Parent then placementTestPlot=plot; return plot,resolved end
    placementTestPlot=nil
    return nil
end

task.spawn(function()
    while not closed do
        local plot=resolveOwnedPlot()
        plotInfo.Text=plot and ("Base plot: "..plot.Name) or "Base plot: waiting for ownership data"
        task.wait(2)
    end
end)
local function placementInventory()
    local records={}
    local client=game:GetService("ReplicatedStorage"):FindFirstChild("Client")
    local ok,err=pcall(function()
        local module=client and client:FindFirstChild("EggState")
        assert(module,"EggState missing")
        local groups=require(module).ReadOwnedEggs()
        for _,group in pairs(groups) do
            if type(group)=="table" and tonumber(group.OwnerUserId)==player.UserId then
                for uid,record in pairs(group.Records) do
                    if type(record)=="table" then records[tostring(uid)]={record=record,inventory=true} end
                end
            end
        end
    end)
    for _,container in ipairs({player.Character or false,player:FindFirstChild("Backpack") or false}) do
        if container then
            for _,tool in ipairs(container:GetChildren()) do
                local uid=tool:GetAttribute("UID")
                if tool:IsA("Tool") and tool:GetAttribute("ItemType")=="AssetEgg" and uid then
                    uid=tostring(uid); records[uid]=records[uid] or {}
                    records[uid].tool=tool
                end
            end
        end
    end
    return records,ok and "OK" or tostring(err)
end
do
    local scan=button("Scan Pen Geometry + Inventory",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local save=button("Save Pen Geometry + Inventory",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local status=label("Resolve Assigned Plot, then scan its current geometry.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,80),true)
    local report=""
    connect(scan.Activated,function()
        local plot=resolveOwnedPlot()
        if not plot or not plot.Parent then status.Text="Resolve Assigned Plot first."; return end
        local ok,result=pcall(function()
            local lines={"AcidHub Pen Geometry + Inventory", "Plot="..plot.Name.." | UserId="..player.UserId,"UTC="..os.date("!%Y-%m-%d %H:%M:%S")}
            local function attributes(object)
                local entries={}
                for key,value in pairs(object:GetAttributes()) do table.insert(entries,key.."="..tostring(value)) end
                table.sort(entries); return table.concat(entries,"; ")
            end
            table.insert(lines,"Plot attributes: "..attributes(plot))
            local pen=plot:FindFirstChild("StarterPen",true)
            assert(pen and pen:IsA("Model"),"StarterPen missing")
            local cf,size=pen:GetBoundingBox()
            table.insert(lines,"Pen bounding CFrame="..tostring(cf).." | Size="..tostring(size))
            table.insert(lines,"Bounding box includes decorations; it is not a verified placeable boundary.")
            local objects=plot:GetDescendants()
            local count=0
            for _,object in ipairs(objects) do
                if object:IsA("BasePart") then
                    count=count+1
                    if count>3000 then table.insert(lines,"GEOMETRY TRUNCATED at 3000 parts"); break end
                    table.insert(lines,object:GetFullName().." | Class="..object.ClassName.." | InStarterPen="..tostring(object:IsDescendantOf(pen)).." | CFrame="..tostring(object.CFrame).." | Size="..tostring(object.Size).." | Collide="..tostring(object.CanCollide).." | Query="..tostring(object.CanQuery).." | Transparency="..object.Transparency.." | Attributes="..attributes(object))
                end
            end
            local records,readerStatus=placementInventory()
            table.insert(lines,"INVENTORY | ReadOwnedEggs="..readerStatus)
            local ids={}; for uid in pairs(records) do table.insert(ids,uid) end; table.sort(ids)
            for _,uid in ipairs(ids) do
                local entry=records[uid]
                local fields={}
                for key,value in pairs(entry.record or {}) do
                    if type(value)~="table" then table.insert(fields,tostring(key).."="..tostring(value)) end
                end
                table.sort(fields)
                table.insert(lines,"UID="..uid.." | Inventory="..tostring(entry.inventory==true).." | Tool="..(entry.tool and entry.tool:GetFullName() or "not materialized").." | "..table.concat(fields,"; "))
            end
            return table.concat(lines,"\n")
        end)
        if ok then report=result; status.Text="Report ready. Save Pen Geometry + Inventory." else status.Text=tostring(result) end
    end)
    connect(save.Activated,function()
        if report=="" then status.Text="Scan first."; return end
        if type(writefile)~="function" then status.Text="File saving unavailable."; return end
        local filename="AcidHub_Pen_Inventory_"..os.time()..".txt"
        local ok,err=pcall(writefile,filename,report)
        status.Text=ok and ("Saved "..filename) or tostring(err)
    end)
end
do
    label("Auto Treadmill",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),row(debugPage,42)).TextSize=20
    label("Uses PlotState to resolve your assigned treadmill on each route. Movement priorities with other automations will be configured separately.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,110),true).TextSize=14
    local identify=button("Resolve Assigned Plot",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local go=button("Test Route To Treadmill",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local cancel=button("Stop Navigation Test",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local copy=button("Copy Navigation Report",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local status=label("OFF. Your assigned plot is resolved automatically when starting a route.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,110),true)
    local plot,active,token=nil,false,0
    local movingHumanoid,lines=nil,{}
    local automatic=false
    local function note(message)
        reportTask("Auto Treadmill",message)
        table.insert(lines,string.format("[%.2f] %s",os.clock(),message)); status.Text=message
    end
    local function stop(message)
        active=false; token=token+1
        if movingHumanoid then
            pcall(function()
                movingHumanoid:Move(Vector3.zero)
                local root=movingHumanoid.RootPart
                if root then movingHumanoid:MoveTo(root.Position) end
            end)
        end
        movingHumanoid=nil
        if message then note(message) end
    end
    connect(identify.Activated,function()
        if active then return end
        plot=resolveOwnedPlot()
        note(plot and ("Assigned Plot: "..plot.Name.." | ownership data") or "Waiting for plot ownership data.")
    end)
    local function runRoute()
        if active then return end
        if automationFlow.phase~="idle" or automationFlow.placing or automationFlow.collecting or automationFlow.selling or automationFlow.pendingDay then return end
        plot=resolveOwnedPlot()
        if not plot then note("Waiting for plot ownership data."); return end
        local character=player.Character
        local humanoid=movementHumanoid(character)
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local treadmill=plot:FindFirstChild("TreadmillBottom")
        if not humanoid or not root or not treadmill or not treadmill:IsA("BasePart") then note("Character or treadmill unavailable."); return end
        if root.Anchored then note("Character is anchored. Leave the current activity before testing."); return end
        active=true; token=token+1; local run=token; movingHumanoid=humanoid
        task.spawn(function()
            local ok,err=pcall(function()
                local function continueRoute()
                    return active and run==token and automationFlow.phase=="idle" and not automationFlow.pendingDay and not automationFlow.selling and not automationFlow.fusing and not (automationFlow.rift and automationFlow.rift.busy) and not automationFlow.collecting and not automationFlow.placing
                end
                if not inBaseDistrict(root.Position) then
                    note("Outside base district; returning through safe zone")
                    local reached,reason=directBaseTravel(character,autoStealSafeZone,continueRoute,note)
                    if not reached then stop(reason); return end
                end
                local currentPlot=resolveOwnedPlot()
                if currentPlot~=plot then stop("Assigned plot changed; route will be resolved again"); return end
                local destination=treadmill.Position+Vector3.new(0,humanoid.HipHeight+root.Size.Y/2,0)
                local reached,reason=directBaseTravel(character,destination,continueRoute,note,treadmill)
                if active and run==token then stop((reached and "Treadmill reached: " or "Navigation stopped: ")..tostring(reason)) end
            end)
            if not ok and active and run==token then stop("Navigation failed: "..tostring(err)) end
        end)
    end
    connect(go.Activated,runRoute)
    switch(autoTreadmillPage,"Auto Treadmill",false,function(value)
        automatic=value
        if not value then
            stop("Auto Treadmill OFF")
            local character=player.Character
            local root=character and character:FindFirstChild("HumanoidRootPart")
            local humanoid=movementHumanoid(character)
            local belt=plot and plot:FindFirstChild("TreadmillBottom")
            if root and humanoid and belt and root.Anchored and (root.Position-belt.Position).Magnitude<10 then requestTreadmillExitJump(character,humanoid,true) end
        end
    end,"Trains only while idle, after collection, Rift/Fuse, sequence sales and egg placement finish. Pending daytime collection or other sequence work interrupts treadmill travel.")
    automationFlow.stopTreadmill=function()
        stop("Treadmill paused for automation sequence")
        local character=player.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local humanoid=movementHumanoid(character)
        local belt=plot and plot:FindFirstChild("TreadmillBottom")
        if root and humanoid and belt and root.Anchored and (root.Position-belt.Position).Magnitude<10 then requestTreadmillExitJump(character,humanoid,true) end
    end
    task.spawn(function()
        while not closed do
            if automatic and not active and automationFlow.phase=="idle" and not automationFlow.pendingDay and not automationFlow.selling and not automationFlow.fusing and not (automationFlow.rift and automationFlow.rift.busy) and not automationFlow.placing and not automationFlow.collecting then
                local character=player.Character
                local root=character and character:FindFirstChild("HumanoidRootPart")
                local belt=plot and plot:FindFirstChild("TreadmillBottom")
                if root and root.Anchored and belt and (root.Position-belt.Position).Magnitude<10 then
                    status.Text="At assigned treadmill."; reportTask("Auto Treadmill","Running at assigned treadmill")
                else runRoute() end
            end
            task.wait(5)
        end
    end)
    connect(cancel.Activated,function() stop("Navigation stopped.") end)
    connect(copy.Activated,function()
        if type(setclipboard)=="function" then pcall(setclipboard,table.concat(lines,"\n")) end
    end)
    connect(player.CharacterRemoving,function() stop("Respawn: plot ownership will be resolved again."); plot=nil; placementTestPlot=nil end)
    table.insert(cleanupActions,function() automatic=false; stop(); plot=nil end)
end

-- One placement attempt per explicit test; success requires the exact owned UID.
do
    label("Auto Place Eggs",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),row(debugPage,42)).TextSize=20
    label("Resolves your assigned plot, moves directly through the safe zone when outside the base district, then reaches your pen center before equipping and placing an egg. Escape stops subsequent steps; a submitted request cannot be recalled.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,130),true).TextSize=14
    local test=button("Place One Egg",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local cancel=button("Stop Placement Test",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local copy=button("Copy Auto Placement Report",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local status=label("Ready. Returns through safe zone when needed, moves to pen center, then places eggs.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,110),true)
    local active,sequence=false,0
    local lines={}
    local requestPending=false
    local automatic=false
    local attemptedPlacement={}
    local placementRound=-1
    local function note(message) reportTask("Auto Place Eggs",message); if #lines>=150 then table.remove(lines,2) end; table.insert(lines,string.format("[%.2f] %s",os.clock(),message)); status.Text=message end
    local function finish(message)
        active=false; sequence=sequence+1
        if not requestPending then automationFlow.placing=false end
        if message then note(message) end
    end
    connect(cancel.Activated,function() finish("Stopped by user.") end)
    connect(Input.InputBegan,function(input) if active and input.KeyCode==Enum.KeyCode.Escape then finish("Cancelled with Escape.") end end)
    connect(copy.Activated,function() if type(setclipboard)=="function" then pcall(setclipboard,table.concat(lines,"\n")) end end)
    local function placeOne()
        if active or requestPending or automationFlow.selling then return end
        if automationFlow.steal and automationFlow.phase~="placing" then return end
        if placementRound~=automationFlow.placementRound then attemptedPlacement={}; placementRound=automationFlow.placementRound end
        local client=game:GetService("ReplicatedStorage"):FindFirstChild("Client")
        local loaded,eggState,plotState,resolved=pcall(function()
            local eggs=require(client:FindFirstChild("EggState"))
            local plots=require(client:FindFirstChild("PlotState"))
            return eggs,plots,plots.ResolvePlot()
        end)
        if not loaded or not resolved then note("Plot resolution unavailable: "..tostring(eggState)); return end
        if type(eggState.WearEggTool)~="function" or type(eggState.PlantEgg)~="function" then note("EggState wrappers unavailable."); return end
        local plot=resolved.PlotFolder
        local character=player.Character
        local humanoid=movementHumanoid(character)
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if not root or not humanoid then note("Wait for your character."); return end
        local eggs={}
        local inventory,readerStatus=placementInventory()
        if readerStatus~="OK" then note("Waiting for inventory reader: "..tostring(readerStatus)); return end
        local inventoryOnly=0
        local existingRenders=workspace:FindFirstChild("PlacedEggRenders")
        for uid,entry in pairs(inventory) do
            if entry.inventory and entry.record.Placement==nil and not attemptedPlacement[uid] and not (existingRenders and existingRenders:FindFirstChild(tostring(player.UserId).."_"..uid)) then
                entry.uid=uid; table.insert(eggs,entry)
                if not entry.tool then inventoryOnly=inventoryOnly+1 end
            end
        end
        local riftCategories={}
        local rift=automationFlow.rift
        if automatic and rift and rift.enabled and rift.placementPriority then
            local ok,ready=pcall(rift.refresh,false)
            if ok and ready and rift.state then
                for _,category in ipairs(rift.state.Requirements) do riftCategories[category]=true end
            end
        end
        table.sort(eggs,function(a,b)
            local riftA=riftCategories[a.record.AssetCategory]==true
            local riftB=riftCategories[b.record.AssetCategory]==true
            if riftA~=riftB then return riftA end
            local heldA=a.tool and a.tool.Parent==character or false
            local heldB=b.tool and b.tool.Parent==character or false
            if heldA~=heldB then return heldA end
            return a.uid<b.uid
        end)
        if #eggs==0 then
            status.Text="No remaining eligible unplaced eggs. Inventory reader="..readerStatus
            reportTask("Auto Place Eggs","No remaining unplaced eggs")
            if automationFlow.phase=="placing" then flowPhase("idle","Placement complete; waiting for next day") end
            return
        end
        local egg=eggs[1]
        local uid=egg.uid
        local renderName=tostring(player.UserId).."_"..uid
        local placed=workspace:FindFirstChild("PlacedEggRenders")
        if not placed or placed:FindFirstChild(renderName) then note("Placed render folder missing or selected egg already placed."); return end
        local pen=plot:FindFirstChild("StarterPen",true)
        if not pen or not pen:IsA("Model") then note("StarterPen model missing."); return end
        local petArea=resolved.PetArea
        if not petArea or not petArea:IsA("BasePart") then note("Live PetArea boundary missing. Scan geometry again."); return end
        lines={"AcidHub Auto Placement Wrapper Test | Plot "..plot.Name,"UID="..uid.." | Egg="..tostring(egg.record.AssetCategory).." | Unplaced eggs="..#eggs.." | Inventory-only records="..inventoryOnly.." | Inventory reader="..readerStatus}
        active=true; sequence=sequence+1; local run=sequence
        automationFlow.placing=true
        task.spawn(function()
            local ok,err=pcall(function()
                local function check()
                    if not active or sequence~=run then error("Cancelled") end
                    if automatic and automationFlow.phase~="placing" then error("Placement deferred for the next phase") end
                    humanoid=movementHumanoid(character)
                    if player.Character~=character or not root.Parent or not humanoid or humanoid.Health<=0 then error("Character unavailable") end
                end
                local function continuePlacement()
                    return active and sequence==run and (not automatic or automationFlow.phase=="placing")
                end
                if not inBaseDistrict(root.Position) then
                    note("Outside base district; returning through safe zone before placement")
                    local reached,reason=directBaseTravel(character,autoStealSafeZone,continuePlacement,note)
                    if not reached then error(reason) end
                end
                check()
                local center=petArea.Position+Vector3.new(0,humanoid.HipHeight+root.Size.Y/2,0)
                note("Moving to the center of your pen before placement")
                local reached,reason=directBaseTravel(character,center,continuePlacement,note)
                if not reached then error(reason) end
                check()
                local cf,size=petArea.CFrame,petArea.Size
                if math.abs(cf.UpVector.Y)<0.99 then error("PetArea is not horizontal") end
                if size.X<=0 or size.Z<=0 then error("PetArea has invalid dimensions") end
                local inset=math.min(2,math.min(size.X,size.Z)/4)
                note("Live PetArea Size="..tostring(size).." | edge inset="..inset.." | BaseUpgradeLevel="..tostring(plot:GetAttribute("BaseUpgradeLevel")))
                local occupied={}
                local ownerPrefix=tostring(player.UserId).."_"
                for _,object in ipairs(placed:GetChildren()) do
                    if object:IsA("Model") and object.Name:sub(1,#ownerPrefix)==ownerPrefix then
                        local position=object:GetPivot().Position
                        local localPosition=cf:PointToObjectSpace(position)
                        if math.abs(localPosition.X)<=size.X/2 and math.abs(localPosition.Z)<=size.Z/2 then table.insert(occupied,position) end
                    end
                end
                local halfX,halfZ=size.X/2-inset,size.Z/2-inset
                local stepsX=math.clamp(math.ceil(halfX*2/5.5),1,100)
                local stepsZ=math.clamp(math.ceil(halfZ*2/5.5),1,100)
                local target,bestGap=nil,-1
                -- Existing render pivots rank points only; they do not veto a request.
                -- The server decides whether the selected location is valid.
                for iz=0,stepsZ do
                    for ix=0,stepsX do
                        local candidate=cf:PointToWorldSpace(Vector3.new(-halfX+2*halfX*ix/stepsX,size.Y/2,-halfZ+2*halfZ*iz/stepsZ))
                        local gap=math.huge
                        for _,position in ipairs(occupied) do
                            local delta=position-candidate
                            gap=math.min(gap,Vector2.new(delta.X,delta.Z).Magnitude)
                        end
                        if gap>bestGap then target=candidate; bestGap=gap end
                    end
                end
                note("Grid candidate XYZ="..tostring(target).." | existing egg pivots="..#occupied.." | nearest pivot distance="..tostring(bestGap))
                local function callOnce(name,callback)
                    check(); note("Calling "..name)
                    local done,result=false,nil
                    requestPending=true
                    task.spawn(function()
                        result=table.pack(pcall(callback)); done=true; requestPending=false
                        if not active then automationFlow.placing=false end
                    end)
                    local deadline=os.clock()+10
                    while not done do
                        task.wait(0.1); check()
                        if os.clock()>deadline then error(name.." timed out; outcome unknown. No retry. Wait for pending request before another test.") end
                    end
                    check()
                    if not result[1] then error(name.." failed: "..tostring(result[2])) end
                    note(name.." returned "..tostring(result[2]).." | "..tostring(result[3]))
                    if result[2]~=true then
                        local reason=string.lower(tostring(result[3]))
                        if name=="PlantEgg" and (reason:find("full",1,true) or reason:find("maximum",1,true) or reason:find("capacity",1,true) or reason:find("limit",1,true) or reason:find("too many",1,true)) then
                            if automationFlow.phase=="placing" then flowPhase("idle","Server rejected placement: "..tostring(result[3])) end
                        end
                        error(name.." rejected: "..tostring(result[3]))
                    end
                end
                attemptedPlacement[uid]=true
                callOnce("WearEggTool",function() return eggState.WearEggTool(uid) end)
                local equipDeadline=os.clock()+3
                local held
                repeat
                    check()
                    for _,object in ipairs(character:GetChildren()) do
                        if object:IsA("Tool") and object:GetAttribute("UID")==uid and object:GetAttribute("ItemType")=="AssetEgg" then held=object; break end
                    end
                    if held then break end
                    task.wait(0.1)
                until os.clock()>equipDeadline
                if not held then error("Equip acknowledged but matching held egg was not observed.") end
                if automatic and automationFlow.phase~="placing" then error("New sequence phase; placement deferred") end
                local currentPlot=plotState.ResolvePlot()
                if not currentPlot or currentPlot.PlotFolder~=plot or currentPlot.PetArea~=petArea or petArea.CFrame~=cf or petArea.Size~=size then error("Plot changed; start a new test.") end
                local record=eggState.ReadOwnedEgg(player.UserId,uid)
                if not record or record.Placement~=nil then error("Egg is no longer unplaced.") end
                local relative=currentPlot.CenterPoint.CFrame:ToObjectSpace(CFrame.new(target))
                note("PlantEgg LocalCFrame="..tostring(relative))
                callOnce("PlantEgg",function() return eggState.PlantEgg(uid,relative) end)
                local untilTime=os.clock()+5
                repeat
                    check()
                    local result=placed:FindFirstChild(renderName)
                    if result then
                        finish("PLACED exact UID "..uid..(result:IsA("Model") and (" | actual XYZ="..tostring(result:GetPivot().Position)) or "")); return
                    end
                    task.wait(0.1)
                until os.clock()>untilTime
                error("PlantEgg accepted, but exact UID render was not observed within five seconds. No retry sent.")
            end)
            if not ok and active and sequence==run then finish("Test stopped: "..tostring(err)) end
        end)
    end
    connect(test.Activated,placeOne)
    switch(autoPlacePage,"Auto Place Eggs",false,function(value)
        automatic=value
        automationFlow.place=value
        if not value then
            finish("Auto Place OFF; submitted requests may still complete.")
            if automationFlow.phase=="placing" then flowPhase("idle","Auto Place disabled") end
        elseif not automationFlow.steal then
            if automationFlow.stopTreadmill then automationFlow.stopTreadmill() end
            flowPlace("Auto Place enabled")
        end
    end,"After collection, Rift/Fuse and sequence sales, places unplaced eggs including newly awarded eggs until none remain or the pen is full. Then yields to idle training until the next day.")
    task.spawn(function()
        while not closed do
            if automatic and not active and not requestPending and automationFlow.phase=="placing" and not automationFlow.collecting then placeOne() end
            task.wait(2)
        end
    end)
    connect(player.CharacterRemoving,function() finish("Character changed; placement test stopped.") end)
    table.insert(cleanupActions,function() automatic=false; automationFlow.place=false; finish() end)
end

-- Focused placement observation. Does not activate tools or send clicks.
do
    label("Placement Capture",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),row(debugPage,42)).TextSize=20
    label("Equip an egg, start capture, click inside your pen, then stop. Captures world clicks and your placed-egg renders for up to 90 seconds. Start near your spawn to identify a plot candidate.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,110),true).TextSize=14
    local startButton=button("Start Placement Capture",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local stopButton=button("Stop Placement Capture",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local saveButton=button("Save Placement Capture",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local copyButton=button("Copy Placement Capture",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local status=label("Ready. Equip the egg you want to place.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,80),true)
    local active,token,started=false,0,0
    local lines,report={},""
    local mouse=player:GetMouse()
    local function xyz(p) return string.format("%.2f, %.2f, %.2f",p.X,p.Y,p.Z) end
    local function note(message)
        if #lines>=400 then return end
        table.insert(lines,string.format("[%.3fs] %s",os.clock()-started,message))
    end
    local function renders()
        local result={}
        local folder=workspace:FindFirstChild("PlacedEggRenders")
        if folder then
            local prefix=tostring(player.UserId).."_"
            for _,object in ipairs(folder:GetChildren()) do
                if object.Name:sub(1,#prefix)==prefix then result[object]=object.Name end
            end
        end
        return result,folder~=nil
    end
    local function describe(object)
        local text=object:GetFullName()
        if object:IsA("Model") then text=text.." | pivot XYZ="..xyz(object:GetPivot().Position)
        elseif object:IsA("BasePart") then text=text.." | XYZ="..xyz(object.Position) end
        local attributes={}
        for key,value in pairs(object:GetAttributes()) do table.insert(attributes,key.."="..tostring(value)) end
        table.sort(attributes)
        return text.." | Attributes: "..table.concat(attributes,"; ")
    end
    local function stop(reason)
        if not active then return end
        note(reason or "Stopped by user")
        active=false; token=token+1
        report=table.concat(lines,"\n")
        status.Text="Capture ready. Save or copy Placement Capture."
    end
    connect(Input.InputBegan,function(input,processed)
        if not active or processed or input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
        note("World click | XYZ="..xyz(mouse.Hit.Position).." | Target="..(mouse.Target and mouse.Target:GetFullName() or "nil"))
    end)
    connect(startButton.Activated,function()
        if active then return end
        local character=player.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local tool=character and character:FindFirstChildOfClass("Tool")
        if not root or not tool then status.Text="Equip an egg before starting capture."; return end
        started=os.clock(); lines={"AcidHub Placement Capture", "Game ID: "..game.GameId.." | Place ID: "..game.PlaceId,
            "Read-only. Nearest plot is a candidate; load/capture at spawn for reliable matching.",
            "UTC: "..os.date("!%Y-%m-%d %H:%M:%S").." | User ID: "..player.UserId}
        report=""; active=true; token=token+1
        local captureToken=token
        note("Player XYZ="..xyz(root.Position))
        note("Equipped "..describe(tool))
        local expected={}
        local prefix=tostring(player.UserId).."_"
        for _,object in ipairs(tool:GetDescendants()) do
            if object.Name:sub(1,#prefix)==prefix then expected[object.Name]=true; note("Held render identity="..object.Name) end
        end
        local plots=workspace:FindFirstChild("Plots")
        local nearest,distance=nil,math.huge
        if plots then
            for _,plot in ipairs(plots:GetChildren()) do
                local spawn=plot:FindFirstChild("SpawnPoint")
                if spawn and spawn:IsA("BasePart") then
                    local delta=root.Position-spawn.Position
                    local horizontal=Vector2.new(delta.X,delta.Z).Magnitude
                    if horizontal<distance then nearest=plot; distance=horizontal end
                end
            end
        end
        if nearest then
            note("Nearest plot="..nearest.Name.." | horizontal spawn distance="..string.format("%.2f",distance).." | Spawn proximity match="..tostring(distance<=8))
            for _,name in ipairs({"SpawnPoint","TreadmillBottom","StarterPen"}) do
                local object=nearest:FindFirstChild(name,true)
                if object then note("Destination "..describe(object)) end
            end
        end
        local previous,available=renders()
        note("PlacedEggRenders present="..tostring(available))
        for object in pairs(previous) do note("Existing "..describe(object)) end
        status.Text="Recording. Place your egg, then Stop Placement Capture."
        task.spawn(function()
            local toolPresent=true
            while active and token==captureToken do
                local ok,err=pcall(function()
                    if player.Character~=character then stop("Character changed"); return end
                    local present=tool.Parent==character
                    if present~=toolPresent then note("Held tool in character="..tostring(present)); toolPresent=present end
                    local current=renders()
                    for object,name in pairs(current) do
                        if not previous[object] then
                            note("ADDED "..describe(object).." | Matches held render identity="..tostring(expected[name]==true))
                        end
                    end
                    for object,name in pairs(previous) do if not current[object] then note("REMOVED placed render="..name) end end
                    previous=current
                    if os.clock()-started>=90 then stop("90 second capture limit") end
                end)
                if not ok then stop("Capture error: "..tostring(err)) end
                task.wait(0.2)
            end
        end)
    end)
    connect(stopButton.Activated,function() stop() end)
    connect(copyButton.Activated,function()
        if active then status.Text="Stop capture before copying."; return end
        if report=="" then status.Text="Capture a placement first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        status.Text=ok and "Placement capture copied." or "Clipboard unavailable. Save the report."
    end)
    connect(saveButton.Activated,function()
        if active then status.Text="Stop capture before saving."; return end
        if report=="" then status.Text="Capture a placement first."; return end
        if type(writefile)~="function" then status.Text="File saving unavailable."; return end
        local filename="AcidHub_Placement_"..os.time()..".txt"
        local ok,err=pcall(writefile,filename,report)
        status.Text=ok and ("Saved "..filename) or tostring(err)
    end)
    table.insert(cleanupActions,function() active=false; token=token+1 end)
end

-- Destination discovery is separate from route planning: names are candidates,
-- and ownership must be established before using a base or treadmill.
do
    label("World Map Discovery",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),row(debugPage,42)).TextSize=20
    label("Scan near your base and treadmill. Records loaded map objects, interactions, positions and ownership evidence. Streaming can hide distant locations; repeat in other areas. No movement or interaction is sent.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,110),true).TextSize=14
    local scanButton=button("Scan World Map",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local copyButton=button("Copy World Map",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local saveButton=button("Save World Map",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local status=label("Ready to discover base, treadmill and placement candidates.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,70),true)
    local reportBox=make("TextBox",{Text="",MultiLine=true,TextEditable=false,ClearTextOnFocus=false,
        TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
        BackgroundTransparency=1,TextColor3=colors.text,TextSize=14,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),
        Position=UDim2.fromOffset(10,6),Size=UDim2.new(1,-20,1,-12)},row(debugPage,260))
    local report,busy,cancelled="",false,false
    local function xyz(position)
        return string.format("%.2f, %.2f, %.2f",position.X,position.Y,position.Z)
    end
    local function positionOf(object)
        if object:IsA("Attachment") then return object.WorldPosition end
        if object:IsA("BasePart") then return object.Position end
        if object:IsA("Model") then return object:GetPivot().Position end
        if object.Parent and object.Parent~=workspace then return positionOf(object.Parent) end
    end
    local function relevant(name)
        name=string.lower(name)
        for _,word in ipairs({"base","plot","spawn","treadmill","train","placement","placeegg","pen","incubat","hatch","grow","owner"}) do
            if string.find(name,word,1,true) then return true end
        end
        return false
    end
    connect(scanButton.Activated,function()
        if busy then return end
        busy=true; status.Text="Scanning loaded map..."
        task.spawn(function()
            local ok,result=pcall(function()
                local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                local origin=root and root.Position
                local lines={"AcidHub World Map Discovery", "Game ID: "..game.GameId.." | Place ID: "..game.PlaceId,
                    "Captured UTC: "..os.date("!%Y-%m-%d %H:%M:%S"),"Local user ID: "..player.UserId,
                    "Player XYZ: "..(origin and xyz(origin) or "unavailable"),
                    "StreamingEnabled: "..tostring(workspace.StreamingEnabled),
                    "Read-only loaded-world candidates. Names/nearest distance do not prove ownership. No routes computed.",
                    "Model pivots are not verified walkable interaction points.",""}
                local objects=workspace:GetDescendants()
                local count,visited=0,0
                for index,object in ipairs(objects) do
                    if cancelled then return nil end
                    if index>100000 or count>=1000 then break end
                    visited=index
                    local interaction=object:IsA("ProximityPrompt") or object:IsA("ClickDetector") or object:IsA("Seat") or object:IsA("SpawnLocation")
                    local named=relevant(object.Name) and (object:IsA("Model") or object:IsA("Folder") or object:IsA("BasePart") or object:IsA("ValueBase"))
                    if object.Parent and (interaction or named) and not (player.Character and object:IsDescendantOf(player.Character)) then
                        count=count+1
                        local position=positionOf(object)
                        table.insert(lines,string.format("[%d] %s | %s",count,object.ClassName,object:GetFullName()))
                        if position then table.insert(lines,"XYZ: "..xyz(position)..(origin and string.format(" | distance %.1f",(position-origin).Magnitude) or "")) end
                        if object:IsA("ProximityPrompt") then
                            table.insert(lines,string.format("Prompt: Action=%s | Object=%s | Enabled=%s | Range=%.1f | Hold=%.2f",object.ActionText,object.ObjectText,tostring(object.Enabled),object.MaxActivationDistance,object.HoldDuration))
                        end
                        if object:IsA("BasePart") then table.insert(lines,"Size: "..xyz(object.Size).." | CanCollide="..tostring(object.CanCollide).." | CanTouch="..tostring(object.CanTouch)) end
                        if object:IsA("ValueBase") then pcall(function() table.insert(lines,"Value: "..tostring(object.Value)) end) end
                        local ancestor=object
                        for _=1,6 do
                            if not ancestor or ancestor==workspace then break end
                            local evidence={}
                            for key,value in pairs(ancestor:GetAttributes()) do table.insert(evidence,key.."="..tostring(value)) end
                            for _,child in ipairs(ancestor:GetChildren()) do
                                if child:IsA("ValueBase") and (relevant(child.Name) or string.find(string.lower(child.Name),"userid",1,true)) then
                                    pcall(function() table.insert(evidence,child.Name.."="..tostring(child.Value)) end)
                                end
                            end
                            table.sort(evidence)
                            if #evidence>0 then table.insert(lines,"Evidence "..ancestor:GetFullName()..": "..table.concat(evidence," | ")) end
                            ancestor=ancestor.Parent
                        end
                        table.insert(lines,"")
                    end
                    if index%250==0 then task.wait() end
                end
                table.insert(lines,string.format("Loaded objects: %d | Inspected: %d | Candidates: %d | Limited: %s",#objects,visited,count,tostring(visited<#objects)))
                return table.concat(lines,"\n")
            end)
            busy=false
            if cancelled then return end
            if ok and result then report=result; reportBox.Text=report; status.Text="Scan ready. Copy or save World Map for destination matching."
            else status.Text="Scan failed: "..tostring(result) end
        end)
    end)
    connect(copyButton.Activated,function()
        if report=="" then status.Text="Scan World Map first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        status.Text=ok and "World map copied." or "Clipboard unavailable. Use Save World Map."
    end)
    connect(saveButton.Activated,function()
        if report=="" then status.Text="Scan World Map first."; return end
        if type(writefile)~="function" then status.Text="File saving unavailable."; return end
        local filename="AcidHub_World_Map_"..os.time()..".txt"
        local ok,err=pcall(writefile,filename,report)
        status.Text=ok and ("Saved "..filename) or tostring(err)
    end)
    table.insert(cleanupActions,function() cancelled=true end)
end

-- Read-only diagnostics. Capture starts a bounded event trace; Compare stops it.
do
    label("Treadmill Exit Capture",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),row(debugPage,38)).TextSize=20
    local startButton=button("Start Treadmill Capture",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    label("Start while running on the treadmill. Press Space, wait 2 seconds, then stop and copy. Compare a fresh normal character with No Slow. Read-only; no exit requests are sent by this capture.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,110),true)
    local stopButton=button("Stop Treadmill Capture",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local copyButton=button("Copy Treadmill Capture",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local saveButton=button("Save Treadmill Capture",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local status=label("Ready. Capture a normal exit first, then a No Slow exit.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,80),true)
    local active=false
    local started,token=0,0
    local lines,watches,last={}, {}, {}
    local function log(message)
        if #lines<500 then table.insert(lines,string.format("[%.3fs] %s",os.clock()-started,message)) end
    end
    local function stop(reason)
        if not active then return end
        log(reason or "Stopped by user")
        active=false; token=token+1
        for _,connection in ipairs(watches) do connection:Disconnect() end
        watches={}
        status.Text="Treadmill report ready: "..#lines.." lines. Copy or save it."
    end
    local function watch(signal,callback) table.insert(watches,signal:Connect(callback)) end
    local function attributes(object,name)
        for key,value in pairs(object:GetAttributes()) do log(name.." attribute "..key.."="..tostring(value)) end
        watch(object.AttributeChanged,function(key) log(name.." attribute "..key.."="..tostring(object:GetAttribute(key))) end)
    end
    connect(startButton.Activated,function()
        stop("New capture")
        local character=player.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local humanoid=movementHumanoid(character)
        if not root or not humanoid then status.Text="Wait for your character."; return end
        active=true; token=token+1; local run=token; started=os.clock(); last={}
        lines={"AcidHub Treadmill Exit Capture | Place ID: "..game.PlaceId,
            "Read-only. No remote calls or forced exit. UTC: "..os.date("!%Y-%m-%d %H:%M:%S"),
            "No Slow="..tostring(character:GetAttribute("AcidHubNoSlow")==true)}
        attributes(player,"Player"); attributes(character,"Character")
        local tracked={humanoid}
        local storage=player:FindFirstChild("AcidHubRespawnStorage")
        local original=storage and storage:FindFirstChildOfClass("Humanoid")
        if original and original~=humanoid then table.insert(tracked,original) end
        for _,human in ipairs(tracked) do
            local name=human==humanoid and "Active Humanoid" or "Original Humanoid"
            log(name.."="..human:GetFullName()); attributes(human,name)
            watch(human.StateChanged,function(before,after) log(name.." state "..before.Name.." -> "..after.Name) end)
            for _,property in ipairs({"Jump","Sit","PlatformStand","WalkSpeed","EvaluateStateMachine","Health"}) do
                log(name.." "..property.."="..tostring(human[property]))
                watch(human:GetPropertyChangedSignal(property),function() log(name.." "..property.."="..tostring(human[property])) end)
            end
        end
        watch(root:GetPropertyChangedSignal("Anchored"),function() log("Root Anchored="..tostring(root.Anchored)) end)
        watch(Input.JumpRequest,function() log("INPUT JumpRequest") end)
        watch(Input.InputBegan,function(input,processed) if input.KeyCode==Enum.KeyCode.Space then log("INPUT Space | processed="..tostring(processed)) end end)
        watch(player.CharacterRemoving,function(leaving) if leaving==character then stop("Character removed") end end)
        local plot=resolveOwnedPlot()
        log("Assigned plot="..(plot and plot.Name or "unresolved"))
        local belt=plot and plot:FindFirstChild("TreadmillBottom")
        if belt then log("Belt="..belt:GetFullName().." | XYZ="..tostring(belt.Position)); attributes(belt,"Belt") end
        local client=game:GetService("ReplicatedStorage"):FindFirstChild("Client")
        for _,object in ipairs(client and client:GetDescendants() or {}) do
            local name=object.Name:lower()
            if name:find("treadmill",1,true) or name:find("training",1,true) then log("Client candidate="..object:GetFullName().." ["..object.ClassName.."]") end
        end
        status.Text="Recording: press Space, wait 2 seconds, then Stop Treadmill Capture."
        task.spawn(function()
            while active and token==run do
                if not root.Parent then stop("Root removed"); return end
                local v=root.AssemblyLinearVelocity
                local sample=string.format("Root anchored=%s | XYZ=%.1f,%.1f,%.1f | velocity=%.1f,%.1f,%.1f | Floor=%s | State=%s",
                    tostring(root.Anchored),root.Position.X,root.Position.Y,root.Position.Z,v.X,v.Y,v.Z,humanoid.FloorMaterial.Name,humanoid:GetState().Name)
                if last.root~=sample then last.root=sample; log(sample) end
                if #lines>=499 then stop("500 line limit"); return end
                if os.clock()-started>=60 then stop("60 second limit"); return end
                task.wait(0.2)
            end
        end)
    end)
    connect(stopButton.Activated,function() stop() end)
    connect(copyButton.Activated,function()
        if active then stop("Stopped for copy") end
        if #lines==0 then status.Text="Capture first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,table.concat(lines,"\n"))
        status.Text=ok and "Treadmill report copied." or "Clipboard unavailable. Save the report instead."
    end)
    connect(saveButton.Activated,function()
        if active then stop("Stopped for save") end
        if #lines==0 then status.Text="Capture first."; return end
        local name="AcidHub_Treadmill_Exit_"..os.time()..".txt"
        local ok=type(writefile)=="function" and pcall(writefile,name,table.concat(lines,"\n"))
        status.Text=ok and ("Saved "..name) or "File saving unavailable."
    end)
    table.insert(cleanupActions,function() stop("UI closed") end)
end

-- Manual duplicate-UID fuse experiment, isolated from Auto Fuse.
do
(function()
    local selected,busy=nil,false
    local function testRow(height) local frame=row(debugPage,height); frame.LayoutOrder=-310; return frame end
    label("Fuse — Repeated UID Test",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),testRow(38)).TextSize=20
    local report=make("TextBox",{Text="Select a Legendary pet, then test the same UID in all three slots. Accepted fusion may consume the pet and charge currency.",MultiLine=true,TextEditable=false,ClearTextOnFocus=false,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,BackgroundTransparency=1,TextColor3=colors.text,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextSize=14,Size=UDim2.new(1,-20,1,-10),Position=UDim2.fromOffset(10,5)},testRow(180))
    local choose=button("Choose Random Legendary Pet",UDim2.new(),UDim2.new(1,0,1,0),testRow(38))
    local run=button("Test Fuse Same UID x3",UDim2.new(),UDim2.new(1,0,1,0),testRow(38))
    local function note(message) report.Text=report.Text.."\n"..os.date("%H:%M:%S").." | "..message end
    local function idle()
        assert(not closed,"Hub closed")
        for _,key in ipairs({"AutoStealEnabled","Auto Place Eggs","Auto Treadmill","Auto Hatch","Auto Equip Best","Auto Fuse","Steal Rift Pets","Auto Buy Trail","Auto Upgrade Base","Auto Upgrade Treadmill","Auto Claim","Auto Sell Pets","Auto Sell Eggs"}) do
            assert(not settingsBindings[key] or not settingsBindings[key].get(),"Turn automations OFF first")
        end
        assert(not automationFlow.fusing and not automationFlow.selling and not (automationFlow.rift and automationFlow.rift.busy),"Wait for active work to finish")
    end
    local function read()
        local storage=game:GetService("ReplicatedStorage")
        local save=require(storage.Shared.Save).Get()
        assert(save and type(save.Inventory)=="table" and type(save.FusionSlots)=="table","Inventory unavailable")
        assert(not save.FusionLocked and save.FusionEggReward==false,"Finish the pending fuse first")
        return storage,save
    end
    connect(choose.Activated,function()
        if busy then return end
        selected=nil; report.Text="AcidHub Repeated UID Fuse Test"
        local ok,err=pcall(function()
            idle()
            local storage,save=read()
            local kernel=require(storage.Shared.Util.FuseKernel)
            local pool={}
            for uid,item in pairs(save.Inventory) do
                if type(item)=="table" and automationFlow.audit.rarity(item.Category)=="Legendary" then
                    local valid,allowed=pcall(kernel.MayEnterFuse,uid,item,nil,false)
                    if valid and allowed and not table.find(save.EquippedAssets or {},uid) then pool[#pool+1]={uid=uid,item=copySetting(item)} end
                end
            end
            assert(#pool>0,"No eligible unequipped Legendary pets")
            selected=pool[math.random(1,#pool)]
            note(Rarity.Resolve(selected.item.Category).." | Legendary | UID "..selected.uid)
            note("Test will attempt this UID three times. May consume the pet if accepted.")
        end)
        if not ok then note(tostring(err)) end
    end)
    connect(run.Activated,function()
        if busy then return end
        if not selected then note("Choose a pet first"); return end
        local target=selected; selected=nil; busy=true
        task.spawn(function()
            local ok,err=pcall(function()
                idle()
                local storage,save=read()
                for _,uid in pairs(save.FusionSlots) do assert(not uid or uid=="","Empty all fuse slots first") end
                local item=save.Inventory[target.uid]
                assert(item and item.Category==target.item.Category and automationFlow.audit.rarity(item.Category)=="Legendary","Selected pet changed or disappeared")
                assert(require(storage.Shared.Util.FuseKernel).MayEnterFuse(target.uid,item,nil,false),"Selected pet is no longer eligible")
                assert(not table.find(save.EquippedAssets or {},target.uid),"Selected pet is equipped")
                local remotes=require(storage.Shared.Remotes).Fusery
                for slot=1,3 do
                    idle()
                    local _,current=read()
                    for _,uid in pairs(current.FusionSlots) do assert(not uid or uid=="" or uid==target.uid,"Another pet entered the machine; stopping") end
                    note("LoadPet "..slot.."/3 | UID "..target.uid)
                    local accepted,message=remotes.LoadPet:InvokeServer(target.uid)
                    note("LoadPet returned "..tostring(accepted).." | "..tostring(message))
                    if accepted~=true then note("Stopped. No BeginFuse sent; inspect/eject any loaded pet in the game."); return end
                end
                idle()
                local _,current=read()
                for i=1,3 do assert(current.FusionSlots[i]==target.uid,"Three repeated slots not confirmed; no BeginFuse sent") end
                note("Calling BeginFuse once")
                local accepted,message=remotes.BeginFuse:InvokeServer()
                note("BeginFuse returned "..tostring(accepted).." | "..tostring(message))
                if accepted==true then
                    local finished,reason=remotes.FinishReveal:InvokeServer()
                    note("FinishReveal returned "..tostring(finished).." | "..tostring(reason))
                end
            end)
            busy=false
            if not ok and not closed then note("Stopped: "..tostring(err).." | No automatic retry; inspect machine slots.") end
        end)
    end)
end)()
end

-- Read-only network endpoint observation. ConnectionAccepted is not replayed for late listeners.
do
    local frame=row(debugPage,94)
    frame.LayoutOrder=-320
    label("Server IP / Port",UDim2.fromOffset(10,3),UDim2.new(1,-20,0,24),frame).TextSize=20
    local endpoint=make("TextBox",{Text="Not captured — AcidHub may have loaded after connection.",TextEditable=false,ClearTextOnFocus=false,MultiLine=true,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,BackgroundTransparency=1,TextColor3=colors.text,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextSize=14,Position=UDim2.fromOffset(10,30),Size=UDim2.new(1,-20,0,58)},frame)
    local ok,err=pcall(function()
        local client=game:GetService("NetworkClient")
        connect(client.ConnectionAccepted,function(peer)
            if closed then return end
            endpoint.Text="Server endpoint: "..tostring(peer).."\nSource: NetworkClient.ConnectionAccepted"
        end)
        connect(player.OnTeleport,function(state)
            if state==Enum.TeleportState.InProgress and not closed then endpoint.Text="Changing server — endpoint not captured yet." end
        end)
    end)
    if not ok then endpoint.Text="Endpoint observation unavailable: "..tostring(err) end
end

-- General snapshot comparison.
do
    local captureButton=button("Capture Baseline",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    label("Capture before a test, trigger the effect, then Compare Now. Events preserve brief state changes even if the effect ends first.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(debugPage,100),true).TextSize=14
    local compareButton=button("Compare Now",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local copyButton=button("Copy Report",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local saveButton=button("Save Report",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local clearButton=button("Clear Debug",UDim2.new(),UDim2.new(1,0,1,0),row(debugPage,38))
    local debugStatus=label("Ready. Capture a baseline before testing.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(debugPage,66),true)
    debugStatus.TextSize=14
    local reportBox=make("TextBox",{Name="DebugReport",Text="",MultiLine=true,TextEditable=false,
        ClearTextOnFocus=false,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Top,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextSize=14,
        TextColor3=colors.text,BackgroundTransparency=1,Size=UDim2.new(1,-20,1,-12),
        Position=UDim2.fromOffset(10,6)},row(debugPage,240))
    local baseline,report=nil,""
    local eventConnections,events={},{}
    local tracing,started,eventLimited=false,0,false
    -- Keep Instance references alive until Clear/new baseline so GC cannot change comparison IDs.
    local identities={}
    local nextId=0
    local function identity(object)
        if not identities[object] then nextId=nextId+1; identities[object]=nextId end
        return identities[object]
    end
    local function valueText(value)
        if typeof(value)=="Instance" then return value:GetFullName().." #"..identity(value) end
        return tostring(value)
    end
    local function stopTrace()
        tracing=false
        for _,connection in ipairs(eventConnections) do connection:Disconnect() end
        eventConnections={}
    end
    table.insert(cleanupActions,function()
        stopTrace(); baseline=nil; identities={}; events={}; report=""
    end)
    local function event(text)
        if not tracing then return end
        if #events>=500 then eventLimited=true; stopTrace(); debugStatus.Text="Event limit reached. Press Compare Now."; return end
        table.insert(events,string.format("[%.3fs] %s",os.clock()-started,text))
    end
    local function watch(signal,callback)
        table.insert(eventConnections,signal:Connect(callback))
    end
    local function properties(object)
        if object:IsA("Humanoid") then
            return {"WalkSpeed","JumpPower","JumpHeight","UseJumpPower","PlatformStand","Sit","AutoRotate","EvaluateStateMachine","Health","HipHeight"}
        elseif object:IsA("BasePart") then return {"Anchored","CanCollide","CanTouch","Massless"}
        elseif object:IsA("LocalScript") or object:IsA("Script") then return {"Enabled"}
        elseif object:IsA("ValueBase") then return {"Value"}
        elseif object:IsA("Motor6D") or (object:IsA("Constraint") and not object:IsA("LinearVelocity")) then return {"Enabled"}
        elseif object:IsA("BodyVelocity") then return {"Velocity","MaxForce","P"}
        elseif object:IsA("BodyPosition") then return {"Position","MaxForce","P","D"}
        elseif object:IsA("LinearVelocity") then return {"Enabled","VectorVelocity","MaxForce"}
        end
        return {}
    end
    local function fields(object)
        local result={Class=object.ClassName,Path=object:GetFullName()}
        for name,value in pairs(object:GetAttributes()) do result["Attribute:"..name]=valueText(value) end
        for _,property in ipairs(properties(object)) do
            local ok,value=pcall(function() return object[property] end)
            if ok then result[property]=valueText(value) end
        end
        return result
    end
    local function scopes()
        local result={}
        if player.Character then table.insert(result,player.Character) end
        table.insert(result,player)
        local client=game:GetService("ReplicatedStorage"):FindFirstChild("Client")
        if client then table.insert(result,client) end
        return result
    end
    local function included(object)
        return object~=playerGui and not object:IsDescendantOf(playerGui)
    end
    local function movement()
        local result={}
        local character=player.Character
        local humanoid=character and movementHumanoid(character)
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if humanoid then
            for key,value in pairs(fields(humanoid)) do result["Humanoid "..key]=value end
            result.State=humanoid:GetState().Name
            result.MoveDirection=tostring(humanoid.MoveDirection)
            result.FloorMaterial=tostring(humanoid.FloorMaterial)
            local animator=humanoid:FindFirstChildOfClass("Animator")
            local tracks={}
            if animator then
                for _,track in ipairs(animator:GetPlayingAnimationTracks()) do
                    table.insert(tracks,track.Name.." | "..(track.Animation and track.Animation.AnimationId or "?").." | speed="..track.Speed)
                end
            end
            table.sort(tracks); result.Animations=table.concat(tracks,"; ")
        end
        if root and root:IsA("BasePart") then
            result.Position=tostring(root.Position)
            result.Velocity=tostring(root.AssemblyLinearVelocity)
            result.AngularVelocity=tostring(root.AssemblyAngularVelocity)
        end
        result.SpeedControl=tostring(speedLocked).." target="..targetSpeed
        return result
    end
    local function snapshot()
        local result={character=player.Character,objects={},movement=movement(),count=0,truncated=false}
        local seen={}
        local function add(object)
            if seen[object] or not included(object) then return end
            seen[object]=true
            if result.count>=4000 then result.truncated=true; return end
            result.count=result.count+1
            result.objects[identity(object)]=fields(object)
        end
        for _,scope in ipairs(scopes()) do
            add(scope)
            for _,object in ipairs(scope:GetDescendants()) do add(object) end
        end
        -- Named trap objects are candidates, not proof of their function.
        local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        local searched=0
        if root and root:IsA("BasePart") then
            for _,object in ipairs(workspace:GetDescendants()) do
                searched=searched+1
                if searched>10000 then result.worldLimited=true; break end
                if object:IsA("BasePart") and string.lower(object.Name):find("trap",1,true) and (object.Position-root.Position).Magnitude<=150 then add(object) end
            end
        end
        return result
    end
    local function startTrace()
        tracing=true; started=os.clock(); events={}; eventLimited=false
        local watched={}; local count=0
        local function observe(object)
            if watched[object] or not included(object) then return end
            if count>=800 then return end
            count=count+1; watched[object]=true
            local path=object:GetFullName().." #"..identity(object)
            watch(object.AttributeChanged,function(name)
                event(path.." Attribute:"..name.." = "..valueText(object:GetAttribute(name)))
            end)
            for _,property in ipairs(properties(object)) do
                pcall(function()
                    watch(object:GetPropertyChangedSignal(property),function()
                        local ok,value=pcall(function() return object[property] end)
                        if ok then event(path.." "..property.." = "..valueText(value)) end
                    end)
                end)
            end
            if object:IsA("Humanoid") then
                watch(object.StateChanged,function(old,new) event(path.." State: "..old.Name.." -> "..new.Name) end)
            end
        end
        for _,scope in ipairs(scopes()) do
            observe(scope)
            for _,object in ipairs(scope:GetDescendants()) do observe(object) end
            watch(scope.DescendantAdded,function(object)
                if included(object) then event("ADDED "..object:GetFullName().." #"..identity(object)); observe(object) end
            end)
            watch(scope.DescendantRemoving,function(object)
                if included(object) then event("REMOVED "..object:GetFullName().." #"..identity(object)) end
            end)
        end
        watch(player.CharacterAdded,function() event("CHARACTER CHANGED: capture a new baseline for a same-character comparison") end)
        event("Watching "..count.." objects; maximum 800 (character first). Snapshot maximum 4000.")
        local traceStart=started
        task.delay(120,function()
            if tracing and started==traceStart then
                event("Trace stopped at 120 seconds."); stopTrace()
                debugStatus.Text="Trace time limit reached. Press Compare Now."
            end
        end)
    end
    local function sortedKeys(values)
        local result={}; for key in pairs(values) do table.insert(result,key) end
        table.sort(result); return result
    end
    local function compare(before,after)
        local lines={"AcidHub Debug | Game ID: "..game.GameId.." | Place ID: "..game.PlaceId,
            "Read-only snapshots and selected events. Changes do not establish cause.",
            "Scopes: Character, Player excluding PlayerGui, ReplicatedStorage.Client, nearby named trap candidates.",
            "Same character: "..tostring(before.character==after.character),
            "Objects before/after: "..before.count.." / "..after.count,
            "Snapshot truncated: "..tostring(before.truncated or after.truncated).." | World scan limited: "..tostring(before.worldLimited==true or after.worldLimited==true),
            "Event limit reached: "..tostring(eventLimited),
            "Coverage limits can make added/removed objects inconclusive.","","BEFORE MOVEMENT / ANIMATIONS"}
        for _,key in ipairs(sortedKeys(before.movement)) do table.insert(lines,key.." = "..before.movement[key]) end
        table.insert(lines,"\nAFTER MOVEMENT / ANIMATIONS")
        for _,key in ipairs(sortedKeys(after.movement)) do table.insert(lines,key.." = "..after.movement[key]) end
        table.insert(lines,"\nOBJECT / PROPERTY DIFFERENCES")
        for _,id in ipairs(sortedKeys(before.objects)) do
            local old,new=before.objects[id],after.objects[id]
            if not new then table.insert(lines,"REMOVED #"..id.." "..old.Path)
            else
                local keys={}; for key in pairs(old) do keys[key]=true end; for key in pairs(new) do keys[key]=true end
                for _,key in ipairs(sortedKeys(keys)) do
                    if old[key]~=new[key] then table.insert(lines,"CHANGED #"..id.." "..new.Path.." "..key..": "..tostring(old[key]).." -> "..tostring(new[key])) end
                end
            end
        end
        for _,id in ipairs(sortedKeys(after.objects)) do
            if not before.objects[id] then
                table.insert(lines,"ADDED #"..id.." "..after.objects[id].Path)
                for _,key in ipairs(sortedKeys(after.objects[id])) do table.insert(lines,"  "..key.." = "..after.objects[id][key]) end
            end
        end
        table.insert(lines,"\nEVENTS BETWEEN CAPTURES")
        for _,entry in ipairs(events) do table.insert(lines,entry) end
        return table.concat(lines,"\n")
    end
    local function showReport(text)
        report=text
        reportBox.Text=#text>14000 and (text:sub(1,14000).."\n[Preview shortened; Copy/Save contains the full report.]") or text
    end
    connect(captureButton.Activated,function()
        stopTrace(); baseline=nil; showReport("")
        identities={}; nextId=0
        local ok,result=pcall(snapshot)
        if not ok then debugStatus.Text="Capture failed: "..tostring(result); return end
        baseline=result
        local traceOK,err=pcall(startTrace)
        if not traceOK then stopTrace() end
        debugStatus.Text=traceOK and "Baseline captured. Trigger the effect, then Compare Now (within 120 seconds)." or ("Baseline captured; event trace failed: "..tostring(err))
    end)
    connect(compareButton.Activated,function()
        if not baseline then debugStatus.Text="Capture a baseline first."; return end
        stopTrace()
        local ok,result=pcall(function() return compare(baseline,snapshot()) end)
        if not ok then debugStatus.Text="Comparison failed: "..tostring(result); return end
        showReport(result); debugStatus.Text="Comparison ready. Copy or save the report. Capture a new baseline for the next test."
    end)
    connect(copyButton.Activated,function()
        if report=="" then debugStatus.Text="Compare first to create a report."; return end
        if type(setclipboard)~="function" then debugStatus.Text="Clipboard unavailable. Use Save Report."; return end
        local ok=pcall(setclipboard,report)
        debugStatus.Text=ok and "Full report copied." or "Could not copy report. Use Save Report."
    end)
    connect(saveButton.Activated,function()
        if report=="" then debugStatus.Text="Compare first to create a report."; return end
        if type(writefile)~="function" then debugStatus.Text="File saving unavailable. Use Copy Report."; return end
        local filename="AcidHub_Debug_"..os.time()..".txt"
        local ok,err=pcall(writefile,filename,report)
        debugStatus.Text=ok and ("Saved in executor workspace: "..filename) or ("Save failed: "..tostring(err))
    end)
    connect(clearButton.Activated,function()
        stopTrace(); baseline=nil; events={}; identities={}; nextId=0
        showReport(""); debugStatus.Text="Cleared. Capture a baseline before testing."
    end)
end

do
(function()
    local fusePage
    for _,section in ipairs(automationSubtabs) do if section.name=="Auto Fuse" then fusePage=section.page end end
    local active,working,paused=false,false,false
    local revision=0
    local priority,maximum,species,skipMutated,ejectIncomplete="Lowest Rarity First","All",{},false,false
    local skipEquipped,skipHeavy=false,false
    local heavyLimit="2x Normal Weight"
    local openDropdown
    local function note(message) reportTask("Auto Fuse",message); automationFlow.audit.emit("AutoFuse","status",{message=message}) end
    local function invalidate()
        revision=revision+1; paused=false
        if active and automationFlow.phase=="idle" then flowPhase("fusing","Auto Fuse settings updated") end
    end
    local function dropdown(title,options,multiple,get,set,caption)
        local frame=row(fusePage,42)
        label(title,UDim2.fromOffset(10,0),UDim2.new(0.48,-10,0,42),frame).TextSize=14
        local control=button("",UDim2.new(0.48,0,0,6),UDim2.new(0.52,-8,0,30),frame)
        control.TextSize=16
        local body=make("Frame",{Position=UDim2.fromOffset(8,44),Size=UDim2.new(1,-16,0,224),
            BackgroundColor3=colors.panel,BorderSizePixel=0,Visible=false},frame)
        local search=make("TextBox",{Text="",PlaceholderText="Search",ClearTextOnFocus=false,
            Position=UDim2.fromOffset(6,4),Size=UDim2.new(1,-12,0,28),BackgroundColor3=colors.card,
            TextColor3=colors.text,BorderSizePixel=0,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextSize=14},body)
        local list=make("ScrollingFrame",{Position=UDim2.fromOffset(6,36),Size=UDim2.new(1,-12,1,-42),
            BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.new(),
            AutomaticCanvasSize=Enum.AutomaticSize.Y},body)
        make("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,3)},list)
        local entries={}
        local function refresh()
            local value=get()
            local selected={}
            if multiple then for name,enabled in pairs(value) do if enabled then table.insert(selected,name) end end; table.sort(selected) end
            control.Text=(multiple and (#selected==0 and "All" or #selected==1 and selected[1] or tostring(#selected).." selected") or value).."  v"
            local query=string.lower(search.Text)
            for _,entry in ipairs(entries) do
                local active=multiple and value[entry.value] or value==entry.value
                entry.button.Text=(active and "✓ " or "")..entry.caption
                entry.button.TextColor3=active and colors.accent or colors.text
                entry.button.Visible=query=="" or string.find(string.lower(entry.caption),query,1,true)~=nil
            end
        end
        local function close() body.Visible=false; frame.Size=UDim2.new(1,0,0,42) end
        if multiple then
            local clear=button("Clear selection (All)",UDim2.new(),UDim2.new(1,-4,0,28),list)
            clear.LayoutOrder=0
            connect(clear.Activated,function() set({}); invalidate(); refresh() end)
        end
        for index,value in ipairs(options) do
            local option=button("",UDim2.new(),UDim2.new(1,-4,0,28),list)
            option.LayoutOrder=index; option.TextSize=16
            table.insert(entries,{value=value,caption=caption and caption(value) or value,button=option})
            connect(option.Activated,function()
                if multiple then local nextValue=copySetting(get()); nextValue[value]=not nextValue[value]; set(nextValue)
                else set(value); close() end
                invalidate(); refresh()
            end)
        end
        connect(search:GetPropertyChangedSignal("Text"),refresh)
        connect(control.Activated,function()
            if body.Visible then close(); return end
            if openDropdown then openDropdown() end
            openDropdown=close; body.Visible=true; frame.Size=UDim2.new(1,0,0,276); refresh()
        end)
        refresh()
        return refresh
    end
    switch(fusePage,"Auto Fuse",false,function(value)
        automationFlow.fuse=value
        active=value; invalidate()
        if not value and automationFlow.phase=="fusing" and not working then flowPhase("idle","Fuse stage complete") end
        note(value and "Waiting for three eligible matching pets" or "OFF; an accepted fuse will finish granting its reward.")
    end,"Fuses three matching eligible pets and grants the egg directly, without animations. Consumes pets and pays the game's fuse cost. Favorites are always protected. A failed request pauses until settings change or the switch is restarted.")
    settingsBindings["Auto Fuse"].busy=function() return working end
    local function choice(title,key,options,default,get,set,multiple,caption)
        local refresh=dropdown(title,options,multiple,get,set,caption)
        registerSetting(key,default,get,function(value)
            if key=="Fuse.Species" then
                local resolved={}
                for name,on in pairs(value) do
                    local liveName=Rarity.Resolve(name)
                    resolved[liveName]=resolved[liveName] or on
                end
                value=resolved
            end
            set(copySetting(value)); invalidate(); refresh(); return true
        end,function(value)
            if not multiple then return type(value)=="string" and table.find(options,value)~=nil end
            if type(value)~="table" then return false end
            for name,on in pairs(value) do
                local liveName=key=="Fuse.Species" and Rarity.Resolve(name) or name
                if type(on)~="boolean" or not table.find(options,liveName) then return false end
            end
            return true
        end)
    end
    choice("Fuse Priority Mode","Fuse.Priority",{"Lowest Rarity First","Highest Rarity First","Most Duplicates First","Specific Species Only"},priority,function() return priority end,function(v) priority=v end,false)
    local rarities={"All"}; for _,r in ipairs(rarityOptions) do if r~="Unknown" then table.insert(rarities,r) end end
    choice("Max Rarity to Fuse","Fuse.MaxRarity",rarities,maximum,function() return maximum end,function(v) maximum=v end,false)
    local options,ranks={},{}
    for _,entry in pairs(Rarity.Species) do if not ranks[entry.name] then options[#options+1]=entry.name; ranks[entry.name]=entry.rarity end end
    table.sort(options,function(a,b)
        local ar,br=table.find(rarityOptions,ranks[a]) or 99,table.find(rarityOptions,ranks[b]) or 99
        return ar==br and a<b or ar<br
    end)
    choice("Specific Species to Fuse","Fuse.Species",options,{},function() return species end,function(v) species=v end,true,function(v) return v.." ["..ranks[v].."]" end)
    switch(fusePage,"Skip Mutated Pets",false,function(v) skipMutated=v; invalidate() end,"Exclude pets with mutations or a base mutation, including Silver, Golden and Rainbow.")
    switch(fusePage,"Skip Equipped Pets",false,function(v) skipEquipped=v; invalidate() end,"Exclude pets listed in the game's EquippedAssets, including before loading and before the fuse request.")
    switch(fusePage,"Skip Very Heavy Pets",false,function(v) skipHeavy=v; invalidate() end,"Protect pets whose weight exceeds the selected multiple of their species' normal weight at scale 1. Missing weight data is excluded while this filter is ON.")
    choice("Heavy Weight Limit","Fuse.HeavyWeightLimit",{"2x Normal Weight","3x Normal Weight","5x Normal Weight","10x Normal Weight","20x Normal Weight"},"2x Normal Weight",function() return heavyLimit end,function(v) heavyLimit=v end,false)
    switch(fusePage,"Eject Incomplete Slots",false,function(v) ejectIncomplete=v; invalidate() end,"Return pets from an incomplete machine when fewer than three matching eligible pets are available. Never eject a full set or a running fuse.")
    -- Read-only probability model from EggRecords captured 2026-09-11.
    do
        local bands={{0.85,1.05,2000},{1.45,1.55,250},{1.9,2.1,125},{2.85,3.15,62.5},{3.8,4.2,31.25},{0.3,0.45,18},{0.1,0.2,5},{5.8,6.2,15.625},{9.5,12.5,3},{12,17,0.05},{20,35,0.0001}}
        local function escape(value) return tostring(value):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;") end
        local function color(value,hex) return '<font color="#'..hex..'">'..escape(value)..'</font>' end
        local function distribution(scales,kernel)
            local probabilities,total={},0
            for i,b in ipairs(bands) do probabilities[i]=b[3]*kernel.BandWeightBias(scales,b[1],b[2]); total=total+probabilities[i] end
            assert(total>0 and total<math.huge,"Invalid probability total")
            local components={}
            for i,b in ipairs(bands) do
                probabilities[i]=probabilities[i]/total
                for k=0,12 do
                    local factor=2^k
                    local lo,hi=b[1],math.min(b[2],150/factor)
                    if hi<=lo then break end
                    local split=math.max(lo,math.min(hi,75/factor))
                    local function add(a,z,stop)
                        if z>a then components[#components+1]={a*factor,z*factor,probabilities[i]*0.01^k*stop*(z-a)/(b[2]-b[1])} end
                    end
                    add(lo,split,0.99); add(split,hi,1)
                end
            end
            local function cdf(scale)
                local sum=0
                for _,part in ipairs(components) do sum=sum+part[3]*math.max(0,math.min(1,(scale-part[1])/(part[2]-part[1]))) end
                return math.max(0,math.min(1,sum))
            end
            local function quantile(p)
                local lo,hi=0,150
                for _=1,60 do local mid=(lo+hi)/2; if cdf(mid)<p then lo=mid else hi=mid end end
                return (lo+hi)/2
            end
            return probabilities,cdf,quantile
        end
        automationFlow.fuseCalculator=function()
            local ok,result=pcall(function()
                local storage=game:GetService("ReplicatedStorage")
                local save=require(storage.Shared.Save).Get()
                assert(save and save.FusionSlots and save.Inventory,"Waiting for inventory")
                local items=require(storage.Shared.Util.AssetItems)
                local kernel=require(storage.Shared.Util.FuseKernel)
                local earnings=require(storage.Shared.Util.AssetEarnings)
                local inputs,scales,category={},{},nil
                local lines={color("FUSE MACHINE STATUS · 3/3 PETS","4AD5B4")}
                for i=1,3 do
                    local uid=save.FusionSlots[i]; local raw=uid and save.Inventory[uid]
                    if not raw then return "FUSE CALCULATOR — load three matching pets into the machine to calculate odds." end
                    local item=items.Decode(raw)
                    assert(not category or item.Category==category,"All three pets must match")
                    assert(type(item.Scale)=="number" and item.Scale>0,"Invalid pet scale")
                    category=item.Category; inputs[i]=item; scales[i]=item.Scale
                end
                local species,rarity,tint=Rarity.Resolve(category)
                lines[#lines+1]="Species: "..color(species.." ["..rarity.."]",tint:ToHex())
                local probabilities,cdf,quantile=distribution(scales,kernel)
                local mean=(scales[1]+scales[2]+scales[3])/3
                local function weight(scale) local item=copySetting(inputs[1]); item.Scale=scale; return items.WeightKg(item) end
                local function number(value)
                    local text=string.format("%.0f",value)
                    return text:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
                end
                lines[#lines+1]="Average scale  "..color(string.format("%.2fx",mean).."  ·  "..number(weight(mean)).." kg","FFDA57")
                lines[#lines+1]="Fuse cost  "..color(Rarity.ESP.compact(kernel.PriceFor(inputs)) or "Unavailable","4AD5B4")
                lines[#lines+1]=""
                lines[#lines+1]=color("PREDICTED SIZE PROBABILITIES","4AD5B4")
                local names={"Normal","Large","Giant","Huge","Gigantic","Small","Tiny","Titan","Colossal","12–17x band","20–35x band"}
                local colors={"59D98E","C7D94B","52B9F3","E6C337","EE8840","A3C7BB","99ADB8","D266E0","9B72E4","E86DA1","F18BBD"}
                local order={}; for i in ipairs(bands) do order[#order+1]=i end
                table.sort(order,function(a,b) return probabilities[a]>probabilities[b] end)
                for _,i in ipairs(order) do
                    local b=bands[i]
                    local percent=100*probabilities[i]
                    local probability=percent<0.0001 and "< 0.0001%" or string.format(percent>=1 and "%.1f%%" or "%.3g%%",percent)
                    lines[#lines+1]=""
                    lines[#lines+1]=color(names[i].."  ·  "..string.format("%.2f–%.2fx",b[1],b[2]),colors[i]).."  "..color(probability,colors[i])
                    lines[#lines+1]=number(weight(b[1])).." – "..number(weight(b[2])).." kg"
                end
                lines[#lines+1]=""
                lines[#lines+1]=color("RESULT ESTIMATES","FF857E")
                lines[#lines+1]="Mutation prediction: unverified"
                local p5,p50,p95=quantile(0.05),quantile(0.5),quantile(0.95)
                lines[#lines+1]="Median weight: "..color(number(weight(p50)).." kg","FFDA57")
                lines[#lines+1]="Middle 90% weight: "..number(weight(p5)).." – "..number(weight(p95)).." kg"
                local function income(scale)
                    local item=copySetting(inputs[1]); item.Scale=scale; item.Mutations={}; item.BaseMutation=nil
                    return earnings.MutationOnlyRatePerSecond(item)
                end
                local likely=bands[order[1]]
                lines[#lines+1]="Normal income · most likely band:"
                lines[#lines+1]=color((Rarity.ESP.compact(income(likely[1])) or "?").."/s – "..(Rarity.ESP.compact(income(likely[2])) or "?").."/s","4AD5B4")
                lines[#lines+1]="Normal income · middle 90%:"
                lines[#lines+1]=color((Rarity.ESP.compact(income(p5)) or "?").."/s – "..(Rarity.ESP.compact(income(p95)) or "?").."/s","4AD5B4")
                lines[#lines+1]=""
                lines[#lines+1]=color("Size model: rules captured 11 Sep 2026. Tier odds exclude bonus doublings; final estimates include them. Mutation inheritance is not verified.","9BAABE")
                return table.concat(lines,"\n")
            end)
            return ok and result or ("Fuse Calculator unavailable: "..escape(result))
        end
    end
    local function cycle()
        local token=revision
        local function live() return active and not closed and revision==token and automationFlow.phase=="fusing" and not automationFlow.collecting and not automationFlow.placing end
        local storage=game:GetService("ReplicatedStorage")
        local Save=require(storage.Shared.Save)
        local kernel=require(storage.Shared.Util.FuseKernel)
        local items=require(storage.Shared.Util.AssetItems)
        local remotes=require(storage.Shared.Remotes).Fusery
        local function read()
            local save=Save.Get()
            assert(save and type(save.Inventory)=="table" and type(save.FusionSlots)=="table","Inventory or fuse state unavailable")
            return save
        end
        local save=read()
        if save.FusionLocked or save.FusionEggReward~=false then note("Machine busy or reward pending; finish the existing reveal in Debug/game first."); return end
        if not save.FusionInfoAcknowledged then note("Accept the game's fuse briefing first."); return end
        local function eligible(uid,item,inMachine,category)
            local ok=kernel.MayEnterFuse(uid,item,category,inMachine)
            if not ok then return false end
            local name=Rarity.Resolve(item.Category)
            local rarity,rank=automationFlow.audit.rarity(item.Category)
            if maximum~="All" and (not rank or rarity=="Unknown" or rank>(table.find(rarityOptions,maximum) or 0)) then return false end
            local selected=false; for _,v in pairs(species) do if v then selected=true; break end end
            if (selected or priority=="Specific Species Only") and not species[name] then return false end
            if skipEquipped then
                local latest=Save.Get()
                if not latest or type(latest.EquippedAssets)~="table" then return false end
                if table.find(latest.EquippedAssets,uid) then return false end
            end
            local decoded=items.Decode(item)
            if skipHeavy then
                local normal=copySetting(decoded); normal.Scale=1
                local base=items.WeightKg(normal)
                local actual=items.WeightKg(decoded)
                local multiplier=tonumber(heavyLimit:match("^(%d+)x"))
                if not multiplier or type(base)~="number" or base<=0 or base~=base or base==math.huge
                    or type(actual)~="number" or actual~=actual or actual==math.huge or actual<0 then return false end
                if actual>base*multiplier then return false end
            end
            if skipMutated then
                if type(decoded.Mutations)~="table" or next(decoded.Mutations)~=nil then return false end
                if decoded.BaseMutation~=nil and decoded.BaseMutation~="" then return false end
            end
            return true,rank or 99
        end
        local loaded,category={},nil
        for i=1,3 do
            local uid=save.FusionSlots[i]
            if uid then
                local item=save.Inventory[uid]
                if not item or not eligible(uid,item,true,category) then note("Loaded pets do not match fuse filters; adjust filters or remove them manually."); return end
                category=category or item.Category; loaded[#loaded+1]=uid
            end
        end
        local groups={}
        for uid,item in pairs(save.Inventory) do
            if type(uid)=="string" and type(item)=="table" then
                local allowed,rank=eligible(uid,item,false,category)
                if allowed then
                    local group=groups[item.Category] or {category=item.Category,ids={},rank=rank}
                    groups[item.Category]=group; group.ids[#group.ids+1]=uid
                end
            end
        end
        local candidates={}
        for _,group in pairs(groups) do
            table.sort(group.ids)
            if #group.ids+#loaded>=3 then candidates[#candidates+1]=group end
        end
        table.sort(candidates,function(a,b)
            if priority=="Most Duplicates First" and #a.ids~=#b.ids then return #a.ids>#b.ids end
            if a.rank~=b.rank then if priority=="Highest Rarity First" then return a.rank>b.rank end; return a.rank<b.rank end
            return a.category<b.category
        end)
        local chosen=category and groups[category] or candidates[1]
        if #loaded<3 and (not chosen or #chosen.ids+#loaded<3) then
            if #loaded>0 and ejectIncomplete then
                for _,uid in ipairs(loaded) do
                    if not live() then return end
                    local current=read()
                    assert(not current.FusionLocked and current.FusionEggReward==false,"Machine changed before eject")
                    local count,found=0,false
                    for i=1,3 do if current.FusionSlots[i] then count=count+1 end; if current.FusionSlots[i]==uid then found=true end end
                    assert(count<3 and found,"Slots changed before eject; paused")
                    note("Returning incomplete fuse pet "..uid)
                    local ok,reason=remotes.EjectPet:InvokeServer(uid)
                    assert(ok==true,"EjectPet denied: "..tostring(reason))
                end
                note("Incomplete slots returned; waiting for a full eligible set.")
            else note("Waiting for three matching eligible pets.") end
            return
        end
        local eggCount=0
        assert(type(save.EggInventory)=="table","Egg inventory unavailable")
        for _ in pairs(save.EggInventory) do eggCount=eggCount+1 end
        if eggCount>=require(storage.Shared.Types.Eggs).MAX_INVENTORY then note("Waiting: egg inventory is full."); return end
        local selected={}; for _,uid in ipairs(loaded) do selected[#selected+1]=uid end
        if #selected<3 then for _,uid in ipairs(chosen.ids) do selected[#selected+1]=uid; if #selected==3 then break end end end
        for i=#loaded+1,3 do
            if not live() then return end
            local current=read(); local item=current.Inventory[selected[i]]
            assert(not current.FusionLocked and current.FusionEggReward==false and item and eligible(selected[i],item,false,category or chosen.category),"Pet or machine changed before loading")
            note("Loading "..tostring(item.Category).." ("..i.."/3)")
            automationFlow.audit.emit("AutoFuse","load_requested",{uid=selected[i],slot=i,values=automationFlow.audit.values(item),maximum=maximum,priority=priority,skipEquipped=skipEquipped,skipHeavy=skipHeavy,heavyLimit=heavyLimit})
            local ok,reason=remotes.LoadPet:InvokeServer(selected[i])
            automationFlow.audit.emit("AutoFuse","load_result",{uid=selected[i],accepted=ok,message=reason})
            assert(ok==true,"LoadPet denied: "..tostring(reason))
        end
        local deadline=os.clock()+8
        local current,decoded
        repeat
            if not live() then return end
            current=read(); decoded={}
            local set={}; for _,uid in ipairs(selected) do set[uid]=true end
            for i=1,3 do
                local uid=current.FusionSlots[i]; local item=uid and current.Inventory[uid]
                if uid and set[uid] and item and eligible(uid,item,true,category or chosen.category) then decoded[#decoded+1]=items.Decode(item); set[uid]=nil end
            end
            if #decoded==3 then break end
            task.wait(0.2)
        until os.clock()>=deadline
        assert(#decoded==3,"Loaded slots unconfirmed; no BeginFuse sent")
        assert(not current.FusionLocked and current.FusionEggReward==false,"Machine state changed")
        if not live() then return end
        note("Fusing "..tostring(decoded[1].Category).." | Cost: "..tostring(kernel.PriceFor(decoded)))
        local inputValues={}; for i,item in ipairs(decoded) do inputValues[i]={uid=selected[i],values=automationFlow.audit.values(item)} end
        automationFlow.audit.emit("AutoFuse","fuse_requested",{pets=inputValues,cost=kernel.PriceFor(decoded),maximum=maximum})
        local accepted,reason,reward=remotes.BeginFuse:InvokeServer()
        automationFlow.audit.emit("AutoFuse","fuse_result",{accepted=accepted,message=reason,reward=reward})
        assert(accepted==true,"BeginFuse denied: "..tostring(reason))
        -- Complete accepted work even if OFF is clicked during the request.
        assert(require(storage.Shared.Types.FuseMachine).FuseResult(reward),"Invalid fuse result; recover pending reward in Debug")
        local finished,finishReason=remotes.FinishReveal:InvokeServer()
        automationFlow.audit.emit("AutoFuse","finish_result",{accepted=finished,message=finishReason})
        assert(finished==true,"FinishReveal denied: "..tostring(finishReason).."; recover pending reward in Debug")
        deadline=os.clock()+15
        repeat
            current=read()
            local consumed=true; for _,uid in ipairs(selected) do if current.Inventory[uid] then consumed=false end end
            if consumed and not current.FusionLocked and current.FusionEggReward==false then note("Fuse completed; egg granted. Checking next eligible set."); return true end
            task.wait(0.25)
        until closed or os.clock()>=deadline
        error("Reward completion unconfirmed; check inventory and machine before restarting")
    end
    task.spawn(function()
        while not closed do
            if paused and automationFlow.phase=="fusing" then flowPhase("idle","Fuse stage complete") end
            if active and not paused and not working and not automationFlow.selling and automationFlow.phase=="fusing" and not automationFlow.collecting and not automationFlow.placing and not treadmillExitBusy then
                working=true
                automationFlow.fusing=true
                local ok,err=pcall(cycle)
                working=false
                automationFlow.fusing=false
                if not ok then paused=true; note("Paused: "..tostring(err)) end
                if automationFlow.phase=="fusing" and (not ok or err~=true or not active) then flowPhase("idle","Fuse stage complete") end
            end
            task.wait(5)
        end
    end)
    table.insert(cleanupActions,function() active=false; automationFlow.fuse=false; revision=revision+1 end)
end)()
end

do
(function()
    local rift={enabled=false,placementPriority=false,busy=false,paused=false,state=nil,revision=0,refreshed=0,banner="Any"}
    automationFlow.rift=rift
    local maximum="All"
    local page
    for _,tab in ipairs(tabs) do if tab.name=="Events" then page=tab.page.TheRiftSection.RiftSettings end end
    local function note(message) reportTask("The Rift",message) end
    local function changed()
        rift.revision=rift.revision+1; rift.paused=false; rift.refreshed=0
        if rift.enabled and automationFlow.phase=="idle" then flowPhase("rift","Rift enabled/settings updated") end
    end
    switch(page,"Steal Rift Pets",false,function(v)
        rift.enabled=v; changed()
        if not v and not rift.busy and automationFlow.phase=="rift" then flowPhase("idle","Rift stage complete") end
        note(v and "Reading current recipe" or "OFF; an accepted trade will still finish granting its egg.")
    end,"After normal Auto Steal targets, collects missing Rift species regardless of steal filters. Requires Auto Steal for collection and Auto Place/Auto Hatch to turn stolen eggs into pets. Trades eligible sets before Auto Fuse. Favorites and equipped pets are protected.")
    do
        local options={"Any","Riftborn","Riftbeasts","Shattered Rift"}
        local frame=row(page,42)
        label("Rift Banner",UDim2.fromOffset(10,0),UDim2.new(0.5,-10,0,42),frame).TextSize=14
        local control=button("Any  v",UDim2.new(0.5,0,0,6),UDim2.new(0.5,-8,0,30),frame)
        local list=make("Frame",{Position=UDim2.fromOffset(8,44),Size=UDim2.new(1,-16,0,124),Visible=false,BackgroundColor3=colors.panel,BorderSizePixel=0},frame)
        make("UIListLayout",{Padding=UDim.new(0,3)},list)
        local function set(value) rift.banner=value; control.Text=value.."  v"; changed(); return true end
        for _,value in ipairs(options) do
            local item=button(value,UDim2.new(),UDim2.new(1,0,0,28),list)
            connect(item.Activated,function() set(value); list.Visible=false; frame.Size=UDim2.new(1,-6,0,42) end)
        end
        connect(control.Activated,function() list.Visible=not list.Visible; frame.Size=UDim2.new(1,-6,0,list.Visible and 176 or 42) end)
        registerSetting("Rift.Banner","Any",function() return rift.banner end,set,function(value) return table.find(options,value)~=nil end)
    end
    function rift.bannerMatches()
        if not rift.state or not rift.state.BannerId then return false end
        local ok,matched=pcall(function()
            local data=require(game:GetService("ReplicatedStorage").Data.Rift)
            if data.CurrentBannerId()~=rift.state.BannerId then return false end
            if rift.banner=="Any" then return true end
            local name=data.GetBannerDisplayName(rift.state.BannerId)
            return type(name)=="string" and name:lower():gsub("[^%w]","")==rift.banner:lower():gsub("[^%w]","")
        end)
        return ok and matched==true
    end
    switch(page,"Prioritize Rift Egg Placement",false,function(v)
        rift.placementPriority=v
    end,"While Steal Rift Pets is enabled, place eggs for the current Rift requirements before other eggs.")
    local choices={"All","Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret","Eternal","Divine"}
    local frame=row(page,42)
    label("Max Trade Rarity",UDim2.fromOffset(10,0),UDim2.new(0.5,-10,0,42),frame).TextSize=14
    local buttonChoice=button("All  v",UDim2.new(0.5,0,0,6),UDim2.new(0.5,-8,0,30),frame)
    local list=make("ScrollingFrame",{Position=UDim2.fromOffset(8,44),Size=UDim2.new(1,-16,0,190),Visible=false,BackgroundColor3=colors.panel,BorderSizePixel=0,ScrollBarThickness=4,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new()},frame)
    make("UIListLayout",{Padding=UDim.new(0,3)},list)
    local function setMaximum(v) maximum=v; buttonChoice.Text=v.."  v"; changed(); return true end
    for i,v in ipairs(choices) do
        local option=button(v,UDim2.new(),UDim2.new(1,-4,0,28),list); option.LayoutOrder=i
        connect(option.Activated,function() setMaximum(v); list.Visible=false; frame.Size=UDim2.new(1,-6,0,42) end)
    end
    connect(buttonChoice.Activated,function() list.Visible=not list.Visible; frame.Size=UDim2.new(1,-6,0,list.Visible and 240 or 42) end)
    registerSetting("Rift.MaxTradeRarity","All",function() return maximum end,setMaximum,function(v) return type(v)=="string" and table.find(choices,v)~=nil end)
    local refreshButton=button("Refresh Rift Requirements",UDim2.new(),UDim2.new(1,0,1,0),row(page,38))
    local function allowed(category)
        if maximum=="All" then return true end
        local _,rank=automationFlow.audit.rarity(category)
        return rank~=nil and rank<=((table.find(choices,maximum) or 1)-1)
    end
    function rift.refresh(force)
        if not rift.enabled then return false end
        local data=require(game:GetService("ReplicatedStorage").Data.Rift)
        local rotation=math.floor(workspace:GetServerTimeNow()/data.RotationSeconds())
        if not force and rift.state and rift.rotation==rotation and rift.day==automationFlow.epoch and os.clock()-rift.refreshed<15 then return true end
        if rift.reading then return false end
        rift.reading=true
        local ok,state=pcall(function() return require(game:GetService("ReplicatedStorage").Shared.Remotes).Rift.AskState:InvokeServer() end)
        rift.reading=false
        if not ok or type(state)~="table" or type(state.Requirements)~="table" or #state.Requirements~=3 then rift.state=nil; note("Rift state unavailable; waiting for refresh"); return false end
        for _,c in ipairs(state.Requirements) do if type(c)~="string" then rift.state=nil; return false end end
        rift.state=state; rift.recipeKey=tostring(rotation)..":"..tostring(state.BannerId)..":"..table.concat(state.Requirements,"|"); rift.rotation=rotation; rift.day=automationFlow.epoch; rift.refreshed=os.clock()
        if rift.enabled and not rift.paused and not rift.busy then
            local names={}; for _,c in ipairs(state.Requirements) do names[#names+1]=Rarity.Resolve(c) end
            note("Requires "..table.concat(names,", ").." | banner "..tostring(state.BannerId))
        end
        return true
    end
    connect(refreshButton.Activated,function() if rift.enabled then task.spawn(function() rift.refresh(true) end) else note("Enable Steal Rift Pets to read the live recipe.") end end)
    function rift.plan()
        local storage=game:GetService("ReplicatedStorage")
        local save=require(storage.Shared.Save).Get()
        assert(save and type(save.Inventory)=="table" and type(save.EquippedAssets)=="table","Rift inventory unavailable")
        assert(rift.state,"Rift recipe unavailable")
        local kernel=require(storage.Shared.Util.FuseKernel)
        local items=require(storage.Shared.Util.AssetItems)
        local selected,reserved,missing={},{},{}
        local blocked=false
        for i,category in ipairs(rift.state.Requirements) do
            if not allowed(category) then blocked=true end
            local pool={}
            if allowed(category) then
                for uid,item in pairs(save.Inventory) do
                    if type(item)=="table" and item.Category==category and not reserved[uid] and not table.find(save.EquippedAssets,uid) then
                        local ok,valid=pcall(kernel.MayEnterRift,uid,item)
                        if ok and valid then pool[#pool+1]={uid=uid,weight=items.WeightKg(items.Decode(item))} end
                    end
                end
            end
            table.sort(pool,function(a,b) return a.weight==b.weight and a.uid<b.uid or a.weight<b.weight end)
            if pool[1] then selected[i]=pool[1].uid; reserved[pool[1].uid]=true
            elseif allowed(category) then missing[category]=(missing[category] or 0)+1 end
        end
        local pending=false; local unplaced=false
        local owned=require(storage.Client.EggState).ReadOwnerEggs(player.UserId)
        for _,egg in pairs(owned) do
            local category=egg.AssetCategory
            if missing[category] and missing[category]>0 then missing[category]=missing[category]-1; if egg.Placement~=nil then pending=true else unplaced=true end end
        end
        return {selected=selected,reserved=reserved,missing=missing,pending=pending,unplaced=unplaced,blocked=blocked,save=save}
    end
    function rift.needs()
        if not rift.enabled or rift.paused or not rift.refresh(false) or not rift.bannerMatches() then return {} end
        local plan=rift.plan()
        if plan.blocked then return {} end
        return plan.missing
    end
    function rift.holdEquip()
        if not rift.enabled or not rift.bannerMatches() then return false end
        local ok,plan=pcall(rift.plan)
        return not ok or rift.busy or (not plan.blocked and (next(plan.reserved)~=nil or plan.pending or plan.unplaced))
    end
    local function stage()
        if not rift.refresh(false) then return end
        if not rift.bannerMatches() then note("Waiting for selected banner: "..rift.banner.."; continuing to Fuse/Treadmill"); return false end
        local plan=rift.plan()
        if plan.blocked then note("Recipe exceeds Max Trade Rarity; Rift skipped"); return false end
        if not plan.selected[1] or not plan.selected[2] or not plan.selected[3] then
            note("No complete eligible Rift pet set available; continuing to Fuse/Treadmill"); return false
        end
        if not rift.refresh(true) then return true end
        if not rift.bannerMatches() then return false end
        plan=rift.plan()
        if plan.blocked or not plan.selected[1] or not plan.selected[2] or not plan.selected[3] then return true end
        local token=rift.revision
        local storage=game:GetService("ReplicatedStorage")
        local remotes=require(storage.Shared.Remotes).Rift
        local before={}; local count=0
        for uid in pairs(plan.save.EggInventory) do before[uid]=true; count=count+1 end
        if count>=require(storage.Shared.Types.Eggs).MAX_INVENTORY then note("Rift waiting: egg inventory full"); return false end
        if closed or not rift.enabled or token~=rift.revision or automationFlow.phase~="rift" or not rift.bannerMatches() then return false end
        local accepted,message=remotes.AskTradeIn:InvokeServer(plan.selected)
        assert(accepted==true,"Rift trade rejected: "..tostring(message))
        -- Finish accepted work even when disabled or a new day begins during the request.
        local result,reason=remotes.AskFinishReveal:InvokeServer()
        assert(result~=false,"Rift reveal rejected: "..tostring(reason))
        local deadline=os.clock()+15
        repeat
            local save=require(storage.Shared.Save).Get()
            local consumed=true; for _,uid in ipairs(plan.selected) do if save.Inventory[uid] then consumed=false end end
            if consumed then
                for uid in pairs(save.EggInventory) do if not before[uid] then
                    note("Rift trade complete; egg received. Refreshing recipe.")
                    rift.refreshed=0; rift.refresh(true)
                    return true
                end end
            end
            task.wait(0.25)
        until closed or os.clock()>deadline
        error("Rift reward unconfirmed; inspect inventory before restarting the switch")
    end
    task.spawn(function()
        while not closed do
            if rift.enabled then
                local ok,err=pcall(function()
                    rift.refresh(false)
                    if automationFlow.phase=="rift" and not automationFlow.selling and not automationFlow.collecting and not automationFlow.placing and not automationFlow.fusing and not treadmillExitBusy then
                        if rift.paused then flowPhase("idle","Rift stage complete"); return end
                        rift.busy=true
                        local more=stage()
                        rift.busy=false
                        if more==false and automationFlow.phase=="rift" then flowPhase("idle","Rift stage complete") end
                    end
                end)
                rift.busy=false
                if not ok then rift.paused=true; note("Paused: "..tostring(err)); if automationFlow.phase=="rift" then flowPhase("idle","Rift stage complete") end end
            end
            if not rift.enabled and not rift.busy and automationFlow.phase=="rift" then flowPhase("idle","Rift stage complete") end
            task.wait(3)
        end
    end)
    table.insert(cleanupActions,function() rift.enabled=false; rift.revision=rift.revision+1 end)
end)()
end

do (function()
    local sellPage
    for _,section in ipairs(automationSubtabs) do if section.name=="Auto Sell" then sellPage=section.page end end
    local petOn,eggOn=false,false
    local sellWhen,skipEvent="90% Capacity",false
    automationFlow.sellSequence=function() return sellWhen=="Sequence" and (petOn or eggOn) end
    local rule,petMax,eggMax,threshold,blacklist="Rarity Only","Rare","Rare",0,{}
    local revision,paused,openDropdown=0,false,nil
    local previews={}
    local function note(message) reportTask("Auto Sell",message) end
    local function invalidate() revision=revision+1; paused=false; previews={} end
    local function dropdown(title,options,multiple,get,set,caption)
        local frame=row(sellPage,42)
        label(title,UDim2.fromOffset(10,0),UDim2.new(0.48,-10,0,42),frame).TextSize=14
        local control=button("",UDim2.new(0.48,0,0,6),UDim2.new(0.52,-8,0,30),frame)
        control.TextSize=16
        local body=make("Frame",{Position=UDim2.fromOffset(8,44),Size=UDim2.new(1,-16,0,224),
            BackgroundColor3=colors.panel,BorderSizePixel=0,Visible=false},frame)
        local search=make("TextBox",{Text="",PlaceholderText="Search",ClearTextOnFocus=false,
            Position=UDim2.fromOffset(6,4),Size=UDim2.new(1,-12,0,28),BackgroundColor3=colors.card,
            TextColor3=colors.text,BorderSizePixel=0,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextSize=14},body)
        local list=make("ScrollingFrame",{Position=UDim2.fromOffset(6,36),Size=UDim2.new(1,-12,1,-42),
            BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.new(),
            AutomaticCanvasSize=Enum.AutomaticSize.Y},body)
        make("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,3)},list)
        local entries={}
        local function refresh()
            local value=get()
            local selected={}
            if multiple then for name,enabled in pairs(value) do if enabled then table.insert(selected,name) end end; table.sort(selected) end
            control.Text=(multiple and (#selected==0 and "None" or #selected==1 and selected[1] or tostring(#selected).." selected") or value).."  v"
            local query=string.lower(search.Text)
            for _,entry in ipairs(entries) do
                local active=multiple and value[entry.value] or value==entry.value
                entry.button.Text=(active and "✓ " or "")..entry.caption
                entry.button.TextColor3=active and colors.accent or colors.text
                entry.button.Visible=query=="" or string.find(string.lower(entry.caption),query,1,true)~=nil
            end
        end
        local function close() body.Visible=false; frame.Size=UDim2.new(1,0,0,42) end
        if multiple then
            local clear=button("Clear blacklist",UDim2.new(),UDim2.new(1,-4,0,28),list)
            clear.LayoutOrder=0
            connect(clear.Activated,function() set({}); invalidate(); refresh() end)
        end
        for index,value in ipairs(options) do
            local option=button("",UDim2.new(),UDim2.new(1,-4,0,28),list)
            option.LayoutOrder=index; option.TextSize=16
            table.insert(entries,{value=value,caption=caption and caption(value) or value,button=option})
            connect(option.Activated,function()
                if multiple then local nextValue=copySetting(get()); nextValue[value]=not nextValue[value]; set(nextValue)
                else set(value); close() end
                invalidate(); refresh()
            end)
        end
        connect(search:GetPropertyChangedSignal("Text"),refresh)
        connect(control.Activated,function()
            if body.Visible then close(); return end
            if openDropdown then openDropdown() end
            openDropdown=close; body.Visible=true; frame.Size=UDim2.new(1,0,0,276); refresh()
        end)
        refresh()
        return refresh
    end

    local function choice(title,key,options,default,get,set,multiple)
        local refresh=dropdown(title,options,multiple,get,set)
        registerSetting(key,default,get,function(v) set(copySetting(v)); invalidate(); refresh(); return true end,function(v)
            if not multiple then return type(v)=="string" and table.find(options,v)~=nil end
            if type(v)~="table" then return false end
            for name,on in pairs(v) do if type(on)~="boolean" or not table.find(options,name) then return false end end
            return true
        end)
    end
    switch(sellPage,"Auto Sell Pets",false,function(v) petOn=v; invalidate(); note(v and "Auto Sell enabled" or "Pet selling OFF") end)
    choice("Sell When","Sell.When",{"90% Capacity","Sequence"},sellWhen,function() return sellWhen end,function(v) sellWhen=v end,false)
    choice("Sell Pet Rule","Sell.PetRule",{"Rarity Only","Income Only","Both"},rule,function() return rule end,function(v) rule=v end,false)
    local rarities={"All","Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret","Eternal","Divine"}
    choice("Pet Max Rarity","Sell.PetMaxRarity",rarities,petMax,function() return petMax end,function(v) petMax=v end,false)
    local incomeRow=row(sellPage,62)
    label("Pet Income Threshold (0 = disabled)",UDim2.fromOffset(8,0),UDim2.new(1,-16,0,25),incomeRow).TextSize=14
    local input=make("TextBox",{Text="0",ClearTextOnFocus=false,Position=UDim2.fromOffset(8,28),Size=UDim2.new(1,-16,0,28),BackgroundColor3=colors.panel,TextColor3=colors.text,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextSize=14},incomeRow)
    connect(input.FocusLost,function()
        local number,suffix=input.Text:lower():match("^%s*(%d*%.?%d+)%s*([kmbt]?)%s*$")
        local value=tonumber(number); if value then value=value*(({k=1e3,m=1e6,b=1e9,t=1e12})[suffix] or 1) end
        if value and value>=0 and value<math.huge then threshold=value; invalidate() else note("Invalid income threshold; previous value retained") end
        input.Text=tostring(threshold)
    end)
    registerSetting("Sell.IncomeThreshold",0,function() return threshold end,function(v) threshold=v; input.Text=tostring(v); invalidate(); return true end,function(v) return type(v)=="number" and v>=0 and v<math.huge end)
    local options,seen={},{}
    for _,entry in pairs(Rarity.Species) do if not seen[entry.name] then options[#options+1]=entry.name; seen[entry.name]=true end end
    table.sort(options)
    choice("Blacklist Sell Pets","Sell.Blacklist",options,{},function() return blacklist end,function(v) blacklist=v end,true)
    switch(sellPage,"Skip Event Pets",false,function(v) skipEvent=v; invalidate() end)
    local petNow=button("Preview Sell Pets",UDim2.new(),UDim2.new(1,0,1,0),row(sellPage,36))
    switch(sellPage,"Auto Sell Eggs",false,function(v) eggOn=v; invalidate(); note(v and "Auto Sell enabled" or "Egg selling OFF") end)
    choice("Egg Max Rarity","Sell.EggMaxRarity",rarities,eggMax,function() return eggMax end,function(v) eggMax=v end,false)
    local eggNow=button("Preview Sell Eggs",UDim2.new(),UDim2.new(1,0,1,0),row(sellPage,36))
    local function sellRuleMatches(mode,rank,maximum,income,limit)
        local rarityOK=type(rank)=="number" and rank<=maximum
        local incomeOK=limit>0 and type(income)=="number" and income==income and income<limit
        if mode=="Rarity Only" then return rarityOK end
        if mode=="Income Only" then return incomeOK end
        return rarityOK and incomeOK
    end
    -- END sellRuleMatches
    local function inventory()
        local storage=game:GetService("ReplicatedStorage")
        local save=assert(require(storage.Shared.Save).Get(),"Save unavailable")
        assert(type(save.Inventory)=="table" and type(save.EggInventory)=="table" and type(save.EquippedAssets)=="table","Inventory unavailable")
        local count=0
        for _ in pairs(save.Inventory) do count=count+1 end
        for _,egg in pairs(save.EggInventory) do if egg.Placement==nil then count=count+1 end end
        return save,count,require(storage.Shared.Globals.Constants).BACKPACK.LIMIT
    end
    local function eventSpecies()
        local protected={}
        if not skipEvent then return protected end
        local state=require(game:GetService("ReplicatedStorage").Shared.Remotes).Rift.AskState:InvokeServer()
        assert(type(state)=="table" and type(state.Requirements)=="table" and #state.Requirements==3,"Rift requirements unavailable; sale skipped")
        for _,category in ipairs(state.Requirements) do
            assert(type(category)=="string","Invalid Rift requirement; sale skipped")
            protected[category]=true
        end
        return protected
    end
    local function candidates(kind,save,protected)
        local storage=game:GetService("ReplicatedStorage")
        local items=require(storage.Shared.Util.AssetItems)
        local records=require(storage.Shared.Util.EggRecords)
        local earnings=require(storage.Shared.Util.AssetEarnings)
        local maximum=(kind=="Pets" and petMax or eggMax)
        local rankMax=maximum=="All" and 10 or (table.find(rarities,maximum) or 1)-1
        local result={}
        for uid,raw in pairs(kind=="Pets" and save.Inventory or save.EggInventory) do
            local ok,entry=pcall(function()
                if kind=="Pets" then
                    local item=items.Decode(raw)
                    if item.IsFavorite or item.InFuse or table.find(save.EquippedAssets,uid) or table.find(save.FusionSlots or {},uid) then return end
                    if protected[item.Category] then return end
                    if blacklist[Rarity.Resolve(item.Category)] or blacklist[item.Category] then return end
                    local _,rank=automationFlow.audit.rarity(item.Category)
                    if not rank then return end
                    local income=earnings.RatePerSecond(item)
                    if not sellRuleMatches(rule,rank,rankMax,income,threshold) then return end
                    return {uid=uid,category=item.Category,rank=rank,value=items.SalePrice(item),kind=kind}
                else
                    if raw.Placement~=nil then return end
                    local item=records.Decode(raw)
                    if protected[item.AssetCategory] then return end
                    local _,rank=automationFlow.audit.rarity(item.AssetCategory)
                    if not rank or rank>rankMax then return end
                    return {uid=uid,category=item.AssetCategory,rank=rank,value=records.SellPrice(item),kind=kind}
                end
            end)
            if ok and entry then result[#result+1]=entry end
        end
        table.sort(result,function(a,b) if a.rank~=b.rank then return a.rank<b.rank end; if a.value~=b.value then return a.value<b.value end; return a.uid<b.uid end)
        return result
    end
    local function available()
        return not automationFlow.selling and not automationFlow.placing and not automationFlow.fusing and not hatchOperationBusy and not (automationFlow.rift and automationFlow.rift.busy)
    end
    local function run(manual,kind)
        if not available() or paused or closed then return end
        automationFlow.selling=true
        local token,epoch=revision,automationFlow.epoch
        local sequence=not manual and sellWhen=="Sequence"
        task.spawn(function()
            local ok,err=pcall(function()
                local selected=manual and previews[kind] or nil
                if manual then previews[kind]=nil end
                local protected=eventSpecies()
                local save,count,maximum=inventory()
                if not manual and not sequence and count<math.ceil(maximum*0.9) then return end
                local payload={Assets={},Eggs={}}
                for _,typeName in ipairs(manual and {kind} or {"Pets","Eggs"}) do
                    if manual or (typeName=="Pets" and petOn) or (typeName=="Eggs" and eggOn) then
                        for _,entry in ipairs(candidates(typeName,save,protected)) do
                            if not manual or (selected and selected[entry.uid]) then
                                table.insert(typeName=="Pets" and payload.Assets or payload.Eggs,entry.uid)
                            end
                        end
                    end
                end
                if closed or token~=revision or (sequence and (automationFlow.phase~="selling" or epoch~=automationFlow.epoch)) then return end
                if #payload.Assets+#payload.Eggs==0 then note("No eligible items to sell; filters/protections retained"); return end
                note("Selling batch: "..#payload.Assets.." pets, "..#payload.Eggs.." eggs")
                local storage=game:GetService("ReplicatedStorage")
                require(storage.Shared.Remotes).PetSatchel.SellSelection:FireServer(payload)
                local deadline=os.clock()+12
                repeat
                    local current=require(storage.Shared.Save).Get()
                    if current and current.Inventory and current.EggInventory then
                        local remaining=0
                        for _,uid in ipairs(payload.Assets) do if current.Inventory[uid] then remaining=remaining+1 end end
                        for _,uid in ipairs(payload.Eggs) do if current.EggInventory[uid] then remaining=remaining+1 end end
                        if remaining==0 then note("Batch sold: "..#payload.Assets.." pets, "..#payload.Eggs.." eggs"); return end
                    end
                    task.wait(0.25)
                until closed or os.clock()>deadline
                error("Batch completion unconfirmed; no retry. Toggle Auto Sell OFF/ON after checking inventory")
            end)
            automationFlow.selling=false
            if not ok then paused=true; note("Paused: "..tostring(err)) end
            if sequence and automationFlow.phase=="selling" and epoch==automationFlow.epoch then flowPhase("idle","Sell stage complete") end
        end)
    end
    for _,entry in ipairs({{petNow,"Pets"},{eggNow,"Eggs"}}) do
        local control,kind=entry[1],entry[2]
        connect(control.Activated,function()
            if not available() then note("Wait for inventory work to finish"); return end
            if previews[kind] then run(true,kind); control.Text="Preview Sell "..kind; return end
            local ok,err=pcall(function()
                local protected=eventSpecies(); local list=candidates(kind,inventory(),protected); local ids={}; for _,item in ipairs(list) do ids[item.uid]=true end
                if #list==0 then note("No eligible "..kind); return end
                previews[kind]=ids; control.Text="Sell "..#list.." "..kind.." Now"
                note("Preview: "..#list.." eligible "..kind..". Click again to sell this set; filters and protections are rechecked.")
            end)
            if not ok then note(tostring(err)) end
        end)
    end
    task.spawn(function()
        while not closed do
            if automationFlow.phase=="selling" then
                if not automationFlow.selling and (paused or not automationFlow.sellSequence()) then
                    flowPhase("idle","Sell stage complete")
                elseif not paused and available() then run(false) end
            elseif sellWhen=="90% Capacity" and (petOn or eggOn) and not paused and available() then
                local ok,_,count,maximum=pcall(inventory)
                if ok and count>=math.ceil(maximum*0.9) then run(false) end
            end
            task.wait(2)
        end
    end)
    table.insert(cleanupActions,function() petOn=false; eggOn=false; revision=revision+1 end)
end)() end

-- Inventory Panel owns its cards, previews and connections separately from the hub.
do (function()
    local storage=game:GetService("ReplicatedStorage")
    local input=game:GetService("UserInputService")
    local options={Image=true,Name=true,Rarity=true,Mutation=true,Weight=true,WeightPercentage=true,Income=true,UID=true,Status=true,LivePreview=false}
    local activeTab,dirty,busy="Pets",true,false
    local sortBy="Rarity"
    local cards,cardConnections={},{}
    local signature
    local window=make("Frame",{Name="InventoryPanel",Visible=false,Active=true,ZIndex=50,
        BackgroundColor3=colors.panel,BorderSizePixel=0,AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(900,650)},gui)
    make("UICorner",{CornerRadius=UDim.new(0,12)},window)
    make("UIStroke",{Color=colors.accent,Transparency=0.45},window)
    local title=label("Inventory Panel",UDim2.fromOffset(18,0),UDim2.new(1,-70,0,48),window)
    title.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold); title.TextSize=20; title.Active=true
    local dismiss=button("X",UDim2.new(1,-44,0,10),UDim2.fromOffset(32,30),window)
    local status=label("Pets: click a card to load its UID into a fuse slot.",UDim2.fromOffset(18,90),UDim2.new(1,-36,0,44),window,true)
    status.TextSize=14
    local mutationCount=label("Mutation Consumables: —",UDim2.fromOffset(18,134),UDim2.new(1,-36,0,24),window)
    mutationCount.TextSize=14; mutationCount.Visible=false
    local function readMutationCount()
        local count=0
        local seen={}
        for _,container in ipairs({player.Backpack,player.Character or player.Backpack}) do
            for _,tool in ipairs(container:GetChildren()) do
                if not seen[tool] and tool:IsA("Tool") and tool:GetAttribute("ItemType")=="MutationConsumable" then
                    seen[tool]=true
                    local uses=tonumber(tool:GetAttribute("Uses"))
                    if not uses or uses<0 then return nil end
                    count=count+uses
                end
            end
        end
        return count
    end
    local fuseSide=make("ScrollingFrame",{Name="InventoryFuseSide",Position=UDim2.new(1,-516,0,92),Size=UDim2.new(0,500,1,-108),
        BackgroundColor3=Color3.fromRGB(17,22,30),BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y},window)
    make("UICorner",{CornerRadius=UDim.new(0,10)},fuseSide)
    local fuseBar=make("Frame",{Name="InventoryFuseSlots",Position=UDim2.fromOffset(10,12),Size=UDim2.new(1,-24,0,280),BackgroundTransparency=1},fuseSide)
    local slotViews={}
    for index=1,3 do
        local slot=make("Frame",{Position=UDim2.fromOffset(0,(index-1)*94),Size=UDim2.new(1,-128,0,86),BackgroundColor3=colors.card,BorderSizePixel=0},fuseBar)
        make("UICorner",{CornerRadius=UDim.new(0,8)},slot)
        local image=make("ImageLabel",{Position=UDim2.fromOffset(6,12),Size=UDim2.fromOffset(48,48),BackgroundTransparency=1,ScaleType=Enum.ScaleType.Fit},slot)
        local name=label("Slot "..index.." — Empty",UDim2.fromOffset(62,4),UDim2.new(1,-68,0,34),slot)
        name.TextSize=14
        local weight=label("",UDim2.fromOffset(62,38),UDim2.new(1,-68,0,22),slot,true)
        weight.TextSize=14
        local eject=button("Eject",UDim2.new(1,-66,1,-25),UDim2.fromOffset(60,22),slot)
        eject.TextSize=14
        label("SLOT "..index,UDim2.fromOffset(62,62),UDim2.new(1,-132,0,20),slot,true).TextSize=14
        slotViews[index]={image=image,name=name,weight=weight,eject=eject}
    end
    local fuseButton=button("Fuse",UDim2.new(1,-116,0,0),UDim2.fromOffset(116,42),fuseBar)
    fuseButton.BackgroundColor3=Color3.fromRGB(28,85,73)
    local ejectAllButton=button("Eject All",UDim2.new(1,-116,0,52),UDim2.fromOffset(116,38),fuseBar)
    local fuseCost=label("Load three matching pets",UDim2.new(1,-116,0,104),UDim2.fromOffset(116,100),fuseBar,true)
    fuseCost.TextSize=14
    local calculator=make("Frame",{Name="InventoryFuseCalculator",Position=UDim2.fromOffset(10,304),Size=UDim2.new(1,-24,0,100),BackgroundColor3=colors.card,BorderSizePixel=0},fuseSide)
    make("UICorner",{CornerRadius=UDim.new(0,8)},calculator)
    make("UIStroke",{Color=colors.accent,Transparency=0.7},calculator)
    label("Fuse Calculator",UDim2.fromOffset(12,8),UDim2.new(1,-24,0,28),calculator).TextSize=20
    local prediction=label("Load three matching pets to calculate odds.",UDim2.fromOffset(12,44),UDim2.new(1,-24,0,0),calculator)
    prediction.RichText=true; prediction.TextSize=14; prediction.AutomaticSize=Enum.AutomaticSize.Y; prediction.TextYAlignment=Enum.TextYAlignment.Top
    connect(prediction:GetPropertyChangedSignal("TextBounds"),function()
        calculator.Size=UDim2.new(1,-24,0,math.max(110,prediction.TextBounds.Y+60))
    end)
    local grid=make("ScrollingFrame",{Name="InventoryGrid",Position=UDim2.fromOffset(16,142),Size=UDim2.new(1,-32,1,-158),
        BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=5,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y},window)
    local gridContent=make("Frame",{Size=UDim2.fromOffset(1160,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1},grid)
    local layout=make("UIGridLayout",{CellSize=UDim2.fromOffset(210,332),CellPadding=UDim2.fromOffset(10,10),FillDirectionMaxCells=5,SortOrder=Enum.SortOrder.LayoutOrder},gridContent)
    grid.AutomaticCanvasSize=Enum.AutomaticSize.XY
    local settings=make("ScrollingFrame",{Name="InventorySettings",Visible=false,Position=grid.Position,Size=grid.Size,
        BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=5,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y},window)
    make("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},settings)
    local tabsHere={}
    local function clearCards()
        for _,connection in ipairs(cardConnections) do connection:Disconnect() end
        cardConnections={}
        for _,card in ipairs(cards) do card.frame:Destroy() end
        cards={}
    end
    local function fit()
        local camera=workspace.CurrentCamera
        local screen=camera and camera.ViewportSize or Vector2.new(960,720)
        window.Size=UDim2.fromOffset(math.max(700,math.min(1560,screen.X-32)),math.max(380,math.min(850,screen.Y-48)))
        local sideWidth=math.max(360,math.min(540,math.floor(window.Size.X.Offset*0.36)))
        local inset=activeTab=="Pets" and sideWidth+48 or 32
        local width=math.max(840,window.Size.X.Offset-inset-8)
        local columns=5
        gridContent.Size=UDim2.fromOffset(width,0)
        local lines=0
        for _,key in ipairs({"Name","Rarity","Mutation","Weight","WeightPercentage","Income"}) do if options[key] then lines=lines+1 end end
        local height=20+(options.Image and 142 or 0)+lines*22+(options.Name and 22 or 0)+(options.UID and 44 or 0)+(options.Status and 24 or 0)
        layout.CellSize=UDim2.fromOffset(math.floor((width-(columns-1)*10)/columns),math.max(84,height))
        fuseSide.Visible=activeTab=="Pets"
        fuseSide.Size=UDim2.new(0,sideWidth,1,-108)
        fuseSide.Position=UDim2.new(1,-sideWidth-16,0,92)
        local top=90
        status.Position=UDim2.fromOffset(18,top)
        status.Size=UDim2.new(1,-inset,0,44)
        local eggExtra=activeTab=="Eggs" and 28 or 0
        mutationCount.Visible=activeTab=="Eggs"
        grid.Position=UDim2.fromOffset(16,top+52+eggExtra)
        grid.Size=UDim2.new(1,-inset,1,-top-68-eggExtra)
    end
    for index,name in ipairs({"Pets","Eggs","Settings"}) do
        local tab=button(name,UDim2.new((index-1)/3,16-(index-1)*8,0,52),UDim2.new(1/3,-24,0,32),window)
        tabsHere[name]=tab
        connect(tab.Activated,function()
            activeTab=name; dirty=true; signature=nil; grid.CanvasPosition=Vector2.new()
            fit()
            grid.Visible=name~="Settings"; settings.Visible=name=="Settings"
            for key,control in pairs(tabsHere) do control.TextColor3=key==name and colors.accent or colors.text end
            status.Text=name=="Settings" and "Display preferences save with Config > Save settings. Weight Percentage: normal species weight = 100%." or
                (name=="Pets" and "Click a pet to load one fuse slot. This does not start fusion." or "Your owned eggs, including eggs growing in your pen.")
            clearCards()
        end)
    end
    tabsHere.Pets.TextColor3=colors.accent
    local sortOptions={"Rarity","Weight","Weight %","Income"}
    local function sortDropdown(title,key,initial,get,assign)
        local sortRow=row(settings,42)
        label(title,UDim2.fromOffset(10,0),UDim2.new(0.45,-10,0,42),sortRow)
        local sortControl=button(initial.."  v",UDim2.new(0.45,0,0,6),UDim2.new(0.55,-10,0,30),sortRow)
        local sortList=make("Frame",{Position=UDim2.fromOffset(10,48),Size=UDim2.new(1,-20,0,140),BackgroundTransparency=1,Visible=false},sortRow)
        make("UIListLayout",{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder},sortList)
        local function set(value)
            if not table.find(sortOptions,value) then return false end
            assign(value); sortControl.Text=value.."  v"; dirty=true
            sortList.Visible=false; sortRow.Size=UDim2.new(1,-6,0,42)
        end
        connect(sortControl.Activated,function()
            sortList.Visible=not sortList.Visible
            sortRow.Size=UDim2.new(1,-6,0,sortList.Visible and 194 or 42)
        end)
        for index,value in ipairs(sortOptions) do
            local choice=button(value,UDim2.new(),UDim2.new(1,0,0,30),sortList)
            choice.LayoutOrder=index
            connect(choice.Activated,function() set(value) end)
        end
        registerSetting(key,initial,get,set,function(value) return table.find(sortOptions,value)~=nil end)
    end
    sortDropdown("Sort By","InventoryPanel.SortBy","Rarity",function() return sortBy end,function(value) sortBy=value end)
    for _,spec in ipairs({{"Image","Show Pet Image"},{"Name","Show Name"},{"Rarity","Show Rarity"},{"Mutation","Show Mutation"},
        {"Weight","Show Weight"},{"WeightPercentage","Show Weight Percentage"},{"Income","Show Income"},{"UID","Show UID"},{"Status","Show Status"},{"LivePreview","Live 3D Preview"}}) do
        local key=spec[1]
        switch(settings,spec[2],options[key],function(value) options[key]=value; dirty=true; fit() end,nil,"InventoryPanel."..key)
    end
    label("Sorts highest first. 3D previews rotate the normal species model, including for mutated pets. Mutation details remain on the card.",
        UDim2.fromOffset(10,4),UDim2.new(1,-20,1,-8),row(settings,62),true).TextSize=14
    local openRow=row(othersPage,38)
    openRow.LayoutOrder=-10000
    local open=button("Inventory Panel",UDim2.new(),UDim2.new(1,0,1,0),openRow)
    open.TextSize=16
    connect(open.Activated,function() fit(); window.Visible=true; dirty=true end)
    connect(dismiss.Activated,function() window.Visible=false; clearCards(); signature=nil end)
    local dragStart,dragPosition
    connect(title.InputBegan,function(event)
        if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then
            dragStart=event.Position; dragPosition=window.Position
        end
    end)
    connect(input.InputEnded,function(event)
        if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then dragStart=nil end
    end)
    connect(input.InputChanged,function(event)
        if dragStart and (event.UserInputType==Enum.UserInputType.MouseMovement or event.UserInputType==Enum.UserInputType.Touch) then
            local delta=event.Position-dragStart
            window.Position=UDim2.new(dragPosition.X.Scale,dragPosition.X.Offset+delta.X,dragPosition.Y.Scale,dragPosition.Y.Offset+delta.Y)
        end
    end)
    -- INVENTORY LOAD VALIDATION START
    local function canLoadInventoryPet(save,uid)
        assert(type(save)=="table" and type(save.Inventory)=="table" and type(save.FusionSlots)=="table","Inventory or fuse slots unavailable")
        local item=assert(save.Inventory[uid],"Pet is no longer in your inventory")
        assert(not save.FusionLocked and save.FusionEggReward==false,"Finish the pending fuse first")
        assert(not item.IsFavorite and not item.InFuse,"Pet is favorite or already in the fuse machine")
        for _,equipped in pairs(save.EquippedAssets or {}) do assert(equipped~=uid,"Unequip this pet before loading it") end
        local count,category=0,nil
        for _,slot in pairs(save.FusionSlots) do
            if type(slot)=="string" and slot~="" then
                assert(slot~=uid,"Pet is already in a fuse slot")
                local loaded=assert(save.Inventory[slot],"Loaded pet data is unavailable")
                category=category or loaded.Category
                assert(category==loaded.Category,"Fuse slots contain incompatible categories")
                count=count+1
            end
        end
        assert(count<3,"All three fuse slots are full")
        assert(not category or category==item.Category,"All three pets must be the same species")
        return category
    end
    -- INVENTORY LOAD VALIDATION END
    local function manualReady()
        assert(not closed,"Hub closed")
        for _,key in ipairs({"Auto Fuse","Auto Sell Pets","Auto Sell Eggs","Steal Rift Pets","Auto Equip Best"}) do
            assert(not settingsBindings[key] or not settingsBindings[key].get(),"Turn OFF "..key.." before manually using fuse slots")
        end
        assert(not automationFlow.fusing and not automationFlow.selling and not (automationFlow.rift and automationFlow.rift.busy),"Wait for current inventory work to finish")
    end
    local function fuseSelection(save)
        assert(save and type(save.Inventory)=="table" and type(save.FusionSlots)=="table","Fuse data unavailable")
        assert(not save.FusionLocked and save.FusionEggReward==false,"Finish the pending fuse first")
        assert(save.FusionInfoAcknowledged,"Read and accept the game's fuse briefing first")
        local uids,items,seen={},{},{}
        local kernel=require(storage.Shared.Util.FuseKernel)
        for index=1,3 do
            local uid=save.FusionSlots[index]
            assert(type(uid)=="string" and uid~="" and not seen[uid],"Load three different pets of the same species")
            seen[uid]=true
            local item=assert(save.Inventory[uid],"Loaded pet data unavailable")
            for _,equipped in pairs(save.EquippedAssets or {}) do assert(equipped~=uid,"Unequip loaded pets before fusing") end
            local allowed,reason=kernel.MayEnterFuse(uid,item,items[1] and items[1].Category,true)
            assert(allowed,reason or "Loaded pet cannot be fused")
            uids[index]=uid; items[index]=require(storage.Shared.Util.AssetItems).Decode(item)
        end
        return uids,kernel.PriceFor(items)
    end
    local function machineAction(action)
        if busy then return end
        busy=true
        local ok,err=pcall(function() manualReady(); action() end)
        busy=false; dirty=true
        if not ok and not closed then status.Text=tostring(err) end
    end
    local function updateSlots()
        local save=assert(require(storage.Shared.Save).Get(),"Save unavailable")
        for index,view in ipairs(slotViews) do
            local uid=(save.FusionSlots or {})[index]
            local item=type(uid)=="string" and (save.Inventory or {})[uid] or nil
            view.eject.Visible=item~=nil
            if item then
                local name,_,color=Rarity.Resolve(item.Category)
                view.name.Text=name; view.name.TextColor3=color
                local decoded=require(storage.Shared.Util.AssetItems).Decode(item)
                view.weight.Text=string.format("%.0f kg",require(storage.Shared.Util.AssetItems).WeightKg(decoded))
                if view.uid~=uid then
                    pcall(function() require(storage.Client.UI.AssetIconShape).Paint(view.image,decoded) end)
                end
            else
                view.name.Text="Slot "..index.." — Empty"; view.name.TextColor3=colors.muted
                view.weight.Text=""; view.image.Image=""
                if view.uid then pcall(function() require(storage.Client.UI.AssetIconShape).Strip(view.image) end) end
            end
            view.uid=item and uid or nil
        end
        local ready,_,cost=pcall(fuseSelection,save)
        fuseButton.Text=busy and "Working..." or "Fuse"
        fuseButton.TextColor3=ready and colors.accent or colors.muted
        fuseCost.Text=ready and ("Cost: "..(Rarity.ESP.compact(cost) or tostring(cost))) or "Load three matching pets"
        prediction.Text=automationFlow.fuseCalculator and automationFlow.fuseCalculator() or "Calculator unavailable"
    end
    local function ejectUID(uid)
        manualReady()
        local save=require(storage.Shared.Save).Get()
        assert(save and not save.FusionLocked and save.FusionEggReward==false,"Finish the pending fuse first")
        local present=false
        for _,slot in pairs(save.FusionSlots or {}) do if slot==uid then present=true end end
        if not present then return false end
        local accepted,reason=require(storage.Shared.Remotes).Fusery.EjectPet:InvokeServer(uid)
        assert(accepted==true,reason or "Eject request denied")
        local deadline=os.clock()+8
        repeat
            local current=require(storage.Shared.Save).Get()
            if current and type(current.FusionSlots)=="table" then
                local remains=false
                for _,slot in pairs(current.FusionSlots) do if slot==uid then remains=true end end
                if not remains then return true end
            end
            task.wait(0.2)
        until closed or os.clock()>=deadline
        error("Eject accepted; slot update unconfirmed. No retry sent.")
    end
    connect(ejectAllButton.Activated,function()
        machineAction(function()
            local save=assert(require(storage.Shared.Save).Get(),"Save unavailable")
            local selected,seen={},{}
            for index=1,3 do
                local uid=(save.FusionSlots or {})[index]
                if type(uid)=="string" and uid~="" and not seen[uid] then selected[#selected+1]=uid; seen[uid]=true end
            end
            assert(#selected>0,"No pets in the fuse slots")
            local count=0
            for _,uid in ipairs(selected) do if ejectUID(uid) then count=count+1 end end
            status.Text="Ejected "..count.." pets from the fuse machine."
        end)
    end)
    for index,view in ipairs(slotViews) do
        connect(view.eject.Activated,function()
            local expected=view.uid
            machineAction(function()
                local save=require(storage.Shared.Save).Get()
                assert(expected and save and save.FusionSlots[index]==expected,"Slot changed; check it before ejecting")
                ejectUID(expected)
                status.Text="Pet ejected from slot "..index
            end)
        end)
    end
    connect(fuseButton.Activated,function()
        machineAction(function()
            local save=require(storage.Shared.Save).Get()
            local uids,cost=fuseSelection(save)
            assert(type(save.Money)=="number" and save.Money>=cost,"Not enough money to fuse these pets")
            local remotes=require(storage.Shared.Remotes).Fusery
            status.Text="Fusing the three loaded pets..."
            local accepted,reason,reward=remotes.BeginFuse:InvokeServer()
            assert(accepted==true,reason or "Fuse request denied")
            assert(require(storage.Shared.Types.FuseMachine).FuseResult(reward),"Fuse accepted; invalid reward response. Check the machine before trying again.")
            local finished,finishReason=remotes.FinishReveal:InvokeServer()
            assert(finished==true,finishReason or "Reward pending; finish the reveal in the game or Debug")
            local deadline=os.clock()+15
            repeat
                local current=require(storage.Shared.Save).Get()
                local consumed=current and type(current.Inventory)=="table"
                if consumed then for _,uid in ipairs(uids) do if current.Inventory[uid] then consumed=false end end end
                if consumed and not current.FusionLocked and current.FusionEggReward==false then
                    status.Text="Fuse completed; inputs consumed and reward completed."; return
                end
                task.wait(0.25)
            until closed or os.clock()>=deadline
            error("Fuse accepted; completion unconfirmed. Check the machine before another fuse. No retry sent.")
        end)
    end)
    local function loadPet(uid)
        if busy then return end
        busy=true
        local ok,err=pcall(function()
            manualReady()
            local save=require(storage.Shared.Save).Get()
            local category=canLoadInventoryPet(save,uid)
            local allowed,reason=require(storage.Shared.Util.FuseKernel).MayEnterFuse(uid,save.Inventory[uid],category,false)
            assert(allowed,reason or "This pet cannot enter the fuse machine")
            status.Text="Loading UID "..uid.." into one fuse slot..."
            local accepted,message=require(storage.Shared.Remotes).Fusery.LoadPet:InvokeServer(uid)
            assert(accepted==true,message or "LoadPet was not accepted")
            if not closed then status.Text="Loaded pet into a fuse slot: "..uid..". Fusion has not been started." end
        end)
        busy=false; dirty=true
        if not ok and not closed then status.Text=tostring(err) end
    end
    local function readInventory()
        local save=assert(require(storage.Shared.Save).Get(),"Save unavailable")
        local items=require(storage.Shared.Util.AssetItems)
        local records=require(storage.Shared.Util.EggRecords)
        local earnings=require(storage.Shared.Util.AssetEarnings)
        local directory=require(storage.Data.Assets).Directory
        local source=activeTab=="Pets" and save.Inventory or require(storage.Client.EggState).ReadOwnerEggs(player.UserId)
        assert(type(source)=="table","Inventory unavailable")
        local result,parts={},{}
        for uid,raw in pairs(source) do
            if type(raw)=="table" then
                local ok,entry=pcall(function()
                    -- EggState owner records already contain decoded placement CFrames.
                    local item=activeTab=="Pets" and items.Decode(raw) or records.ToAssetItemData(raw)
                    local config=assert(directory[item.Category],"Species missing from live directory")
                    local name,rarity,color=Rarity.Resolve(item.Category)
                    local _,rank=automationFlow.audit.rarity(item.Category)
                    local weight=items.WeightKg(item)
                    local normal=tonumber(config.ModelWeight)
                    local income=earnings.RatePerSecond(item)
                    local mutation=mutationNames(item.Mutations,item.BaseMutation)
                    local inSlot,equipped=false,false
                    for _,equippedUID in pairs(save.EquippedAssets or {}) do if equippedUID==uid then equipped=true end end
                    for _,slot in pairs(save.FusionSlots or {}) do if slot==uid then inSlot=true end end
                    return {uid=tostring(uid),item=item,name=name,rarity=rarity,rank=rank,color=color,weight=weight,
                        percent=normal and normal>0 and weight/normal*100 or nil,income=income,mutation=mutation,
                        inSlot=inSlot,equipped=equipped,placed=raw.Placement~=nil}
                end)
                if ok then
                    result[#result+1]=entry
                    parts[#parts+1]=table.concat({entry.uid,entry.name,entry.rarity,tostring(entry.weight),tostring(entry.income),entry.mutation,tostring(entry.inSlot),tostring(entry.placed),tostring(entry.equipped)},"|")
                else
                    result[#result+1]={uid=tostring(uid),name=tostring(raw.Category or raw.AssetCategory or "Pet"),error=tostring(entry),color=colors.muted}
                    parts[#parts+1]=tostring(uid)..tostring(entry)
                end
            end
        end
        table.sort(parts)
        local sortFields={Rarity="rank",Weight="weight",["Weight %"]="percent",Income="income"}
        local field=sortFields[sortBy] or "rank"
        table.sort(result,function(a,b)
            local av,bv=a[field] or -math.huge,b[field] or -math.huge
            if av~=bv then return av>bv end
            if a.name~=b.name then return a.name<b.name end
            return a.uid<b.uid
        end)
        return result,table.concat(parts,"\n")
    end
    local function build(entries)
        clearCards(); fit()
        for index,entry in ipairs(entries) do
            local card=button("",UDim2.new(),UDim2.new(),gridContent)
            card.LayoutOrder=index; card.Name="Inventory_"..entry.uid
            local stroke=make("UIStroke",{Color=entry.inSlot and colors.accent or entry.color,Thickness=entry.inSlot and 2 or 1,Transparency=0.35},card)
            local y=10
            local icon
            if options.Image then
                icon=make("ImageLabel",{Size=UDim2.new(1,-20,0,132),Position=UDim2.fromOffset(10,y),BackgroundTransparency=1,ScaleType=Enum.ScaleType.Fit},card)
                if entry.item then
                    local painted=pcall(function() require(storage.Client.UI.AssetIconShape).Paint(icon,entry.item) end)
                    if not painted then
                        pcall(function() icon.Image=require(storage.Data.Assets).Directory[entry.item.Category].Icon end)
                    end
                end
                y=y+142
            end
            local function line(text,color,wrap)
                local height=wrap and 44 or 22
                local textLabel=label(text,UDim2.fromOffset(10,y),UDim2.new(1,-20,0,height),card)
                textLabel.TextSize=14; textLabel.TextColor3=color or colors.text
                textLabel.TextTruncate=wrap and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd; textLabel.TextWrapped=wrap==true
                y=y+height
            end
            if options.Name then line(entry.name,entry.color,true) end
            if entry.error then line("Data unavailable",colors.muted)
            else
                if options.Rarity then line(entry.rarity,entry.color) end
                if options.Mutation then line(entry.mutation~="" and entry.mutation or "Normal",colors.muted) end
                if options.Weight then line(string.format("Weight: %.0f kg",entry.weight)) end
                if options.WeightPercentage then line("Weight: "..(entry.percent and string.format("%.0f%%",entry.percent) or "unavailable").." of normal") end
                if options.Income then line((Rarity.ESP.compact(entry.income) or "?").."/s",colors.accent) end
            end
            if options.UID then
                make("TextBox",{Text=entry.uid,ClearTextOnFocus=false,TextEditable=false,MultiLine=false,TextWrapped=true,
                    TextSize=14,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextColor3=colors.muted,BackgroundTransparency=1,Size=UDim2.new(1,-20,0,40),Position=UDim2.fromOffset(10,y)},card)
                y=y+44
            end
            if options.Status then line(activeTab=="Pets" and (entry.equipped and "Equipped" or "In Backpack") or (entry.placed and "In Pen" or "In Backpack"),colors.accent) end
            cards[#cards+1]={frame=card,icon=icon,entry=entry,stroke=stroke}
            if activeTab=="Pets" and not entry.error then
                cardConnections[#cardConnections+1]=card.Activated:Connect(function() loadPet(entry.uid) end)
            end
        end
        if #entries==0 then status.Text="No "..activeTab:lower().." in your inventory." end
    end
    local function updatePreviews()
        local visibleCount=0
        for _,card in ipairs(cards) do
            local top=card.frame.AbsolutePosition.Y
            local visible=options.Image and options.LivePreview and top+card.frame.AbsoluteSize.Y>grid.AbsolutePosition.Y and top<grid.AbsolutePosition.Y+grid.AbsoluteSize.Y
            if visible then visibleCount=visibleCount+1 end
            if not visible or visibleCount>24 then
                if card.viewport then card.viewport:Destroy(); card.viewport=nil end
                if card.icon then card.icon.Visible=true end
            elseif card.icon and not card.viewport and not card.previewUnavailable then
                local ok=pcall(function()
                    local entry=card.entry
                    assert(entry.item,"Pet data unavailable")
                    local models=assert(storage:FindFirstChild("AssetModels"),"Pet models unavailable")
                    local category=assert(models:FindFirstChild(entry.item.Category),"Species model unavailable")
                    local template=assert(category:FindFirstChild("Model"),"Preview template unavailable")
                    assert(template:IsA("Model"),"Preview template is not a model")
                    local viewport=make("ViewportFrame",{Size=card.icon.Size,Position=card.icon.Position,BackgroundTransparency=1,
                        Ambient=Color3.fromRGB(210,210,210),LightColor=Color3.new(1,1,1),LightDirection=Vector3.new(-1,-1,-1)},card.frame)
                    card.viewport=viewport
                    local world=make("WorldModel",{},viewport)
                    local model=template:Clone()
                    for _,object in ipairs(model:GetDescendants()) do
                        if object:IsA("LuaSourceContainer") then object:Destroy()
                        elseif object:IsA("BasePart") then object.Anchored=true; object.CanCollide=false end
                    end
                    model.Parent=world
                    local frame,size=model:GetBoundingBox()
                    local camera=make("Camera",{FieldOfView=35},viewport)
                    viewport.CurrentCamera=camera
                    card.center=frame.Position; card.radius=math.max(size.X,size.Y,size.Z)*1.9; card.camera=camera
                    card.icon.Visible=false
                end)
                if not ok then
                    card.previewUnavailable=true
                    if card.viewport then card.viewport:Destroy(); card.viewport=nil end
                    card.icon.Visible=true
                end
            end
            if card.viewport then
                local angle=os.clock()*0.35
                local offset=Vector3.new(math.sin(angle),0.3,math.cos(angle))*card.radius
                card.camera.CFrame=CFrame.lookAt(card.center+offset,card.center)
            end
        end
    end
    task.spawn(function()
        local nextRead=0
        while not closed do
            if window.Visible and activeTab~="Settings" then
                if dirty or os.clock()>=nextRead then
                    if activeTab=="Pets" then
                        local slotsOK,slotsError=pcall(updateSlots)
                        if not slotsOK then status.Text="Fuse slots unavailable: "..tostring(slotsError) end
                    end
                    if activeTab=="Eggs" then
                        local ok,count=pcall(readMutationCount)
                        mutationCount.Text="Mutation Consumables: "..(ok and count and tostring(count) or "unavailable")
                    end
                    local ok,entries,newSignature=pcall(readInventory)
                    if ok then
                        if dirty or signature~=newSignature then
                            local built,buildError=pcall(build,entries)
                            if built then signature=newSignature
                            else clearCards(); signature=nil; status.Text="Panel display unavailable: "..tostring(buildError) end
                        end
                    else status.Text="Inventory unavailable: "..tostring(entries) end
                    dirty=false; nextRead=os.clock()+2
                end
                local previewOK,previewError=pcall(updatePreviews)
                if not previewOK then status.Text="Preview unavailable: "..tostring(previewError) end
            end
            task.wait(0.1)
        end
    end)
    table.insert(cleanupActions,clearCards)
end)() end

-- Manual arena diagnostics and a bounded, single-crystal experiment.
do (function()
    local order=-1100
    local function r(h) local frame=row(debugPage,h); frame.LayoutOrder=order; order=order+1; return frame end
    label("Boss — Live / One Crystal Test",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),r(38)).TextSize=20
    local observing=false
    local live=label("Enable Boss Live Readout after entering the arena.",UDim2.fromOffset(10,4),UDim2.new(1,-20,1,-8),r(190),true)
    live.TextSize=14; live.TextYAlignment=Enum.TextYAlignment.Top
    local toggle=button("Boss Live Readout: OFF",UDim2.new(),UDim2.new(1,0,1,0),r(38))
    local preview=button("Preview Nearest Living Crystal",UDim2.new(),UDim2.new(1,0,1,0),r(38))
    local runButton=button("Approach + Test One Crystal",UDim2.new(),UDim2.new(1,0,1,0),r(38))
    local stopButton=button("Stop Boss Test",UDim2.new(),UDim2.new(1,0,1,0),r(38))
    local copyButton=button("Copy Boss Test Report",UDim2.new(),UDim2.new(1,0,1,0),r(38))
    local status=label("Enter manually, enable live readout, preview a crystal, then test. Uses normal movement and bat activation. Stops on HP loss; dodge manually. No automatic entry, hand attacks or return yet.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),r(115),true)
    status.TextSize=14
    local lines={"AcidHub One Crystal Test"}
    local active=false
    local running=false
    local selected,selectedAt=nil,0
    local controlledHumanoid,controlledRoot,usedTool=nil,nil,nil
    local function note(message)
        lines[#lines+1]=os.date("%H:%M:%S").." | "..message
        if #lines>250 then table.remove(lines,2) end
        status.Text=message
    end
    local function conflict()
        for _,key in ipairs({"AutoStealEnabled","Auto Place Eggs","Auto Treadmill","Auto Hatch","Auto Equip Best","Auto Fuse","Steal Rift Pets","Auto Sell Pets","Auto Sell Eggs"}) do
            if settingsBindings[key] and settingsBindings[key].get() then return true end
        end
        return baseTravelActive or treadmillExitBusy or automationFlow.collecting or automationFlow.placing or automationFlow.fusing or automationFlow.selling or (automationFlow.rift and automationFlow.rift.busy)
    end
    local function characterParts()
        local character=player.Character
        return character,character and movementHumanoid(character),character and character:FindFirstChild("HumanoidRootPart")
    end
    local function arena() return workspace:FindFirstChild("BossArena",true) end
    local function crystals(model)
        local result={}
        local folder=model and model:FindFirstChild("CrystalTowers")
        if folder then for _,tower in ipairs(folder:GetChildren()) do
            local hit=tower:FindFirstChild("Hitbox")
            if hit and hit:IsA("BasePart") then result[#result+1]=hit end
        end end
        return result
    end
    local function bat(character)
        for _,container in ipairs({character,player:FindFirstChild("Backpack")}) do
            if container then for _,tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and tool:GetAttribute("IsBat")==true then return tool end
            end end
        end
    end
    local function stop(reason)
        if not active then return end
        active=false
        if usedTool then pcall(function() usedTool:Deactivate() end) end
        if controlledHumanoid and controlledRoot and controlledRoot.Parent then
            pcall(function() controlledHumanoid:Move(Vector3.zero,false); controlledHumanoid:MoveTo(controlledRoot.Position) end)
        end
        controlledHumanoid=nil; controlledRoot=nil; usedTool=nil
        note(reason)
    end
    -- CRYSTAL STANDOFF BEGIN
    local function crystalRadius(halfX,halfZ,dx,dz)
        return math.min(math.abs(dx)>0.0001 and halfX/math.abs(dx) or math.huge,
            math.abs(dz)>0.0001 and halfZ/math.abs(dz) or math.huge)
    end
    -- CRYSTAL STANDOFF END
    local function approachPoint(hit,position)
        local away=Vector3.new(position.X-hit.Position.X,0,position.Z-hit.Position.Z)
        local direction=away.Magnitude>0.01 and away.Unit or Vector3.new(1,0,0)
        local localDirection=hit.CFrame:VectorToObjectSpace(direction)
        local radius=crystalRadius(hit.Size.X/2,hit.Size.Z/2,localDirection.X,localDirection.Z)
        local goal=Vector3.new(hit.Position.X,position.Y,hit.Position.Z)+direction*(radius+6)
        local relative=hit.CFrame:PointToObjectSpace(position)
        local half=hit.Size/2
        local nearest=Vector3.new(math.clamp(relative.X,-half.X,half.X),math.clamp(relative.Y,-half.Y,half.Y),math.clamp(relative.Z,-half.Z,half.Z))
        local edgeDistance=(position-hit.CFrame:PointToWorldSpace(nearest)).Magnitude
        return goal,edgeDistance,away.Magnitude>=radius+3
    end
    -- BOSS TEST GUARD BEGIN
    local function crystalStopReason(info)
        if info.conflict then return "Automation started; test stopped" end
        if not info.inside then return "Left boss arena" end
        if not info.sameCharacter or info.hp<=0 then return "Character changed or died" end
        if info.hp<info.initialHP then return "HP dropped; move away from hazards manually" end
        if not info.targetPresent then return "Selected crystal removed; no next target" end
        if type(info.targetHP)~="number" then return "Crystal health unavailable" end
        if info.targetHP<=0 then return "Selected crystal depleted (shared damage); no next target" end
        if info.elapsed>=60 then return "60-second test limit" end
        if info.stalled>=8 then return "No movement/health progress for 8s; test stopped" end
        return nil
    end
    -- BOSS TEST GUARD END
    connect(toggle.Activated,function() observing=not observing; toggle.Text="Boss Live Readout: "..(observing and "ON" or "OFF") end)
    connect(preview.Activated,function()
        if active or running or (automationFlow.bossTestActive and automationFlow.bossTestActive()) then return end
        selected=nil
        local _,humanoid,root=characterParts()
        if player:GetAttribute("InBossArena")~=true or not root or not humanoid or humanoid.Health<=0 then note("Enter the arena manually first"); return end
        local distance=math.huge
        for _,hit in ipairs(crystals(arena())) do
            local health=hit:GetAttribute("Health")
            if type(health)=="number" and health>0 and (hit.Position-root.Position).Magnitude<distance then
                selected=hit; distance=(hit.Position-root.Position).Magnitude
            end
        end
        selectedAt=os.clock()
        if selected then note(string.format("Selected %s | Health %s | %.1f studs. Test approaches and attacks ONLY this crystal.",selected.Parent.Name,tostring(selected:GetAttribute("Health")),distance))
        else note("No living crystal found") end
    end)
    connect(runButton.Activated,function()
        if active or running or (automationFlow.bossTestActive and automationFlow.bossTestActive()) then return end
        if conflict() then note("Turn movement/inventory automations OFF and wait for current work to finish"); return end
        if not selected or os.clock()-selectedAt>30 then note("Preview a living crystal first (valid for 30s)"); return end
        local character,humanoid,root=characterParts()
        local model=arena()
        if player:GetAttribute("InBossArena")~=true or not model or not selected:IsDescendantOf(model) or not root or not humanoid or humanoid.Health<=0 then note("Character or selected crystal unavailable in arena"); return end
        local tool=bat(character)
        if not tool then note("No owned tool with IsBat=true found"); return end
        local target=selected; selected=nil
        active=true; running=true; controlledHumanoid=humanoid; controlledRoot=root; usedTool=tool
        local initialHP=humanoid.Health
        note("START | "..target:GetFullName().." | tool="..tool.Name.." | interval>=0.7s")
        task.spawn(function()
            local ok,err=pcall(function()
                humanoid:EquipTool(tool)
                local equipDeadline=os.clock()+2
                while active and tool.Parent~=character and os.clock()<equipDeadline do task.wait(0.1) end
                if not active then return end
                assert(tool.Parent==character,"Bat did not equip")
                local started=os.clock()
                local progress=started
                local best=math.huge
                local lastHP=target:GetAttribute("Health")
                local lastSwing,lastMove=-math.huge,-math.huge
                local swings=0
                local ownHits=tonumber(player:GetAttribute("BossCrystalHits")) or 0
                while active and not closed do
                    local now=os.clock()
                    local hp=target:GetAttribute("Health")
                    local destination,distance,outside=approachPoint(target,root.Position)
                    local travelDistance=(destination-root.Position).Magnitude
                    if travelDistance<best-1 then best=travelDistance; progress=now end
                    if hp~=lastHP then note("Crystal health "..tostring(lastHP).." -> "..tostring(hp).." (all players)"); lastHP=hp; progress=now end
                    local reason=crystalStopReason({conflict=conflict(),inside=player:GetAttribute("InBossArena")==true,sameCharacter=player.Character==character and root.Parent==character,
                        hp=humanoid.Health,initialHP=initialHP,targetPresent=target:IsDescendantOf(model),targetHP=hp,elapsed=now-started,stalled=now-progress})
                    if reason then stop(reason); break end
                    if tool.Parent~=character then stop("Bat unequipped; test stopped"); break end
                    if distance>10 or not outside then
                        if now-started>20 and swings==0 then stop("Approach timed out; reposition manually"); break end
                        if now-lastMove>=0.4 then
                            humanoid:MoveTo(destination)
                            lastMove=now
                        end
                    else
                        humanoid:Move(Vector3.zero,false); humanoid:MoveTo(root.Position)
                        local cooldown=tonumber(tool:GetAttribute("CooldownEndTime")) or 0
                        if now-lastSwing>=0.7 and workspace:GetServerTimeNow()>=cooldown and tool:GetAttribute("CooldownActive")~=true then
                            lastSwing=now; tool:Activate(); tool:Deactivate(); swings=swings+1
                            note("Swing "..swings..string.format(" | edge distance=%.1f studs",distance).." | crystal health="..tostring(hp).." | your crystal hits="..tostring(player:GetAttribute("BossCrystalHits")))
                        end
                    end
                    task.wait(0.1)
                end
                note("END | swings="..swings.." | your hit-count change="..((tonumber(player:GetAttribute("BossCrystalHits")) or ownHits)-ownHits).." | final crystal health="..tostring(target:GetAttribute("Health")))
            end)
            if not ok then stop("Test error: "..tostring(err)) end
            if active then stop("Test finished") end
            running=false
        end)
    end)
    connect(stopButton.Activated,function() stop("Stopped by user") end)
    connect(stopAll.Activated,function() stop("Stopped by Stop All") end)
    connect(player.CharacterRemoving,function() stop("Character removed") end)
    connect(copyButton.Activated,function()
        local ok=type(setclipboard)=="function" and pcall(setclipboard,table.concat(lines,"\n"))
        status.Text=ok and "Boss test report copied" or "Clipboard unavailable"
    end)
    table.insert(cleanupActions,function() observing=false; stop("Hub closed") end)
    task.spawn(function()
        while not closed do
            if observing then
                local ok,text=pcall(function()
                    local character,humanoid,root=characterParts()
                    local model=arena()
                    local boss=model and model:FindFirstChild("Boss")
                    local hand=boss and boss:FindFirstChild("UpperHand1.R",true)
                    local tool=character and bat(character)
                    local details={"In arena: "..tostring(player:GetAttribute("InBossArena")==true).." | HP: "..(humanoid and tostring(math.floor(humanoid.Health)) or "unavailable")}
                    if boss then details[#details+1]="Spawning: "..tostring(boss:GetAttribute("Spawning")).." | Attacking: "..tostring(boss:GetAttribute("Attacking")).." | PhaseTwoAt: "..tostring(boss:GetAttribute("PhaseTwoAt")) end
                    if hand and hand:IsA("Bone") then local p=hand.TransformedWorldCFrame.Position; details[#details+1]=string.format("Hand XYZ: %.1f, %.1f, %.1f | Health UI: %s",p.X,p.Y,p.Z,tostring(hand:FindFirstChild("Health")~=nil)) end
                    details[#details+1]="Bat: "..(tool and tool.Name or "unavailable").." | cooldown: "..string.format("%.2fs",tool and math.max(0,(tonumber(tool:GetAttribute("CooldownEndTime")) or 0)-workspace:GetServerTimeNow()) or 0)
                    for _,hit in ipairs(crystals(model)) do details[#details+1]=hit.Parent.Name..": Health "..tostring(hit:GetAttribute("Health"))..(root and string.format(" | %.0f studs",(hit.Position-root.Position).Magnitude) or "") end
                    return table.concat(details,"\n")
                end)
                live.Text=ok and text or "Boss read unavailable: "..tostring(text)
            end
            task.wait(0.5)
        end
    end)
    -- Combined boss run. Reuses the verified readers and edge-based crystal approach.
    do
        local eventPage
        for _,tab in ipairs(tabs) do if tab.name=="Events" then eventPage=tab.page.TheRiftSection.RiftSettings end end
        local enabled,enterEnabled,returnEnabled=false,false,false
        local route,routeGoal,routeIndex,routeAt=nil,nil,1,0
        local routeBlocked,routeLink=false,nil
        local aimIndex,lookAt,checkAt=nil,0,0
        local crystalTarget,crystalGoal=nil,nil
        local crystalSide=0
        local attackTarget=nil
        local arrivalPart=nil
        local meteorMemory={}
        local dodgeGoal,dodgeQuietAt,dodgeRetryAt=nil,nil,0
        local routePosition=nil
        local restoreTraps=false
        local pausedSettings=nil
        local pausedPhase,pausedEpoch,pausedPending=nil,nil,nil
        local meteorCache,meteorCacheAt={},0
        local owner,entryWindow,lastSwing=nil,nil,-math.huge
        local remoteJob,entryPending=nil,false
        local entryToken=0
        local runEpoch=0
        local wasInside=false
        local handLast,handStable=nil,0
        local slamUntil=0
        local blacklist={}
        local movingSince,bestWaypoint=0,math.huge
        local lastState=""
        local healthState=nil
        local lastHitProgress,lastHitCount=0,0
        local lastReportWrite=0
        local bossStatus=label("Boss run OFF. Use Boss Capture for the next full test.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(eventPage,78),true)
        bossStatus.TextSize=14
        local function say(message)
            bossStatus.Text=message
            if message~=lastState then lastState=message; note("BOSS RUN | "..message) end
        end
        -- BOSS RECOVERY POLICY BEGIN
        local function validBossSegment(distance)
            return distance==distance and distance>=0 and distance<=512
        end
        local function attackHold(distance,holding,enterRange,exitRange)
            return distance<=(holding and exitRange or enterRange)
        end
        -- BOSS RECOVERY POLICY END
        local function halt()
            route=nil; routeGoal=nil; aimIndex=nil; lookAt=0; checkAt=0
            if routeLink then routeLink:Disconnect(); routeLink=nil end
            local _,h,root=characterParts()
            if h and root then pcall(function()
                h:Move(Vector3.zero,false); h:MoveTo(root.Position)
                if owner==player.Character and player:GetAttribute("InBossArena")==true and h.Health>0 and h.FloorMaterial~=Enum.Material.Air then
                    local velocity=root.AssemblyLinearVelocity
                    root.AssemblyLinearVelocity=Vector3.new(0,velocity.Y,0)
                end
            end) end
        end
        local function invalidateArenaRoute()
            runEpoch=runEpoch+1; arrivalPart=nil; dodgeGoal=nil; dodgeQuietAt=nil; attackTarget=nil; routePosition=nil
            halt()
        end
        connect(player:GetAttributeChangedSignal("InBossArena"),invalidateArenaRoute)
        connect(player.CharacterRemoving,invalidateArenaRoute)
        local function restoreTouchSetting()
            if restoreTraps then
                restoreTraps=false
                local binding=settingsBindings["No Traps"]
                if binding then pcall(binding.set,true) end
            end
        end
        local pauseKeys={"Auto Place Eggs","Auto Treadmill","Auto Hatch","Auto Equip Best","Auto Fuse","Steal Rift Pets","Auto Sell Pets","Auto Sell Eggs","Auto Buy Trail","Auto Upgrade Base","Auto Upgrade Treadmill","Auto Claim","AutoStealEnabled"}
        local function discardResume()
            pausedSettings=nil; automationFlow.bossPauseRequested=false
        end
        local function resumeAutomations()
            if not pausedSettings or closed or player:GetAttribute("InBossArena")==true then return end
            local saved=pausedSettings; pausedSettings=nil; automationFlow.bossPauseRequested=false
            local failures={}
            for _,key in ipairs(pauseKeys) do
                if saved[key] then
                    local binding=settingsBindings[key]
                    local ok,result=pcall(function() return binding and binding.set(true) end)
                    if not ok or result==false or not binding then failures[#failures+1]=key end
                end
            end
            if pausedEpoch==automationFlow.epoch and pausedPhase then
                automationFlow.pendingDay=pausedPending
                -- Re-read live work when resuming rather than treating an interrupted stage as complete.
                if pausedPhase=="stealing" or pausedPhase=="preparing" then
                    if saved.AutoStealEnabled then
                        local ok,night=pcall(readAutomationDay)
                        if ok and not night then flowPhase("preparing","Resuming after boss")
                        else automationFlow.pendingDay=false; flowPhase("processing","Finishing work after boss") end
                    end
                elseif pausedPhase~="idle" then flowPhase("processing","Rechecking work after boss") end
            end
            say(#failures==0 and "Lobby reached; previous automations resumed" or "Resume failed: "..table.concat(failures,", "))
        end
        local function pauseAutomations()
            if not pausedSettings then
                pausedSettings={}; pausedPhase=automationFlow.phase; pausedEpoch=automationFlow.epoch; pausedPending=automationFlow.pendingDay
                for _,key in ipairs(pauseKeys) do local binding=settingsBindings[key]; pausedSettings[key]=binding and binding.get()==true or false end
                automationFlow.bossPauseRequested=true
                note("BOSS PAUSE | Remembered enabled automations; waiting for current actions")
            end
            for _,key in ipairs(pauseKeys) do
                local binding=settingsBindings[key]
                if binding and binding.get() and not (key=="AutoStealEnabled" and automationFlow.collecting and player:GetAttribute("InBossArena")~=true) then
                    local ok,result=pcall(binding.set,false)
                    if not ok or result==false then say("Waiting to pause "..key); return false end
                end
            end
            if conflict() then say("Boss pending: finishing delivery / active work / treadmill exit"); return false end
            if player:GetAttribute("InBossArena")==true then return true end
            local ok,carrying=pcall(function()
                local snapshot=require(game:GetService("ReplicatedStorage").Client.EggState).ReadFieldEggs()
                assert(type(snapshot)=="table" and type(snapshot.Records)=="table","Field snapshot unavailable")
                for _,egg in pairs(snapshot.Records) do if tonumber(egg.CarrierUserId)==player.UserId then return true end end
                return false
            end)
            if not ok or carrying then say(ok and carrying and "Boss pending: deliver the carried egg first" or "Boss pending: cannot verify empty hands"); return false end
            local _,h,root=characterParts()
            if not h or not root or h.Health<=0 or root.Anchored or treadmillExitBusy then say("Boss pending: waiting for character / treadmill exit"); return false end
            return true
        end
        local function disable(reason)
            arrivalPart=nil; dodgeGoal=nil; dodgeQuietAt=nil; attackTarget=nil
            restoreTouchSetting()
            enabled=false; runEpoch=runEpoch+1; entryToken=entryToken+1; halt(); say(reason)
            if type(writefile)=="function" then pcall(writefile,"AcidHub_Boss_Run.txt",table.concat(lines,"\n")) end
            if remoteJob then pcall(task.cancel,remoteJob); remoteJob=nil end
            entryPending=false
            if closed then discardResume() elseif player:GetAttribute("InBossArena")~=true then resumeAutomations() end
        end
        local function trapsOn() return settingsBindings["No Traps"] and settingsBindings["No Traps"].get() end
        switch(eventPage,"Auto Enter Boss",false,function(v) enterEnabled=v end,"One entry request per opening; arrival must be confirmed. Used only while Auto Fight Boss is ON.")
        switch(eventPage,"Auto Return From Boss",false,function(v) returnEnabled=v end,"After confirmed defeat or event closure, pathfind to the arena's return portal.")
        switch(eventPage,"Auto Fight Boss",false,function(v)
            if v and (active or running) then say("Stop the one-crystal test first"); return false end
            runEpoch=runEpoch+1; enabled=v; crystalTarget=nil; crystalGoal=nil; entryWindow=nil; owner=nil; blacklist={}; healthState=nil; wasInside=false; handLast=nil; handStable=os.clock()
            if not v then disable("Boss run OFF") else observing=true; toggle.Text="Boss Live Readout: ON"; say("Boss run enabled; waiting for arena/event") end
        end,"Full test: crystals, exposed hand, comet avoidance and respawn recovery. Other combat hazards are ignored. Normal automations pause for the boss and resume on lobby return. No Traps may stay ON during combat; temporarily restored for the return portal. Ground-checked pathfinding; no straight-line fallback.")
        local function turnOff(reason)
            disable(reason)
            local binding=settingsBindings["Auto Fight Boss"]; if binding then binding.set(false) end
            say(reason)
        end
        automationFlow.bossTestActive=function() return enabled end
        -- BOSS PHASE BEGIN
        local function bossPhase(inside,alive,finished,crystalCount,handReady)
            if not inside then return "outside" end
            if not alive then return "respawn" end
            if finished then return "return" end
            if crystalCount>0 then return "crystals" end
            if handReady then return "hand" end
            return "avoid"
        end
        -- BOSS PHASE END
        local function ground(point,character)
            local params=RaycastParams.new()
            params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={character}
            params.RespectCanCollide=true
            local hit=workspace:Raycast(point+Vector3.new(0,5,0),Vector3.new(0,-15,0),params)
            if not hit or hit.Normal.Y<0.7 then return nil end
            -- Refuse lower pit floors and steep ledges, rather than treating them as support.
            if point.Y-hit.Position.Y>7 or hit.Position.Y-point.Y>3 then return nil end
            return hit.Position
        end
        -- METEOR POLICY BEGIN
        local function meteorPenalty(dx,dz,diameter)
            local distance=math.sqrt(dx*dx+dz*dz)
            local radius=diameter/2+6
            return distance<radius and (radius-distance+1) or 0
        end
        -- METEOR POLICY END
        local function hazardCost(point)
            if os.clock()-meteorCacheAt>0.1 then
                meteorCacheAt=os.clock(); meteorCache={}
                local model=arena()
                if model then for _,part in ipairs(model:GetChildren()) do
                    if part:IsA("BasePart") and part.Name=="MeteorIndicator" and part.Transparency<0.95 then
                        meteorMemory[part]={position=part.Position,diameter=math.max(part.Size.X,part.Size.Y,part.Size.Z),seen=os.clock()}
                    end
                end end
                for part,marker in pairs(meteorMemory) do
                    if os.clock()-marker.seen<=1.5 then meteorCache[#meteorCache+1]=marker else meteorMemory[part]=nil end
                end
            end
            local cost=0
            for _,marker in ipairs(meteorCache) do
                cost=cost+meteorPenalty(point.X-marker.position.X,point.Z-marker.position.Z,marker.diameter)
            end
            return cost
        end
        local function segmentSafe(a,b,character,escaping)
            local delta=b-a
            local horizontal=Vector3.new(delta.X,0,delta.Z)
            local side=horizontal.Magnitude>0.01 and Vector3.new(-horizontal.Z,0,horizontal.X).Unit*3 or Vector3.new(3,0,0)
            local initial=hazardCost(a)
            for step=0,math.max(1,math.ceil(delta.Magnitude/3)) do
                local fraction=step/math.max(1,math.ceil(delta.Magnitude/3))
                local point=a:Lerp(b,fraction)
                if not ground(point,character) or not ground(point+side,character) or not ground(point-side,character) then return false end
                local cost=hazardCost(point)
                if cost>0 and (not escaping or cost>initial+0.1) then return false end
            end
            return true
        end
        -- BOSS SMOOTH POLICY BEGIN
        local function farthestClear(first,last,clear)
            for index=last,first,-1 do if clear(index) then return index end end
            return nil
        end
        local function bossCombatReady(open,exists,spawning,spawnsAt,now,healthInitialized)
            return open==true and exists and spawning~=true and (spawning==false or healthInitialized==true) and (type(spawnsAt)~="number" or now>=spawnsAt)
        end
        -- BOSS SMOOTH POLICY END
        local function clearTravel(a,b,character,escaping)
            local delta=b-a
            if not validBossSegment(delta.Magnitude) then return false end
            if delta.Magnitude<0.1 then return true end
            local params=RaycastParams.new()
            params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={character}; params.RespectCanCollide=true
            local obstacle=workspace:Blockcast(CFrame.new(a+Vector3.new(0,1,0)),Vector3.new(5,4,5),delta,params)
            if obstacle then return false end
            return segmentSafe(a,b,character,escaping)
        end
        -- BOSS LEG BEGIN
        local function bossLegOffsets(dx,dz)
            local distance=math.sqrt(dx*dx+dz*dz)
            if distance<0.01 then return {{dx,dz}} end
            local result={}
            if distance<=480 then result[#result+1]={dx,dz} end
            local length=math.min(480,distance*0.65)
            for _,angle in ipairs({0,math.pi/6,-math.pi/6,math.pi/3,-math.pi/3}) do
                local x=(dx*math.cos(angle)-dz*math.sin(angle))/distance*length
                local z=(dx*math.sin(angle)+dz*math.cos(angle))/distance*length
                if math.sqrt((dx-x)^2+(dz-z)^2)<distance-0.01 then result[#result+1]={x,z} end
            end
            return result
        end
        -- BOSS LEG END
        -- ARENA SEARCH BEGIN
        local function arenaSearch(sx,sz,gx,gz,step,clear,checkpoint)
            -- Bounded A*: unlike greedy legs, allow sideways/backward travel around a pit.
            local nodes,open={},{}
            local function key(x,z) return x..":"..z end
            local function push(node)
                open[#open+1]={node=node,score=node.score,g=node.g}
                local i=#open
                while i>1 do
                    local parent=math.floor(i/2)
                    if open[parent].score<=open[i].score then break end
                    open[parent],open[i]=open[i],open[parent]; i=parent
                end
            end
            local function pop()
                local first=open[1]; local last=table.remove(open)
                if #open>0 then
                    open[1]=last; local i=1
                    while i*2<=#open do
                        local child=i*2
                        if child<#open and open[child+1].score<open[child].score then child=child+1 end
                        if open[i].score<=open[child].score then break end
                        open[i],open[child]=open[child],open[i]; i=child
                    end
                end
                return first
            end
            local function distance(x,z) return math.sqrt((gx-x)^2+(gz-z)^2) end
            local start={x=sx,z=sz,ix=0,iz=0,g=0,score=distance(sx,sz)}
            nodes[key(0,0)]=start; push(start)
            local expanded=0
            while #open>0 and expanded<1800 do
                local entry=pop(); local current=entry.node
                if not current.closed and entry.g==current.g then
                    if expanded%24==0 and not checkpoint() then return nil,"cancelled" end
                    expanded=expanded+1; current.closed=true
                    if distance(current.x,current.z)<=96 and clear(current.x,current.z,gx,gz) then
                        local result={{gx,gz}}
                        while current do table.insert(result,1,{current.x,current.z}); current=current.parent end
                        return result,"search nodes="..expanded
                    end
                    for dx=-1,1 do for dz=-1,1 do
                        if dx~=0 or dz~=0 then
                            local ix,iz=current.ix+dx,current.iz+dz
                            local x,z=sx+ix*step,sz+iz*step
                            if x>=math.min(sx,gx)-256 and x<=math.max(sx,gx)+256 and z>=math.min(sz,gz)-256 and z<=math.max(sz,gz)+256 then
                                local id=key(ix,iz); local node=nodes[id]
                                local cost=current.g+step*math.sqrt(dx*dx+dz*dz)
                                if (not node or not node.closed and cost<node.g) and clear(current.x,current.z,x,z) then
                                    node=node or {x=x,z=z,ix=ix,iz=iz}; nodes[id]=node
                                    node.g=cost; node.score=cost+distance(x,z); node.parent=current; push(node)
                                end
                            end
                        end
                    end end
                end
            end
            return nil,"ground-checked search exhausted ("..expanded.." nodes)"
        end
        -- ARENA SEARCH END
        local useArenaSearch=false
        local function navigate(destination,character,h,root,escaping)
            if not enabled or player:GetAttribute("InBossArena")~=true or player.Character~=character then halt(); return "cancelled" end
            if routePosition and (root.Position-routePosition).Magnitude>512 then invalidateArenaRoute(); return "cancelled after relocation" end
            routePosition=root.Position
            if routeGoal and (routeGoal-destination).Magnitude>8 then halt() end
            if routeBlocked then halt(); routeBlocked=false end
            if not route then
                if os.clock()-routeAt<0.15 then return "waiting" end
                routeAt=os.clock()
                local version=runEpoch
                local origin=root.Position
                local delta=destination-origin
                local clearance=math.max(2,math.min(4,h.HipHeight+root.Size.Y/2))
                local function valid()
                    return enabled and version==runEpoch and player.Character==character and player:GetAttribute("InBossArena")==true and h.Health>0 and (root.Position-origin).Magnitude<=64
                end
                local function setRoute(points)
                    route=points; routeGoal=destination; routeIndex=2; aimIndex=nil
                    bestWaypoint=math.huge; movingSince=os.clock()
                end
                if clearTravel(origin,destination,character,escaping) then
                    setRoute({{Position=origin-Vector3.new(0,clearance,0)},{Position=destination-Vector3.new(0,clearance,0)}})
                    useArenaSearch=false
                else
                    local path=nil
                    -- Use Roblox's navigation mesh once; if its path fails our ground checks,
                    -- search the arena instead of recomputing the same rejected mesh path.
                    if not useArenaSearch then
                        for _,offset in ipairs(bossLegOffsets(delta.X,delta.Z)) do
                            local candidate=Vector3.new(origin.X+offset[1],origin.Y,origin.Z+offset[2])
                            local supported=ground(candidate,character)
                            if supported and (supported-origin).Magnitude<=512 then
                                local trial=game:GetService("PathfindingService"):CreatePath({AgentRadius=3,AgentHeight=6,AgentCanJump=false,AgentCanClimb=false,WaypointSpacing=10})
                                local ok=pcall(function() trial:ComputeAsync(origin,supported) end)
                                if not valid() then halt(); return "cancelled" end
                                if ok and trial.Status==Enum.PathStatus.Success then path=trial; break end
                                -- Don't spend the hand's entire exposure on multiple mesh requests.
                                break
                            end
                        end
                    end
                    if path then
                        setRoute(path:GetWaypoints())
                        routeLink=path.Blocked:Connect(function(index) if index>=routeIndex then routeBlocked=true; useArenaSearch=true end end)
                    else
                        local edges={}
                        local points,reason=arenaSearch(origin.X,origin.Z,destination.X,destination.Z,24,function(ax,az,bx,bz)
                            local id=ax..":"..az..":"..bx..":"..bz
                            if edges[id]==nil then
                                edges[id]=clearTravel(Vector3.new(ax,origin.Y,az),Vector3.new(bx,origin.Y,bz),character,escaping)
                            end
                            return edges[id]
                        end,function() task.wait(); return valid() end)
                        if not valid() then halt(); return "cancelled" end
                        if not points then useArenaSearch=true; return "no safe path: "..reason end
                        local waypoints={}
                        for _,point in ipairs(points) do waypoints[#waypoints+1]={Position=Vector3.new(point[1],origin.Y-clearance,point[2])} end
                        setRoute(waypoints); useArenaSearch=false
                        note("BOSS PATH | Arena detour | "..reason)
                    end
                end
            end
            -- Select long safe segments, retaining only corners needed around obstacles/holes.
            local function pointAt(index)
                local p=route[index].Position
                local clearance=math.max(2,math.min(4,h.HipHeight+root.Size.Y/2))
                return p+Vector3.new(0,clearance,0)
            end
            while routeIndex<=#route do
                local distance=(pointAt(routeIndex)-root.Position).Magnitude
                local cornerRange=math.max(3,math.min(12,h.WalkSpeed*0.06))
                local reached=distance<3
                -- Advance early only if the next segment is already safe from here.
                -- This avoids reversing at high speed without cutting across a pit corner.
                if not reached and routeIndex<#route and distance<cornerRange then
                    reached=clearTravel(root.Position,pointAt(routeIndex+1),character,escaping)
                end
                if not reached then break end
                routeIndex=routeIndex+1; aimIndex=nil
            end
            if routeIndex>#route then halt(); return "arrived" end
            if not aimIndex or (aimIndex<#route and os.clock()-lookAt>=0.75) then
                lookAt=os.clock()
                local nextIndex=farthestClear(routeIndex,#route,function(index)
                    return route[index].Action~=Enum.PathWaypointAction.Jump and clearTravel(root.Position,pointAt(index),character,escaping)
                end)
                if not nextIndex then useArenaSearch=true; halt(); return "route rejected; switching to arena search" end
                if aimIndex~=nextIndex then bestWaypoint=math.huge; movingSince=os.clock(); checkAt=0 end
                aimIndex=nextIndex; routeIndex=nextIndex
            end
            local point=pointAt(aimIndex)
            if os.clock()-checkAt>=0.15 then
                checkAt=os.clock()
                local delta=point-root.Position
                local horizon=math.max(12,math.min(100,h.WalkSpeed*0.25))
                local ahead=delta.Magnitude>horizon and root.Position+delta.Unit*horizon or point
                if not clearTravel(root.Position,ahead,character,escaping) then useArenaSearch=true; halt(); return "route changed; replanning" end
            end
            local distance=(point-root.Position).Magnitude
            if distance<bestWaypoint-0.5 then bestWaypoint=distance; movingSince=os.clock() end
            if os.clock()-movingSince>1.25 then useArenaSearch=true; halt(); return "path stalled; searching alternate route" end
            if not enabled or player.Character~=character or player:GetAttribute("InBossArena")~=true then halt(); return "cancelled" end
            h:MoveTo(point)
            return "moving"
        end
        local function nearbyMeteors(point)
            hazardCost(point) -- refresh cache once per scan interval
            for _,marker in ipairs(meteorCache) do
                if Vector3.new(point.X-marker.position.X,0,point.Z-marker.position.Z).Magnitude<150+marker.diameter/2 then return true end
            end
            return false
        end
        local function escapeGoal(character,root)
            if hazardCost(root.Position)==0 then return root.Position end
            -- Evaluate the whole warning field; prefer the shortest clear, supported escape.
            for _,radius in ipairs({20,40,60,90,120,160}) do
                for n=0,15 do
                    local angle=n*math.pi/8
                    local point=root.Position+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
                    if hazardCost(point)==0 and ground(point,character) and clearTravel(root.Position,point,character,true) then return point end
                end
            end
            return nil
        end
        local function dodgeMeteors(character,h,root)
            if not dodgeGoal and not nearbyMeteors(root.Position) then return false end
            if dodgeGoal and hazardCost(dodgeGoal)>0 then
                note("BOSS DODGE | Destination became unsafe; choosing another")
                dodgeGoal=nil; dodgeQuietAt=nil; dodgeRetryAt=0; halt()
            end
            if not dodgeGoal then
                if os.clock()<dodgeRetryAt then return true end
                dodgeRetryAt=os.clock()+0.25
                dodgeGoal=escapeGoal(character,root)
                if not dodgeGoal then halt(); say("Comets: no clear escape found; rechecking"); return true end
                halt(); note("BOSS DODGE | Committed to "..tostring(dodgeGoal))
            end
            local distance=(root.Position-dodgeGoal).Magnitude
            if distance>7 or hazardCost(root.Position)>0 then
                if clearTravel(root.Position,dodgeGoal,character,true) then
                    say("Moving to committed comet-safe position")
                    h:MoveTo(dodgeGoal)
                else
                    dodgeGoal=nil; dodgeRetryAt=0; halt(); say("Comet escape route changed; rechecking")
                end
                return true
            end
            halt(); say("Holding comet-safe position")
            if nearbyMeteors(root.Position) then dodgeQuietAt=nil
            else
                dodgeQuietAt=dodgeQuietAt or os.clock()
                if os.clock()-dodgeQuietAt>=0.75 then
                    note("BOSS DODGE | Wave cleared; resuming")
                    dodgeGoal=nil; dodgeQuietAt=nil; return false
                end
            end
            return true
        end
        local function swing(character,h,root)
            local tool=bat(character)
            if not tool then say("No owned bat found"); return end
            if tool.Parent~=character then h:EquipTool(tool); return end
            if os.clock()-lastSwing>=0.7 and tool:GetAttribute("CooldownActive")~=true and workspace:GetServerTimeNow()>=(tonumber(tool:GetAttribute("CooldownEndTime")) or 0) then
                lastSwing=os.clock(); tool:Activate(); tool:Deactivate()
            end
        end
        connect(stopAll.Activated,function() discardResume(); turnOff("Boss stopped by Stop All") end)
        connect(stopButton.Activated,function() discardResume(); turnOff("Boss stopped by Stop Boss Test") end)
        table.insert(cleanupActions,function() disable("Hub closed") end)
        local storage=game:GetService("ReplicatedStorage")
        local healthRemote=storage:FindFirstChild("RE/BossEvent/HealthShifted",true)
        if healthRemote then connect(healthRemote.OnClientEvent,function(hp,maxHP) healthState={hp=hp,maxHP=maxHP} end) end
        local stateRemote=storage:FindFirstChild("RE/BossEvent/StateShifted",true)
        if stateRemote then connect(stateRemote.OnClientEvent,function(state) if type(state)=="table" and type(state.BossHealth)=="number" then healthState={hp=state.BossHealth,maxHP=state.BossMaxHealth} end end) end
        local vfx=storage:FindFirstChild("RE/BossEvent/Vfx",true)
        if vfx then connect(vfx.OnClientEvent,function(kind,point) if enabled and kind=="BossSlam" and typeof(point)=="Vector3" then slamUntil=os.clock()+2 end end) end
        local function tickBoss()
            arrivalPart=nil
            if not enabled then
                if pausedSettings and player:GetAttribute("InBossArena")~=true then restoreTouchSetting(); resumeAutomations() end
                return
            end
            local character,h,root=characterParts()
            local inside=player:GetAttribute("InBossArena")==true
            local state=automationFlow.bossSnapshot
            if not inside then
                if wasInside then halt(); wasInside=false; restoreTouchSetting(); resumeAutomations(); say("Returned to lobby; automations resumed; waiting for next boss") end
                if enterEnabled and state and state.Open==true and state.BossHealth~=0 and state.OpensAt~=entryWindow and not entryPending then
                    if not pauseAutomations() then return end
                    halt()
                    entryWindow=state.OpensAt; entryPending=true
                    local remote=storage:FindFirstChild("RF/BossEvent/AskEnter",true)
                    if not remote or not remote:IsA("RemoteFunction") then entryPending=false; resumeAutomations(); say("Boss entry remote unavailable; automations resumed"); return end
                    say("Requesting boss entry once")
                    entryToken=entryToken+1
                    local token=entryToken
                    remoteJob=task.spawn(function()
                        local result=table.pack(pcall(function() return remote:InvokeServer() end))
                        if enabled and token==entryToken then note("BOSS ENTRY | transport="..tostring(result[1]).." | result="..tostring(result[2]).." | "..tostring(result[3])) end
                    end)
                    task.delay(12,function()
                        if token~=entryToken then return end
                        if remoteJob then pcall(task.cancel,remoteJob); remoteJob=nil end
                        entryPending=false
                        if enabled and player:GetAttribute("InBossArena")~=true then resumeAutomations(); say("Entry not confirmed; automations resumed; no retry this opening") end
                    end)
                elseif not enterEnabled then
                    if pausedSettings and not entryPending then resumeAutomations() end
                    say("Waiting for manual arena entry")
                elseif pausedSettings and not entryPending and (not state or state.Open~=true or state.BossHealth==0) then resumeAutomations() end
                return
            end
            wasInside=true
            if not pausedSettings and not pauseAutomations() then return end
            if conflict() and not pauseAutomations() then return end
            if not character or not h or not root or h.Health<=0 then halt(); owner=nil; say("Waiting for respawn in arena"); return end
            if owner~=character then halt(); owner=character; blacklist={}; crystalTarget=nil; crystalGoal=nil; crystalSide=0; handLast=nil; handStable=os.clock(); say("Arena character ready") end
            local model=arena(); if not model then halt(); say("Waiting for arena replication"); return end
            local boss=model:FindFirstChild("Boss")
            local hand=boss and boss:FindFirstChild("UpperHand1.R",true)
            local handPosition=hand and hand:IsA("Bone") and hand.TransformedWorldCFrame.Position or nil
            if handPosition and (not handLast or (handPosition-handLast).Magnitude>2) then handStable=os.clock() end
            handLast=handPosition
            local handReady=handPosition and hand:FindFirstChild("Health")~=nil and boss:GetAttribute("Spawning")~=true
            local living={}
            local healthInitialized=false
            for _,hit in ipairs(crystals(model)) do
                if (tonumber(hit:GetAttribute("MaxHealth")) or 0)>1 then healthInitialized=true end
                if (tonumber(hit:GetAttribute("Health")) or 0)>0 then living[#living+1]=hit end
            end
            table.sort(living,function(a,b) return (a.Position-root.Position).Magnitude<(b.Position-root.Position).Magnitude end)
            local finished=(healthState and healthState.hp==0) or (state and state.Open==false)
            local phase=bossPhase(true,true,finished,#living,handReady)
            if phase=="return" then
                if not returnEnabled then halt(); say("Fight finished; return manually or enable Auto Return From Boss"); return end
                local portal=model:FindFirstChild("BossArenaLeaveTeleport")
                local hit=portal and portal:FindFirstChild("Hitbox")
                if not hit then halt(); say("Return portal unavailable"); return end
                if trapsOn() then
                    restoreTraps=true
                    settingsBindings["No Traps"].set(false)
                end
                say("Returning through lobby portal")
                navigate(Vector3.new(hit.Position.X,root.Position.Y,hit.Position.Z),character,h,root,false)
                return
            end
            if not bossCombatReady(state and state.Open,boss~=nil,boss and boss:GetAttribute("Spawning"),state and state.BossSpawnsAt,workspace:GetServerTimeNow(),healthInitialized) then
                halt(); crystalTarget=nil; crystalGoal=nil
                say("Waiting for boss spawn to finish; crystals are not active yet")
                return
            end
            if dodgeMeteors(character,h,root) then attackTarget=nil; return end
            if phase=="crystals" then
                local target
                if crystalTarget and crystalTarget:IsDescendantOf(model) and (tonumber(crystalTarget:GetAttribute("Health")) or 0)>0 and (not blacklist[crystalTarget] or os.clock()>blacklist[crystalTarget]) then target=crystalTarget end
                if not target then for _,hit in ipairs(living) do if not blacklist[hit] or os.clock()>blacklist[hit] then target=hit; break end end end
                if not target then
                    -- Retry the soonest candidate immediately when no alternative remains.
                    target=living[1]
                    for _,hit in ipairs(living) do if (blacklist[hit] or 0)<(blacklist[target] or 0) then target=hit end end
                    blacklist[target]=nil; useArenaSearch=true; crystalGoal=nil
                end
                local destination,distance,outside=approachPoint(target,root.Position)
                if crystalTarget~=target then crystalSide=0; crystalGoal=nil end
                if crystalTarget~=target or not crystalGoal then
                    crystalTarget=target
                    local direction=root.Position-target.Position
                    local angle=math.atan2(direction.Z,direction.X)+crystalSide*math.pi/4
                    local sample=Vector3.new(target.Position.X+math.cos(angle)*100,root.Position.Y,target.Position.Z+math.sin(angle)*100)
                    crystalGoal=approachPoint(target,sample)
                    halt()
                end
                destination=crystalGoal
                arrivalPart=target
                say("Crystals: "..#living.." alive | target "..target.Parent.Name.." | health "..tostring(target:GetAttribute("Health")))
                if attackHold(distance,attackTarget==target,12,14) then
                    attackTarget=target; halt(); swing(character,h,root)
                    local hits=tonumber(player:GetAttribute("BossCrystalHits")) or 0
                    if hits~=lastHitCount then lastHitCount=hits; lastHitProgress=os.clock() end
                    if lastHitProgress==0 then lastHitProgress=os.clock() end
                    if os.clock()-lastHitProgress>8 then blacklist[target]=os.clock()+8; lastHitProgress=0; note("BOSS RUN | No own crystal hit progress; reconsidering target") end
                else
                    attackTarget=nil; lastHitProgress=0
                    local result=navigate(destination,character,h,root,false)
                    if result=="route rejected; switching to arena search" then return end
                    if result~="moving" and result~="waiting" and result~="arrived" then
                        crystalSide=crystalSide+1; crystalGoal=nil; halt()
                        if crystalSide>=8 then blacklist[target]=os.clock()+3; crystalSide=0 end
                        note("BOSS PATH | Crystal "..target.Parent.Name.." | "..result.." | trying another approach side")
                    end
                end
            elseif phase=="hand" then
                arrivalPart=hand
                local away=Vector3.new(root.Position.X-handPosition.X,0,root.Position.Z-handPosition.Z)
                local destination=Vector3.new(handPosition.X,root.Position.Y,handPosition.Z)+(away.Magnitude>0.1 and away.Unit*9 or Vector3.new(9,0,0))
                say("Hand exposed | Boss HP "..tostring(healthState and healthState.hp or "?"))
                if attackHold((handPosition-root.Position).Magnitude,attackTarget==hand,13,15) then attackTarget=hand; halt(); swing(character,h,root)
                else attackTarget=nil; navigate(destination,character,h,root,false) end
            else
                attackTarget=nil; halt(); say("Waiting for exposed hand / boss spawn")
            end
        end
        -- Brake at frame rate so a fast character does not cross the arrival band between logic ticks.
        connect(game:GetService("RunService").Heartbeat,function()
            if not enabled or player:GetAttribute("InBossArena")~=true then return end
            local character,h,root=characterParts()
            if character~=owner or not h or not root or h.Health<=0 then return end
            if dodgeGoal then
                if (root.Position-dodgeGoal).Magnitude<=7 and hazardCost(root.Position)==0 then halt() end
            elseif arrivalPart and arrivalPart.Parent and hazardCost(root.Position)==0 then
                local distance
                if arrivalPart:IsA("Bone") then
                    if not arrivalPart:FindFirstChild("Health") then return end
                    distance=(arrivalPart.TransformedWorldCFrame.Position-root.Position).Magnitude
                else local _,d=approachPoint(arrivalPart,root.Position); distance=d end
                if distance<=12 then halt() end
            end
        end)
        task.spawn(function()
            while not closed do
                local ok,err=pcall(tickBoss)
                if not ok then turnOff("Boss run error: "..tostring(err)) end
                if enabled and os.clock()-lastReportWrite>=5 and type(writefile)=="function" then
                    lastReportWrite=os.clock(); pcall(writefile,"AcidHub_Boss_Run.txt",table.concat(lines,"\n"))
                end
                task.wait(0.05)
            end
        end)
    end

end)() end

-- Boss schedule display: one initial read, event updates, and bounded boundary refreshes.
do (function()
    local target
    for _,tab in ipairs(tabs) do if tab.name=="Events" then target=tab.page.TheRiftSection.RiftSettings end end
    if not target then return end
    local displayRow=row(target,38); displayRow.LayoutOrder=-100
    local display=label("Next Boss: Loading...",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),displayRow)
    local state,revision,pending=nil,0,false
    local alive=true
    local jobs={}
    local refreshed={}
    local function accept(value)
        if type(value)~="table" or type(value.Open)~="boolean" then return false end
        state=value; automationFlow.bossSnapshot=value; revision=revision+1; return true
    end
    local function readOnce(remote)
        if not alive or pending then return end
        pending=true
        local version=revision
        local done=false
        local worker=task.spawn(function()
            local ok,value=pcall(function() return remote:InvokeServer() end)
            done=true; pending=false
            if alive and not closed and revision==version then
                if not ok or not accept(value) then display.Text="Next Boss: Unavailable" end
            end
        end)
        jobs[#jobs+1]=worker
        jobs[#jobs+1]=task.spawn(function()
            task.wait(12)
            if not done then
                pcall(task.cancel,worker); pending=false
                if alive and not closed and revision==version and not state then display.Text="Next Boss: Unavailable" end
            end
        end)
    end
    table.insert(cleanupActions,function()
        alive=false
        for _,job in ipairs(jobs) do pcall(task.cancel,job) end
    end)
    jobs[#jobs+1]=task.spawn(function()
        local storage=game:GetService("ReplicatedStorage")
        local remote,event
        local deadline=os.clock()+15
        repeat
            remote=storage:FindFirstChild("RF/BossEvent/AskSnapshot",true)
            event=storage:FindFirstChild("RE/BossEvent/StateShifted",true)
            if remote and event then break end
            task.wait(0.5)
        until not alive or closed or os.clock()>=deadline
        if not alive or closed then return end
        if event and event:IsA("RemoteEvent") then connect(event.OnClientEvent,function(value) if alive then accept(value) end end) end
        if not remote or not remote:IsA("RemoteFunction") then display.Text="Next Boss: Unavailable"; return end
        readOnce(remote)
        while alive and not closed do
            if state then
                local now=workspace:GetServerTimeNow()
                local timestamp=state.Open and state.ClosesAt or state.OpensAt
                if type(timestamp)=="number" and timestamp==timestamp and math.abs(timestamp)<1e12 then
                    local remaining=math.max(0,math.ceil(timestamp-now))
                    if remaining>0 then
                        local time=string.format("%02dm %02ds",math.floor(remaining/60),remaining%60)
                        display.Text=state.Open and ("Next Boss: Active | Closes in "..time) or ("Next Boss: "..time)
                    else
                        display.Text="Next Boss: Awaiting server update"
                        local key=tostring(state.Open)..":"..tostring(timestamp)
                        if not refreshed[key] and not pending then refreshed[key]=true; readOnce(remote) end
                    end
                else display.Text=state.Open and "Next Boss: Active" or "Next Boss: Schedule unavailable" end
            end
            task.wait(1)
        end
    end)
end)() end

-- Focused outgoing observer. The original invocation is forwarded unchanged exactly once.
do (function()
    local function captureRow(height,order)
        local frame=row(debugPage,height); frame.LayoutOrder=order; return frame
    end
    local start=button("Start Mutation Use Capture",UDim2.new(),UDim2.new(1,0,1,0),captureRow(38,-1020))
    local stop=button("Stop Mutation Use Capture",UDim2.new(),UDim2.new(1,0,1,0),captureRow(38,-1019))
    local copy=button("Copy Mutation Use Capture",UDim2.new(),UDim2.new(1,0,1,0),captureRow(38,-1018))
    local display=label("Start first. Only after ARMED appears, equip the item and press E on one growing egg once. One item may be consumed even if mutation fails.",UDim2.fromOffset(10,6),UDim2.new(1,-20,1,-12),captureRow(94,-1017),true)
    display.TextSize=14
    local active,started,count=false,0,0
    local lines,report={},""
    local observer
    local function encode(value,depth,seen)
        depth=depth or 0; seen=seen or {}
        local kind=typeof(value)
        if kind=="Instance" then return value.ClassName..":"..value:GetFullName() end
        if type(value)=="string" then return string.format("%q",value:sub(1,2048)) end
        if type(value)~="table" then return tostring(value) end
        if seen[value] then return "<cycle>" end
        if depth>=5 then return "<depth limit>" end
        seen[value]=true
        local result,n={},0
        for k,v in pairs(value) do
            n=n+1; if n>50 then result[#result+1]="<table truncated>"; break end
            result[#result+1]="["..encode(k,depth+1,seen).."]="..encode(v,depth+1,seen)
        end
        seen[value]=nil
        return "{"..table.concat(result,", ").."}"
    end
    local function itemState()
        local found,seen={},{}
        for _,container in ipairs({player.Backpack,player.Character or player.Backpack}) do
            for _,tool in ipairs(container:GetChildren()) do
                if not seen[tool] and tool:IsA("Tool") and tool:GetAttribute("ItemType")=="MutationConsumable" then
                    seen[tool]=true
                    found[#found+1]=tool:GetFullName().." | Uses="..tostring(tool:GetAttribute("Uses"))
                end
            end
        end
        return #found>0 and table.concat(found,"; ") or "No replicated MutationConsumable tool"
    end
    local function finish(reason)
        if not active then return end
        active=false
        if observer then observer.record=nil; observer.target=nil end
        lines[#lines+1]="STOP: "..reason.." | requests observed="..count
        local ok,state=pcall(itemState)
        lines[#lines+1]="ITEM AFTER: "..(ok and state or "unavailable")
        lines[#lines+1]="Coverage: colon InvokeServer calls through __namecall only. Direct function calls or executor limitations may bypass this observer. No requests sent/retried/modified by recorder; no server response intercepted."
        report=table.concat(lines,"\n")
        local saved=type(writefile)=="function" and pcall(writefile,"AcidHub_Mutation_Capture.txt",report)
        display.Text=(count>0 and "Request arguments captured. " or "No matching outgoing request captured. Do not use another item just to retry. ")..
            (saved and "Saved AcidHub_Mutation_Capture.txt. Send this file." or "Use Copy Mutation Use Capture.")
    end
    connect(start.Activated,function()
        if active then display.Text="ARMED: waiting for your one manual application."; return end
        if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" or type(getgenv)~="function" then
            display.Text="UNSUPPORTED: this executor does not expose the required outgoing-call hooks. Do not consume an item for this capture."; return
        end
        local target=game:GetService("ReplicatedStorage"):FindFirstChild("RF/BossMastery/AskUseMutationConsumable",true)
        if not target or not target:IsA("RemoteFunction") then display.Text="Mutation request not found; capture not started."; return end
        local ok,err=pcall(function()
            local env=getgenv()
            local key="AcidHubMutationObserverV1"
            observer=env[key]
            if not observer then
                local state={}
                local previous
                local function intercept(self,...)
                    if self==state.target and getnamecallmethod()=="InvokeServer" and state.record then
                        -- Observer errors must never block or duplicate the game's request.
                        pcall(state.record,table.pack(...))
                    end
                    return previous(self,...)
                end
                local callback=type(newcclosure)=="function" and newcclosure(intercept) or intercept
                previous=hookmetamethod(game,"__namecall",callback)
                assert(type(previous)=="function","Hook did not return a callable original")
                env[key]=state; observer=state
            end
            assert(type(observer)=="table","Observer state unavailable")
            lines={"AcidHub Mutation Use Capture",os.date("!%Y-%m-%d %H:%M:%S UTC"),"TARGET: "..target:GetFullName(),"ITEM BEFORE: "..itemState()}
            report=""; started=os.clock(); count=0; active=true
            observer.target=target
            observer.record=function(args)
                if not active or closed or count>=1 then return end
                count=count+1
                lines[#lines+1]=string.format("[%.3fs] OUTGOING InvokeServer | argument count=%d",os.clock()-started,args.n)
                for i=1,args.n do lines[#lines+1]="ARG "..i.." | type="..typeof(args[i]).." | "..encode(args[i]) end
            end
        end)
        if not ok then
            active=false
            if observer then observer.record=nil; observer.target=nil end
            display.Text="Capture unavailable: "..tostring(err)..". Do not consume an item for this capture."; return
        end
        display.Text="ARMED (hook installed, not yet verified): equip Mutation Consumable and press E on one growing egg ONCE. Auto-stops after the request or 120 seconds."
    end)
    connect(stop.Activated,function() finish("Stopped by user") end)
    connect(copy.Activated,function()
        if active then finish("Stopped to copy") end
        if report=="" then display.Text="No capture report yet."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        display.Text=ok and "Mutation capture copied." or "Clipboard unavailable; use the saved file."
    end)
    task.spawn(function()
        while not closed do
            if active then
                if count>0 then task.wait(1); if active then finish("One request observed; no additional use needed") end
                elseif os.clock()-started>=120 then finish("120-second limit") end
            end
            task.wait(0.25)
        end
    end)
    table.insert(cleanupActions,function()
        if active then finish("Hub closed") end
        if observer then observer.record=nil; observer.target=nil end
        -- Keep a dormant pass-through hook: restoring an old hook could overwrite another script's newer hook.
    end)
end)() end

-- Read-only mutation-item inspection. No consumption requests are sent.
do (function()
    local r=row(debugPage,42); r.LayoutOrder=-1010
    local inspect=button("Inspect Mutation Consumable",UDim2.new(),UDim2.new(1,0,1,0),r)
    local sr=row(debugPage,80); sr.LayoutOrder=-1009
    local display=label("Inspect while the item is in your backpack. Saves item metadata and available client source; consumes nothing.",UDim2.fromOffset(10,6),UDim2.new(1,-20,1,-12),sr,true)
    local cr=row(debugPage,38); cr.LayoutOrder=-1008
    local copy=button("Copy Mutation Inspection",UDim2.new(),UDim2.new(1,0,1,0),cr)
    local busy,report=false,""
    connect(copy.Activated,function()
        if report=="" then display.Text="Run Inspect Mutation Consumable first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        display.Text=ok and "Mutation inspection copied." or "Clipboard unavailable; use AcidHub_Mutation_Inspection.txt."
    end)
    connect(inspect.Activated,function()
        if busy then return end
        busy=true; display.Text="Inspecting mutation item and client source..."
        local ok,err=pcall(function()
            local lines={"AcidHub Mutation Consumable Inspection",os.date("!%Y-%m-%d %H:%M:%S UTC"),"Read-only. No mutation requests sent. Source text may be incomplete."}
            local sources,seen={},{}
            local storage=game:GetService("ReplicatedStorage")
            local function attrs(object)
                local fields={}
                for key,value in pairs(object:GetAttributes()) do fields[#fields+1]=key.."="..tostring(value) end
                table.sort(fields); return table.concat(fields,", ")
            end
            for _,root in ipairs({player,storage,workspace}) do
                for index,object in ipairs(root:GetDescendants()) do
                    local name=object:GetFullName(); local low=name:lower()
                    local relevant=low:find("mutationconsumable",1,true) or low:find("mutation consumable",1,true)
                    if relevant and not seen[object] then
                        seen[object]=true
                        lines[#lines+1]=object.ClassName.." | "..name.." | "..attrs(object)
                    end
                    if object:IsA("LuaSourceContainer") and (relevant or low:find("bossmastery",1,true)) then
                        if #sources<20 then sources[#sources+1]=object end
                    end
                    if index%500==0 then task.wait(); if closed then error("Hub closed") end end
                end
            end
            for _,object in ipairs(sources) do
                if closed then break end
                local done,text=false,nil
                local worker=task.spawn(function()
                    local success,value=pcall(function() return object.Source end)
                    if (not success or type(value)~="string" or value=="") and type(decompile)=="function" then success,value=pcall(decompile,object) end
                    text=success and tostring(value) or "Source unavailable: "..tostring(value); done=true
                end)
                local deadline=os.clock()+3
                while not done and not closed and os.clock()<deadline do task.wait(0.05) end
                if not done then pcall(task.cancel,worker); text="Source inspection timed out" end
                lines[#lines+1]="SOURCE: "..object:GetFullName().."\n"..tostring(text):sub(1,60000)
            end
            report=table.concat(lines,"\n")
            local saved=type(writefile)=="function" and pcall(writefile,"AcidHub_Mutation_Inspection.txt",report)
            display.Text=saved and "Saved AcidHub_Mutation_Inspection.txt. Send this file to verify the consuming call." or "Inspection ready. Use Copy Mutation Inspection."
        end)
        busy=false
        if not ok then display.Text="Inspection failed: "..tostring(err) end
    end)
end)() end

-- Focused boss recording. Only the explicit snapshot button sends a read request.
do (function()
    local order=-1000
    local function captureRow(height) local r=row(debugPage,height); r.LayoutOrder=order; order=order+1; return r end
    label("Boss Fight Capture",UDim2.fromOffset(10,0),UDim2.new(1,-20,1,0),captureRow(38)).TextSize=20
    local start=button("Start Boss Capture",UDim2.new(),UDim2.new(1,0,1,0),captureRow(38))
    local stop=button("Stop Boss Capture",UDim2.new(),UDim2.new(1,0,1,0),captureRow(38))
    local snapshotButton=button("Read Boss Snapshot Once",UDim2.new(),UDim2.new(1,0,1,0),captureRow(38))
    local snapshotPending=false
    local lastSnapshotRequest=-math.huge
    local saveButton=button("Save Boss Report",UDim2.new(),UDim2.new(1,0,1,0),captureRow(38))
    local copy=button("Copy Boss Report",UDim2.new(),UDim2.new(1,0,1,0),captureRow(38))
    local status=label("Start while waiting for the portal, then Read Boss Snapshot Once. Fight manually with normal automations OFF. After returning, read again; if the event is still open, wait until it closes and read once more. Then Stop. No Traps stays unchanged.",UDim2.fromOffset(10,6),UDim2.new(1,-20,1,-12),captureRow(110),true)
    status.TextSize=14
    -- Independent, read-only inventory: no capture/decompiler startup required.
    do
        local inspectButton=button("Inspect Boss Return Remotes",UDim2.new(),UDim2.new(1,0,1,0),captureRow(38))
        local copyRemotes=button("Copy Remote Inspection",UDim2.new(),UDim2.new(1,0,1,0),captureRow(38))
        local display=label("Works from the lobby. Lists replicated remote names only; sends no requests.",UDim2.fromOffset(10,6),UDim2.new(1,-20,1,-12),captureRow(80),true)
        display.TextSize=14
        local report=""
        local busy=false
        connect(inspectButton.Activated,function()
            if busy then return end
            busy=true; display.Text="Reading replicated networking objects..."
            local ok,err=pcall(function()
                local all,candidates,seen={},{},{}
                local function record(object)
                    if seen[object] then return end
                    seen[object]=true
                    if not (object:IsA("RemoteEvent") or object:IsA("RemoteFunction") or object.ClassName=="UnreliableRemoteEvent") then return end
                    local name=object:GetFullName()
                    local entry=object.ClassName.." | "..name
                    all[#all+1]=entry
                    local lower=name:lower()
                    for _,word in ipairs({"boss","arena","leave","exit","return","lobby","teleport"}) do
                        if lower:find(word,1,true) then candidates[#candidates+1]=entry; break end
                    end
                end
                -- Networking first; do not wait for world/source capture initialization.
                for _,root in ipairs({game:GetService("ReplicatedStorage"),game:GetService("ReplicatedFirst"),workspace,player}) do
                    for index,object in ipairs(root:GetDescendants()) do
                        record(object)
                        if index%500==0 then task.wait(); if closed then error("Hub closed") end end
                    end
                end
                table.sort(all); table.sort(candidates)
                report="AcidHub Boss Return Remote Inspection\nUTC: "..os.date("!%Y-%m-%d %H:%M:%S")..
                    "\nGame ID: "..game.GameId.." | Place ID: "..game.PlaceId..
                    "\nInBossArena: "..tostring(player:GetAttribute("InBossArena"))..
                    "\nRead-only names and classes. No requests sent, no source decompilation, no outgoing interception."..
                    "\nCoverage: ReplicatedStorage, ReplicatedFirst, Workspace, LocalPlayer. Server-only or unreplicated objects are unavailable."..
                    "\nNames are candidates only: they do not establish purpose, arguments, or permission to return."..
                    "\n\nBOSS / RETURN NAME CANDIDATES ("..#candidates..")\n"..table.concat(candidates,"\n")..
                    "\n\nALL REPLICATED REMOTES ("..#all..")\n"..table.concat(all,"\n")
                local saved,saveError=false,"writefile unavailable"
                if type(writefile)=="function" then saved,saveError=pcall(writefile,"AcidHub_Boss_Remotes.txt",report) end
                display.Text="Found "..#all.." remotes; "..#candidates.." name candidates. "..
                    (saved and "Saved AcidHub_Boss_Remotes.txt in executor workspace. Send this file." or "Save failed: "..tostring(saveError)..". Use Copy Remote Inspection.")
            end)
            busy=false
            if not ok then display.Text="Remote inspection failed: "..tostring(err) end
        end)
        connect(copyRemotes.Activated,function()
            if report=="" then display.Text="Click Inspect Boss Return Remotes first."; return end
            if type(setclipboard)~="function" then display.Text="Clipboard unavailable. Use the saved file."; return end
            local ok,err=pcall(setclipboard,report)
            display.Text=ok and "Remote inspection copied." or "Copy failed: "..tostring(err)
        end)
    end
    local filename="AcidHub_Boss_Capture.txt"
    local active,generation,started=false,0,0
    local events,sources,links,jobs={},{},{},{}
    local watched,seen,last,queue={},{},{},{}
    local eventBytes,sourceBytes,eventCount,objectCount=0,0,0,0
    local eventLimited,sourceLimited,objectLimited=false,false,false
    local header,report="",""
    local function path(object) local ok,value=pcall(function() return object:GetFullName() end); return ok and value or "<removed>" end
    local function valueText(value,depth,visited)
        depth=depth or 0; visited=visited or {}
        local kind=typeof(value)
        if kind=="Instance" then return value.ClassName..":"..path(value) end
        if kind=="Vector3" then return string.format("(%.2f,%.2f,%.2f)",value.X,value.Y,value.Z) end
        if kind=="CFrame" then return valueText(value.Position,depth,visited) end
        if type(value)=="string" then return string.format("%q",value:sub(1,1500)) end
        if type(value)~="table" then return tostring(value) end
        if visited[value] then return "<cycle>" end
        if depth>=4 then return "<depth limit>" end
        visited[value]=true
        local fields,count={},0
        for key,child in pairs(value) do
            count=count+1; if count>60 then fields[#fields+1]="<field limit>"; break end
            fields[#fields+1]=tostring(key).."="..valueText(child,depth+1,visited)
        end
        table.sort(fields); visited[value]=nil
        return "{"..table.concat(fields,", ").."}"
    end
    local function emit(kind,text)
        if not active then return end
        local line=string.format("[%.3fs] %s | %s\n",os.clock()-started,kind,tostring(text))
        if eventCount>=30000 or eventBytes+#line>4000000 then eventLimited=true; return end
        events[#events+1]=line; eventCount=eventCount+1; eventBytes=eventBytes+#line
    end
    local function listen(signal,fn) links[#links+1]=signal:Connect(function(...) if active then fn(...) end end) end
    local function relevant(object)
        -- Exclude other avatars, accessories and replicated pet/tool templates.
        if not object:IsDescendantOf(workspace) and not object:IsDescendantOf(player.PlayerGui) then return false end
        local ancestor=object
        while ancestor and ancestor~=workspace do
            if ancestor:IsA("Accessory") or ancestor:IsA("Tool") then return false end
            if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then return false end
            ancestor=ancestor.Parent
        end
        if not (object:IsA("Model") or object:IsA("BasePart") or object:IsA("ValueBase") or object:IsA("TextLabel") or object:IsA("Folder")) then return false end
        local text=object.Name:lower()
        for _,word in ipairs({"boss","crystal","pillar","hazard","meteor","blackhole","portal","telegraph","warningcircle","hitbox"}) do
            if text:find(word,1,true) then return true end
        end
        local parent=object.Parent
        for depth=1,3 do
            if not parent or parent==workspace then break end
            local name=parent.Name:lower()
            if name:find("crystal",1,true) or name:find("hazard",1,true) or name:find("blackhole",1,true)
                or name:find("bosshud",1,true) or name:find("bosshand",1,true) or name:find("bossarm",1,true) then return true end
            parent=parent.Parent
        end
        return false
    end
    local function snapshot(object)
        local data={attributes=object:GetAttributes()}
        if object:IsA("BasePart") then
            data.position=object.Position; data.size=object.Size; data.touch=object.CanTouch; data.collide=object.CanCollide; data.transparency=object.Transparency
        elseif object:IsA("Model") then data.position=object:GetPivot().Position
        elseif object:IsA("Humanoid") then data.hp=object.Health; data.maxHP=object.MaxHealth; data.state=object:GetState().Name; data.walkSpeed=object.WalkSpeed
        elseif object:IsA("ValueBase") then data.value=object.Value
        elseif object:IsA("TextLabel") or object:IsA("TextButton") then data.text=object.Text; data.visible=object.Visible end
        return valueText(data)
    end
    local function sourceCandidate(object)
        if not (object:IsA("LocalScript") or object:IsA("ModuleScript")) then return false end
        local text=string.lower(path(object))
        return text:find("bossevent",1,true) or text:find("bossmastery",1,true) or text:find("batcontroller",1,true)
            or text:find("gears.configs",1,true) and (text:find("bat",1,true) or text:find("axe",1,true))
    end
    local function inspect(object)
        if closed or not active or seen[object] then return end
        seen[object]=true
        if sourceCandidate(object) and #queue<80 then queue[#queue+1]=object end
        if object:IsA("RemoteEvent") and (path(object):find("BossEvent",1,true) or path(object):find("BatSwing",1,true) or path(object):find("BossMastery",1,true)) then
            local name=path(object)
            listen(object.OnClientEvent,function(...) emit("SERVER EVENT "..name,valueText(table.pack(...))) end)
            emit("LISTEN",name)
        end
        local ownTool=object:IsA("Tool") and (object:IsDescendantOf(player.Backpack) or player.Character and object:IsDescendantOf(player.Character))
        if ownTool then
            listen(object.Activated,function() emit("TOOL ACTIVATED",path(object).." "..snapshot(object)) end)
            listen(object.Equipped,function() emit("TOOL EQUIPPED",path(object)) end)
            listen(object.Unequipped,function() emit("TOOL UNEQUIPPED",path(object)) end)
        end
        local root=player.Character and object:IsDescendantOf(player.Character) and (object:IsA("Humanoid") or object.Name=="HumanoidRootPart")
        if ownTool or root or object==player or relevant(object) and not object:IsA("LuaSourceContainer") and not object:IsA("RemoteEvent") and not object:IsA("RemoteFunction") then
            if objectCount>=600 then objectLimited=true; return end
            objectCount=objectCount+1; watched[object]=path(object)
            emit("WATCH "..objectCount,object.ClassName.." "..path(object))
        end
    end
    local function textReport()
        return header.."\nCAPTURE SUMMARY\nElapsed: "..string.format("%.1fs",os.clock()-started).." | events: "..eventCount..
            " | event limit reached: "..tostring(eventLimited).." | source limit reached: "..tostring(sourceLimited).." | object limit reached: "..tostring(objectLimited)..
            "\nPolling: 0.5s. Short-lived objects or changes can be missed. Incoming events only; outgoing calls are not intercepted. Tool activations do not prove a server-accepted hit.\n\nTIMELINE\n"..
            table.concat(events).."\nSOURCE INSPECTION (untrusted text; never executed)\n"..table.concat(sources,"\n")
    end
    local function saveReport()
        if report=="" then status.Text="Start and stop a boss capture first."; return end
        local ok,err=pcall(function() assert(type(writefile)=="function","File saving unavailable"); writefile(filename,report) end)
        status.Text=ok and ("Saved "..filename.." in the executor workspace. Send this file.") or (tostring(err)..". Use Copy Boss Report.")
    end
    local function finish(reason)
        if not active then return end
        emit("STOP",reason); report=textReport(); active=false; generation=generation+1
        for _,link in ipairs(links) do link:Disconnect() end; links={}
        for _,job in ipairs(jobs) do pcall(task.cancel,job) end; jobs={}
        watched={}; seen={}; last={}; queue={}
        if not closed then saveReport()
        elseif type(writefile)=="function" then pcall(writefile,filename,report) end
    end
    connect(start.Activated,function()
        if active then status.Text="Boss capture is already running."; return end
        events={}; sources={}; links={}; jobs={}; watched={}; seen={}; last={}; queue={}; snapshotPending=false
        eventBytes=0; sourceBytes=0; eventCount=0; objectCount=0; eventLimited=false; sourceLimited=false; objectLimited=false
        report=""; started=os.clock(); active=true; generation=generation+1; local run=generation
        header="AcidHub Boss Fight Capture\nUTC: "..os.date("!%Y-%m-%d %H:%M:%S").."\nGame ID: "..game.GameId.." | Place ID: "..game.PlaceId..
            "\nFocused recording. No movement, combat, or setting changes. Explicit snapshot button sends one AskSnapshot request. Sources may be incomplete/decompiler output.\n"
        local settings={}
        for _,key in ipairs({"No Traps","NoSlow","AutoStealEnabled","Auto Treadmill","Auto Hatch","Auto Fuse","Steal Rift Pets"}) do
            local binding=settingsBindings[key]; if binding then local ok,value=pcall(binding.get); if ok then settings[key]=value else settings[key]="unavailable" end end
        end
        emit("SETTINGS",valueText(settings))
        local storage=game:GetService("ReplicatedStorage")
        listen(workspace.DescendantAdded,inspect)
        listen(storage.DescendantAdded,inspect)
        listen(player.DescendantAdded,inspect)
        listen(player.CharacterAdded,function(character) emit("CHARACTER ADDED",path(character)); for _,object in ipairs(character:GetDescendants()) do inspect(object) end end)
        listen(player.CharacterRemoving,function(character) emit("CHARACTER REMOVING",path(character)) end)
        inspect(player)
        -- Prioritize the actual character and tools ahead of cosmetic arena parts.
        if player.Character then for _,object in ipairs(player.Character:GetDescendants()) do inspect(object) end end
        for _,object in ipairs(player.Backpack:GetDescendants()) do inspect(object) end
        local scanner=task.spawn(function()
            for _,root in ipairs({player,workspace,storage}) do
                local objects=root:GetDescendants()
                for index,object in ipairs(objects) do
                    if not active or run~=generation then return end
                    if index>60000 then emit("SCAN LIMIT",path(root)); objectLimited=true; break end
                    inspect(object)
                    if index%300==0 then task.wait() end
                end
            end
            emit("INITIAL SCAN COMPLETE","Dynamic object/event observation continues")
        end)
        jobs[#jobs+1]=scanner
        jobs[#jobs+1]=task.spawn(function()
            while active and run==generation do
                local object=table.remove(queue,1)
                if object and not sourceLimited then
                    local name=path(object); local done,output=false,nil
                    local worker=task.spawn(function()
                        local ok,text=pcall(function() return object.Source end)
                        if not ok or type(text)~="string" or #text==0 then
                            if type(decompile)=="function" then ok,text=pcall(decompile,object)
                            else ok=false; text="Source/decompile unavailable" end
                        end
                        output=ok and type(text)=="string" and text or tostring(text); done=true
                    end)
                    jobs[#jobs+1]=worker
                    local deadline=os.clock()+12
                    while active and run==generation and not done and os.clock()<deadline do task.wait(0.1) end
                    if not active or run~=generation then return end
                    if not done then pcall(task.cancel,worker); output="Source inspection timed out" end
                    local chunk="TARGET: "..name.."\n"..tostring(output):sub(1,200000)..(#tostring(output)>200000 and "\n[SOURCE TRUNCATED]" or "").."\n"
                    if sourceBytes+#chunk>2000000 then sourceLimited=true else sources[#sources+1]=chunk; sourceBytes=sourceBytes+#chunk end
                    emit("SOURCE",name.." | "..#chunk.." bytes")
                else task.wait(0.25) end
            end
        end)
        -- Polling job exits itself; finish() only cancels other workers.
        task.spawn(function()
            local checkpoint=os.clock()+15
            while active and run==generation do
                for object,name in pairs(watched) do
                    if not object.Parent and object~=player then emit("REMOVED",name); watched[object]=nil; last[object]=nil; objectCount=objectCount-1
                    else
                        local ok,value=pcall(snapshot,object)
                        if ok and value~=last[object] then emit("STATE "..name,value); last[object]=value end
                    end
                end
                status.Text=string.format("RECORDING %.0fs | %d events | %d objects | %d source bytes. Fight manually; stop after returning to lobby.",os.clock()-started,eventCount,objectCount,sourceBytes)
                if os.clock()>=checkpoint then
                    checkpoint=os.clock()+15
                    if type(writefile)=="function" then pcall(writefile,filename,textReport()) end
                end
                if os.clock()-started>=1800 then finish("30-minute capture limit"); return end
                task.wait(0.5)
            end
        end)
    end)
    connect(snapshotButton.Activated,function()
        if not active then status.Text="Start Boss Capture first."; return end
        if snapshotPending or os.clock()-lastSnapshotRequest<10 then status.Text="Snapshot pending or on 10-second cooldown."; return end
        local storage=game:GetService("ReplicatedStorage")
        local remote=storage:FindFirstChild("RF/BossEvent/AskSnapshot",true)
        if not remote or not remote:IsA("RemoteFunction") then emit("SNAPSHOT ERROR","AskSnapshot RemoteFunction not found"); return end
        snapshotPending=true; lastSnapshotRequest=os.clock()
        local run=generation
        local completed=false
        emit("SNAPSHOT REQUEST","One AskSnapshot request, no arguments; no automatic retry")
        local worker=task.spawn(function()
            local result=table.pack(pcall(function() return remote:InvokeServer() end))
            completed=true; snapshotPending=false
            if active and run==generation then emit("SNAPSHOT RESPONSE",valueText(result)) end
        end)
        jobs[#jobs+1]=worker
        jobs[#jobs+1]=task.spawn(function()
            task.wait(12)
            if active and run==generation and not completed then
                pcall(task.cancel,worker); snapshotPending=false
                emit("SNAPSHOT TIMEOUT","No response within 12s; server outcome unknown; no retry")
            end
        end)
    end)
    connect(stop.Activated,function() finish("Stopped by user") end)
    connect(saveButton.Activated,function() if active then report=textReport() end; saveReport() end)
    connect(copy.Activated,function()
        if active then report=textReport() end
        if report=="" then status.Text="Start a boss capture first."; return end
        local ok=type(setclipboard)=="function" and pcall(setclipboard,report)
        status.Text=ok and "Boss report copied." or "Clipboard unavailable. Use Save Boss Report."
    end)
    table.insert(cleanupActions,function() finish("Hub closed") end)
end)() end

-- Config owns descriptions and versioned, validated settings in the executor workspace.
switch(configPage,"Details",false,function(value)
    detailsEnabled=value
    if value then panel.Size=UDim2.fromOffset(math.max(panel.AbsoluteSize.X,820),panel.AbsoluteSize.Y) end
    for _,update in ipairs(detailFrames) do update(value) end
end,"Show or hide explanatory boxes throughout AcidHub.")
local saveSettings=button("Save settings",UDim2.fromOffset(0,0),UDim2.new(1,0,1,0),row(configPage,38))
local resetSettings=button("Reset Settings",UDim2.fromOffset(0,0),UDim2.new(1,0,1,0),row(configPage,38))
local configStatus=label("Press Save settings to keep your changes for the next load.",UDim2.fromOffset(10,6),UDim2.new(1,-20,1,-12),row(configPage,110),true)
configStatus.TextSize=14
local settingsFile="AcidHub_Settings.json"
local jsonService=game:GetService("HttpService")
local function snapshotSettings(defaults)
    local values={}
    for key,binding in pairs(settingsBindings) do
        if defaults then values[key]=copySetting(binding.default)
        else values[key]=copySetting(binding.get()) end
    end
    return values
end
local function writeSettings(values)
    if type(writefile)~="function" then return false,"File saving is unavailable in this executor." end
    local ok,err=pcall(function()
        writefile(settingsFile,jsonService:JSONEncode({version=1,values=values}))
    end)
    return ok,ok and "Settings saved." or ("Could not save settings: "..tostring(err))
end
local function applySettings(values,restoring)
    -- Validate the entire file before changing controls. Missing keys use defaults.
    if type(values)~="table" then return false,"Invalid settings data." end
    local desired={}
    for key,binding in pairs(settingsBindings) do
        local value=values[key]
        if value==nil then value=copySetting(binding.default) end
        if not binding.validate(value) then return false,"Invalid setting: "..key end
        desired[key]=value
    end
    setSpeedEnabled(false)
    local failed={}
    local function apply(key)
        local binding=settingsBindings[key]
        local setter=restoring and binding.restore or binding.set
        local ok,result=pcall(setter,desired[key])
        if not ok or result==false then table.insert(failed,key) end
    end
    apply("TargetSpeed")
    apply("NoSlow")
    if restoring and #failed>0 then return false,"Saved automation startup paused: could not restore "..table.concat(failed,", ")..". Reload after your character is ready." end
    for key in pairs(settingsBindings) do
        if key~="TargetSpeed" and key~="NoSlow" and key~="KeepSpeed" and key~="AutoStealEnabled" and key~="Auto Fuse" and key~="Steal Rift Pets" then apply(key) end
    end
    apply("KeepSpeed")
    apply("Steal Rift Pets")
    apply("Auto Fuse")
    apply("AutoStealEnabled")
    return true,#failed>0 and ("Could not apply: "..table.concat(failed,", ")..". Try these controls after your character is ready.") or nil
end
connect(saveSettings.Activated,function()
    if speedEditing then configStatus.Text="Apply the edited speed or select Use Game Speed before saving."; return end
    local _,message=writeSettings(snapshotSettings(false))
    configStatus.Text=message
end)
connect(resetSettings.Activated,function()
    local defaults=snapshotSettings(true)
    local _,applyMessage=applySettings(defaults)
    local saved,message=writeSettings(defaults)
    configStatus.Text="Defaults restored."..(saved and " Defaults saved for next load." or (" "..message))
    if applyMessage then configStatus.Text=configStatus.Text.." "..applyMessage end
    local character=player.Character
    if character and (character:GetAttribute("AcidHubNoSlow") or character:GetAttribute("AcidHubHumanoidTest")) then
        configStatus.Text=configStatus.Text.." Rejoin to undo active No Slow."
    end
end)
do
    if type(readfile)~="function" then
        configStatus.Text="Auto-load unavailable: this executor does not provide readfile."
    else
        local existsOK,exists=true,true
        if type(isfile)=="function" then existsOK,exists=pcall(isfile,settingsFile) end
        if existsOK and not exists then
            configStatus.Text="Default settings. Press Save settings to keep your changes."
        else
            local readOK,contents=pcall(readfile,settingsFile)
            if readOK then
                local decodedOK,data=pcall(function() return jsonService:JSONDecode(contents) end)
                if decodedOK and type(data)=="table" and data.version==1 then
                    local applied,message=applySettings(data.values,true)
                    configStatus.Text=message or (applied and "Saved settings loaded." or "Settings could not be loaded.")
                else configStatus.Text="Saved settings are invalid or unsupported; defaults retained." end
            else configStatus.Text="No readable settings file. Press Save settings to create one." end
        end
    end
end

if not automationFlow.stealConfigured then settingsBindings.AutoStealEnabled.set(false) end

task.spawn(function()
    local elapsed = 2
    while not closed do
        local character = player.Character
        local humanoid = character and movementHumanoid(character)
        local pingOK,ping=pcall(function() return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() end)
        info.ServerPing.Text=pingOK and type(ping)=="number" and ping>=0 and string.format("Server Ping: %.0f ms",ping) or "Server Ping: unavailable"
        speedLabel.Text = humanoid and ("Walk speed: " .. tostring(humanoid.WalkSpeed) .. " studs/s") or "Walk speed: waiting for character"
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if root and root:IsA("BasePart") then
            local position=root.Position
            local velocity=root.AssemblyLinearVelocity
            local horizontalSpeed=Vector3.new(velocity.X,0,velocity.Z).Magnitude
            currentSpeedLabel.Text=string.format("Current speed: %.1f studs/s",horizontalSpeed)
            positionLabel.Text=string.format("Player position XYZ: %.1f, %.1f, %.1f",position.X,position.Y,position.Z)
        else
            positionLabel.Text="Player position XYZ: waiting for character"
            currentSpeedLabel.Text="Current speed: waiting for character"
        end
        if elapsed >= 2 then elapsed = 0; refresh() end
        task.wait(0.5)
        elapsed = elapsed + 0.5
    end
end)
]====]
local env=type(getgenv)=="function" and getgenv() or _G
env.AcidHubReloadSource=source
local run,err=loadstring(source)
if not run then error(err) end
run()
