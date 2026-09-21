-- AcidHub: single-file distribution, including automatic reconnect reload support.
-- The source below is retained in memory; no second Lua file is required.
local source=[====[
-- AcidHub: standalone Egg ESP, display name, and walk speed.
-- Requires the game's ReplicatedStorage.Client.EggState module for egg positions.
local function BuildAreas()
    local result={Options={},Aliases={},Configs={}}
    local function key(value) return tostring(value):lower():gsub("[^%w]","") end
    local directory=require(game:GetService("ReplicatedStorage").Data.Areas).Directory
    assert(type(directory)=="table","Live area directory unavailable")
    for id,config in pairs(directory) do
        if type(config)=="table" and config.GuardId and type(config.DropTable)=="table" then
            local name=config.DisplayName or id
            if not result.Configs[name] then result.Options[#result.Options+1]=name end
            result.Configs[name]=config
            result.Aliases[key(id)]=name; result.Aliases[key(config._id or id)]=name; result.Aliases[key(name)]=name
        end
    end
    table.sort(result.Options,function(a,b)
        local ar=result.Configs[a].Rarity; local br=result.Configs[b].Rarity
        local av=type(ar)=="table" and tonumber(ar.RarityNumber) or 0
        local bv=type(br)=="table" and tonumber(br.RarityNumber) or 0
        av,bv=av or 0,bv or 0
        return av==bv and a<b or av<bv
    end)
    assert(#result.Options>0,"No live steal areas available")
    return result
end
local LiveAreas=BuildAreas()
local function BuildRenderer()
-- Renderer for normalized, verified field-egg snapshots.
-- Input records: {id: string, area: string, position: Vector3, text: string}.
-- Receives field-egg snapshots from the reader below.
local Renderer = {}
local AREAS = LiveAreas.Options

function Renderer.new(parent)
    local self = {markers = {}, areas = {}, enabled = false, destroyed = false}
    for _, area in ipairs(AREAS) do self.areas[area] = true end
    local folder = Instance.new("Folder")
    folder.Name = "EggESPMarkers"
    folder:SetAttribute("AcidHubMarker", true)
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
-- Live game rarity metadata, with a readable Secret color for the dark hub/ESP UI.
local Rarity={Species={},Options={},Ranks={},Colors={Unknown=Color3.fromRGB(255,255,255)}}
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
        if key(rarity)=="secret" then color=Color3.fromRGB(173,216,255) end
        Rarity.Colors[rarity]=color
        local rank=type(value)=="table" and tonumber(value.RarityNumber) or nil
        if rarity~="Unknown" and rank and rank==rank and math.abs(rank)<math.huge then
            if not Rarity.Ranks[rarity] then Rarity.Options[#Rarity.Options+1]=rarity end
            Rarity.Ranks[rarity]=rank
        end
        local entry={name=name,category=category,rarity=rarity,color=color,source="Live game asset directory"}
        Rarity.Species[category]=entry
        byCategory[key(category)]=entry
        -- Ambiguous display names are not used to guess a category.
        local k=key(name)
        if byName[k]==nil then byName[k]=entry else byName[k]=false end
    end
end
table.sort(Rarity.Options,function(a,b) return Rarity.Ranks[a]==Rarity.Ranks[b] and a<b or Rarity.Ranks[a]<Rarity.Ranks[b] end)
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
    BackgroundColor3 = colors.panel, BorderSizePixel = 0, Visible = false,
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
local reopen = make("ImageButton", {
    Name = "AcidHubReopen", AnchorPoint = Vector2.new(0.5,0),
    Position = UDim2.new(0.5,0,0,12), Size = UDim2.fromOffset(52,52),
    BackgroundColor3 = colors.panel, BorderSizePixel = 0,
    Image = "", ScaleType = Enum.ScaleType.Fit, AutoButtonColor = true, Visible = true,
}, gui)
make("UICorner", {CornerRadius = UDim.new(0,12)}, reopen)
make("UIStroke", {Color = colors.accent, Thickness = 1, Transparency = 0.35}, reopen)
do
    -- Keep an icon available even when the executor cannot load local images.
    local fallback = make("Frame", {Name="FlaskFallback", Size=UDim2.fromScale(1,1), BackgroundTransparency=1}, reopen)
    local function shape(position,size,color,radius)
        local part=make("Frame", {Position=position, Size=size, BackgroundColor3=color, BorderSizePixel=0}, fallback)
        make("UICorner", {CornerRadius=UDim.new(0,radius)}, part)
        return part
    end
    shape(UDim2.fromOffset(13,22),UDim2.fromOffset(26,24),colors.accent,12)
    shape(UDim2.fromOffset(21,10),UDim2.fromOffset(10,21),colors.accent,2)
    shape(UDim2.fromOffset(18,8),UDim2.fromOffset(16,5),colors.accent,2)
    shape(UDim2.fromOffset(17,30),UDim2.fromOffset(18,12),Color3.fromRGB(173,245,35),6)
    shape(UDim2.fromOffset(24,18),UDim2.fromOffset(4,4),colors.panel,2)
    local function refreshIcon() fallback.Visible=not reopen.IsLoaded end
    connect(reopen:GetPropertyChangedSignal("IsLoaded"),refreshIcon)
    -- Paths are relative to Solara's workspace, like the confirmed Lua loader.
    local assetLoader = type(getcustomasset)=="function" and getcustomasset
        or type(getsynasset)=="function" and getsynasset
    if assetLoader then
        local ok,asset=pcall(assetLoader,"AcidHubIcon.png")
        if ok and type(asset)=="string" and asset~="" then reopen.Image=asset end
    end
    refreshIcon()
end
connect(minimize.Activated, function() panel.Visible = false; reopen.Visible = true end)
local function clampUIPosition(control,position)
    local viewport=gui.AbsoluteSize
    if viewport.X<=0 or viewport.Y<=0 then return position end
    local size=control.AbsoluteSize
    local x=position.X.Scale*viewport.X+position.X.Offset-size.X*control.AnchorPoint.X
    local y=position.Y.Scale*viewport.Y+position.Y.Offset-size.Y*control.AnchorPoint.Y
    local clampedX=math.clamp(x,0,math.max(0,viewport.X-size.X))
    local clampedY=math.clamp(y,0,math.max(0,viewport.Y-size.Y))
    return UDim2.new(position.X.Scale,position.X.Offset+clampedX-x,
        position.Y.Scale,position.Y.Offset+clampedY-y)
end
do
    local pointer,origin,startPosition
    local dragged=false
    connect(reopen.InputBegan,function(input)
        if pointer then return end
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            pointer=input; origin=input.Position; startPosition=reopen.Position; dragged=false
        end
    end)
    connect(Input.InputChanged,function(input)
        if not pointer then return end
        if input~=pointer and not (pointer.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement) then return end
        local delta=input.Position-origin
        if delta.Magnitude>=6 then dragged=true end
        if dragged then
            reopen.Position=clampUIPosition(reopen,UDim2.new(startPosition.X.Scale,startPosition.X.Offset+delta.X,
                startPosition.Y.Scale,startPosition.Y.Offset+delta.Y))
        end
    end)
    connect(Input.InputEnded,function(input)
        if input==pointer then pointer=nil end
        -- Retain dragged through Activated, regardless of release event ordering.
    end)
    connect(Input.WindowFocusReleased,function() pointer=nil; dragged=true end)
    connect(reopen.Activated,function(input)
        local isPointer=input and (input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch)
        if dragged and isPointer then return end
        panel.Visible=true; reopen.Visible=false
    end)
end
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
local tabs={
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
    miscTab.Position=UDim2.fromOffset(0,220); configTab.Position=UDim2.fromOffset(0,264)
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
do
    local function positionValue(control)
        local position=control.Position
        return {xScale=position.X.Scale,xOffset=position.X.Offset,yScale=position.Y.Scale,yOffset=position.Y.Offset}
    end
    local function validPosition(value)
        if type(value)~="table" then return false end
        for _,key in ipairs({"xScale","xOffset","yScale","yOffset"}) do
            local number=value[key]
            if type(number)~="number" or number~=number or math.abs(number)>1000000 then return false end
        end
        return true
    end
    local function bindPosition(key,control)
        registerSetting(key,positionValue(control),function() return positionValue(control) end,function(value)
            control.Position=clampUIPosition(control,UDim2.new(value.xScale,value.xOffset,value.yScale,value.yOffset))
        end,validPosition)
    end
    bindPosition("UI.PanelPosition",panel)
    bindPosition("UI.IconPosition",reopen)
    local function keepUIOnScreen()
        if closed then return end
        panel.Position=clampUIPosition(panel,panel.Position)
        reopen.Position=clampUIPosition(reopen,reopen.Position)
    end
    connect(gui:GetPropertyChangedSignal("AbsoluteSize"),keepUIOnScreen)
    task.defer(keepUIOnScreen)
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
local requestStates={}
local function awaitRequest(key,callback,readOnly)
    local previous=requestStates[key]
    if previous then error("Previous request pending or outcome unknown: "..tostring(key).."; inspect game state before reloading the hub") end
    local state={done=false}
    requestStates[key]=state
    task.spawn(function()
        state.result=table.pack(pcall(callback)); state.done=true
        if state.expired and readOnly then requestStates[key]=nil end
    end)
    local deadline=os.clock()+12
    while not state.done and not closed and os.clock()<deadline do task.wait(0.05) end
    if not state.done then
        state.expired=true
        error("Request timed out: "..tostring(key).."; outcome unknown, no automatic retry")
    end
    requestStates[key]=nil
    if not state.result[1] then error(state.result[2]) end
    return table.unpack(state.result,2,state.result.n)
end
local function invokeBounded(remote,...)
    local args=table.pack(...)
    local name=remote.Name:match("([^/]+)$")
    local readOnly=name=="AskState" or name=="FetchSummary" or name=="FetchWearBestStatus" or name=="AskSnapshot"
    return awaitRequest(remote,function() return remote:InvokeServer(table.unpack(args,1,args.n)) end,readOnly)
end
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
    if automationFlow.rift and automationFlow.rift.isActive() then any=true; table.insert(lines,"The Rift: "..(taskMessages["The Rift"] or "Waiting")) end
    if automationFlow.samples and automationFlow.samples.enabled() then any=true; table.insert(lines,"DrScrample: "..(taskMessages.DrScrample or "Waiting")) end
    currentTaskLabel.Text=automationFlow.bossPauseRequested and "Automations paused for boss battle" or (any and table.concat(lines,"\n") or "All automations OFF")
end
local function reportTask(name,message)
    taskMessages[name]=tostring(message)
    renderAutomationStatus()
end
local function flowPhase(phase,reason)
    -- Collection -> Samples (through outbreak end) -> Rift -> Fuse -> sales -> placement.
    -- Advance from the current stage; idle after placement must not restart it.
    local order={"samples","rift","fusing","selling","placing"}
    local previous=automationFlow.phase
    local advance=phase=="processing" and 0 or nil
    if phase=="idle" and reason~="Stopped all automations" then
        for index,name in ipairs(order) do if previous==name and index<#order then advance=index; break end end
    end
    if advance~=nil then
        phase="idle"
        for index=advance+1,#order do
            local nextPhase=order[index]
            local enabled=nextPhase=="samples" and automationFlow.samples and automationFlow.samples.isActive()
                or nextPhase=="rift" and automationFlow.rift and automationFlow.rift.isActive()
                or nextPhase=="fusing" and automationFlow.fuse
                or nextPhase=="selling" and automationFlow.sellSequence and automationFlow.sellSequence()
                or nextPhase=="placing" and automationFlow.place
            if enabled then phase=nextPhase; break end
        end
    end
    if phase=="samples" and previous~="samples" and automationFlow.samples and automationFlow.samples.enter then
        automationFlow.samples.enter()
    end
    if phase=="placing" and previous~="placing" then automationFlow.placementRound=automationFlow.placementRound+1 end
    if previous=="samples" and phase~="samples" and automationFlow.samples then automationFlow.samples.suspend() end
    if previous=="samples" and phase~="samples" and phase~="preparing" and phase~="stealing" then
        automationFlow.finishSampleSequence=true
    end
    if phase=="idle" or reason=="Stopped all automations" then automationFlow.finishSampleSequence=false end
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
    if not value then
        for _,key in ipairs({"DrScrample.AutoSamples","DrScrample.CollectLostParts"}) do
            if settingsBindings[key] then
                local ok,result=pcall(settingsBindings[key].set,false)
                if not ok or result==false then failures[#failures+1]=key end
            end
        end
        flowPhase("idle","Stopped all automations")
    end
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
    if not automationFlow.collecting and automationFlow.phase~="samples" and not automationFlow.finishSampleSequence then flowPhase("preparing","Day started: check location and wait 4 seconds") end
end
-- Persistent JSONL audit records use live game rarity, never the static display catalog.
do
(function()
    local audit={error=nil,queue={},files={},enabled=false,mode="Full"}
    automationFlow.audit=audit
    local MAX_LOG_BYTES=1024*1024
    local function enqueue(file,data)
        local bytes=0; for _,pending in pairs(audit.queue) do bytes=bytes+#pending end
        if bytes+#data>MAX_LOG_BYTES then
            audit.dropped=(audit.dropped or 0)+1
            audit.error="Log buffer full; dropped records: "..audit.dropped
            return
        end
        audit.queue[file]=(audit.queue[file] or "")..data
    end
    local http=game:GetService("HttpService")
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
        local _,rarity=Rarity.Resolve(category)
        return rarity,Rarity.Ranks[rarity]
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
                if event~="first_observed" or not data.values or not data.values.rarityRank or data.values.rarityRank<(Rarity.Ranks.Secret or math.huge) then return end
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
            enqueue(file,table.concat(fields,",").."\n")
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
        enqueue(file,encoded)
        audit.files[channel]=file
    end
    function audit.flush()
        if audit.flushing then return end
        audit.flushing=true
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
            if ok then local rest=(audit.queue[file] or ""):sub(#data+1); audit.queue[file]=rest~="" and rest or nil; audit.written=audit.written or {}; audit.written[file]=true
            else audit.error=tostring(err) end
        end
        audit.flushing=false
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
                            if values.rarityRank>=(Rarity.Ranks.Secret or math.huge) then audit.emit("Spawns","first_observed",{uid=record.Uid,values=values}) end
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
        Position=UDim2.fromOffset(10,30),Size=UDim2.new(1,-190,0,38),BackgroundTransparency=1,
        TextColor3=colors.text,TextSize=14,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextWrapped=true,
        TextEditable=false,ClearTextOnFocus=false,TextXAlignment=Enum.TextXAlignment.Left},currentServer)
    local reconnect=button("Reconnect",UDim2.new(1,-176,0,30),UDim2.fromOffset(102,36),currentServer)
    reconnect.TextSize=16
    local hop=button("Hop",UDim2.new(1,-66,0,30),UDim2.fromOffset(56,36),currentServer)
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
    local hopGeneration,hopWorker,hopActive=0,nil,false
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
        hopGeneration=hopGeneration+1
        if hopWorker and hopWorker~=coroutine.running() then pcall(task.cancel,hopWorker) end
        hopWorker=nil
        hopActive=false; hop.Text="Hop"
        joining=false; join.Text="Join"; reconnect.Text="Reconnect"; feedback.Text=message
    end
    -- SERVER HOP BEGIN
    local function chooseHopServer(servers,currentId)
        for _,server in ipairs(servers) do
            if type(server)=="table" then
                local playing,maximum=tonumber(server.playing),tonumber(server.maxPlayers)
                if type(server.id)=="string" and server.id~="" and server.id~=currentId
                    and playing and maximum and playing>=0 and maximum>0 and playing<maximum then
                    return server.id
                end
            end
        end
    end
    connect(hop.Activated,function()
        if joining then return end
        if type(game.JobId)~="string" or game.JobId=="" then feedback.Text="Current server ID unavailable."; return end
        joining=true; hopActive=true; hop.Text="Finding"
        feedback.Text="Finding another server with room..."
        joinDeadline=os.clock()+30
        hopGeneration=hopGeneration+1
        local generation=hopGeneration
        local function live() return not closed and joining and hopActive and generation==hopGeneration end
        hopWorker=task.spawn(function()
            local ok,err=pcall(function()
                local http=game:GetService("HttpService")
                local cursor,seen=nil,{}
                local destination
                for _=1,10 do
                    if not live() then return end
                    local url="https://games.roblox.com/v1/games/"..tostring(game.PlaceId).."/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"
                    if cursor then url=url.."&cursor="..http:UrlEncode(cursor) end
                    local data=http:JSONDecode(game:HttpGet(url))
                    if not live() then return end
                    assert(type(data)=="table" and type(data.data)=="table","Server list unavailable")
                    destination=chooseHopServer(data.data,game.JobId)
                    if destination then break end
                    cursor=data.nextPageCursor
                    if type(cursor)~="string" or cursor=="" or seen[cursor] then break end
                    seen[cursor]=true
                    task.wait(0.2)
                end
                if not live() then return end
                if not destination then failed("No other available server found. Try again shortly."); return end
                local queuedOK,queueError=prepareExecute()
                if not live() then return end
                if not queuedOK then failed("Auto Execute failed: "..tostring(queueError)); return end
                hop.Text="Joining"; feedback.Text="Joining a different server..."
                joinDeadline=os.clock()+30
                teleport:TeleportToPlaceInstance(game.PlaceId,destination,player)
            end)
            if not ok and live() then failed("Server Hop failed: "..tostring(err)) end
            if generation==hopGeneration then hopWorker=nil end
        end)
    end)
    -- SERVER HOP END
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
        hopGeneration=hopGeneration+1
        if hopWorker then pcall(task.cancel,hopWorker); hopWorker=nil end
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

local combatInput={delay=0.7}
do
    -- COMBAT INPUT POLICY BEGIN
    local function validAttackDelay(value)
        return type(value)=="number" and value==value and value>=0.01 and value<=60
    end
    local function attackReady(now,last,delay,cooling,cooldownEnd,serverNow)
        return now-last>=delay and not cooling and serverNow>=(tonumber(cooldownEnd) or 0)
    end
    local function newHeldJumpGate()
        local g={}
        function g:ready(now,grounded,airborne,retryDelay)
            if airborne then self.sawAir=true end
            if not grounded then return false end
            if not self.requestAt or self.sawAir or now-self.requestAt>=retryDelay then return true end
            return false
        end
        function g:sent(now) self.requestAt=now; self.sawAir=false end
        return g
    end
    -- COMBAT INPUT POLICY END
    local attackTimes=setmetatable({},{__mode="k"})
    function combatInput.attack(tool)
        local character=player.Character
        local humanoid=movementHumanoid(character)
        if closed or not tool or tool.Parent~=character or not tool:IsA("Tool")
            or tool:GetAttribute("IsBat")~=true or not humanoid or humanoid.Health<=0 then return false end
        local now=os.clock()
        if not attackReady(now,attackTimes[tool] or -math.huge,combatInput.delay,
            tool:GetAttribute("CooldownActive")==true,tool:GetAttribute("CooldownEndTime"),workspace:GetServerTimeNow()) then return false end
        attackTimes[tool]=now
        tool:Activate(); tool:Deactivate()
        return true
    end
    local attackRow=row(othersPage,76)
    label("Attack delay (seconds)",UDim2.fromOffset(10,4),UDim2.new(1,-20,0,25),attackRow,true)
    local box=make("TextBox",{Name="AttackDelay",Position=UDim2.fromOffset(10,34),Size=UDim2.new(1,-106,0,32),
        Text="0.7",ClearTextOnFocus=false,BackgroundColor3=colors.panel,TextColor3=colors.text,TextSize=14,
        Font=Enum.Font.Gotham,BorderSizePixel=0},attackRow)
    make("UICorner",{CornerRadius=UDim.new(0,6)},box)
    local apply=button("Apply",UDim2.new(1,-86,0,34),UDim2.fromOffset(76,32),attackRow)
    local delayStatus=label("Shared by boss, drones and continuous attacks. Game cooldowns still apply.",UDim2.fromOffset(10,4),UDim2.new(1,-20,1,-8),detailRow(othersPage,48),true)
    local function setDelay(value)
        if not validAttackDelay(value) then delayStatus.Text="Enter a delay from 0.01 to 60 seconds."; return false end
        combatInput.delay=value; box.Text=tostring(value)
        delayStatus.Text="Attack delay: "..tostring(value).."s. Shared by boss, drones and continuous attacks; game cooldowns still apply."
        return true
    end
    connect(apply.Activated,function() setDelay(tonumber(box.Text)) end)
    connect(box.FocusLost,function(enter) if enter then setDelay(tonumber(box.Text)) end end)
    registerSetting("AttackDelay",0.7,function() return combatInput.delay end,setDelay,validAttackDelay)
    local attacks,jumps=false,false
    local mouseHeld,spaceHeld=false,false
    local heldTool
    local jumpGate=newHeldJumpGate()
    local attackControl=switch(othersPage,"Continuous Attacks",false,function(value)
        attacks=value; mouseHeld=false; heldTool=nil
    end,"Hold left click with an equipped bat to repeat at Attack delay. Releasing click stops repetition.","ContinuousAttacks")
    combatInput.noSlowOrder=attackControl.Parent.LayoutOrder
    attackControl.Parent.LayoutOrder+=1
    local jumpControl=switch(othersPage,"Continuous Jumps",false,function(value)
        jumps=value; spaceHeld=false; jumpGate=newHeldJumpGate()
    end,nil,"ContinuousJumps")
    jumpControl.Parent.LayoutOrder+=1
    local jumpStatus=label("Hold Space to repeat on landing. Jump timing follows the live character and animation.",UDim2.fromOffset(10,4),UDim2.new(1,-20,1,-8),detailRow(othersPage,76),true)
    jumpStatus.TextSize=14
    local watched=setmetatable({},{__mode="k"})
    local function watchTool(tool)
        if not tool:IsA("Tool") or watched[tool] then return end
        watched[tool]=true
        connect(tool.Activated,function() attackTimes[tool]=os.clock() end)
    end
    local function clearHeld()
        mouseHeld=false; spaceHeld=false; heldTool=nil; jumpGate=newHeldJumpGate()
    end
    local function watchCharacter(character)
        clearHeld()
        for _,child in ipairs(character:GetChildren()) do watchTool(child) end
        connect(character.ChildAdded,watchTool)
    end
    if player.Character then watchCharacter(player.Character) end
    connect(player.CharacterAdded,watchCharacter)
    connect(player.CharacterRemoving,clearHeld)
    connect(Input.WindowFocusReleased,clearHeld)
    connect(Input.TextBoxFocused,clearHeld)
    connect(Input.InputBegan,function(input,processed)
        if processed or Input:GetFocusedTextBox() then return end
        if input.UserInputType==Enum.UserInputType.MouseButton1 and attacks then
            local character=player.Character
            local tool=character and character:FindFirstChildOfClass("Tool")
            if tool and tool:GetAttribute("IsBat")==true then
                heldTool=tool; mouseHeld=true
                -- The client's normal click supplies the first swing.
                attackTimes[tool]=os.clock()
            end
        elseif input.KeyCode==Enum.KeyCode.Space and jumps then
            spaceHeld=true; jumpGate=newHeldJumpGate()
        end
    end)
    connect(Input.InputEnded,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then mouseHeld=false; heldTool=nil end
        if input.KeyCode==Enum.KeyCode.Space then spaceHeld=false; jumpGate=newHeldJumpGate() end
    end)
    local animationAt=0
    local jumpAnimationLength
    local function readJumpAnimation(character,humanoid,now)
        if now-animationAt<1 then return end
        animationAt=now; jumpAnimationLength=nil
        local animate=character:FindFirstChild("Animate")
        local jump=animate and animate:FindFirstChild("jump")
        local animation=jump and jump:FindFirstChildWhichIsA("Animation",true)
        local animator=humanoid:FindFirstChildOfClass("Animator")
        local id=animation and animation.AnimationId:match("%d+")
        if id and animator then
            for _,track in ipairs(animator:GetPlayingAnimationTracks()) do
                if track.Animation and track.Animation.AnimationId:match("%d+")==id and track.Length>0 then
                    jumpAnimationLength=track.Length/math.max(math.abs(track.Speed),0.01)
                    break
                end
            end
        end
        jumpStatus.Text="Hold Space | Jump: "..(id and ("animation "..id) or "live Humanoid")
            ..(jumpAnimationLength and string.format(" | %.2fs",jumpAnimationLength) or "")..". Repeats on landing."
    end
    connect(game:GetService("RunService").Heartbeat,function()
        if closed then return end
        if Input:GetFocusedTextBox() then clearHeld(); return end
        local character=player.Character
        local humanoid=movementHumanoid(character)
        if not humanoid or humanoid.Health<=0 then clearHeld(); return end
        if attacks and mouseHeld then
            if heldTool and heldTool.Parent==character then combatInput.attack(heldTool) else mouseHeld=false; heldTool=nil end
        end
        if not jumps or not spaceHeld or treadmillExitBusy or humanoid.Sit or humanoid.PlatformStand then return end
        local now=os.clock()
        readJumpAnimation(character,humanoid,now)
        local state=humanoid:GetState()
        local grounded=humanoid.FloorMaterial~=Enum.Material.Air
            and state~=Enum.HumanoidStateType.Jumping and state~=Enum.HumanoidStateType.Freefall
        local airborne=humanoid.FloorMaterial==Enum.Material.Air or state==Enum.HumanoidStateType.Freefall
        local gravity=math.max(workspace.Gravity,1)
        local launch=humanoid.UseJumpPower and humanoid.JumpPower or math.sqrt(2*gravity*math.max(humanoid.JumpHeight,0))
        local retryDelay=math.max(0.2,jumpAnimationLength or (2*launch/gravity))
        if launch<=0 or not jumpGate:ready(now,grounded,airborne,retryDelay) then return end
        jumpGate:sent(now)
        if character:GetAttribute("AcidHubNoSlow")==true and combatInput.noSlowJump then
            combatInput.noSlowJump()
        elseif not requestTreadmillExitJump(character,humanoid,true) and humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
            humanoid.Jump=true
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
    table.insert(cleanupActions,clearHeld)
end

-- No Slow retains the working Animator and grounded jump handling.
do
    local noSlowRow=row(othersPage,42)
    noSlowRow.LayoutOrder=combatInput.noSlowOrder or noSlowRow.LayoutOrder
    local noSlowButton=button("No Slow",UDim2.fromOffset(6,6),UDim2.new(1,-12,0,30),noSlowRow)
    noSlowButton.Name="NoSlow"
    local noSlowStatus=label("ON enables No Slow and reapplies it after respawn. OFF restores the original Humanoid.",UDim2.fromOffset(10,6),UDim2.new(1,-20,1,-12),detailRow(othersPage,76),true)
    noSlowStatus.TextSize=14
    local replacementForInput,replacementCharacter
    local noSlowDesired=false
    local disableNoSlow
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
    combatInput.noSlowJump=requestReplacementJump
    table.insert(cleanupActions,function() combatInput.noSlowJump=nil end)
    connect(Input.JumpRequest,requestReplacementJump)
    connect(Input.InputBegan,function(input,processed)
        if not processed and input.KeyCode==Enum.KeyCode.Space then requestReplacementJump() end
    end)
    local function enableNoSlow(reapply)
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
        local movementControls
        do
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

        local camera=workspace.CurrentCamera
        local cameraSubject=camera and camera.CameraSubject
        local archivable=old.Archivable
        local cloneOK,replacement=pcall(function()
            old.Archivable=true
            return old:Clone()
        end)
        old.Archivable=archivable
        if not cloneOK or not replacement then

            noSlowStatus.Text="Could not clone Humanoid; original retained."
            return
        end
        replacement.Archivable=archivable
        do
            replacement.BreakJointsOnDeath=false
        end
        -- Preserve the existing Animator and its loaded tracks/references.
        -- Cloning an Animator does not preserve its live AnimationTracks.
        local clonedAnimator=replacement:FindFirstChildOfClass("Animator")
        if clonedAnimator then clonedAnimator:Destroy() end
        local respawnStorage
        do
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
            do
                old.Name="AcidHubRespawnHumanoid"
                old.EvaluateStateMachine=false
                replacement.Name="Humanoid"
            end
            replacement.Parent=character
            do
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

            pcall(function() if camera then camera.CameraSubject=cameraSubject end end)
            pcall(function() if animateEnabled then animate.Enabled=true end end)
            noSlowStatus.Text="Replacement failed; attempted to restore original: "..tostring(err)
            return
        end
        do
            local restored=false
            local movementConnection
            local wasManual=false
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
                                enableNoSlow(true)
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
                    if enableNoSlow(true) then return end
                end
                task.wait(0.5)
            end
        end)
    end)
    local function setNoSlow(value)
        if not value then
            if replacementForInput and not disableNoSlow then
                noSlowStatus.Text="A previous character replacement needs a rejoin to restore safely."
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
    -- Refresh the replacement without changing the saved/user No Slow preference.
    do
        local refreshing=false
        settingsBindings.NoSlow.refreshForTreadmill=function(character,stillIdle)
            if refreshing or closed or treadmillExitBusy or not noSlowDesired or player.Character~=character
                or (replacementForInput and (replacementCharacter~=character or not disableNoSlow))
                or not stillIdle() then return false end
            -- Share the exit transition lock: new movement waits until the Humanoid is stable.
            refreshing=true; treadmillExitBusy=true
            local ok,result=pcall(function()
                if disableNoSlow then disableNoSlow() end
                noSlowStatus.Text="Refreshing No Slow for treadmill startup..."
                for attempt=1,2 do
                    task.wait(0.5)
                    -- Complete restoration if work was queued, but respect user OFF, cleanup and respawn.
                    if closed or not noSlowDesired or player.Character~=character then return false end
                    local restoredOK,restored=pcall(enableNoSlow,true)
                    if restoredOK and restored then
                        adoptCharacter(character)
                        noSlowStatus.Text="No Slow refreshed; checking treadmill startup."
                        return true
                    end
                end
                noSlowStatus.Text="No Slow reapplication failed; another bounded recovery can retry."
                return false
            end)
            refreshing=false; treadmillExitBusy=false
            if not closed and player.Character==character and not stillIdle() then
                -- An OFF/new-sequence request during the lock still needs its deferred exit.
                pcall(function() requestTreadmillExitJump(character,movementHumanoid(character),true) end)
            end
            if not ok then
                if not closed then noSlowStatus.Text="Treadmill No Slow refresh failed: "..tostring(result) end
                return false
            end
            return result==true
        end
    end
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
                    local ok=enableNoSlow(true)
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
local areaOptions=LiveAreas.Options
local rarityOptions=Rarity.Options
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
        panel.Position = clampUIPosition(panel,UDim2.new(panelOrigin.X.Scale, panelOrigin.X.Offset + delta.X,
            panelOrigin.Y.Scale, panelOrigin.Y.Offset + delta.Y))
    end
end)
connect(Input.InputEnded, function(input)
    if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

local areas = LiveAreas.Aliases
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
-- Auto Steal filters, live target ranking, and collection controller.
do
    local previewAreas={}
    for _,name in ipairs(areaOptions) do previewAreas[name]=false end
    local minimum,priority,speciesText="All","Best Rarity",""
    local approachSpeed="Current Speed"
    local generation=0
    local function invalidate() generation=generation+1 end
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
        local function key(name) local k=tostring(name):lower():gsub("[^%w]",""); return LiveAreas.Aliases[k] or k end
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
    state.snapshot=progressionSnapshot
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
        local ar,br=Rarity.Ranks[speciesRarities[a]] or 0,Rarity.Ranks[speciesRarities[b]] or 0
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
    local function nameKey(value) return string.lower(value):gsub("[%s%-%_]","") end
    local ranks={}
    for name,rank in pairs(Rarity.Ranks) do ranks[name]=rank end
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
                    weight=weight,income=income}) end
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
    -- Automated collection controller.
    do
        local running=false
        local cycleJob
        local runId=0
        local job
        local heldPrompt,movingHumanoid
        local ignored={}
        local returnedHome=false
        local masterRow=row(autoStealPage,42)
        label("Auto Steal",UDim2.fromOffset(10,0),UDim2.new(1,-88,1,0),masterRow)
        local control=button("OFF",UDim2.new(1,-74,0,6),UDim2.fromOffset(64,30),masterRow)
        control.Parent.LayoutOrder=-1
        label("Uses your filters and the daily automation sequence. Remains ON while idle or recovering after respawn. Defaults to OFF; Save settings remembers your ON/OFF choice.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),detailRow(autoStealPage,130),true).TextSize=14

        local function note(message)
            reportTask("Auto Steal",message)
            automationFlow.audit.stealReason=message
            automationFlow.audit.emit("AutoSteal","status",{message=message})

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
            if automationFlow.bossPauseRequested or automationFlow.phase=="samples" or automationFlow.finishSampleSequence or treadmillExitBusy or (automationFlow.rift and automationFlow.rift.busy) then task.wait(0.1); return end
            if automationFlow.pendingDay then flowPhase("preparing","Starting the new day's collection") end
            if automationFlow.phase~="stealing" and automationFlow.phase~="preparing" then task.wait(0.25); return end
            if automationFlow.placing or not automationFlow.cycleReady then task.wait(0.25); return end
            local character=player.Character
            local humanoid=movementHumanoid(character)
            assert(character and humanoid and humanoid.Health>0,"Wait for a living character")
            assert(not character:FindFirstChild("AcidHubOriginalHumanoid"),"A previous character replacement conflicts with automatic movement. Rejoin before enabling No Slow.")
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
            if automationFlow.rift and automationFlow.rift.isActive() then
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
                if target.rift and (not automationFlow.rift or not automationFlow.rift.isActive() or automationFlow.rift.paused or not automationFlow.rift.bannerMatches() or target.riftKey~=automationFlow.rift.recipeKey) then return false,false end
                return generation==filterGeneration,false
            end
            local approached=directMove(character,humanoid,destination,approachCheck,3,45,outboundMode)
            if not approached then ignored[target.id]=os.clock()+20; note("Direct move did not reach target; moving to next target"); task.wait(0.5); return end
            local _,_,current=fields()
            if generation~=filterGeneration or not current[target.id] or not stealableFieldState(current[target.id].State) then return end
            note(string.format("Approach completed in %.2fs | WalkSpeed %.1f",os.clock()-approachStarted,humanoid.WalkSpeed))
            -- Hard stop and restore approach speed without a fixed pickup dwell.
            movingHumanoid=humanoid
            stopMotion()
            if target.rift and (not automationFlow.rift.isActive() or (automationFlow.rift.needs()[target.rawName] or 0)<=0) then return end
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
                        game:GetService("RunService").Heartbeat:Wait()
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
            local untilTime=os.clock()+8
            while running and not deliveredUid and not lostCarry and os.clock()<untilTime do checkDelivery(); task.wait(0.25) end
            if lostCarry then return end
            if not deliveredUid then ignored[target.id]=os.clock()+60; note("No matching owned egg confirmed at safe zone; moving to next target"); return end
            automationFlow.stealLimits.record(deliveredUid)
            automationFlow.indexCompletion.secured[target.rawName]=true
            ignored[target.id]=os.clock()+60
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

    end

end

local hatchOperationBusy=false
do

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
        local needed,reason=invokeBounded(haul.FetchWearBestStatus)
        if closed or not equipEnabled then return "Cancelled" end
        if needed==false then return "Best pets already equipped; no equip request needed." end
        if needed~=true then error("Equip Best status unavailable: "..tostring(reason)) end
        lastEquip=os.clock()
        local accepted,message=invokeBounded(haul.WearBest)
        if accepted~=true then error("WearBest denied: "..tostring(message or accepted)) end
        return "Best pets equipped (server confirmed)."
    end
    local attempted={}
    local retryAfter={}
    local function note(message)
        reportTask("Auto Hatch",message)
    end
    switch(autoHatchPage,"Auto Hatch",false,function(value)
        if value and hatchOperationBusy then note("Wait for the current hatch operation to finish."); return false end
        active=value
        note(value and "Auto Hatch ON" or (working and "OFF; current hatch may finish, no next egg will start." or "Auto Hatch OFF"))
    end,"Hatches ready owned eggs sequentially without animations. Explicit rejections retry after 30 seconds; rejected completion retries only FinishHatch. Unknown outcomes are not automatically repeated. OFF stops new hatches; special upgrade results are not handled.")
    switch(autoHatchPage,"Auto Equip Best",false,function(value)
        equipEnabled=value
        if not value then equipPending=false end
        reportTask("Auto Equip Best",value and "Waiting for a successful Auto Hatch" or "OFF")
    end,"After a successful Auto Hatch, checks the game's Equip Best status and requests WearBest when needed. Checks and equip calls are at least five seconds apart; multiple hatches during the cooldown share one request.")
    task.spawn(function()
        while not closed do
            if equipEnabled and equipPending and automationFlow.phase~="samples" and not automationFlow.selling and os.clock()-lastEquip>=5 and not (settingsBindings["Auto Fuse"] and settingsBindings["Auto Fuse"].busy()) and not (automationFlow.rift and automationFlow.rift.holdEquip()) then
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

    task.spawn(function()
        while not closed do
            if active and not working and automationFlow.phase~="samples" and not hatchOperationBusy and not automationFlow.selling then
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
                    if #ids==0 then return end
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
                        local accepted,message,outcome=awaitRequest("BeginHatch",function() return reader.BeginHatch(uid) end)
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
                    local finished,reason,assetUid=awaitRequest("FinishHatch",function() return reader.FinishHatch(uid) end)
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
                if not ok and not closed then note("Hatch error: "..tostring(err)) end
            end
            task.wait(2)
        end
    end)
    table.insert(cleanupActions,function() active=false; equipEnabled=false; equipPending=false end)
end

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
    if automationFlow.phase=="samples" then return false,"DrScrample owns movement; turn off event collection first" end
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
    if plot and plot.Parent then return plot,resolved end

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

    -- TREADMILL START WATCH BEGIN
    local function newTreadmillStartWatch()
        local w={attempts=0,nextTry=0}
        function w:check(now,character,belt,near,running)
            if self.character~=character or self.belt~=belt or not near or running==true then
                self.character=character; self.belt=belt; self.since=nil; self.attempts=0; self.nextTry=0
            end
            if not near or running~=false then return false end
            self.since=self.since or now
            if now-self.since<8 or now<self.nextTry or self.attempts>=2 then return false end
            self.attempts+=1; self.nextTry=now+45
            return true
        end
        return w
    end
    -- TREADMILL START WATCH END
    local trainingWatch=newTreadmillStartWatch()
    -- TREADMILL PROGRESS BEGIN
    local trainingObservation={}
    local function observeTraining(now,character,belt,near,anchored,power)
        local o=trainingObservation
        if o.character~=character or o.belt~=belt or not near then
            o.character=character; o.belt=belt; o.power=nil; o.since=now; o.progressAt=nil
        end
        if not near then return nil end
        if type(power)=="number" and power==power and math.abs(power)<math.huge then
            if o.power and power>o.power then o.progressAt=now end
            if o.power and power<o.power then o.since=now; o.progressAt=nil end
            o.power=power
        else power=nil end
        if not anchored then return false end
        if not power then return nil end
        if o.progressAt and now-o.progressAt<8 then return true end
        if now-(o.progressAt or o.since)<8 then return nil end
        return false
    end
    -- TREADMILL PROGRESS END

    local plot,active,token=nil,false,0
    local movingHumanoid
    local automatic=false
    local function note(message)
        reportTask("Auto Treadmill",message)
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
        if root.Anchored then note("Character is anchored. Leave the current activity before travel."); return end
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
    local function trainingAllowed()
        return automatic and not closed and automationFlow.phase=="idle" and not automationFlow.pendingDay
            and not automationFlow.bossPauseRequested and not treadmillExitBusy
            and not automationFlow.selling and not automationFlow.fusing
            and not (automationFlow.rift and automationFlow.rift.busy)
            and not automationFlow.placing and not automationFlow.collecting
    end
    task.spawn(function()
        while not closed do
            if trainingAllowed() and not active and not baseTravelActive then
                local character=player.Character
                local root=character and character:FindFirstChild("HumanoidRootPart")
                local humanoid=movementHumanoid(character)
                plot=resolveOwnedPlot()
                local belt=plot and plot:FindFirstChild("TreadmillBottom")
                local near=false
                if root and belt and belt:IsA("BasePart") then
                    local delta=root.Position-belt.Position
                    near=(Vector3.new(delta.X,0,delta.Z).Magnitude<=4 and math.abs(delta.Y)<=8)
                        or (root.Anchored and delta.Magnitude<10)
                end
                if near and humanoid and humanoid.Health>0 then
                    local ok,power=pcall(function() return require(game:GetService("ReplicatedStorage").Shared.Save).Get().SpeedPower end)
                    local now=os.clock()
                    local running=observeTraining(now,character,belt,true,root.Anchored,ok and power or nil)
                    local noSlow=settingsBindings.NoSlow
                    local canRefresh=noSlow and noSlow.get() and type(noSlow.refreshForTreadmill)=="function"
                    if running==true then
                        trainingWatch:check(now,character,belt,true,true)
                        note("Training confirmed: Speed Power is increasing.")
                    elseif canRefresh and trainingWatch:check(now,character,belt,true,running) then
                        note("Treadmill did not start; refreshing No Slow.")
                        local refreshed=noSlow.refreshForTreadmill(character,trainingAllowed)
                        if trainingAllowed() and player.Character==character then
                            note(refreshed and "No Slow refreshed; waiting for confirmed training progress."
                                or "No Slow refresh unavailable; treadmill startup still unconfirmed.")
                        end
                    else
                        if not canRefresh then trainingWatch:check(now,character,belt,false,nil) end
                        note(trainingWatch.attempts>=2 and "Training still unconfirmed after two refreshes; recovery paused."
                            or "At treadmill; waiting for training to start.")
                    end
                else
                    observeTraining(os.clock(),character,belt,false,false,nil)
                    trainingWatch:check(os.clock(),character,belt,false,nil)
                    runRoute()
                end
            elseif not active then
                trainingWatch:check(os.clock(),nil,nil,false,nil)
                observeTraining(os.clock(),nil,nil,false,false,nil)
            end
            task.wait(1)
        end
    end)

    connect(player.CharacterRemoving,function() stop("Respawn: plot ownership will be resolved again."); plot=nil end)
    table.insert(cleanupActions,function() automatic=false; stop(); plot=nil end)
end

-- Automatic egg placement; confirmation requires the exact owned UID.
do

    local active,sequence=false,0
    local requestPending=false
    local automatic=false
    local attemptedPlacement={}
    local placementRound=-1
    local function note(message) reportTask("Auto Place Eggs",message) end
    local function finish(message)
        active=false; sequence=sequence+1
        if not requestPending then automationFlow.placing=false end
        if message then note(message) end
    end

    connect(Input.InputBegan,function(input) if active and input.KeyCode==Enum.KeyCode.Escape then finish("Cancelled with Escape.") end end)

    local function placeOne()
        if automationFlow.phase=="samples" then return end
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
        if automatic and rift and rift.isActive() and rift.placementPriority then
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
                -- Cancel the remaining movement command and momentum at the pen center.
                humanoid:Move(Vector3.zero,false)
                humanoid:MoveTo(root.Position)
                if not root.Anchored then
                    root.AssemblyLinearVelocity=Vector3.zero
                    root.AssemblyAngularVelocity=Vector3.zero
                end
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
                        if os.clock()>deadline then error(name.." timed out; outcome unknown. No retry. Wait for pending request before another attempt.") end
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
                if not currentPlot or currentPlot.PlotFolder~=plot or currentPlot.PetArea~=petArea or petArea.CFrame~=cf or petArea.Size~=size then error("Plot changed; retry when ready.") end
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
            if not ok and active and sequence==run then finish("Placement stopped: "..tostring(err)) end
        end)
    end

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
    connect(player.CharacterRemoving,function() finish("Character changed; placement stopped.") end)
    table.insert(cleanupActions,function() automatic=false; automationFlow.place=false; finish() end)
end

-- Automatic upgrades and reward claims.
do
(function()
    local busy=false
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
            local summary=offlineSummary or invokeBounded(remotes.AwayEarnings.FetchSummary)
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
            if kind=="Trail" then accepted,message=invokeBounded(remotes.Trailwear.AskPurchase,current.key)
            elseif kind=="Base" then remotes.Homestead.AskBaseTierRaise:FireServer()
            elseif kind=="Treadmill" then accepted,message=invokeBounded(remotes.Treadmill.AskTierRaise,current.key)
            elseif kind=="Offline" then accepted,message,result=invokeBounded(remotes.AwayEarnings.AskCollect,{Kind="Claim"})
            else accepted,message,result=invokeBounded(remotes.Codex.AskRedeemAll) end
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
            error("Result unconfirmed after 12 seconds; inspect the game before retrying")
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
end)()
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
        local ar,br=Rarity.Ranks[ranks[a]] or math.huge,Rarity.Ranks[ranks[b]] or math.huge
        return ar==br and a<b or ar<br
    end)
    choice("Specific Species to Fuse","Fuse.Species",options,{},function() return species end,function(v) species=v end,true,function(v) return v.." ["..ranks[v].."]" end)
    switch(fusePage,"Skip Mutated Pets",false,function(v) skipMutated=v; invalidate() end,"Exclude pets with mutations or a base mutation, including Silver, Golden and Rainbow.")
    switch(fusePage,"Skip Equipped Pets",false,function(v) skipEquipped=v; invalidate() end,"Exclude pets listed in the game's EquippedAssets, including before loading and before the fuse request.")
    switch(fusePage,"Skip Very Heavy Pets",false,function(v) skipHeavy=v; invalidate() end,"Protect pets whose weight exceeds the selected multiple of their species' normal weight at scale 1. Missing weight data is excluded while this filter is ON.")
    choice("Heavy Weight Limit","Fuse.HeavyWeightLimit",{"2x Normal Weight","3x Normal Weight","5x Normal Weight","10x Normal Weight","20x Normal Weight"},"2x Normal Weight",function() return heavyLimit end,function(v) heavyLimit=v end,false)
    switch(fusePage,"Eject Incomplete Slots",false,function(v) ejectIncomplete=v; invalidate() end,"Return pets from an incomplete machine when fewer than three matching eligible pets are available. Never eject a full set or a running fuse.")
    -- Read the live scale generator locally; no server calls or fixed game probability tables.
    do
        local function escape(value) return tostring(value):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;") end
        local function color(value,hex) return '<font color="#'..hex..'">'..escape(value)..'</font>' end
        local cachedKey,cachedDistribution
        local function distribution(scales,kernel,records)
            local key=table.concat(scales,",")
            if key==cachedKey then return table.unpack(cachedDistribution) end
            local bands,index={},{}
            local function bias(lo,hi)
                assert(type(lo)=="number" and type(hi)=="number" and hi>=lo,"Invalid live size band")
                if not index[lo] then bands[#bands+1]={lo,hi}; index[lo]=#bands end
                return kernel.BandWeightBias(scales,lo,hi)
            end
            local function drawAt(value)
                local calls=0
                local rng={NextNumber=function()
                    calls=calls+1; assert(calls<=64,"Unsupported live random draw contract")
                    if calls==1 then return value elseif calls==2 then return 0 else return 1 end
                end}
                local scale=records.DrawAssetScale(rng,bias)
                assert(index[scale],"Live scale generator contract changed")
                return index[scale]
            end
            drawAt(0)
            assert(#bands>0,"Live size bands unavailable")
            local probabilities,previous={},0
            for i=1,#bands do
                local lo,hi=previous,1
                if i<#bands then
                    for _=1,46 do local mid=(lo+hi)/2; if drawAt(mid)<=i then lo=mid else hi=mid end end
                end
                local boundary=i==#bands and 1 or (lo+hi)/2
                probabilities[i]=math.max(0,boundary-previous); previous=boundary
            end
            -- Full-size quantiles include all current bonus rules via the real generator.
            local samples={}; local rng=Random.new(81731)
            for i=1,4096 do
                samples[i]=records.DrawAssetScale(rng,function(lo,hi) return kernel.BandWeightBias(scales,lo,hi) end)
                assert(type(samples[i])=="number" and samples[i]>0 and samples[i]<math.huge,"Invalid live size sample")
            end
            table.sort(samples)
            local function quantile(p) return samples[math.max(1,math.min(#samples,math.ceil(p*#samples)))] end
            cachedKey=key; cachedDistribution={bands,probabilities,quantile}
            return bands,probabilities,quantile
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
                local bands,probabilities,quantile=distribution(scales,kernel,require(storage.Shared.Util.EggRecords))
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
                local colors={"59D98E","C7D94B","52B9F3","E6C337","EE8840","A3C7BB","99ADB8","D266E0","9B72E4","E86DA1","F18BBD"}
                local order={}; for i in ipairs(bands) do order[#order+1]=i end
                table.sort(order,function(a,b) return probabilities[a]>probabilities[b] end)
                for _,i in ipairs(order) do
                    local b=bands[i]
                    local percent=100*probabilities[i]
                    local probability=percent<0.0001 and "< 0.0001%" or string.format(percent>=1 and "%.1f%%" or "%.3g%%",percent)
                    lines[#lines+1]=""
                    lines[#lines+1]=color(string.format("%.2f–%.2fx",b[1],b[2]),colors[(i-1)%#colors+1]).."  "..color(probability,colors[(i-1)%#colors+1])
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
                lines[#lines+1]=color("Live game size bands and tier odds. Final weight/income ranges are estimates from 4,096 local samples including current bonus rules. Mutation inheritance is not verified.","9BAABE")
                return table.concat(lines,"\n")
            end)
            return ok and result or ("Fuse Calculator unavailable: "..escape(result))
        end
    end
    local function canAffordFuse(save,decoded,kernel)
        local price=kernel.PriceFor(decoded)
        assert(type(price)=="number" and price==price and price>=0 and price<math.huge,"Fuse cost unavailable")
        assert(type(save.Money)=="number" and save.Money==save.Money,"Money unavailable")
        return save.Money>=price,price
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
        if save.FusionLocked or save.FusionEggReward~=false then note("Machine busy or reward pending; finish the existing reveal in the game first."); return end
        if not save.FusionInfoAcknowledged then note("Accept the game's fuse briefing first."); return end
        local function eligible(uid,item,inMachine,category)
            local ok=kernel.MayEnterFuse(uid,item,category,inMachine)
            if not ok then return false end
            local name=Rarity.Resolve(item.Category)
            local rarity,rank=automationFlow.audit.rarity(item.Category)
            if maximum~="All" and (not rank or rarity=="Unknown" or rank>(Rarity.Ranks[maximum] or 0)) then return false end
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
            return true,rank or math.huge
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
                    local ok,reason=invokeBounded(remotes.EjectPet,uid)
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
        local planned={}; for i,uid in ipairs(selected) do planned[i]=items.Decode(save.Inventory[uid]) end
        local affordable,price=canAffordFuse(save,planned,kernel)
        if not affordable then note("Not enough money to fuse | Cost: "..tostring(price).."; continuing sequence, checked again next cycle."); return end
        for i=#loaded+1,3 do
            if not live() then return end
            local current=read(); local item=current.Inventory[selected[i]]
            assert(not current.FusionLocked and current.FusionEggReward==false and item and eligible(selected[i],item,false,category or chosen.category),"Pet or machine changed before loading")
            note("Loading "..tostring(item.Category).." ("..i.."/3)")
            automationFlow.audit.emit("AutoFuse","load_requested",{uid=selected[i],slot=i,values=automationFlow.audit.values(item),maximum=maximum,priority=priority,skipEquipped=skipEquipped,skipHeavy=skipHeavy,heavyLimit=heavyLimit})
            local ok,reason=invokeBounded(remotes.LoadPet,selected[i])
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
        local affordable,price=canAffordFuse(read(),decoded,kernel)
        if not affordable then note("Not enough money to fuse | Cost: "..tostring(price).."; keeping slots and continuing sequence."); return end
        note("Fusing "..tostring(decoded[1].Category).." | Cost: "..tostring(kernel.PriceFor(decoded)))
        local inputValues={}; for i,item in ipairs(decoded) do inputValues[i]={uid=selected[i],values=automationFlow.audit.values(item)} end
        automationFlow.audit.emit("AutoFuse","fuse_requested",{pets=inputValues,cost=kernel.PriceFor(decoded),maximum=maximum})
        local accepted,reason,reward=invokeBounded(remotes.BeginFuse)
        automationFlow.audit.emit("AutoFuse","fuse_result",{accepted=accepted,message=reason,reward=reward})
        assert(accepted==true,"BeginFuse denied: "..tostring(reason))
        -- Complete accepted work even if OFF is clicked during the request.
        assert(require(storage.Shared.Types.FuseMachine).FuseResult(reward),"Invalid fuse result; recover pending reward in the game")
        local finished,finishReason=invokeBounded(remotes.FinishReveal)
        automationFlow.audit.emit("AutoFuse","finish_result",{accepted=finished,message=finishReason})
        assert(finished==true,"FinishReveal denied: "..tostring(finishReason).."; recover pending reward in the game")
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
    function rift.isActive() return rift.enabled and automationFlow.steal and not automationFlow.bossPauseRequested end
    local maximum="All"
    local page
    for _,tab in ipairs(tabs) do if tab.name=="Events" then page=tab.page.TheRiftSection.RiftSettings end end
    local function note(message) reportTask("The Rift",message) end
    local function changed()
        rift.revision=rift.revision+1; rift.paused=false; rift.refreshed=0
        if rift.isActive() and automationFlow.phase=="idle" then flowPhase("rift","Rift enabled/settings updated") end
    end
    switch(page,"Steal Rift Pets",false,function(v)
        rift.enabled=v; changed()
        if not v and not rift.busy and automationFlow.phase=="rift" then flowPhase("idle","Rift stage complete") end
        note(v and (automationFlow.steal and "Reading current recipe" or "Enabled; waiting for Auto Steal") or "OFF; an accepted trade will still finish granting its egg.")
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
    local choices={"All"}; for _,name in ipairs(Rarity.Options) do choices[#choices+1]=name end
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
        return rank~=nil and rank<=(Rarity.Ranks[maximum] or -math.huge)
    end
    function rift.refresh(force)
        if not rift.isActive() then return false end
        local data=require(game:GetService("ReplicatedStorage").Data.Rift)
        local rotation=math.floor(workspace:GetServerTimeNow()/data.RotationSeconds())
        if not force and rift.state and rift.rotation==rotation and rift.day==automationFlow.epoch and os.clock()-rift.refreshed<15 then return true end
        if rift.reading then return false end
        rift.reading=true
        local ok,state=pcall(function() return invokeBounded(require(game:GetService("ReplicatedStorage").Shared.Remotes).Rift.AskState) end)
        rift.reading=false
        if not ok or type(state)~="table" or type(state.Requirements)~="table" or #state.Requirements~=3 then rift.state=nil; note("Rift state unavailable; waiting for refresh"); return false end
        for _,c in ipairs(state.Requirements) do if type(c)~="string" then rift.state=nil; return false end end
        rift.state=state; rift.recipeKey=tostring(rotation)..":"..tostring(state.BannerId)..":"..table.concat(state.Requirements,"|"); rift.rotation=rotation; rift.day=automationFlow.epoch; rift.refreshed=os.clock()
        if rift.isActive() and not rift.paused and not rift.busy then
            local names={}; for _,c in ipairs(state.Requirements) do names[#names+1]=Rarity.Resolve(c) end
            note("Requires "..table.concat(names,", ").." | banner "..tostring(state.BannerId))
        end
        return true
    end
    connect(refreshButton.Activated,function() if rift.isActive() then task.spawn(function() rift.refresh(true) end) else note("Enable Auto Steal and Steal Rift Pets to read the live recipe.") end end)
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
        if not rift.isActive() or rift.paused or not rift.refresh(false) or not rift.bannerMatches() then return {} end
        local plan=rift.plan()
        if plan.blocked then return {} end
        return plan.missing
    end
    function rift.holdEquip()
        if not rift.isActive() or not rift.bannerMatches() then return false end
        local ok,plan=pcall(rift.plan)
        return not ok or rift.busy or (not plan.blocked and (next(plan.reserved)~=nil or plan.pending or plan.unplaced))
    end
    local function stage()
        if not rift.refresh(false) then return false end
        if not rift.bannerMatches() then note("Waiting for selected banner: "..rift.banner.."; continuing to Fuse/Treadmill"); return false end
        local plan=rift.plan()
        if plan.blocked then note("Recipe exceeds Max Trade Rarity; Rift skipped"); return false end
        if not plan.selected[1] or not plan.selected[2] or not plan.selected[3] then
            note("No complete eligible Rift pet set available; continuing to Fuse/Treadmill"); return false
        end
        if not rift.refresh(true) then return false end
        if not rift.bannerMatches() then return false end
        plan=rift.plan()
        if plan.blocked or not plan.selected[1] or not plan.selected[2] or not plan.selected[3] then return true end
        local token=rift.revision
        local storage=game:GetService("ReplicatedStorage")
        local remotes=require(storage.Shared.Remotes).Rift
        local before={}; local count=0
        for uid in pairs(plan.save.EggInventory) do before[uid]=true; count=count+1 end
        if count>=require(storage.Shared.Types.Eggs).MAX_INVENTORY then note("Rift waiting: egg inventory full"); return false end
        if closed or not rift.isActive() or token~=rift.revision or automationFlow.phase~="rift" or not rift.bannerMatches() then return false end
        local accepted,message=invokeBounded(remotes.AskTradeIn,plan.selected)
        assert(accepted==true,"Rift trade rejected: "..tostring(message))
        -- Finish accepted work even when disabled or a new day begins during the request.
        local result,reason=invokeBounded(remotes.AskFinishReveal)
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
            if rift.isActive() then
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
            if not rift.isActive() and not rift.busy and automationFlow.phase=="rift" then flowPhase("idle","Rift stage complete") end
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
    local rarities={"All"}; for _,name in ipairs(Rarity.Options) do rarities[#rarities+1]=name end
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
        local state=invokeBounded(require(game:GetService("ReplicatedStorage").Shared.Remotes).Rift.AskState)
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
        local rankMax=maximum=="All" and math.huge or (Rarity.Ranks[maximum] or -math.huge)
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
        return automationFlow.phase~="samples" and not automationFlow.selling and not automationFlow.placing and not automationFlow.fusing and not hatchOperationBusy and not (automationFlow.rift and automationFlow.rift.busy)
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
    -- Keep the legacy WeightPercentage setting key so saved display preferences still restore.
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
    local status=label("Pets: fuse icon loads a slot; Sell needs two clicks. Click elsewhere to cancel.",UDim2.fromOffset(18,90),UDim2.new(1,-36,0,44),window,true)
    status.TextSize=14
    local mutationCount=label("Mutation Consumables: —",UDim2.fromOffset(18,134),UDim2.new(1,-36,0,24),window)
    mutationCount.TextSize=14; mutationCount.Visible=false
    -- MUTATION CONSUMABLE MATCH BEGIN
    local function matchesMutationTool(tool,mutationId)
        if not tool:IsA("Tool") or tool:GetAttribute("ItemType")~="MutationConsumable" then return false end
        local id,template=tool:GetAttribute("MutationId"),tool:GetAttribute("MutationTemplate")
        if id~=nil and id~=mutationId then return false end
        if template~=nil and template~=mutationId then return false end
        return id==mutationId or template==mutationId
    end
    -- MUTATION CONSUMABLE MATCH END
    local function readMutationCount(mutationId)
        mutationId=mutationId or "Boss"
        local count=0
        local seen={}
        for _,container in ipairs({player.Backpack,player.Character or player.Backpack}) do
            for _,tool in ipairs(container:GetChildren()) do
                if not seen[tool] and matchesMutationTool(tool,mutationId) then
                    seen[tool]=true
                    local uses=tonumber(tool:GetAttribute("Uses"))
                    if not uses or uses<0 then return nil end
                    count=count+uses
                end
            end
        end
        return count
    end
    local function updateMutationCounts()
        local function count(id)
            local ok,value=pcall(readMutationCount,id)
            return ok and value and tostring(value) or "unavailable"
        end
        mutationCount.Text="Boss: "..count("Boss").."  |  Scrambled: "..count("Scrambled")
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
    local pendingSell
    local function cancelSell()
        local pending=pendingSell
        pendingSell=nil
        if pending then
            if pending.control.Parent then pending.paint(false) end
            if status.Text==pending.message then status.Text=pending.previousText end
        end
    end
    local function cancelSellForPointer(event)
        if not pendingSell then return end
        local kind=event.UserInputType
        if kind~=Enum.UserInputType.MouseButton1 and kind~=Enum.UserInputType.MouseButton2
            and kind~=Enum.UserInputType.MouseButton3 and kind~=Enum.UserInputType.Touch then return end
        local hits=playerGui:GetGuiObjectsAtPosition(event.Position.X,event.Position.Y)
        local control=pendingSell.control
        -- Containers may precede their children in the hit list. Recognize the
        -- button anywhere in that list; only its Activated event confirms a sale.
        for _,hit in ipairs(hits) do
            if hit==control or hit:IsDescendantOf(control) then return end
        end
        cancelSell()
    end
    connect(input.InputBegan,cancelSellForPointer)
    connect(grid:GetPropertyChangedSignal("CanvasPosition"),cancelSell)
    connect(window:GetPropertyChangedSignal("Visible"),function() if not window.Visible then cancelSell() end end)
    connect(panel:GetPropertyChangedSignal("Visible"),function() if not panel.Visible then cancelSell() end end)
    local function clearCards()
        cancelSell()
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
        local height=20+(options.Image and 142 or 0)+lines*22+(options.Name and 22 or 0)+(options.UID and 44 or 0)+(options.Status and 24 or 0)+(activeTab=="Eggs" and 22 or 0)+38
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
            cancelSell()
            activeTab=name; dirty=true; signature=nil; grid.CanvasPosition=Vector2.new()
            fit()
            grid.Visible=name~="Settings"; settings.Visible=name=="Settings"
            for key,control in pairs(tabsHere) do control.TextColor3=key==name and colors.accent or colors.text end
            status.Text=name=="Settings" and "Display preferences save with Config > Save settings. Size Percentage: normal species size = 100%." or
                (name=="Pets" and "Fuse icon loads a slot. Sell icon asks for confirmation; click its checkmark to sell, or elsewhere to cancel." or "Use the bottom-right vial icon on a growing pen egg for ONE Mutation Consumable (10% Boss chance). Each attempt spends an item.")
            clearCards()
        end)
    end
    tabsHere.Pets.TextColor3=colors.accent
    local sortOptions={"Rarity","Weight","Size %","Income"}
    local function sortDropdown(title,key,initial,get,assign)
        local sortRow=row(settings,42)
        label(title,UDim2.fromOffset(10,0),UDim2.new(0.45,-10,0,42),sortRow)
        local sortControl=button(initial.."  v",UDim2.new(0.45,0,0,6),UDim2.new(0.55,-10,0,30),sortRow)
        local sortList=make("Frame",{Position=UDim2.fromOffset(10,48),Size=UDim2.new(1,-20,0,140),BackgroundTransparency=1,Visible=false},sortRow)
        make("UIListLayout",{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder},sortList)
        local function set(value)
            if value=="Weight %" then value="Size %" end -- Migrate saved inventory sorting.
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
        registerSetting(key,initial,get,set,function(value) return value=="Weight %" or table.find(sortOptions,value)~=nil end)
    end
    sortDropdown("Sort By","InventoryPanel.SortBy","Rarity",function() return sortBy end,function(value) sortBy=value end)
    for _,spec in ipairs({{"Image","Show Pet Image"},{"Name","Show Name"},{"Rarity","Show Rarity"},{"Mutation","Show Mutation"},
        {"Weight","Show Weight"},{"WeightPercentage","Show Size Percentage"},{"Income","Show Income"},{"UID","Show UID"},{"Status","Show Status"},{"LivePreview","Live 3D Preview"}}) do
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
        assert(not (automationFlow.rift and automationFlow.rift.isActive()),"Turn OFF Auto Steal or Steal Rift Pets before manually using fuse slots")
        for _,key in ipairs({"Auto Fuse","Auto Sell Pets","Auto Sell Eggs","Auto Equip Best"}) do
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
        local accepted,reason=invokeBounded(require(storage.Shared.Remotes).Fusery.EjectPet,uid)
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
            local accepted,reason,reward=invokeBounded(remotes.BeginFuse)
            assert(accepted==true,reason or "Fuse request denied")
            assert(require(storage.Shared.Types.FuseMachine).FuseResult(reward),"Fuse accepted; invalid reward response. Check the machine before trying again.")
            local finished,finishReason=invokeBounded(remotes.FinishReveal)
            assert(finished==true,finishReason or "Reward pending; finish the reveal in the game ")
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
            local accepted,message=invokeBounded(require(storage.Shared.Remotes).Fusery.LoadPet,uid)
            assert(accepted==true,message or "LoadPet was not accepted")
            if not closed then status.Text="Loaded pet into a fuse slot: "..uid..". Fusion has not been started." end
        end)
        busy=false; dirty=true
        if not ok and not closed then status.Text=tostring(err) end
    end
    local mutationPending=false
    local mutationLastUse=-math.huge
    local function applyMutation(uid,mutationId)
        mutationId=mutationId or "Boss"
        if mutationId~="Boss" and mutationId~="Scrambled" then return end
        if busy or mutationPending or os.clock()-mutationLastUse<1 then return end
        local reader=require(storage.Client.EggState)
        local tool,egg,beforeUses,beforeMutation
        local ready,reason=pcall(function()
            assert(not closed,"Hub closed")
            assert(automationFlow.phase~="samples","Turn OFF event collection before using a mutation item")
            for _,key in ipairs({"Auto Hatch","Auto Sell Eggs"}) do
                assert(not settingsBindings[key] or not settingsBindings[key].get(),"Turn OFF "..key.." before using a mutation item")
            end
            assert(not automationFlow.selling,"Wait for the current sale to finish")
            local eggs=reader.ReadOwnerEggs(player.UserId)
            egg=assert(type(eggs)=="table" and eggs[uid],"Egg is no longer in your inventory")
            assert(egg.Placement~=nil,"Choose an egg placed in your pen")
            assert(not reader.IsReadyToHatch(uid),"Choose a growing egg; this egg is ready to hatch")
            beforeMutation=mutationNames(egg.Mutations,egg.BaseMutation)
            assert(not beforeMutation:lower():find(mutationId:lower(),1,true),"This egg already has "..mutationId.." mutation")
            beforeUses=assert(readMutationCount(mutationId),"Item count unavailable")
            assert(beforeUses>0,"No "..mutationId.." consumables remaining")
            for _,container in ipairs({player.Backpack,player.Character or player.Backpack}) do
                for _,candidate in ipairs(container:GetChildren()) do
                    if matchesMutationTool(candidate,mutationId) and (tonumber(candidate:GetAttribute("Uses")) or 0)>0 then tool=candidate; break end
                end
                if tool then break end
            end
            assert(tool,"Mutation Consumable tool unavailable")
        end)
        if not ready then status.Text=tostring(reason); return end
        local remote=storage:FindFirstChild("RF/BossMastery/AskUseMutationConsumable",true)
        if not remote or not remote:IsA("RemoteFunction") then status.Text="Mutation request unavailable"; return end
        busy=true; mutationPending=true; mutationLastUse=os.clock()
        status.Text="Applying ONE "..mutationId.." consumable to egg "..uid.."..."
        local responded=false
        task.delay(15,function()
            if not responded and not closed then status.Text="Mutation response pending. Further uses blocked; no retry sent." end
        end)
        local ok,err=pcall(function()
            local character=assert(player.Character,"Character unavailable")
            local humanoid=assert(movementHumanoid(character),"Humanoid unavailable")
            assert(humanoid.Health>0,"Wait for respawn")
            if tool.Parent~=character then humanoid:EquipTool(tool) end
            assert(tool.Parent==character and matchesMutationTool(tool,mutationId),"Could not equip the selected mutation consumable")
            -- Retain the existing one-UID request; the equipped tool identifies the mutation. No retries.
            local result=table.pack(invokeBounded(remote,uid))
            responded=true
            local deadline=os.clock()+5
            local afterMutation,afterUses=beforeMutation,beforeUses
            repeat
                task.wait(0.2)
                local current=reader.ReadOwnerEggs(player.UserId)
                local currentEgg=current and current[uid]
                afterUses=readMutationCount(mutationId)
                if currentEgg then afterMutation=mutationNames(currentEgg.Mutations,currentEgg.BaseMutation) end
                if afterMutation~=beforeMutation or (afterUses and afterUses<beforeUses) then break end
            until closed or os.clock()>=deadline
            if not closed then
                local countText=afterUses and tostring(afterUses) or "unavailable"
                updateMutationCounts()
                if afterMutation:lower():find(mutationId:lower(),1,true) then
                    status.Text=mutationId.." mutation observed! Remaining items: "..countText
                elseif afterUses and afterUses<beforeUses then
                    status.Text="Item consumed; "..mutationId.." mutation not observed. Remaining: "..countText..". No retry sent."
                else
                    status.Text="Use unconfirmed. Server result: "..tostring(result[1]).." | "..tostring(result[2])..". No retry sent."
                end
            end
        end)
        responded=true; mutationPending=false; busy=false; dirty=true; mutationLastUse=os.clock()
        if not ok and not closed then status.Text="Mutation use stopped: "..tostring(err)..". No retry sent." end
    end
    local saleRequests={}
    local function saleCandidate(uid)
        assert(not closed,"Hub closed")
        assert(not busy and not mutationPending,"Wait for the current panel action to finish")
        assert(not automationFlow.fusing and not automationFlow.selling and not automationFlow.placing
            and not hatchOperationBusy and not (automationFlow.rift and automationFlow.rift.busy),"Wait for inventory work to finish")
        assert(not (automationFlow.rift and automationFlow.rift.isActive()),"Turn OFF Auto Steal or Steal Rift Pets before selling manually")
        for _,key in ipairs({"Auto Fuse","Auto Sell Pets","Auto Sell Eggs","Auto Equip Best"}) do
            assert(not settingsBindings[key] or not settingsBindings[key].get(),"Turn OFF "..key.." before selling manually")
        end
        assert(not saleRequests[uid],"A sale was already sent for this pet; check inventory before trying again")
        local save=assert(require(storage.Shared.Save).Get(),"Save unavailable")
        assert(type(save.Inventory)=="table" and type(save.EquippedAssets)=="table" and type(save.FusionSlots)=="table","Pet state unavailable")
        local raw=assert(save.Inventory[uid],"Pet is no longer in your inventory")
        local items=require(storage.Shared.Util.AssetItems)
        local item=items.Decode(raw)
        assert(not item.IsFavorite,"Unfavorite this pet before selling")
        assert(not item.InFuse and not table.find(save.FusionSlots,uid),"Eject this pet from the fuse machine before selling")
        assert(not table.find(save.EquippedAssets,uid),"Unequip this pet before selling")
        local price=items.SalePrice(item)
        assert(type(price)=="number" and price>=0 and price<math.huge,"Sale value unavailable")
        return Rarity.Resolve(item.Category),price
    end
    local function sellPet(uid,name)
        -- Recheck ownership/protections at confirmation, then send exactly one UID.
        local valid,reason=pcall(saleCandidate,uid)
        if not valid then status.Text=tostring(reason); return end
        busy=true; automationFlow.selling=true
        local ok,err=pcall(function()
            saleRequests[uid]=true -- Uncertain requests are never resent in this session.
            require(storage.Shared.Remotes).PetSatchel.SellSelection:FireServer({Assets={uid},Eggs={}})
            status.Text="Selling "..name.."..."
            local deadline=os.clock()+12
            repeat
                local save=require(storage.Shared.Save).Get()
                if save and type(save.Inventory)=="table" and save.Inventory[uid]==nil then
                    if not closed then status.Text="Sold "..name.."." end
                    return
                end
                task.wait(0.25)
            until closed or os.clock()>=deadline
            error("Sale unconfirmed. Check inventory; no repeat request will be sent for this pet.")
        end)
        busy=false; automationFlow.selling=false; dirty=true
        if not ok and not closed then status.Text=tostring(err) end
    end
    local function clickSell(entry,control,paint)
        if pendingSell and pendingSell.uid==entry.uid and pendingSell.control==control then
            cancelSell()
            sellPet(entry.uid,entry.name)
            return
        end
        cancelSell()
        local ok,name,price=pcall(saleCandidate,entry.uid)
        if not ok then status.Text=tostring(name); return end
        local message="Sell "..name.." for $"..(Rarity.ESP.compact(price) or tostring(price)).."? Click its checkmark to confirm; click elsewhere to cancel."
        pendingSell={uid=entry.uid,control=control,paint=paint,message=message,previousText=status.Text}
        paint(true); status.Text=message
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
                    assert(directory[item.Category],"Species missing from live directory")
                    local name,rarity,color=Rarity.Resolve(item.Category)
                    local _,rank=automationFlow.audit.rarity(item.Category)
                    local weight=items.WeightKg(item)
                    local scale=tonumber(item.Scale)
                    local income=earnings.RatePerSecond(item)
                    local mutation=mutationNames(item.Mutations,item.BaseMutation)
                    local inSlot,equipped=false,false
                    for _,equippedUID in pairs(save.EquippedAssets or {}) do if equippedUID==uid then equipped=true end end
                    for _,slot in pairs(save.FusionSlots or {}) do if slot==uid then inSlot=true end end
                    return {uid=tostring(uid),item=item,name=name,rarity=rarity,rank=rank,color=color,weight=weight,
                        percent=scale and scale>=0 and scale<math.huge and scale*100 or nil,income=income,mutation=mutation,
                        inSlot=inSlot,equipped=equipped,placed=raw.Placement~=nil}
                end)
                if ok then
                    result[#result+1]=entry
                    parts[#parts+1]=table.concat({entry.uid,entry.name,entry.rarity,tostring(entry.weight),tostring(entry.percent),tostring(entry.income),entry.mutation,tostring(entry.inSlot),tostring(entry.placed),tostring(entry.equipped)},"|")
                else
                    result[#result+1]={uid=tostring(uid),name=tostring(raw.Category or raw.AssetCategory or "Pet"),error=tostring(entry),color=colors.muted}
                    parts[#parts+1]=tostring(uid)..tostring(entry)
                end
            end
        end
        table.sort(parts)
        local sortFields={Rarity="rank",Weight="weight",["Size %"]="percent",Income="income"}
        local field=sortFields[sortBy] or "rank"
        table.sort(result,function(a,b)
            local av,bv=a[field] or -math.huge,b[field] or -math.huge
            if av~=bv then return av>bv end
            if a.name~=b.name then return a.name<b.name end
            return a.uid<b.uid
        end)
        return result,table.concat(parts,"\n")
    end
    local function hatchTimeText(egg,records,now)
        local speed=egg.GrowthSpeedMultiplier
        assert(type(speed)=="number" and speed>0 and speed<math.huge,"Growth speed unavailable")
        local credit=records.CurrentNightCredit(egg,now,speed)
        local remaining=records.GrowthSecondsRemaining(egg,now,speed,credit,player)/speed
        assert(type(remaining)=="number" and remaining==remaining and math.abs(remaining)<math.huge,"Invalid growth time")
        local seconds=math.ceil(math.max(0,remaining))
        if seconds==0 then return "Ready to hatch" end
        local h=math.floor(seconds/3600)
        local m=math.floor(seconds%3600/60)
        local sec=seconds%60
        local time=h>0 and string.format("%dh %dm %ds",h,m,sec) or (m>0 and string.format("%dm %ds",m,sec) or (sec.."s"))
        return "Hatch: "..time
    end
    local function cardActionIcon(card,isPet,enabled)
        local control=button("",UDim2.new(1,-40,1,-38),UDim2.fromOffset(30,30),card)
        control.Name=isPet and "LoadFusePet" or "UseMutationConsumable"
        control.AutoButtonColor=enabled
        control.Active=enabled
        control.BackgroundColor3=colors.panel
        local ink=enabled and colors.accent or colors.muted
        local function shape(x,y,w,h,rotation,round)
            local part=make("Frame",{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
                BackgroundColor3=ink,BorderSizePixel=0,Rotation=rotation or 0,Active=false},control)
            if round then make("UICorner",{CornerRadius=UDim.new(1,0)},part) end
            return part
        end
        if isPet then
            -- Three inputs converging into one output: fuse/load icon.
            shape(8,8,12,2,35); shape(8,20,12,2,-35); shape(8,14,12,2)
            shape(4,4,6,6,0,true); shape(4,12,6,6,0,true); shape(4,20,6,6,0,true)
            shape(20,11,8,8,0,true)
        else
            -- Consumable vial, drawn locally so no external icon asset is required.
            shape(11,5,8,3); shape(13,8,4,5)
            local vial=shape(9,12,12,13,0,true)
            vial.BackgroundColor3=colors.panel
            make("UIStroke",{Color=ink,Thickness=1.5},vial)
            shape(11,18,8,5,0,true)
            shape(23,5,2,6); shape(21,7,6,2)
        end
        return control
    end
    local function sellActionIcon(card,enabled)
        local control=button("",UDim2.new(1,-76,1,-38),UDim2.fromOffset(30,30),card)
        control.Name="SellInventoryPet"; control.Active=enabled; control.AutoButtonColor=enabled
        control.BackgroundColor3=colors.panel
        local coin=label("$",UDim2.fromOffset(0,0),UDim2.fromScale(1,1),control)
        coin.TextSize=22; coin.TextXAlignment=Enum.TextXAlignment.Center
        coin.TextColor3=enabled and colors.accent or colors.muted
        local check=make("Frame",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false},control)
        for _,part in ipairs({{7,16,9,3,45},{12,12,15,3,-45}}) do
            make("Frame",{Position=UDim2.fromOffset(part[1],part[2]),Size=UDim2.fromOffset(part[3],part[4]),
                Rotation=part[5],BackgroundColor3=Color3.fromRGB(255,201,92),BorderSizePixel=0},check)
        end
        local function paint(confirm) coin.Visible=not confirm; check.Visible=confirm end
        return control,paint
    end
    local function updateEggTimers()
        local reader=require(storage.Client.EggState)
        local records=require(storage.Shared.Util.EggRecords)
        local eggs=reader.ReadOwnerEggs(player.UserId)
        local now=workspace:GetServerTimeNow()
        for _,card in ipairs(cards) do
            if card.hatchLabel then
                local egg=eggs and eggs[card.entry.uid]
                local ok,text=pcall(function()
                    assert(egg and egg.Placement,"Egg is no longer in pen")
                    return hatchTimeText(egg,records,now)
                end)
                card.hatchLabel.Text=ok and text or "Hatch: unavailable"
            end
        end
    end
    local function build(entries)
        clearCards(); fit()
        for index,entry in ipairs(entries) do
            local card=make("Frame",{BackgroundColor3=colors.card,BorderSizePixel=0},gridContent)
            make("UICorner",{CornerRadius=UDim.new(0,7)},card)
            card.LayoutOrder=index; card.Name="Inventory_"..entry.uid
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
                if options.WeightPercentage then line("Size: "..(entry.percent and string.format("%.0f%%",entry.percent) or "unavailable")) end
                if options.Income then line((Rarity.ESP.compact(entry.income) or "?").."/s",colors.accent) end
            end
            if options.UID then
                make("TextBox",{Text=entry.uid,ClearTextOnFocus=false,TextEditable=false,MultiLine=false,TextWrapped=true,
                    TextSize=14,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold),TextColor3=colors.muted,BackgroundTransparency=1,Size=UDim2.new(1,-20,0,40),Position=UDim2.fromOffset(10,y)},card)
                y=y+44
            end
            if options.Status then line(activeTab=="Pets" and (entry.equipped and "Equipped" or "In Backpack") or (entry.placed and "In Pen" or "In Backpack"),colors.accent) end
            local hatchLabel
            if activeTab=="Eggs" and entry.placed and not entry.error then
                hatchLabel=label("Hatch: ...",UDim2.fromOffset(10,y),UDim2.new(1,-20,0,22),card)
                hatchLabel.TextSize=14; hatchLabel.TextTruncate=Enum.TextTruncate.AtEnd; hatchLabel.TextWrapped=false
            end
            cards[#cards+1]={frame=card,icon=icon,entry=entry,hatchLabel=hatchLabel}
            local isPet=activeTab=="Pets"
            local action=cardActionIcon(card,isPet,not entry.error)
            if not entry.error then
                cardConnections[#cardConnections+1]=action.Activated:Connect(function()
                    cancelSell()
                    if isPet then loadPet(entry.uid) else applyMutation(entry.uid,"Boss") end
                end)
            end
            if not isPet then
                local scrambled=button("",UDim2.new(1,-76,1,-38),UDim2.fromOffset(30,30),card)
                scrambled.Name="UseScrambledConsumable"
                scrambled.BackgroundColor3=colors.panel
                scrambled.Active=not entry.error; scrambled.AutoButtonColor=not entry.error
                make("ImageLabel",{Name="ScrambledIcon",Image="rbxassetid://134710848063255",
                    BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ScaleType=Enum.ScaleType.Fit,
                    ImageTransparency=entry.error and 0.5 or 0},scrambled)
                if not entry.error then
                    cardConnections[#cardConnections+1]=scrambled.Activated:Connect(function()
                        cancelSell(); applyMutation(entry.uid,"Scrambled")
                    end)
                end
            end
            if isPet then
                local sell,paint=sellActionIcon(card,not entry.error)
                if not entry.error then
                    cardConnections[#cardConnections+1]=sell.Activated:Connect(function() clickSell(entry,sell,paint) end)
                end
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
        local nextRead,nextHatchUpdate=0,0
        while not closed do
            if window.Visible and activeTab~="Settings" then
                if dirty or os.clock()>=nextRead then
                    if activeTab=="Pets" then
                        local slotsOK,slotsError=pcall(updateSlots)
                        if not slotsOK then status.Text="Fuse slots unavailable: "..tostring(slotsError) end
                    end
                    if activeTab=="Eggs" then
                        updateMutationCounts()
                    end
                    local ok,entries,newSignature=pcall(readInventory)
                    if ok then
                        if dirty or signature~=newSignature then
                            local built,buildError=pcall(build,entries)
                            if built then signature=newSignature; nextHatchUpdate=0
                            else clearCards(); signature=nil; status.Text="Panel display unavailable: "..tostring(buildError) end
                        end
                    else status.Text="Inventory unavailable: "..tostring(entries) end
                    dirty=false; nextRead=os.clock()+2
                end
                if activeTab=="Eggs" and os.clock()>=nextHatchUpdate then
                    local timed=pcall(updateEggTimers)
                    if not timed then
                        for _,card in ipairs(cards) do if card.hatchLabel then card.hatchLabel.Text="Hatch: unavailable" end end
                    end
                    nextHatchUpdate=os.clock()+1
                end
                local previewOK,previewError=pcall(updatePreviews)
                if not previewOK then status.Text="Preview unavailable: "..tostring(previewError) end
            end
            task.wait(0.1)
        end
    end)
    table.insert(cleanupActions,clearCards)
end)() end

-- DrScrample event: production controls and coordinated sample collection.
do (function()
    local eventPage
    for _,tab in ipairs(tabs) do if tab.name=="Events" then eventPage=tab.page end end
    if not eventPage then return end
    local section=make("Frame",{Name="DrScrampleSection",Size=UDim2.new(1,-6,0,36),BackgroundTransparency=1,LayoutOrder=2},eventPage)
    local expand=button("DrScrample  >",UDim2.new(),UDim2.new(1,0,0,36),section)
    expand.TextXAlignment=Enum.TextXAlignment.Left
    local eventBody=make("Frame",{Name="DrScrampleSettings",Position=UDim2.fromOffset(0,44),Size=UDim2.new(1,0,0,0),BackgroundTransparency=1,Visible=false},section)
    local layout=make("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},eventBody)
    local function resizeSection()
        eventBody.Size=UDim2.new(1,0,0,layout.AbsoluteContentSize.Y)
        section.Size=UDim2.new(1,-6,0,eventBody.Visible and layout.AbsoluteContentSize.Y+48 or 36)
    end
    connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"),resizeSection)
    connect(expand.Activated,function()
        eventBody.Visible=not eventBody.Visible; expand.Text=eventBody.Visible and "DrScrample  v" or "DrScrample  >"; resizeSection()
    end)
    -- SCRAMBLE HELPERS BEGIN
    local function tierAllowed(tier, selection) return selection[tier] == true end
    local function waypointPassed(px,pz,ax,az,bx,bz,reach)
        local dx,dz=px-bx,pz-bz
        if dx*dx+dz*dz <= reach*reach then return true end
        local sx,sz=bx-ax,bz-az
        local length=sx*sx+sz*sz
        return length>0 and dx*sx+dz*sz>=0 and (dx*sz-dz*sx)^2/length<=reach*reach
    end
    local function countdown(seconds)
        seconds=math.max(0,math.ceil(seconds))
        return string.format("%dm %02ds",math.floor(seconds/60),seconds%60)
    end
    local function inAttackRange(distance,holding,useAttacks)
        if useAttacks==false then return distance <= (holding and 3 or 2) end
        return distance <= (holding and 7 or 5)
    end
    local function forwardDrone(progress,frontier,distance,length)
        return progress>=frontier-40 and progress<=length+5 and distance<=120
    end
    local function betterDrone(tier,distance,bestTier,bestDistance)
        local ranks={AugmentedDrone=3,ReactorDrone=2,ScrapDrone=1}
        local rank,best=ranks[tier] or 0,ranks[bestTier] or 0
        return rank>best or (rank==best and distance<bestDistance)
    end
    local function mergeScramble(snapshot,message)
        if type(message)~="table" then return end
        if message.Patch~=true then
            for key in pairs(snapshot) do snapshot[key]=nil end
        end
        local function merge(into,from)
            for key,value in pairs(from) do
                if type(value)=="table" then
                    if type(into[key])~="table" then into[key]={} end
                    merge(into[key],value)
                else into[key]=value end
            end
        end
        merge(snapshot,message)
        -- LostParts is a set supplied by the server; an empty set clears a claimed cycle.
        if type(message.State)=="table" and type(message.State.LostParts)=="table" then
            snapshot.State.LostParts={}
            for key,value in pairs(message.State.LostParts) do snapshot.State.LostParts[key]=value end
            snapshot.State.LostPartCount=nil
        end
    end
    local function nextOutbreak(snapshot,now)
        local window=snapshot.Window
        if type(window)~="table" or window.Available==false then return nil end
        local nextAt=tonumber(window.NextAt)
        local startsAt=tonumber(window.StartsAt)
        if startsAt and startsAt>now then nextAt=startsAt end
        if not nextAt then return nil end
        if nextAt<=now then
            local cadence=tonumber(window.NextAt) and startsAt and window.NextAt-startsAt
            if not cadence or cadence<=0 then return nil end
            nextAt=nextAt+(math.floor((now-nextAt)/cadence)+1)*cadence
        end
        if tonumber(snapshot.EventEndsAt) and nextAt>=snapshot.EventEndsAt then return nil end
        return nextAt-now
    end
    -- OUTBREAK HUNT WINDOW BEGIN
    local function outbreakHuntOpen(snapshot,active,endsAt,now)
        if not active then return false end
        endsAt=tonumber(endsAt)
        if not endsAt then
            local window=snapshot.Window
            local startsAt=type(window)=="table" and tonumber(window.StartsAt)
            if startsAt and startsAt<=now then endsAt=tonumber(window.EndsAt) end
        end
        return endsAt~=nil and endsAt==endsAt and endsAt<math.huge and endsAt-now>10
    end
    -- OUTBREAK HUNT WINDOW END
    -- SCRAMBLE HELPERS END
    local selectedTiers={ScrapDrone=true,ReactorDrone=true,AugmentedDrone=true}
    local timer = label("Scrample Time: Waiting for server...\nLost Parts: --/2\nDrone Parts: --/3\nSamples: --", UDim2.new(), UDim2.new(1,-6,0,108), eventBody)
    timer.LayoutOrder=-10
    timer.BackgroundTransparency=0
    timer.BackgroundColor3=colors.card
    timer.TextSize=14
    make("UICorner",{CornerRadius=UDim.new(0,7)},timer)
    make("UIPadding",{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10)},timer)
    local status = label("Waits for Dr Scramble's outbreak, then hunts living drones.", UDim2.new(), UDim2.new(1,-6,0,64), eventBody, true)
    status.LayoutOrder = 3
    status.TextSize = 14
    local enabled, revision = false, 0
    local useAttacks=false
    local retryAt=0
    local samples={busy=false}
    automationFlow.samples=samples
    local collectParts=false
    local vaultState={LostParts={}}
    local scrambleSnapshot={}
    local http=game:GetService("HttpService")
    local cacheName="AcidHubScrambleState"
    local cached=playerGui:GetAttribute(cacheName) or playerGui:GetAttribute("AcidHubTestsScrambleState")
    if type(cached)=="string" then
        local ok,data=pcall(function() return http:JSONDecode(cached) end)
        if ok and type(data)=="table" and data.JobId==game.JobId and type(data.Snapshot)=="table" then
            scrambleSnapshot=data.Snapshot
            vaultState=scrambleSnapshot.State or {LostParts={}}
            vaultState.LostParts=vaultState.LostParts or {}
        end
    end
    local function acceptScrambleState(message)
        if closed or type(message)~="table" then return end
        mergeScramble(scrambleSnapshot,message)
        vaultState=type(scrambleSnapshot.State)=="table" and scrambleSnapshot.State or {LostParts={}}
        if type(vaultState.LostParts)~="table" then vaultState.LostParts={} end
        pcall(function()
            playerGui:SetAttribute(cacheName,http:JSONEncode({JobId=game.JobId,Snapshot=scrambleSnapshot}))
        end)
    end
    local partTarget,heldPartPrompt,partHeldAt,partReleasedAt,partCharacter
    local partAttempts=0
    local partWaitAt
    local partsRetryAt=0
    local attemptedParts={}
    local partStatus=label("Collects available Lost Parts before resuming drone hunting.",UDim2.new(),UDim2.new(1,-6,0,56),eventBody,true)
    partStatus.LayoutOrder=5; partStatus.TextSize=14
    local target, lastHealth, progressAt = nil, nil, 0
    local holdingTarget
    local ignored = setmetatable({}, {__mode = "k"})
    local route, routeIndex, routeGoal, routeAt, computing = nil, 1, nil, 0, false
    local routeJob,routePath
    local movingHumanoid, movingRoot, lastPosition, lastMovedAt
    local patrolGoal, patrolArea, patrolArrived, patrolIndex = nil, nil, nil, 1
    local patrolAreas={"Light Dark","Titan Temple","Cherry Blossom","Cosmic","Prehistoric","Abyss Ocean"}
    local scanMethod="By Area"
    local prioritizeTen=true
    local priorityResume,priorityCharacter
    local priorityScanAt=-math.huge
    local sweepStart,sweepEnd,sweepAxis,sweepLength,sweepFrontier
    local sweepReturning,sweepReady=false,false
    local sweepCharacter
    local sweepRetryAt=0
    local allowedAreas={}
    for _,area in ipairs(patrolAreas) do allowedAreas[area]=true end
    local timerUpdatedAt = -math.huge
    -- Listen only to the confirmed state event; do not guess request operations.
    local stateJob=task.spawn(function()
        local remote
        while not closed and not remote do
            local packages=game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
            local networking=packages and packages:FindFirstChild("Networking")
            local candidate=networking and networking:FindFirstChild("RE/Scramble/State")
            if candidate and candidate:IsA("RemoteEvent") then remote=candidate else task.wait(1) end
        end
        if closed then return end
        connect(remote.OnClientEvent,function(message)
            if closed or type(message)~="table" then return end
            acceptScrambleState(message)
        end)
    end)
    table.insert(cleanupActions,function() pcall(task.cancel,stateJob) end)
    local pathfinding = game:GetService("PathfindingService")
    local function halt(humanoid,root)
        humanoid,root=humanoid or movingHumanoid,root or movingRoot
        if humanoid and humanoid.Parent and root and root.Parent then
            humanoid:MoveTo(root.Position)
            humanoid:Move(Vector3.zero,false)
            if humanoid.Health>0 and humanoid.FloorMaterial~=Enum.Material.Air then
                local velocity=root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity=Vector3.new(0,velocity.Y,0)
            end
        end
        movingHumanoid, movingRoot = nil, nil
        lastPosition, lastMovedAt = nil, os.clock()
    end
    local function resetRoute()
        revision = revision + 1
        if routeJob then pcall(task.cancel,routeJob); routeJob=nil end
        if routePath then pcall(function() routePath:Destroy() end); routePath=nil end
        route, routeGoal, computing = nil, nil, false
        routeAt = 0
        lastPosition, lastMovedAt = nil, os.clock()
    end
    local function clearTarget()
        holdingTarget=nil
        target, lastHealth = nil, nil
        resetRoute()
        halt()
    end
    local function resetSweep()
        priorityResume=nil; priorityCharacter=nil; priorityScanAt=-math.huge
        sweepStart,sweepEnd,sweepAxis,sweepLength,sweepFrontier=nil,nil,nil,nil,nil
        sweepReturning,sweepReady=false,false
        sweepCharacter=nil; sweepRetryAt=0
    end
    local function releasePartHold()
        if heldPartPrompt then pcall(function() heldPartPrompt:InputHoldEnd() end) end
        heldPartPrompt,partHeldAt=nil,nil
    end
    local function stopParts(message)
        releasePartHold()
        partTarget=nil; partCharacter=nil; partReleasedAt=nil
        partsRetryAt=os.clock()+5
        if message then partStatus.Text=message end
        clearTarget()
    end
    -- SCRAMBLE CURRENT DISPLAY BEGIN
    local function uiText(root,path)
        for _,name in ipairs(path) do root=root and root:FindFirstChild(name) end
        return root and (root:IsA("TextLabel") or root:IsA("TextButton")) and root.Text or nil
    end
    local function progressCount(text,total)
        if type(text)~="string" then return nil end
        local count,maximum=text:match("^%s*(%d+)%s*/%s*(%d+)%s*$")
        count,maximum=tonumber(count),tonumber(maximum)
        return count and maximum==total and count<=total and count or nil
    end
    local function sampleCount(text)
        if type(text)~="string" then return nil end
        local digits=text:gsub(",",""):match("^%s*(%d+)%s*$")
        return digits and tonumber(digits) or nil
    end
    local function lostPartCount(state)
        if type(state)~="table" then return nil end
        if type(state.LostPartCount)=="number" then return state.LostPartCount end
        local lost=state.LostParts
        if type(lost)=="table" then return (lost.LostPart1==true and 1 or 0)+(lost.LostPart2==true and 1 or 0) end
        return nil
    end
    local function readCurrentEventDisplay()
        local lost=progressCount(uiText(playerGui,{"StolenVaultEventUI","StolenVaultEventUIMain","ContentFrame","LostParts","ProgressLabel"}),2)
        local drones=progressCount(uiText(playerGui,{"StolenVaultEventUI","StolenVaultEventUIMain","ContentFrame","DroneParts","ProgressLabel"}),3)
        local count=sampleCount(uiText(playerGui,{"DrScrambleEventUI","DRScrambleEventUIMain","CurrencyHolder","QuantityLabel"}))
        if lost==nil and drones==nil and count==nil then return end
        local state=type(scrambleSnapshot.State)=="table" and scrambleSnapshot.State or {}
        if lost~=nil then
            local previous=lostPartCount(state)
            if previous and lost<previous then
                -- The displayed vault progress reset; the next collection cycle can begin.
                state.LostParts={}; attemptedParts={}; partsRetryAt=0
            end
            state.LostPartCount=lost
            if lost==2 then attemptedParts={} end
        end
        if drones~=nil then state.DroneParts=drones end
        if count~=nil then state.Samples=count end
        scrambleSnapshot.State=state
        vaultState=state
        if type(vaultState.LostParts)~="table" then vaultState.LostParts={} end
    end
    -- SCRAMBLE CURRENT DISPLAY END
    local function partsReady()
        if not collectParts or os.clock()<partsRetryAt then return false end
        local state=scrambleSnapshot.State
        local count=lostPartCount(state)
        if count==nil then
            partStatus.Text="ON — waiting for current vault progress."
            return false
        end
        for id in pairs(attemptedParts) do if state.LostParts[id]==true then attemptedParts[id]=nil end end
        if count==2 then
            partStatus.Text="ON — 2/2 Lost Parts owned; watching for the next missing part."
            return false
        end
        if heldPartPrompt or partReleasedAt then return true end
        local folder=workspace:FindFirstChild("DrScrambleEvent")
        for _,id in ipairs({"LostPart1","LostPart2"}) do
            if state.LostParts[id]~=true and not attemptedParts[id] then
                local model=folder and folder:FindFirstChild(id)
                local hit=model and model:FindFirstChild("Hitbox")
                local prompt=hit and hit:FindFirstChild("ClaimLostPart")
                if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then return true end
            end
        end
        partStatus.Text=next(attemptedParts) and "ON — waiting for confirmation of a previous claim; no repeat sent."
            or "ON — waiting for a missing Lost Part to become available."
        return false
    end
    local function updateTimer()
        if os.clock()-timerUpdatedAt<1 then return end
        timerUpdatedAt=os.clock()
        readCurrentEventDisplay()
        local active=workspace:GetAttribute("ScrambleOutbreakActive")==true
        local now=workspace:GetServerTimeNow()
        local remaining=nextOutbreak(scrambleSnapshot,now)
        local timeText=remaining and ("Next in "..countdown(remaining)) or "Next outbreak time unavailable"
        if tonumber(scrambleSnapshot.EventEndsAt) and now>=scrambleSnapshot.EventEndsAt then timeText="Event finished"
        elseif active then
            local endsAt=tonumber(workspace:GetAttribute("ScrambleOutbreakEndsAt"))
            timeText=endsAt and endsAt>now and ("Active — "..countdown(endsAt-now).." left") or "Active now"
            if remaining then timeText=timeText.." | Next in "..countdown(remaining) end
        end
        local state=scrambleSnapshot.State
        local lost=lostPartCount(state)
        local lostText=lost~=nil and tostring(lost) or "--"
        timer.Text="Scrample Time: "..timeText.."\nLost Parts: "..lostText.."/2\nDrone Parts: "
            ..tostring(state and state.DroneParts or "--").."/3\nSamples: "..tostring(state and state.Samples or "--")
    end
    local function liveHit(model, folder)
        if not folder or not model or model.Parent ~= folder or not model:IsA("Model") then return nil end
        if not allowedAreas[model:GetAttribute("ScrambleArea")] then return nil end
        local id = model:GetAttribute("ScrambleDroneId")
        if type(id) ~= "string" or id == "" or model:GetAttribute("ScrambleTestFixture") == true then return nil end
        local hit = model:FindFirstChild("Hitbox")
        local health = hit and hit:GetAttribute("Health")
        if hit and hit:IsA("BasePart") and type(health) == "number" and health > 0 then return hit, health end
    end
    local function hitDistance(hit,position)
        local relative=hit.CFrame:PointToObjectSpace(position)
        local half=hit.Size/2
        local edge=hit.CFrame:PointToWorldSpace(Vector3.new(math.clamp(relative.X,-half.X,half.X),math.clamp(relative.Y,-half.Y,half.Y),math.clamp(relative.Z,-half.Z,half.Z)))
        return (position-edge).Magnitude,edge
    end
    -- A single-target check each physics frame catches arrival between automation ticks.
    connect(game:GetService("RunService").PreSimulation,function()
        if closed or not samples.busy or automationFlow.phase~="samples" or automationFlow.bossPauseRequested or player:GetAttribute("InBossArena")==true or not enabled or not target or workspace:GetAttribute("ScrambleOutbreakActive")~=true then holdingTarget=nil; return end
        local character=player.Character
        local humanoid=character and movementHumanoid(character)
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local hit=liveHit(target,workspace:FindFirstChild("ScrambleLocalVisuals"))
        if not humanoid or humanoid.Health<=0 or not root or not hit then holdingTarget=nil; return end
        if inAttackRange(hitDistance(hit,root.Position),holdingTarget==target,useAttacks) then
            if holdingTarget~=target then resetRoute(); holdingTarget=target end
            halt(humanoid,root)
        else holdingTarget=nil end
    end)
    local function bat(character)
        local tool = character:FindFirstChildOfClass("Tool")
        if tool and tool:GetAttribute("IsBat") == true then return tool end
        local backpack = player:FindFirstChild("Backpack")
        if backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                if item:IsA("Tool") and item:GetAttribute("IsBat") == true then return item end
            end
        end
    end
    local function travel(humanoid, root, goal)
        movingHumanoid, movingRoot = humanoid, root
        local character=player.Character
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        local excluded={character}
        local visuals=workspace:FindFirstChild("ScrambleLocalVisuals")
        if visuals then excluded[#excluded+1]=visuals end
        params.FilterDescendantsInstances=excluded
        params.RespectCanCollide=true
        local clearance=humanoid.HipHeight+root.Size.Y/2
        local function supported(position)
            local floor=workspace:Raycast(position+Vector3.new(0,6,0),Vector3.new(0,-24,0),params)
            return floor and floor.Normal.Y>0.55 and floor.Position+Vector3.new(0,clearance,0) or nil
        end
        local function clearTravel(destination)
            local delta=destination-root.Position
            if workspace:Blockcast(CFrame.new(root.Position),Vector3.new(3,3,3),delta,params) then return false end
            local samples=math.max(1,math.ceil(delta.Magnitude/8))
            local previous=root.Position
            for i=1,samples do
                local ground=supported(root.Position+delta*(i/samples))
                if not ground or math.abs(ground.Y-previous.Y)>5 then return false end
                previous=ground
            end
            return true
        end
        if not lastPosition or (root.Position-lastPosition).Magnitude > 2 then
            lastPosition, lastMovedAt = root.Position, os.clock()
        end
        local stuckFor=os.clock()-lastMovedAt
        if stuckFor>5 then return false end
        if stuckFor>1.2 and os.clock()-routeAt>1 then humanoid.Jump=true; route=nil end
        local delta=goal-root.Position
        local horizon=math.max(24,math.min(100,humanoid.WalkSpeed*0.25))
        local direct=delta.Magnitude>horizon and root.Position+delta.Unit*horizon or goal
        direct=supported(direct) or direct
        if stuckFor<1.2 and clearTravel(direct) then
            -- Start immediately on open terrain, as the boss mover does.
            if route or computing then resetRoute() end
            humanoid:MoveTo(direct)
            return true
        end
        if not computing and (not routeGoal or (goal-routeGoal).Magnitude > 10 or not route or os.clock()-routeAt > 4)
            and os.clock()-routeAt>0.3 then
            computing = true
            routeGoal, routeAt = goal, os.clock()
            local token = revision
            local start = root.Position
            routeJob=task.spawn(function()
                local path = pathfinding:CreatePath({AgentRadius=2, AgentHeight=5, AgentCanJump=true, WaypointSpacing=10})
                routePath=path
                local destination=supported(goal) or goal
                local ok = pcall(function() path:ComputeAsync(start, destination) end)
                if token == revision and not closed and player.Character==character then
                    route = ok and path.Status == Enum.PathStatus.Success and path:GetWaypoints() or nil
                    routeIndex, computing = 2, false
                end
                path:Destroy()
                if routePath==path then routePath=nil; routeJob=nil end
            end)
        end
        local waypoint = route and route[routeIndex]
        local reach=math.max(3,math.min(12,humanoid.WalkSpeed*0.06))
        while waypoint do
            local point=waypoint.Position
            local previous=route[math.max(1,routeIndex-1)].Position
            if not waypointPassed(root.Position.X,root.Position.Z,previous.X,previous.Z,point.X,point.Z,reach) then break end
            local following=route[routeIndex+1]
            if following and not clearTravel(following.Position+Vector3.new(0,clearance,0)) then break end
            routeIndex = routeIndex + 1
            waypoint = route[routeIndex]
        end
        if waypoint then
            -- Skip intermediate points only where the whole segment is supported and clear.
            for i=math.min(#route,routeIndex+6),routeIndex+1,-1 do
                if clearTravel(route[i].Position+Vector3.new(0,clearance,0)) then
                    routeIndex=i; waypoint=route[i]; break
                end
            end
            if waypoint.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
            humanoid:MoveTo(waypoint.Position)
        else
            -- Do not keep an old MoveTo running into an obstacle while a detour is computed.
            humanoid:MoveTo(root.Position)
        end
        return true
    end
    local function areaPatrolGoal(area,humanoid,root)
        local bounds=area and area:FindFirstChild("Bounds")
        if not bounds then return nil end
        local frame,size
        if bounds:IsA("BasePart") then frame,size=bounds.CFrame,bounds.Size
        elseif bounds:IsA("Model") then frame,size=bounds:GetBoundingBox()
        else return nil end
        local center=frame.Position
        -- Bounds define the area; the guard and egg positions are not patrol landmarks.
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        local excluded={bounds}
        if player.Character then excluded[#excluded+1]=player.Character end
        local guard=area:FindFirstChild("Guard")
        if guard then excluded[#excluded+1]=guard end
        local visuals=workspace:FindFirstChild("ScrambleLocalVisuals")
        if visuals then excluded[#excluded+1]=visuals end
        params.FilterDescendantsInstances=excluded
        params.RespectCanCollide=true
        local halfHeight=(math.abs(frame.RightVector.Y)*size.X+math.abs(frame.UpVector.Y)*size.Y+math.abs(frame.LookVector.Y)*size.Z)/2
        local floor=workspace:Raycast(center+Vector3.new(0,halfHeight+8,0),Vector3.new(0,-(halfHeight*2+72),0),params)
        if not floor or floor.Normal.Y<=0.55 then return nil end
        return Vector3.new(center.X,floor.Position.Y+humanoid.HipHeight+root.Size.Y/2,center.Z)
    end
    local function prepareSweep(humanoid,root)
        if sweepCharacter~=player.Character then resetSweep(); sweepCharacter=player.Character end
        if not sweepStart then
            if os.clock()<sweepRetryAt then return false end
            sweepRetryAt=os.clock()+1
            local objects=workspace:FindFirstChild("__OBJECTS")
            local areas=objects and objects:FindFirstChild("Areas")
            local guards=areas and areas:FindFirstChild("GuardAreas")
            local first=areaPatrolGoal(guards and guards:FindFirstChild("Abyss Ocean"),humanoid,root)
            local last=areaPatrolGoal(guards and guards:FindFirstChild("Light Dark"),humanoid,root)
            if not first or not last then status.Text="Waiting for patrol endpoint centers to load."; halt(); return false end
            local delta=Vector3.new(last.X-first.X,0,last.Z-first.Z)
            if delta.Magnitude<1 then return false end
            sweepStart,sweepEnd,sweepAxis,sweepLength=first,last,delta.Unit,delta.Magnitude
        end
        if not sweepReady then
            status.Text="Continuous Patrol | Moving to Abyss Ocean center."
            local delta=root.Position-sweepStart
            if Vector3.new(delta.X,0,delta.Z).Magnitude>8 or math.abs(delta.Y)>8 then
                if not travel(humanoid,root,sweepStart) then
                    clearTarget(); resetSweep(); sweepCharacter=player.Character; sweepRetryAt=os.clock()+2
                    status.Text="Patrol approach blocked; replanning."
                end
                return false
            end
            sweepReady=true; sweepFrontier=0; resetRoute()
        end
        local origin=sweepReturning and sweepEnd or sweepStart
        local direction=sweepReturning and -sweepAxis or sweepAxis
        sweepFrontier=math.max(sweepFrontier,(root.Position-origin):Dot(direction))
        local destination=sweepReturning and sweepStart or sweepEnd
        local delta=root.Position-destination
        if Vector3.new(delta.X,0,delta.Z).Magnitude<=8 and math.abs(delta.Y)<=8 then
            clearTarget(); sweepReturning=not sweepReturning; sweepFrontier=0
        end
        return true
    end
    local function sweepAllows(hit,root)
        if scanMethod=="By Area" then return true end
        if not sweepReady then return false end
        local origin=sweepReturning and sweepEnd or sweepStart
        local direction=sweepReturning and -sweepAxis or sweepAxis
        return forwardDrone((hit.Position-origin):Dot(direction),sweepFrontier,(hit.Position-root.Position).Magnitude,sweepLength)
    end
    local function patrol(humanoid,root)
        if scanMethod=="Continuous Patrol" then
            status.Text="Continuous Patrol | Hunting toward "..(sweepReturning and "Abyss Ocean" or "Angels and Demons")
            if not travel(humanoid,root,sweepReturning and sweepStart or sweepEnd) then
                clearTarget(); resetSweep(); sweepCharacter=player.Character; sweepRetryAt=os.clock()+2
                status.Text="Patrol blocked; replanning from the start."
            end
            return
        end
        if not patrolGoal then
            local objects=workspace:FindFirstChild("__OBJECTS")
            local areas=objects and objects:FindFirstChild("Areas")
            local guards=areas and areas:FindFirstChild("GuardAreas")
            for _=1,#patrolAreas do
                local name=patrolAreas[patrolIndex]
                patrolIndex=patrolIndex%#patrolAreas+1
                local area=guards and guards:FindFirstChild(name)
                local center=areaPatrolGoal(area,humanoid,root)
                if center then
                    patrolGoal=center
                    patrolArea=name; patrolArrived=nil; resetRoute(); break
                end
            end
        end
        if not patrolGoal then status.Text="Waiting for walkable area centers to load."; halt(); return end
        status.Text="Searching the center of "..patrolArea.." for selected drones."
        local delta=patrolGoal-root.Position
        if Vector3.new(delta.X,0,delta.Z).Magnitude<8 and math.abs(delta.Y)<8 then
            halt(); patrolArrived=patrolArrived or os.clock()
            if os.clock()-patrolArrived>3 then patrolGoal=nil; resetRoute() end
        elseif not travel(humanoid,root,patrolGoal) then
            patrolGoal=nil; resetRoute(); halt()
        end
    end
    local function collectLostParts()
        if not partsReady() then
            if partTarget or heldPartPrompt then stopParts(partStatus.Text) end
            return false
        end
        if vaultState.LostParts.LostPart1==true and vaultState.LostParts.LostPart2==true then
            partWaitAt=nil
            stopParts("Both Lost Parts collected (server confirmed).")
            return false
        end
        local function waitForParts(message)
            partWaitAt=partWaitAt or os.clock()
            if os.clock()-partWaitAt>=15 then
                stopParts("ON — Lost Parts unavailable; will check again automatically.")
                return false
            end
            partStatus.Text=message; halt(); return true
        end
        local character=player.Character
        local humanoid=character and movementHumanoid(character)
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if not humanoid or humanoid.Health<=0 or not root then
            releasePartHold(); clearTarget(); partCharacter=nil
            partStatus.Text="Waiting for your character."; return true
        end
        if partCharacter~=character then
            releasePartHold(); clearTarget(); partTarget=nil; partReleasedAt=nil; partCharacter=character
        end
        for id in pairs(attemptedParts) do if vaultState.LostParts[id]==true then attemptedParts[id]=nil end end
        local folder=workspace:FindFirstChild("DrScrambleEvent")
        if not folder then return waitForParts("Waiting for Lost Parts to load.") end
        local function available(model)
            if not model or model.Parent~=folder or vaultState.LostParts[model.Name]==true then return nil end
            local hit=model:FindFirstChild("Hitbox")
            local prompt=hit and hit:FindFirstChild("ClaimLostPart")
            if hit and hit:IsA("BasePart") and prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then return hit,prompt end
        end
        local hit,prompt=available(partTarget)
        if not hit then
            if partTarget then releasePartHold(); clearTarget(); partTarget=nil end
            local nearest=math.huge
            for _,id in ipairs({"LostPart1","LostPart2"}) do
                local model=folder:FindFirstChild(id)
                local candidate=available(model)
                if candidate and not attemptedParts[id] then
                    local distance=(candidate.Position-root.Position).Magnitude
                    if distance<nearest then partTarget=model; nearest=distance end
                end
            end
            hit,prompt=available(partTarget)
            partAttempts=0; partReleasedAt=nil
            if not hit then
                local confirmed=vaultState.LostParts.LostPart1==true and vaultState.LostParts.LostPart2==true
                if not folder:FindFirstChild("LostPart1") or not folder:FindFirstChild("LostPart2") then
                    return waitForParts("Waiting for both Lost Part objects to load.")
                end
                stopParts(confirmed and "ON — 2/2 Lost Parts owned." or "ON — waiting for a missing Lost Part to become available.")
                return false
            end
            clearTarget()
        end
        local distance=(hit.Position-root.Position).Magnitude
        partWaitAt=nil
        local range=math.max(0.1,prompt.MaxActivationDistance-1)
        partStatus.Text="Collecting "..tostring(partTarget:GetAttribute("DisplayName") or partTarget.Name)..string.format(" | %.0f studs",distance)
        if distance>range then
            releasePartHold(); partReleasedAt=nil
            local away=Vector3.new(root.Position.X-hit.Position.X,0,root.Position.Z-hit.Position.Z)
            local goal=hit.Position+(away.Magnitude>0.01 and away.Unit*2 or Vector3.new(2,0,0))
            if not travel(humanoid,root,goal) then stopParts("ON — path blocked; will replan shortly.") end
            return true
        end
        halt(humanoid,root)
        if heldPartPrompt then
            if os.clock()-partHeldAt>=prompt.HoldDuration+0.15 then
                releasePartHold(); partReleasedAt=os.clock()
            end
        elseif partReleasedAt and os.clock()-partReleasedAt<5 then
            partStatus.Text="Waiting for collection confirmation..."
        elseif partAttempts>=1 then
            stopParts("Collection unconfirmed; no automatic retry. Check the prompt and vault progress.")
        else
            resetRoute()
            heldPartPrompt=prompt; partHeldAt=os.clock(); partAttempts=partAttempts+1
            attemptedParts[partTarget.Name]=true
            prompt:InputHoldBegin()
        end
        return true
    end
    local function priorityHunt(humanoid,root,folder)
        if priorityCharacter~=player.Character then
            priorityResume=nil; priorityScanAt=-math.huge; priorityCharacter=player.Character
        end
        local candidate
        if prioritizeTen and selectedTiers.AugmentedDrone then
            -- Keep an existing 10 HP tier target even after its health drops below 10.
            if target and target:GetAttribute("ScrambleTier")=="AugmentedDrone"
                and liveHit(target,folder) and (ignored[target] or 0)<=os.clock() then
                candidate=target
            elseif os.clock()-priorityScanAt>=0.2 then
                priorityScanAt=os.clock()
                local nearest=math.huge
                for _,model in ipairs(folder and folder:GetChildren() or {}) do
                    if model:GetAttribute("ScrambleTier")=="AugmentedDrone" and (ignored[model] or 0)<=os.clock() then
                        local hit=liveHit(model,folder)
                        if hit then
                            local distance=(hit.Position-root.Position).Magnitude
                            if distance<nearest then candidate=model; nearest=distance end
                        end
                    end
                end
            end
        end
        if candidate then
            priorityResume=priorityResume or root.Position
            if target~=candidate then
                clearTarget(); target=candidate
                local _,health=liveHit(target,folder)
                lastHealth=health; progressAt=os.clock()
            end
            local hit,health=liveHit(target,folder)
            return hit,health,true
        end
        if priorityResume then
            if target then clearTarget() end
            local delta=root.Position-priorityResume
            if Vector3.new(delta.X,0,delta.Z).Magnitude>8 or math.abs(delta.Y)>8 then
                status.Text="Returning to interrupted "..scanMethod.." scan."
                if not travel(humanoid,root,priorityResume) then
                    -- A destroyed/blocked return route must not trap the hunt forever.
                    priorityResume=nil; resetRoute(); halt(humanoid,root)
                end
                return nil,nil,true
            end
            priorityResume=nil; patrolArrived=nil; resetRoute(); halt(humanoid,root)
        end
        return nil,nil,false
    end
    -- SCRAMBLE SEQUENCE BEGIN
    local eventStage="parts"
    local resumingEventPass=false
    local function huntWindowOpen()
        return outbreakHuntOpen(scrambleSnapshot,workspace:GetAttribute("ScrambleOutbreakActive")==true,
            workspace:GetAttribute("ScrambleOutbreakEndsAt"),workspace:GetServerTimeNow())
    end
    function samples.enter()
        if not resumingEventPass then eventStage="parts" end
    end
    function samples.resumeAfterBoss()
        resumingEventPass=true
        flowPhase("processing","Resuming interrupted event step after boss")
        resumingEventPass=false
    end
    function samples.enabled() return enabled or collectParts end
    function samples.isActive()
        if closed or automationFlow.bossPauseRequested or player:GetAttribute("InBossArena")==true then return false end
        if os.clock()<retryAt then return false end
        local hunting=enabled and huntWindowOpen()
            and (selectedTiers.ScrapDrone or selectedTiers.ReactorDrone or selectedTiers.AugmentedDrone)
        if automationFlow.phase=="samples" or resumingEventPass then
            -- Finish the Lost Parts pass once, then only the outbreak can keep this stage alive.
            return eventStage=="parts" or hunting
        end
        return partsReady() or hunting
    end
    function samples.suspend()
        releasePartHold(); clearTarget(); resetSweep()
        partTarget=nil; partCharacter=nil; partReleasedAt=nil; partWaitAt=nil
        patrolGoal=nil; patrolArrived=nil; samples.busy=false
    end
    local function finishSamples(message)
        samples.suspend()
        status.Text=message
        reportTask("DrScrample",message)
        if automationFlow.phase=="samples" then flowPhase("idle",message) end
    end
    local function beginSampleTick()
        if not samples.isActive() then
            if samples.busy or automationFlow.phase=="samples" then finishSamples("Sample stage finished; continuing sequence.") end
            return false
        end
        if automationFlow.phase~="samples" then
            if samples.busy then samples.suspend() end
            if automationFlow.phase=="idle" and not automationFlow.steal and not automationFlow.pendingDay then
                flowPhase("samples","DrScrample collection")
            else
                status.Text="Waiting for egg collection / current sequence stage."
                return false
            end
        end
        if automationFlow.collecting or automationFlow.placing or automationFlow.fusing or automationFlow.selling
            or hatchOperationBusy or baseTravelActive or treadmillExitBusy or (automationFlow.rift and automationFlow.rift.busy) then
            if samples.busy then samples.suspend() end
            status.Text="Waiting for active movement / inventory work to finish."
            return false
        end
        local character=player.Character
        local humanoid=character and movementHumanoid(character)
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if not root or not humanoid or humanoid.Health<=0 or root.Anchored then
            if samples.busy then samples.suspend() end
            status.Text="Waiting for your character / treadmill exit."
            return false
        end
        if not samples.busy then
            local ok,carrying=pcall(function()
                local snapshot=require(game:GetService("ReplicatedStorage").Client.EggState).ReadFieldEggs()
                assert(type(snapshot)=="table" and type(snapshot.Records)=="table","Field snapshot unavailable")
                for _,egg in pairs(snapshot.Records) do if tonumber(egg.CarrierUserId)==player.UserId then return true end end
                return false
            end)
            if not ok then
                status.Text="Waiting for egg state after respawn; drone collection will resume."
                return false
            end
            if carrying then
                retryAt=os.clock()+5
                finishSamples("Carried egg detected; sample collection deferred.")
                return false
            end
            if not samples.isActive() or automationFlow.phase~="samples" then return false end
        end
        samples.busy=true
        return true
    end
    -- SCRAMBLE SEQUENCE END
    local function tick()
        updateTimer()
        if automationFlow.phase=="samples" and eventStage=="drones" and not huntWindowOpen() then
            finishSamples("Drone hunting stopped before outbreak close; continuing sequence.")
            return
        end
        if not beginSampleTick() then return end
        if eventStage=="parts" then
            if collectLostParts() then return end
            eventStage="drones"
        end
        if not enabled then finishSamples("Lost Parts pass finished; continuing sequence."); return end
        if not (selectedTiers.ScrapDrone or selectedTiers.ReactorDrone or selectedTiers.AugmentedDrone) then
            finishSamples("Select at least one drone type; continuing sequence."); return
        end
        if not huntWindowOpen() then
            finishSamples("Outbreak inactive, closing within 10 seconds, or end time unavailable; continuing sequence.")
            return
        end
        local character = player.Character
        local humanoid = character and movementHumanoid(character)
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not humanoid or humanoid.Health <= 0 or not root then
            clearTarget(); resetSweep(); status.Text = "Waiting for your character to respawn."; return
        end
        if movingRoot and movingRoot~=root then clearTarget(); resetSweep(); patrolGoal=nil end
        local tool = bat(character)
        if not tool then
            samples.suspend()
            status.Text="Waiting for your bat after respawn; drone collection will resume."
            return
        end
        local folder = workspace:FindFirstChild("ScrambleLocalVisuals")
        local hit,health,priorityHandled=priorityHunt(humanoid,root,folder)
        if priorityHandled and not hit then return end
        if not priorityHandled then
            if scanMethod=="Continuous Patrol" and not prepareSweep(humanoid,root) then return end
            if target and not tierAllowed(target:GetAttribute("ScrambleTier"),selectedTiers) then clearTarget() end
            hit, health = liveHit(target, folder)
            if hit and not sweepAllows(hit,root) then clearTarget(); hit,health=nil,nil end
            if not hit then
                if target then clearTarget() end
                local nearest = math.huge
                local bestTier
                if folder then
                    for _, model in ipairs(folder:GetChildren()) do
                        local candidate = liveHit(model, folder)
                        if candidate and sweepAllows(candidate,root) and tierAllowed(model:GetAttribute("ScrambleTier"),selectedTiers) and (ignored[model] or 0) <= os.clock() then
                            local distance = (candidate.Position-root.Position).Magnitude
                            local tier=model:GetAttribute("ScrambleTier")
                            if betterDrone(tier,distance,bestTier,nearest) then target, nearest, bestTier = model, distance, tier end
                        end
                    end
                end
                hit, health = liveHit(target, folder)
                if hit then resetRoute(); patrolGoal=nil end
                progressAt, lastHealth = os.clock(), health
            end
        end
        if not hit then
            patrol(humanoid,root)
            return
        end
        if health ~= lastHealth then lastHealth, progressAt = health, os.clock() end
        local distance,edge=hitDistance(hit,root.Position)
        status.Text = tostring(target:GetAttribute("ScrambleArea")) .. " | " .. tostring(target:GetAttribute("ScrambleTier")) .. " | HP " .. health
        if not inAttackRange(distance,holdingTarget==target,useAttacks) then
            holdingTarget=nil
            progressAt = os.clock()
            local away = Vector3.new(root.Position.X-hit.Position.X,0,root.Position.Z-hit.Position.Z)
            local standOff=useAttacks and 3 or 1
            local goal = edge + (away.Magnitude > 0.01 and away.Unit*standOff or Vector3.new(standOff,0,0))
            goal = Vector3.new(goal.X,root.Position.Y,goal.Z)
            if not travel(humanoid,root,goal) then ignored[target]=os.clock()+20; clearTarget() end
            return
        end
        if holdingTarget~=target then resetRoute(); holdingTarget=target end
        halt(humanoid,root)
        if os.clock()-progressAt > 12 then ignored[target]=os.clock()+20; clearTarget(); status.Text="Target not taking damage; searching for another."; return end
        local look = Vector3.new(hit.Position.X,root.Position.Y,hit.Position.Z)
        if (look-root.Position).Magnitude > 0.01 then root.CFrame = CFrame.lookAt(root.Position,look) end
        if tool.Parent ~= character then humanoid:EquipTool(tool); return end
        if useAttacks then combatInput.attack(tool) end
    end
    local function eventSwitch(title,key,initial,callback,order,description)
        local control=switch(eventBody,title,initial,callback,description,key)
        control.Parent.LayoutOrder=order
        return control
    end
    eventSwitch("Auto Samples","DrScrample.AutoSamples",false,function(value)
        enabled=value; retryAt=0
        samples.suspend()
        patrolIndex=1
        status.Text=value and "Waiting for egg collection / active outbreak." or "Auto Samples OFF"
        reportTask("DrScrample",status.Text)
    end,1,"After egg stealing and the Lost Parts pass, hunts selected drones until 10 seconds before outbreak end, then continues Rift, Fuse, Sell and Placement. Boss automation takes priority.")
    eventSwitch("Use Attacks","DrScrample.UseAttacks",false,function(value)
        useAttacks=value
        holdingTarget=nil; resetRoute()
    end,2,"OFF: close within 2 studs of the hitbox and follow again beyond 3 studs without sending bat attacks. ON: use the original approach distances and attack at your configured delay. Distance is checked each physics frame. Applies only to Auto Samples.")
    eventSwitch("Collect Lost Parts","DrScrample.CollectLostParts",false,function(value)
        collectParts=value; retryAt=0; partsRetryAt=0
        -- A deliberate OFF/ON starts a new pass; never retry within an uncertain pass.
        if value then attemptedParts={} end
        partWaitAt=nil
        releasePartHold(); clearTarget(); partTarget=nil; partCharacter=nil; partReleasedAt=nil
        partStatus.Text=value and "Queued after egg stealing, before drone hunting." or "Lost Part collection stopped."
    end,4,"Stays ON and watches your vault. Collects missing Lost Parts when available, waits at 2/2, and resumes after a confirmed reset. Uncertain claims are not automatically repeated.")
    eventSwitch("Prioritize 10 HP Drones","DrScrample.PrioritizeTen",true,function(value)
        prioritizeTen=value; priorityScanAt=-math.huge; clearTarget()
    end,6)
    for i,option in ipairs({{"ScrapDrone","Scrap — 3 HP"},{"ReactorDrone","Reactor — 5 HP"},{"AugmentedDrone","Augmented — 10 HP"}}) do
        local tier,title=option[1],option[2]
        eventSwitch(title,"DrScrample."..tier,true,function(value) selectedTiers[tier]=value; clearTarget() end,7+i)
    end
    local methodToggle=button("Drone Scan: By Area",UDim2.new(),UDim2.new(1,-6,0,36),eventBody)
    methodToggle.LayoutOrder=7
    local function setMethod(value)
        if value~="By Area" and value~="Continuous Patrol" then return false end
        scanMethod=value; methodToggle.Text="Drone Scan: "..value
        clearTarget(); resetSweep(); patrolGoal=nil; patrolIndex=1
        return true
    end
    registerSetting("DrScrample.ScanMethod","By Area",function() return scanMethod end,setMethod,
        function(value) return value=="By Area" or value=="Continuous Patrol" end)
    connect(methodToggle.Activated,function() setMethod(scanMethod=="By Area" and "Continuous Patrol" or "By Area") end)
    connect(player.CharacterRemoving,function() samples.suspend() end)
    table.insert(cleanupActions,function() enabled=false; collectParts=false; samples.suspend() end)
    task.spawn(function()
        while not closed do
            local tickCharacter=player.Character
            local ok, err = pcall(tick)
            if not ok then
                local character=player.Character
                local humanoid=character and movementHumanoid(character)
                local root=character and character:FindFirstChild("HumanoidRootPart")
                if character~=tickCharacter or not root or not humanoid or humanoid.Health<=0 then
                    samples.suspend()
                    status.Text="Character changed during collection; waiting to resume after respawn."
                else
                    stopParts("Stopped: "..tostring(err))
                    settingsBindings["DrScrample.AutoSamples"].set(false)
                    finishSamples("Sample controller stopped after an error; continuing sequence.")
                    status.Text="Stopped: " .. tostring(err)
                    warn("AcidHub Auto Samples: " .. tostring(err))
                end
            end
            reportTask("DrScrample",collectParts and partStatus.Text or status.Text)
            task.wait(samples.busy and 0.05 or 0.5)
        end
    end)
end)() end

-- Boss automation and shared arena navigation helpers.
do (function()
    local function note(message) reportTask("Boss",message) end
    local function conflict()
        for _,key in ipairs({"AutoStealEnabled","Auto Place Eggs","Auto Treadmill","Auto Hatch","Auto Equip Best","Auto Fuse","Auto Sell Pets","Auto Sell Eggs"}) do
            if settingsBindings[key] and settingsBindings[key].get() then return true end
        end
        return baseTravelActive or treadmillExitBusy or automationFlow.collecting or automationFlow.placing or automationFlow.fusing or automationFlow.selling or (automationFlow.samples and automationFlow.samples.busy) or (automationFlow.rift and automationFlow.rift.busy)
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
    -- Boss entry, combat, return, and automation pause/resume.
    do
        local eventPage
        for _,tab in ipairs(tabs) do if tab.name=="Events" then eventPage=tab.page.TheRiftSection.RiftSettings end end
        local enabled,enterEnabled,returnEnabled=false,false,false
        local route,routeGoal,routeIndex,routeAt=nil,nil,1,0
        local routeBlocked,routeLink=false,nil
        local aimIndex,lookAt,checkAt=nil,0,0
        local crystalTarget,crystalGoal=nil,nil
        local crystalSide=0
        local crystalWatch={target=nil,best=math.huge,at=0,reported=0}
        local attackTarget=nil
        local arrivalPart=nil
        local meteorMemory={}
        local dodgeGoal,dodgeQuietAt,dodgeRetryAt=nil,nil,0
        local routePosition=nil
        local portalRoute=nil
        local descentState,nextDescentAt,descentSide,descentFloor=nil,0,0,nil
        local restoreTraps=false
        local pausedSettings=nil
        local pausedPhase,pausedEpoch,pausedPending=nil,nil,nil
        local meteorCache,meteorCacheAt={},0
        local owner,entryWindow=nil,nil
        local remoteJob,entryPending=nil,false
        local entryToken=0
        local runEpoch=0
        local wasInside=false
        local blacklist={}
        local movingSince,bestWaypoint=0,math.huge
        local lastState=""
        local healthState=nil
        local healthWindow=nil
        local function syncBossWindow(state)
            if type(state)=="table" and state.OpensAt~=nil and state.OpensAt~=healthWindow then
                healthWindow=state.OpensAt; healthState=nil
            end
        end
        local lastHitProgress,lastHitCount=0,0
        local bossStatus=label("Boss automation OFF.",UDim2.fromOffset(10,5),UDim2.new(1,-20,1,-10),row(eventPage,78),true)
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
            descentState=nil; nextDescentAt=0; descentFloor=nil
            runEpoch=runEpoch+1; portalRoute=nil; arrivalPart=nil; dodgeGoal=nil; dodgeQuietAt=nil; attackTarget=nil; routePosition=nil
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
        local pauseKeys={"Auto Place Eggs","Auto Treadmill","Auto Hatch","Auto Equip Best","Auto Fuse","Auto Sell Pets","Auto Sell Eggs","Auto Buy Trail","Auto Upgrade Base","Auto Upgrade Treadmill","Auto Claim","AutoStealEnabled"}
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
                elseif pausedPhase=="samples" and automationFlow.samples and automationFlow.samples.resumeAfterBoss then
                    automationFlow.samples.resumeAfterBoss()
                elseif pausedPhase~="idle" then flowPhase("processing","Rechecking work after boss") end
            end
            say(#failures==0 and "Lobby reached; previous automations resumed" or "Resume failed: "..table.concat(failures,", "))
        end
        local function pauseAutomations()
            if not pausedSettings then
                pausedSettings={}; pausedPhase=automationFlow.phase; pausedEpoch=automationFlow.epoch; pausedPending=automationFlow.pendingDay
                for _,key in ipairs(pauseKeys) do local binding=settingsBindings[key]; pausedSettings[key]=binding and binding.get()==true or false end
                automationFlow.bossPauseRequested=true
                if automationFlow.samples then automationFlow.samples.suspend() end
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
            descentState=nil
            arrivalPart=nil; dodgeGoal=nil; dodgeQuietAt=nil; attackTarget=nil
            restoreTouchSetting()
            enabled=false; runEpoch=runEpoch+1; entryToken=entryToken+1; halt(); say(reason)
            if remoteJob then pcall(task.cancel,remoteJob); remoteJob=nil end
            entryPending=false
            if closed then discardResume() elseif player:GetAttribute("InBossArena")~=true then resumeAutomations() end
        end
        local function trapsOn() return settingsBindings["No Traps"] and settingsBindings["No Traps"].get() end
        switch(eventPage,"Auto Enter Boss",false,function(v) enterEnabled=v end,"One entry request per opening; arrival must be confirmed. Used only while Auto Fight Boss is ON.")
        switch(eventPage,"Auto Return From Boss",false,function(v) returnEnabled=v end,"After confirmed defeat or event closure, pathfind to the arena's return portal.")
        switch(eventPage,"Auto Fight Boss",false,function(v)
            runEpoch=runEpoch+1; enabled=v; crystalTarget=nil; crystalGoal=nil; entryWindow=nil; owner=nil; blacklist={}; healthState=nil; wasInside=false
            if not v then disable("Boss run OFF") else say("Boss run enabled; waiting for arena/event") end
        end,"Fights crystals and the exposed hand, avoids comets, and recovers after respawn. Other combat hazards are ignored. Normal automations pause for the boss and resume on lobby return. No Traps may stay ON during combat; temporarily restored for the return portal. Ground-checked pathfinding; no straight-line fallback.")
        local function turnOff(reason)
            disable(reason)
            local binding=settingsBindings["Auto Fight Boss"]; if binding then binding.set(false) end
            say(reason)
        end
        automationFlow.bossActive=function() return enabled end
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
                    if os.clock()-marker.seen<=0.25 then meteorCache[#meteorCache+1]=marker else meteorMemory[part]=nil end
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
        -- BOSS DESCENT BEGIN
        local function traceBossDescent(origin,dx,dz,length,clearance,surface,blocked,hazard,floorLimit)
            if length<=0 or length>24 or type(floorLimit)~="number" then return nil end
            local magnitude=math.sqrt(dx*dx+dz*dz)
            if magnitude<0.01 then return nil end
            dx,dz=dx/magnitude,dz/magnitude
            local side=Vector3.new(-dz*2.5,0,dx*2.5)
            local initial,normal=surface(origin)
            if not initial or not normal or normal<0.35 or initial.Y<floorLimit or origin.Y-initial.Y>7 or initial.Y>origin.Y then return nil end
            local points={origin}
            local previous=origin
            local previousFloor=initial.Y
            local initialCost=hazard(origin)
            local steps=math.ceil(length/2)
            for index=1,steps do
                local distance=length*index/steps
                local probe=Vector3.new(origin.X+dx*distance,previousFloor+clearance,origin.Z+dz*distance)
                local floor,slope=surface(probe)
                -- Follow supported descending surfaces, never a blind drop to a lower pit floor.
                if not floor or not slope or slope<0.35 or floor.Y<floorLimit or floor.Y-previousFloor>0.75 or previousFloor-floor.Y>4 then return nil end
                local point=Vector3.new(floor.X,floor.Y+clearance,floor.Z)
                for _,offset in ipairs({side,side*-1}) do
                    local edge,edgeSlope=surface(point+offset)
                    if not edge or not edgeSlope or edgeSlope<0.35 or edge.Y<floorLimit or math.abs(edge.Y-floor.Y)>3 then return nil end
                    if hazard(edge)>initialCost+0.1 then return nil end
                end
                if blocked(previous,point) or hazard(point)>initialCost+0.1 then return nil end
                points[#points+1]=point; previous=point; previousFloor=floor.Y
            end
            return points,initial.Y-previousFloor
        end
        -- BOSS DESCENT END
        local function descentChecks(character)
            local params=RaycastParams.new()
            params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={character}; params.RespectCanCollide=true
            local function surface(point)
                local hit=workspace:Raycast(point+Vector3.new(0,3,0),Vector3.new(0,-14,0),params)
                if hit then return hit.Position,hit.Normal.Y end
            end
            local function blocked(a,b)
                return workspace:Blockcast(CFrame.new(a+Vector3.new(0,1,0)),Vector3.new(5,4,5),b-a,params)~=nil
            end
            return surface,blocked
        end
        local function recoveryFloor(character)
            if descentFloor then return descentFloor end
            -- Anchor descent to the return-gate floor, never a deeper pit floor.
            local model=arena()
            local portal=model and model:FindFirstChild("BossArenaLeaveTeleport")
            local hit=portal and portal:FindFirstChild("Hitbox")
            if not hit or not hit:IsA("BasePart") then return nil end
            local params=RaycastParams.new()
            params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={character,portal}; params.RespectCanCollide=true
            local heights={}
            for _,offset in ipairs({Vector3.new(hit.Size.X/2+8,0,0),Vector3.new(-hit.Size.X/2-8,0,0),
                Vector3.new(0,0,hit.Size.Z/2+8),Vector3.new(0,0,-hit.Size.Z/2-8)}) do
                local point=hit.CFrame:PointToWorldSpace(offset)
                local support=workspace:Raycast(point+Vector3.new(0,5,0),Vector3.new(0,-64,0),params)
                if support and support.Normal.Y>=0.9 then heights[#heights+1]=support.Position.Y end
            end
            table.sort(heights)
            for index=1,#heights-2 do
                if heights[index+2]-heights[index]<=2 then
                    descentFloor=heights[index]-1
                    return descentFloor
                end
            end
            return nil -- No agreed floor reference: do not guess a landing depth.
        end
        local function beginDescent(destination,character,h,root)
            if os.clock()<nextDescentAt then return false end
            nextDescentAt=os.clock()+0.75
            if h.FloorMaterial==Enum.Material.Air then return false end
            local floorLimit=recoveryFloor(character)
            if not floorLimit then return false end
            local clearance=math.max(2,math.min(4,h.HipHeight+root.Size.Y/2))
            local surface,blocked=descentChecks(character)
            local best,bestScore
            local direction=destination-root.Position
            local base=math.atan2(direction.Z,direction.X)+descentSide*math.pi/4
            for _,length in ipairs({8,16,24}) do
                for index=0,15 do
                    local angle=base+index*math.pi/8
                    local points,drop=traceBossDescent(root.Position,math.cos(angle),math.sin(angle),length,clearance,surface,blocked,hazardCost,floorLimit)
                    if points and drop>=1.5 then
                        local score=drop-length*0.05-index*0.01
                        if not bestScore or score>bestScore then best,bestScore=points,score end
                    end
                end
                if best then break end -- Prefer a short controlled descent over a long run.
            end
            if not best then return false end
            halt(); dodgeGoal=nil; attackTarget=nil; arrivalPart=nil
            descentState={points=best,index=2,character=character,at=os.clock(),progressAt=os.clock(),best=math.huge}
            note("BOSS RECOVERY | Following checked terrain downhill from an elevated/blocked position")
            h:MoveTo(best[2])
            return true
        end
        local function stepDescent(character,h,root)
            local state=descentState
            if not state then return false end
            if state.character~=character or os.clock()-state.at>6 then
                descentState=nil; descentSide=descentSide+1; halt(); return false
            end
            local target=state.points[state.index]
            while target and (target-root.Position).Magnitude<2.5 do
                state.index=state.index+1; state.best=math.huge; state.progressAt=os.clock()
                target=state.points[state.index]
            end
            if not target then
                descentState=nil; crystalGoal=nil; portalRoute=nil; useArenaSearch=false; halt()
                note("BOSS RECOVERY | Descent complete; rebuilding route at current height")
                return true
            end
            local delta=target-root.Position
            local length=Vector3.new(delta.X,0,delta.Z).Magnitude
            local surface,blocked=descentChecks(character)
            local clearance=math.max(2,math.min(4,h.HipHeight+root.Size.Y/2))
            local checked=traceBossDescent(root.Position,delta.X,delta.Z,length,clearance,surface,blocked,hazardCost,descentFloor)
            if not checked or math.abs(checked[#checked].Y-target.Y)>2 then
                descentState=nil; descentSide=descentSide+1; halt()
                note("BOSS RECOVERY | Descent support changed; replanning")
                return true
            end
            local distance=delta.Magnitude
            if distance<state.best-0.25 then state.best=distance; state.progressAt=os.clock() end
            if os.clock()-state.progressAt>1.25 then
                descentState=nil; descentSide=descentSide+1; halt()
                note("BOSS RECOVERY | Descent stalled; trying another supported direction")
                return true
            end
            routePosition=root.Position
            h:MoveTo(target); say("Recovering downhill from rock / raised terrain")
            return true
        end
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
                    if not ground(origin,character) and beginDescent(destination,character,h,root) then return "moving" end
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
                        if beginDescent(destination,character,h,root) then return "moving" end
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
                if not nextIndex then
                    useArenaSearch=true; halt()
                    if beginDescent(destination,character,h,root) then return "moving" end
                    return "route rejected; switching to arena search"
                end
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
            if os.clock()-movingSince>1.25 then
                useArenaSearch=true; halt()
                if beginDescent(destination,character,h,root) then return "moving" end
                return "path stalled; searching alternate route"
            end
            if not enabled or player.Character~=character or player:GetAttribute("InBossArena")~=true then halt(); return "cancelled" end
            h:MoveTo(point)
            return "moving"
        end
        -- PORTAL POLICY BEGIN
        local function portalRecovery(result,distance,stalled)
            if stalled>3 then return true end
            -- "arrived" may mean a completed intermediate leg; continue toward the same gate.
            if result=="arrived" then return false end
            return result~="moving" and result~="waiting" and result~="arrived" and result~="jumping"
                and result~="route rejected; switching to arena search"
        end
        -- PORTAL POLICY END
        local function returnThroughPortal(hit,character,h,root)
            if not portalRoute or portalRoute.hit~=hit or portalRoute.character~=character then
                portalRoute={hit=hit,character=character,attempt=0,stage="approach",best=math.huge,at=os.clock()}
                dodgeGoal=nil; dodgeQuietAt=nil; attackTarget=nil; halt()
            end
            local state=portalRoute
            if not state.goal then
                -- Approach the nearest face, then cross the thin dimension of the gate.
                local localRoot=hit.CFrame:PointToObjectSpace(root.Position)
                local thinX=hit.Size.X<hit.Size.Z
                local coordinate=thinX and localRoot.X or localRoot.Z
                local sign=coordinate>=0 and 1 or -1
                if math.floor(state.attempt/3)%2==1 then sign=-sign end
                local offset=({0,0.28,-0.28})[state.attempt%3+1]
                local near=(thinX and hit.Size.X or hit.Size.Z)/2+7
                local lateral=(thinX and hit.Size.Z or hit.Size.X)*offset
                local function point(side)
                    local localPoint=thinX and Vector3.new(side*near,0,lateral) or Vector3.new(lateral,0,side*near)
                    local world=hit.CFrame:PointToWorldSpace(localPoint)
                    return Vector3.new(world.X,root.Position.Y,world.Z)
                end
                state.goal=point(sign); state.cross=point(-sign); state.stage="approach"
                state.best=math.huge; state.at=os.clock(); state.touchWait=nil
            end
            local distance=(root.Position-state.goal).Magnitude
            if distance<state.best-1 then state.best=distance; state.at=os.clock() end
            if distance<=5 then
                if state.stage=="approach" then
                    state.stage="cross"; state.goal=state.cross; state.best=math.huge; state.at=os.clock(); halt()
                    -- Do not let a navigation detour go around the gate instead of through it.
                    if not clearTravel(root.Position,state.goal,character,false) then
                        state.attempt=state.attempt+1; state.goal=nil; useArenaSearch=true
                        note("BOSS RETURN | Crossing obstructed; choosing another gate approach"); return
                    end
                    distance=(root.Position-state.goal).Magnitude
                else
                    state.touchWait=state.touchWait or os.clock()
                    if os.clock()-state.touchWait<1 then return end
                    state.attempt=state.attempt+1; state.goal=nil; useArenaSearch=true; halt()
                    note("BOSS RETURN | Crossed gate but still in arena; trying another crossing"); return
                end
            end
            local result
            if state.stage=="cross" and clearTravel(root.Position,state.goal,character,false) then
                h:MoveTo(state.goal); result="moving"
            elseif state.stage=="cross" then result="gate crossing changed"
            else result=navigate(state.goal,character,h,root,false) end
            if player:GetAttribute("InBossArena")~=true then return end
            if portalRecovery(result,distance,os.clock()-state.at) then
                note(string.format("BOSS RETURN | %s | distance %.1f | alternate approach %d",result,distance,state.attempt+1))
                state.attempt=state.attempt+1; state.goal=nil; useArenaSearch=true; halt()
            end
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
                if not dodgeGoal then
                    if beginDescent(root.Position,character,h,root) then say("Comets: recovering down supported terrain"); return true end
                    halt(); say("Comets: no clear escape found; rechecking"); return true
                end
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
                if os.clock()-dodgeQuietAt>=0.5 then
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
            combatInput.attack(tool)
        end
        connect(stopAll.Activated,function() discardResume(); turnOff("Boss stopped by Stop All") end)
        table.insert(cleanupActions,function() disable("Hub closed") end)
        local storage=game:GetService("ReplicatedStorage")
        local healthRemote=storage:FindFirstChild("RE/BossEvent/HealthShifted",true)
        if healthRemote then connect(healthRemote.OnClientEvent,function(hp,maxHP) syncBossWindow(automationFlow.bossSnapshot); healthState={hp=hp,maxHP=maxHP} end) end
        local stateRemote=storage:FindFirstChild("RE/BossEvent/StateShifted",true)
        if stateRemote then connect(stateRemote.OnClientEvent,function(state) syncBossWindow(state); if type(state)=="table" and type(state.BossHealth)=="number" then healthState={hp=state.BossHealth,maxHP=state.BossMaxHealth} end end) end
        local function tickBoss()
            arrivalPart=nil
            if not enabled then
                if pausedSettings and player:GetAttribute("InBossArena")~=true then restoreTouchSetting(); resumeAutomations() end
                return
            end
            local character,h,root=characterParts()
            local inside=player:GetAttribute("InBossArena")==true
            local state=automationFlow.bossSnapshot
            syncBossWindow(state)
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
            if not character or not h or not root or h.Health<=0 then descentState=nil; halt(); owner=nil; say("Waiting for respawn in arena"); return end
            if owner~=character then descentState=nil; halt(); owner=character; blacklist={}; crystalTarget=nil; crystalGoal=nil; crystalSide=0; say("Arena character ready") end
            local model=arena(); if not model then descentState=nil; halt(); say("Waiting for arena replication"); return end
            if stepDescent(character,h,root) then return end
            local boss=model:FindFirstChild("Boss")
            local hand=boss and boss:FindFirstChild("UpperHand1.R",true)
            local handPosition=hand and hand:IsA("Bone") and hand.TransformedWorldCFrame.Position or nil
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
                returnThroughPortal(hit,character,h,root)
                return
            end
            if not bossCombatReady(state and state.Open,boss~=nil,boss and boss:GetAttribute("Spawning"),state and state.BossSpawnsAt,workspace:GetServerTimeNow(),healthInitialized) then
                halt(); crystalTarget=nil; crystalGoal=nil
                say("Waiting for boss spawn to finish; crystals are not active yet")
                return
            end
            if dodgeMeteors(character,h,root) then attackTarget=nil; crystalWatch.at=os.clock(); crystalWatch.best=math.huge; return end
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
                if crystalWatch.target~=target then
                    crystalWatch={target=target,best=distance,at=os.clock(),reported=0}
                elseif distance<crystalWatch.best-1 then
                    crystalWatch.best=distance; crystalWatch.at=os.clock()
                end
                if distance>8 and os.clock()-crystalWatch.at>4 then
                    note(string.format("BOSS APPROACH | Crystal %s | edge %.1f | goal %.1f | no approach progress; replanning",target.Parent.Name,distance,(destination-root.Position).Magnitude))
                    crystalSide=crystalSide+1; crystalGoal=nil; useArenaSearch=true; halt()
                    crystalWatch.best=math.huge; crystalWatch.at=os.clock(); return
                end
                arrivalPart=target
                say("Crystals: "..#living.." alive | target "..target.Parent.Name.." | health "..tostring(target:GetAttribute("Health")))
                if attackHold(distance,attackTarget==target,8,10) then
                    attackTarget=target; halt(); swing(character,h,root)
                    local hits=tonumber(player:GetAttribute("BossCrystalHits")) or 0
                    if hits~=lastHitCount then lastHitCount=hits; lastHitProgress=os.clock() end
                    if lastHitProgress==0 then lastHitProgress=os.clock() end
                    if os.clock()-lastHitProgress>8 then blacklist[target]=os.clock()+8; lastHitProgress=0; note("BOSS RUN | No own crystal hit progress; reconsidering target") end
                else
                    attackTarget=nil; lastHitProgress=0
                    local result=navigate(destination,character,h,root,false)
                    if result=="arrived" and distance>8 and (destination-root.Position).Magnitude<4 then
                        result="approach endpoint reached outside attack range (edge "..string.format("%.1f",distance)..")"
                    end
                    if result=="route rejected; switching to arena search" then return end
                    if result~="moving" and result~="waiting" and result~="arrived" and result~="jumping" then
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
                if distance<=(arrivalPart:IsA("Bone") and 12 or 8) then halt() end
            end
        end)
        task.spawn(function()
            while not closed do
                local ok,err=pcall(tickBoss)
                if not ok then turnOff("Boss run error: "..tostring(err)) end
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
        if type(value)=="table" and (key=="Areas" or key=="StealPreview.Areas") then
            local mapped=copySetting(binding.default)
            for name,on in pairs(value) do
                local live=LiveAreas.Aliases[tostring(name):lower():gsub("[^%w]","")]
                if not live or type(on)~="boolean" then return false,"Invalid saved area: "..tostring(name) end
                mapped[live]=on
            end
            value=mapped
        elseif type(value)=="table" and (key=="Rarities" or key=="PenESP.Rarities") then
            local mapped=copySetting(binding.default)
            for name,on in pairs(value) do
                if type(on)~="boolean" then return false,"Invalid saved rarity selection" end
                if Rarity.Ranks[name] then mapped[name]=on end
            end
            value=mapped
        end
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
local function startupError(message)
    warn("AcidHub startup failed: "..tostring(message))
    pcall(function()
        local parent=game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui",5)
        if not parent then return end
        local old=parent:FindFirstChild("AcidHubStartupError"); if old then old:Destroy() end
        local gui=Instance.new("ScreenGui"); gui.Name="AcidHubStartupError"; gui.ResetOnSpawn=false; gui.DisplayOrder=10000
        local text=Instance.new("TextButton"); text.Size=UDim2.new(0.8,0,0,200); text.Position=UDim2.new(0.1,0,0.1,0)
        text.BackgroundColor3=Color3.fromRGB(45,18,18); text.TextColor3=Color3.new(1,1,1); text.TextSize=16; text.TextWrapped=true
        text.Text="AcidHub could not start\n"..tostring(message).."\nClick to dismiss"; text.Parent=gui; gui.Parent=parent
        text.Activated:Connect(function() gui:Destroy() end)
    end)
end
local run,err=loadstring(source)
if not run then startupError(err) else
    local ok,message=xpcall(run,function(value) return debug.traceback(tostring(value),2) end)
    if not ok then startupError(message) end
end
