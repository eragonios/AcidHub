-- AcidHub Tests: standalone UI for future test functions.
-- Run on the Roblox client. This window can coexist with AcidHub.
local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
assert(player, "Run AcidHubTests on the Roblox client after joining a game.")
local playerGui = player:WaitForChild("PlayerGui")
local previous = playerGui:FindFirstChild("AcidHubTestsUI")
if previous and previous:GetAttribute("AcidHubTestsUI") then previous:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AcidHubTestsUI"
gui:SetAttribute("AcidHubTestsUI", true)
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local connections = {}
local cleanupActions = {}
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end
connect(gui.Destroying, function()
    for _, action in ipairs(cleanupActions) do pcall(action) end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
end)

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
    Name = "Panel", Size = UDim2.fromOffset(540, 510), Position = UDim2.fromOffset(60,84),
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
label("AcidHub Tests", UDim2.fromOffset(16,0), UDim2.new(1,-16,1,0), header).TextSize=20
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
local reopen = button("AcidHub Tests", UDim2.new(1,-174,0,66), UDim2.fromOffset(150,34), gui)
reopen.Visible = false
connect(minimize.Activated, function() panel.Visible = false; reopen.Visible = true end)
connect(reopen.Activated, function() panel.Visible = true; reopen.Visible = false end)
connect(close.Activated, function() gui:Destroy() end)

local sidebar=make("Frame",{Name="Sidebar",Position=UDim2.fromOffset(12,54),
    Size=UDim2.new(0,130,1,-68),BackgroundTransparency=1},panel)
make("Frame",{Position=UDim2.fromOffset(148,54),Size=UDim2.new(0,1,1,-68),
    BorderSizePixel=0,BackgroundColor3=colors.card},panel)
local testsTab = button("Tests", UDim2.fromOffset(0,0), UDim2.new(1,0,0,36), sidebar)
testsTab.TextColor3 = colors.accent
local pageTitle = label("Tests", UDim2.fromOffset(162,50), UDim2.new(1,-176,0,34), panel)
pageTitle.TextSize = 20
local testsPage = make("ScrollingFrame", {
    Name = "TestsPage", Position = UDim2.fromOffset(162,94),
    Size = UDim2.new(1,-176,1,-108), BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 3, CanvasSize = UDim2.fromOffset(0,0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, panel)
make("UIListLayout", {Padding = UDim.new(0,8), SortOrder = Enum.SortOrder.LayoutOrder}, testsPage)

-- Add future test controls here, parented to testsPage.
do
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
    local function inAttackRange(distance,holding)
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
        end
    end
    local function vaultComplete(state)
        local lost=state and state.LostParts
        return lost and lost.LostPart1==true and lost.LostPart2==true
            and type(state.DroneParts)=="number" and state.DroneParts>=3
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
    -- SCRAMBLE HELPERS END
    local selectedTiers={ScrapDrone=true,ReactorDrone=true,AugmentedDrone=true}
    local timer = label("Scrample Time: Waiting for server...\nLost Parts: --/2\nDrone Parts: --/3\nSamples: --", UDim2.new(), UDim2.new(1,-6,0,108), testsPage)
    timer.LayoutOrder=-10
    timer.BackgroundTransparency=0
    timer.BackgroundColor3=colors.card
    timer.TextSize=14
    make("UICorner",{CornerRadius=UDim.new(0,7)},timer)
    make("UIPadding",{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10)},timer)
    local toggle = button("Auto Samples: OFF", UDim2.new(), UDim2.new(1,-6,0,38), testsPage)
    toggle.LayoutOrder = -3
    local status = label("Waits for Dr Scramble's outbreak, then hunts living drones.", UDim2.new(), UDim2.new(1,-6,0,64), testsPage, true)
    status.LayoutOrder = -2
    status.TextSize = 14
    local enabled, closed, revision = false, false, 0
    local collectParts=false
    local vaultState={LostParts={}}
    local scrambleSnapshot={}
    local http=game:GetService("HttpService")
    local cacheName="AcidHubTestsScrambleState"
    local cached=playerGui:GetAttribute(cacheName)
    if type(cached)=="string" then
        local ok,data=pcall(function() return http:JSONDecode(cached) end)
        if ok and type(data)=="table" and data.JobId==game.JobId and type(data.Snapshot)=="table" then
            scrambleSnapshot=data.Snapshot
            vaultState=scrambleSnapshot.State or {LostParts={}}
            vaultState.LostParts=vaultState.LostParts or {}
        end
    end
    local partTarget,heldPartPrompt,partHeldAt,partReleasedAt,partCharacter
    local partAttempts=0
    local collectToggle=button("Collect Lost Parts: OFF",UDim2.new(),UDim2.new(1,-6,0,36),testsPage)
    collectToggle.LayoutOrder=-5
    local partStatus=label("Collects available Lost Parts before resuming drone hunting.",UDim2.new(),UDim2.new(1,-6,0,56),testsPage,true)
    partStatus.LayoutOrder=-4; partStatus.TextSize=14
    local target, lastHealth, progressAt, lastSwing = nil, nil, 0, -math.huge
    local holdingTarget
    local ignored = setmetatable({}, {__mode = "k"})
    local route, routeIndex, routeGoal, routeAt, computing = nil, 1, nil, 0, false
    local movingHumanoid, movingRoot, lastPosition, lastMovedAt
    local patrolGoal, patrolArea, patrolArrived, patrolIndex = nil, nil, nil, 1
    local patrolAreas={"Light Dark","Titan Temple","Cherry Blossom","Cosmic","Prehistoric","Abyss Ocean"}
    local scanMethod="By Area"
    local prioritizeTen=true
    local priorityResume,priorityCharacter
    local priorityScanAt=-math.huge
    local priorityToggle=button("Prioritize 10 HP Drones: ON",UDim2.new(),UDim2.new(1,-6,0,36),testsPage)
    priorityToggle.LayoutOrder=-9
    priorityToggle.TextColor3=colors.accent
    local sweepStart,sweepEnd,sweepAxis,sweepLength,sweepFrontier
    local sweepReturning,sweepReady=false,false
    local sweepCharacter
    local sweepRetryAt=0
    local methodToggle=button("Drone Scan method: 1 - By Area",UDim2.new(),UDim2.new(1,-6,0,36),testsPage)
    methodToggle.LayoutOrder=-9
    local allowedAreas={}
    for _,area in ipairs(patrolAreas) do allowedAreas[area]=true end
    local timerUpdatedAt = -math.huge
    local scheduleCaptureStatus = "Reading event schedule definitions..."
    -- A one-time capture of the confirmed event modules, never a recurring UI scan.
    local scheduleCaptureJob=task.spawn(function()
        local lines={"AcidHub Tests - Scramble schedule definitions"}
        local seen,count={},0
        local function dump(path,value,depth)
            if count>=1200 then return end
            count=count+1
            if type(value)~="table" then lines[#lines+1]=path.." = "..tostring(value); return end
            if seen[value] then lines[#lines+1]=path.." = <shared table>"; return end
            seen[value]=true
            if depth>=5 then lines[#lines+1]=path.." = <depth limit>"; return end
            local keys={}
            for key in pairs(value) do keys[#keys+1]=key end
            table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
            for _,key in ipairs(keys) do dump(path.."."..tostring(key),value[key],depth+1) end
        end
        local ok,err=pcall(function()
            local storage=game:GetService("ReplicatedStorage")
            local shared=storage:FindFirstChild("Shared")
            assert(shared,"Shared modules not loaded")
            -- Observe server state; the manual vault buttons below use captured Request operations.
            local packages=storage:FindFirstChild("Packages")
            local networking=packages and packages:FindFirstChild("Networking")
            local stateEvent=networking and networking:FindFirstChild("RE/Scramble/State")
            if stateEvent and stateEvent:IsA("RemoteEvent") then
                local captures=0
                connect(stateEvent.OnClientEvent,function(...)
                    if closed then return end
                    local message=select(1,...)
                    if type(message)=="table" then
                        mergeScramble(scrambleSnapshot,message)
                        vaultState=scrambleSnapshot.State or {LostParts={}}
                        vaultState.LostParts=vaultState.LostParts or {}
                        -- Cache only plain progress/timing fields, never CFrames or whole payloads.
                        pcall(function()
                            playerGui:SetAttribute(cacheName,http:JSONEncode({JobId=game.JobId,Snapshot={
                                State=vaultState,Window=scrambleSnapshot.Window,EventEndsAt=scrambleSnapshot.EventEndsAt,
                            }}))
                        end)
                    end
                    if captures>=3 then return end
                    captures=captures+1
                    seen={}; count=0
                    dump("ServerState"..captures,table.pack(...),0)
                    if type(writefile)=="function" then
                        pcall(writefile,"AcidHubTests_ScheduleScan.txt",table.concat(lines,"\n"))
                    end
                end)
                lines[#lines+1]="Listening for up to 3 Scramble state messages."
            end
            local util=shared:FindFirstChild("Util")
            local rules=util and util:FindFirstChild("ScrambleRules")
            assert(rules and rules:IsA("ModuleScript"),"ScrambleRules not loaded")
            local ruleApi=require(rules)
            dump("ScrambleRules",ruleApi,0)
            local types=shared:FindFirstChild("Types")
            local scramble=types and types:FindFirstChild("Scramble")
            if scramble and scramble:IsA("ModuleScript") then dump("ScrambleTypes",require(scramble),0) end
            local remoteModule=shared:FindFirstChild("Remotes")
            if remoteModule and remoteModule:IsA("ModuleScript") then
                local remotes=require(remoteModule)
                if type(remotes)=="table" then
                    for key,value in pairs(remotes) do
                        local name=tostring(key):lower()
                        if name:find("scramble",1,true) or name:find("experiment",1,true) then dump("Remotes."..tostring(key),value,0) end
                    end
                end
            end
            -- Capture a small sample of actual drone/drop payloads to investigate part rewards.
            for _,eventName in ipairs({"RE/Scramble/Drones","RE/Scramble/Drops"}) do
                local event=networking and networking:FindFirstChild(eventName)
                if event and event:IsA("RemoteEvent") then
                    local captured=0
                    connect(event.OnClientEvent,function(...)
                        if closed or captured>=2 then return end
                        captured=captured+1
                        local oldLines,oldSeen,oldCount=lines,seen,count
                        lines={"AcidHub Tests - Drone Part investigation",eventName,"ServerTime="..workspace:GetServerTimeNow()}
                        seen={}; count=0
                        dump("Payload",table.pack(...),0)
                        local output=table.concat(lines,"\n")
                        lines,seen,count=oldLines,oldSeen,oldCount
                        local filename="AcidHubTests_"..eventName:match("([^/]+)$").."Capture"..captured..".txt"
                        if type(writefile)=="function" then pcall(writefile,filename,output) end
                    end)
                end
            end
        end)
        if not ok then lines[#lines+1]="Capture error: "..tostring(err) end
        if closed then return end
        local saved=false
        if type(writefile)=="function" then saved=pcall(writefile,"AcidHubTests_ScheduleScan.txt",table.concat(lines,"\n")) end
        scheduleCaptureStatus=saved and "Schedule data saved for inspection" or "Schedule capture unavailable"
    end)
    local captureWatchdog=task.delay(12,function()
        if scheduleCaptureStatus=="Reading event schedule definitions..." then
            pcall(task.cancel,scheduleCaptureJob)
            scheduleCaptureStatus="Schedule module read timed out"
        end
    end)
    table.insert(cleanupActions,function() pcall(task.cancel,scheduleCaptureJob); pcall(task.cancel,captureWatchdog) end)
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
    connect(methodToggle.Activated,function()
        scanMethod=scanMethod=="By Area" and "Continuous Patrol" or "By Area"
        methodToggle.Text="Drone Scan method: "..(scanMethod=="By Area" and "1 - By Area" or "2 - Continuous Patrol")
        clearTarget(); resetSweep(); patrolGoal=nil; patrolIndex=1
    end)
    connect(priorityToggle.Activated,function()
        prioritizeTen=not prioritizeTen
        priorityToggle.Text="Prioritize 10 HP Drones: "..(prioritizeTen and "ON" or "OFF")
        priorityToggle.TextColor3=prioritizeTen and colors.accent or colors.text
        priorityScanAt=-math.huge
        clearTarget()
    end)
    local function releasePartHold()
        if heldPartPrompt then pcall(function() heldPartPrompt:InputHoldEnd() end) end
        heldPartPrompt,partHeldAt=nil,nil
    end
    local function stopParts(message)
        releasePartHold()
        collectParts=false; partTarget=nil; partCharacter=nil; partReleasedAt=nil
        collectToggle.Text="Collect Lost Parts: OFF"; collectToggle.TextColor3=colors.text
        if message then partStatus.Text=message end
        clearTarget()
    end
    for i, option in ipairs({{"ScrapDrone","Scrap — 3 HP"},{"ReactorDrone","Reactor — 5 HP"},{"AugmentedDrone","Augmented — 10 HP"}}) do
        local tier,name=option[1],option[2]
        local control=button(name..": ON",UDim2.new(),UDim2.new(1,-6,0,32),testsPage)
        control.LayoutOrder=-9+i
        control.TextColor3=colors.accent
        connect(control.Activated,function()
            selectedTiers[tier]=not selectedTiers[tier]
            control.Text=name..(selectedTiers[tier] and ": ON" or ": OFF")
            control.TextColor3=selectedTiers[tier] and colors.accent or colors.muted
            clearTarget()
        end)
    end
    local function updateTimer()
        if os.clock()-timerUpdatedAt<1 then return end
        timerUpdatedAt=os.clock()
        local active=workspace:GetAttribute("ScrambleOutbreakActive")==true
        local now=workspace:GetServerTimeNow()
        local remaining=nextOutbreak(scrambleSnapshot,now)
        local timeText=remaining and countdown(remaining) or "Waiting for server..."
        if tonumber(scrambleSnapshot.EventEndsAt) and now>=scrambleSnapshot.EventEndsAt then timeText="Event finished"
        elseif active then timeText=timeText.." (active now)" end
        local state=scrambleSnapshot.State
        local lost=state and state.LostParts
        local lostText=lost and tostring((lost.LostPart1==true and 1 or 0)+(lost.LostPart2==true and 1 or 0)) or "--"
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
        if closed or not enabled or not target or workspace:GetAttribute("ScrambleOutbreakActive")~=true then holdingTarget=nil; return end
        local character=player.Character
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local hit=liveHit(target,workspace:FindFirstChild("ScrambleLocalVisuals"))
        if not humanoid or humanoid.Health<=0 or not root or not hit then holdingTarget=nil; return end
        if inAttackRange(hitDistance(hit,root.Position),holdingTarget==target) then
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
            if route or computing then revision=revision+1; route=nil; computing=false end
            humanoid:MoveTo(direct)
            return true
        end
        if not computing and (not routeGoal or (goal-routeGoal).Magnitude > 10 or not route or os.clock()-routeAt > 4)
            and os.clock()-routeAt>0.3 then
            computing = true
            routeGoal, routeAt = goal, os.clock()
            local token = revision
            local start = root.Position
            task.spawn(function()
                local path = pathfinding:CreatePath({AgentRadius=2, AgentHeight=5, AgentCanJump=true, WaypointSpacing=10})
                local destination=supported(goal) or goal
                local ok = pcall(function() path:ComputeAsync(start, destination) end)
                if token == revision and not closed and player.Character==character then
                    route = ok and path.Status == Enum.PathStatus.Success and path:GetWaypoints() or nil
                    routeIndex, computing = 2, false
                end
                path:Destroy()
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
                travel(humanoid,root,sweepStart); return false
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
            travel(humanoid,root,sweepReturning and sweepStart or sweepEnd)
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
        if not collectParts then return false end
        local character=player.Character
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if not humanoid or humanoid.Health<=0 or not root then
            releasePartHold(); clearTarget(); partCharacter=nil
            partStatus.Text="Waiting for your character."; return true
        end
        if partCharacter~=character then
            releasePartHold(); clearTarget(); partTarget=nil; partReleasedAt=nil; partCharacter=character
        end
        local folder=workspace:FindFirstChild("DrScrambleEvent")
        if not folder then partStatus.Text="Waiting for Lost Parts to load."; halt(); return true end
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
                if candidate then
                    local distance=(candidate.Position-root.Position).Magnitude
                    if distance<nearest then partTarget=model; nearest=distance end
                end
            end
            hit,prompt=available(partTarget)
            partAttempts=0; partReleasedAt=nil
            if not hit then
                local confirmed=vaultState.LostParts.LostPart1==true and vaultState.LostParts.LostPart2==true
                if not folder:FindFirstChild("LostPart1") or not folder:FindFirstChild("LostPart2") then
                    partStatus.Text="Waiting for both Lost Part objects to load."; return true
                end
                stopParts(confirmed and "Both Lost Parts collected (server confirmed)." or "No enabled Lost Part prompts. Check your vault progress.")
                return false
            end
            clearTarget()
        end
        local distance=(hit.Position-root.Position).Magnitude
        local range=math.max(0.1,prompt.MaxActivationDistance-1)
        partStatus.Text="Collecting "..tostring(partTarget:GetAttribute("DisplayName") or partTarget.Name)..string.format(" | %.0f studs",distance)
        if distance>range then
            releasePartHold(); partReleasedAt=nil
            local away=Vector3.new(root.Position.X-hit.Position.X,0,root.Position.Z-hit.Position.Z)
            local goal=hit.Position+(away.Magnitude>0.01 and away.Unit*2 or Vector3.new(2,0,0))
            if not travel(humanoid,root,goal) then stopParts("Path blocked. Move closer and enable collection again.") end
            return true
        end
        halt(humanoid,root)
        if heldPartPrompt then
            if os.clock()-partHeldAt>=prompt.HoldDuration+0.15 then
                releasePartHold(); partReleasedAt=os.clock()
            end
        elseif partReleasedAt and os.clock()-partReleasedAt<2 then
            partStatus.Text="Waiting for collection confirmation..."
        elseif partAttempts>=3 then
            stopParts("Collection unconfirmed after 3 attempts. Check the prompt and vault progress.")
        else
            resetRoute()
            heldPartPrompt=prompt; partHeldAt=os.clock(); partAttempts=partAttempts+1
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
    local function tick()
        updateTimer()
        if collectLostParts() then return end
        if not enabled then return end
        if not next(selectedTiers) or not (selectedTiers.ScrapDrone or selectedTiers.ReactorDrone or selectedTiers.AugmentedDrone) then
            clearTarget(); status.Text="Select at least one drone type."; return
        end
        if workspace:GetAttribute("ScrambleOutbreakActive") ~= true then
            clearTarget()
            resetSweep()
            status.Text = "Waiting for the next Dr Scramble outbreak."
            return
        end
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not humanoid or humanoid.Health <= 0 or not root then
            clearTarget(); resetSweep(); status.Text = "Waiting for your character to respawn."; return
        end
        if movingRoot and movingRoot~=root then clearTarget(); resetSweep(); patrolGoal=nil end
        local tool = bat(character)
        if not tool then clearTarget(); status.Text = "No owned bat found. Equip or obtain a bat."; return end
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
        if not inAttackRange(distance,holdingTarget==target) then
            holdingTarget=nil
            progressAt = os.clock()
            local away = Vector3.new(root.Position.X-hit.Position.X,0,root.Position.Z-hit.Position.Z)
            local goal = edge + (away.Magnitude > 0.01 and away.Unit*3 or Vector3.new(3,0,0))
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
        if os.clock()-lastSwing >= 0.7 and tool:GetAttribute("CooldownActive") ~= true
            and workspace:GetServerTimeNow() >= (tonumber(tool:GetAttribute("CooldownEndTime")) or 0) then
            lastSwing = os.clock()
            tool:Activate()
            tool:Deactivate()
        end
    end
    connect(toggle.Activated,function()
        enabled = not enabled
        clearTarget()
        resetSweep()
        patrolGoal=nil; patrolIndex=1
        toggle.Text = enabled and "Auto Samples: ON" or "Auto Samples: OFF"
        toggle.TextColor3 = enabled and colors.accent or colors.text
        status.Text = enabled and "Checking event..." or "Stopped."
    end)
    connect(collectToggle.Activated,function()
        if collectParts then stopParts("Lost Part collection stopped."); return end
        clearTarget(); collectParts=true; partTarget=nil; partCharacter=nil
        collectToggle.Text="Collect Lost Parts: ON"; collectToggle.TextColor3=colors.accent
        partStatus.Text="Locating available Lost Parts..."
    end)
    table.insert(cleanupActions,function() closed=true; enabled=false; stopParts(); clearTarget() end)
    task.spawn(function()
        while not closed do
            local ok, err = pcall(tick)
            if not ok then
                stopParts("Stopped: "..tostring(err))
                enabled=false; clearTarget(); toggle.Text="Auto Samples: OFF"; toggle.TextColor3=colors.text
                status.Text="Stopped: " .. tostring(err)
                warn("AcidHub Tests Auto Samples: " .. tostring(err))
            end
            task.wait((collectParts or (enabled and workspace:GetAttribute("ScrambleOutbreakActive")==true)) and 0.05 or 0.5)
        end
    end)
end
do
    local description = label("Dr Scramble's Experiments", UDim2.new(), UDim2.new(1,-6,0,30), testsPage)
    description.LayoutOrder = 1
    local scan = button("Scan Event Details", UDim2.new(), UDim2.new(1,-6,0,36), testsPage)
    scan.LayoutOrder = 2
    local status = label("Spawn some event enemies, then scan. This captures their names, attributes and health so the automation can be connected to the live event.",
        UDim2.new(), UDim2.new(1,-6,0,92), testsPage, true)
    status.LayoutOrder = 3
    status.TextSize = 14
    local output = make("TextBox", {
        Name = "EventDetails", Size = UDim2.new(1,-6,0,220), LayoutOrder = 4,
        BackgroundColor3 = colors.card, TextColor3 = colors.text, BorderSizePixel = 0,
        Font = Enum.Font.Code, TextSize = 12, Text = "Event scan results will appear here.",
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = false, MultiLine = true, ClearTextOnFocus = false, TextEditable = false,
    }, testsPage)
    local function eventName(name)
        name = name:lower()
        for _, word in ipairs({"scrambl", "experiment", "sample", "mutant", "minion"}) do
            if name:find(word, 1, true) then return true end
        end
        return false
    end
    local function inspect(object)
        local lines = {object:GetFullName() .. " [" .. object.ClassName .. "]"}
        local attributes = object:GetAttributes()
        local keys = {}
        for key in pairs(attributes) do keys[#keys+1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do lines[#lines+1] = "  @" .. key .. " = " .. tostring(attributes[key]) end
        if object:IsA("Humanoid") then
            lines[#lines+1] = "  Health=" .. object.Health .. "/" .. object.MaxHealth
        elseif object:IsA("ValueBase") then
            local ok, value = pcall(function() return object.Value end)
            if ok then lines[#lines+1] = "  Value=" .. tostring(value) end
        end
        return table.concat(lines, "\n")
    end
    local scanning = false
    local rewardCapture=button("Start Vault Reward Capture",UDim2.new(),UDim2.new(1,-6,0,36),testsPage)
    rewardCapture.LayoutOrder=0
    local capturing,captureClosed=false,false
    local captureLines,captureConnection,captureGeneration={},nil,0
    local captureClaimButton,captureClaimConnection
    local capturePending={}
    local function captureValue(value,depth,seen)
        if type(value)=="string" then return string.format("%q",value) end
        if type(value)~="table" then return tostring(value) end
        if depth>=5 or seen[value] then return "<table limit>" end
        seen[value]=true
        local fields,count={},0
        for key,item in pairs(value) do
            count=count+1; if count>60 then fields[#fields+1]="<entry limit>"; break end
            fields[#fields+1]="["..captureValue(key,depth+1,seen).."]="..captureValue(item,depth+1,seen)
        end
        return "{"..table.concat(fields,", ").."}"
    end
    local function appendCapture(name,args)
        if not capturing or captureClosed or #captureLines>=80 then return end
        captureLines[#captureLines+1]=string.format("%.3f %s %s",workspace:GetServerTimeNow(),name,captureValue(args,0,{}))
        output.Text=table.concat(captureLines,"\n")
        if type(writefile)=="function" then pcall(writefile,"AcidHubTests_VaultRewardCapture.txt",output.Text) end
    end
    local function flushCapture()
        local pending=capturePending
        capturePending={}
        for _,entry in ipairs(pending) do pcall(appendCapture,entry.name,entry.args) end
    end
    local function stopCapture()
        flushCapture()
        capturing=false; captureGeneration=captureGeneration+1
        if captureConnection then captureConnection:Disconnect(); captureConnection=nil end
        if captureClaimConnection then captureClaimConnection:Disconnect(); captureClaimConnection=nil end
        captureClaimButton=nil
        rewardCapture.Text="Start Vault Reward Capture"
    end
    connect(rewardCapture.Activated,function()
        if capturing then stopCapture(); status.Text="Capture stopped. Results are shown below and saved when file writing is available."; return end
        local packages=game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
        local networking=packages and packages:FindFirstChild("Networking")
        local state=networking and networking:FindFirstChild("RE/Scramble/State")
        if not state then status.Text="Scramble state event is not loaded yet."; return end
        captureLines={"AcidHub Tests - Passive vault reward capture (UI clicks and server State; no outgoing interception)"}
        capturePending={}
        capturing=true; captureGeneration=captureGeneration+1
        local generation=captureGeneration
        appendCapture("START",{})
        captureConnection=state.OnClientEvent:Connect(function(...)
            if capturing and not captureClosed and captureGeneration==generation and #capturePending<80 then
                capturePending[#capturePending+1]={name="IN State",args=table.pack(...)}
            end
        end)
        local function bindClaim()
            -- Four exact lookups, only during this manual capture; no broad UI traversal.
            local vault=playerGui:FindFirstChild("StolenVaultEventUI")
            local main=vault and vault:FindFirstChild("StolenVaultEventUIMain")
            local content=main and main:FindFirstChild("ContentFrame")
            local claim=content and content:FindFirstChild("Claim")
            if claim==captureClaimButton then return end
            if captureClaimConnection then captureClaimConnection:Disconnect(); captureClaimConnection=nil end
            captureClaimButton=claim
            if claim and claim:IsA("GuiButton") then
                captureClaimConnection=claim.Activated:Connect(function()
                    if capturing and not captureClosed and captureGeneration==generation and #capturePending<80 then
                        capturePending[#capturePending+1]={name="UI Claim activated (not proof of success)",args={}}
                    end
                end)
            end
        end
        local function drain()
            if captureClosed or not capturing or captureGeneration~=generation then return end
            flushCapture()
            pcall(bindClaim)
            task.delay(0.25,drain)
        end
        drain()
        rewardCapture.Text="Stop Vault Reward Capture"
        status.Text="Passive capture for 60 seconds. Open the vault and claim normally, then stop and copy."
        task.delay(60,function()
            if not captureClosed and capturing and captureGeneration==generation then
                stopCapture(); status.Text="Vault capture finished. Results saved when file writing is available."
            end
        end)
    end)
    table.insert(cleanupActions,function()
        stopCapture(); captureClosed=true
    end)
    local copyRewardCapture=button("Copy Vault Reward Capture",UDim2.new(),UDim2.new(1,-6,0,36),testsPage)
    copyRewardCapture.LayoutOrder=0
    connect(copyRewardCapture.Activated,function()
        flushCapture()
        if #captureLines==0 then
            status.Text="No vault reward capture yet. Start capture, claim manually, then stop and copy."
            return
        end
        local report=table.concat(captureLines,"\n")
        local copy=type(setclipboard)=="function" and setclipboard or (type(toclipboard)=="function" and toclipboard)
        if copy then
            local ok,result=pcall(copy,report)
            if ok and result~=false then
                status.Text=capturing and "Current capture copied. Stop after claiming and copy again for the complete report."
                    or "Vault reward capture copied. Paste it into the chat."
                return
            end
        end
        -- Preserve the stored report while allowing manual selection on executors without clipboard support.
        output.Text=report
        output.TextEditable=true
        output:CaptureFocus()
        output.CursorPosition=#report+1
        output.SelectionStart=1
        status.Text="Clipboard unavailable. Report selected below: press Ctrl+C to copy."
    end)
    -- VAULT REQUEST BUTTONS BEGIN
    local openVault=button("Open Vault UI",UDim2.new(),UDim2.new(1,-6,0,36),testsPage)
    local claimVault=button("Claim Vault Rewards",UDim2.new(),UDim2.new(1,-6,0,36),testsPage)
    openVault.LayoutOrder=0; claimVault.LayoutOrder=0
    local vaultRequestStatus=label("Manual vault calls: open the UI or claim your completed parts.",UDim2.new(),UDim2.new(1,-6,0,72),testsPage,true)
    vaultRequestStatus.LayoutOrder=0; vaultRequestStatus.TextSize=14
    local vaultRequestBusy,vaultRequestClosed=false,false
    local vaultRequestGeneration=0
    local function requestVault(operation)
        if vaultRequestClosed or vaultRequestBusy then return end
        local packages=game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
        local networking=packages and packages:FindFirstChild("Networking")
        local request=networking and networking:FindFirstChild("RF/Scramble/Request")
        if not request or not request:IsA("RemoteFunction") then
            vaultRequestStatus.Text="Vault request remote is not loaded yet. Try again after the game loads."
            return
        end
        vaultRequestBusy=true; vaultRequestGeneration=vaultRequestGeneration+1
        local generation=vaultRequestGeneration
        vaultRequestStatus.Text=(operation=="Discover" and "Opening vault UI" or "Requesting vault reward").." — waiting for server..."
        task.delay(10,function()
            if not vaultRequestClosed and vaultRequestBusy and generation==vaultRequestGeneration then
                vaultRequestStatus.Text="Still waiting for the server. Repeated clicks are blocked until this request returns."
            end
        end)
        -- Exact captured argument shape: operation followed by two explicit nil arguments.
        local ok,result=pcall(function() return table.pack(request:InvokeServer(operation,nil,nil)) end)
        vaultRequestBusy=false
        if vaultRequestClosed then return end
        if not ok then
            vaultRequestStatus.Text="Vault request error: "..tostring(result)
            return
        end
        local response=captureValue(result,0,{})
        vaultRequestStatus.Text="Server returned: "..response:sub(1,240).."\nCheck the vault UI/reward to confirm the result."
    end
    connect(openVault.Activated,function() requestVault("Discover") end)
    connect(claimVault.Activated,function() requestVault("Vault") end)
    table.insert(cleanupActions,function() vaultRequestClosed=true end)
    -- VAULT REQUEST BUTTONS END
    local rewardScan=button("Scan Vault Reward UI",UDim2.new(),UDim2.new(1,-6,0,36),testsPage)
    rewardScan.LayoutOrder=0
    connect(rewardScan.Activated,function()
        local vaultUI=playerGui:FindFirstChild("StolenVaultEventUI")
        if not vaultUI then status.Text="Open the vault UI first, then scan its reward controls."; return end
        local lines={"AcidHub Tests - Vault reward UI",vaultUI:GetFullName()}
        if vaultUI:IsA("ScreenGui") then lines[#lines+1]="Enabled="..tostring(vaultUI.Enabled) end
        -- Explicit manual scan of this one known UI only; never runs in the automation loop.
        for _,object in ipairs(vaultUI:GetDescendants()) do
            if object:IsA("GuiButton") or object:IsA("TextLabel") then
                lines[#lines+1]=object:GetFullName().." ["..object.ClassName.."] Visible="..tostring(object.Visible)
                    ..((object:IsA("TextButton") or object:IsA("TextLabel")) and " Text="..object.Text or "")
            end
        end
        output.Text=table.concat(lines,"\n")
        local saved=type(writefile)=="function" and pcall(writefile,"AcidHubTests_VaultRewardScan.txt",output.Text)
        status.Text=saved and "Vault controls saved to AcidHubTests_VaultRewardScan.txt." or "Vault controls shown below."
    end)
    local vaultScan=button("Scan Lost Vault Parts",UDim2.new(),UDim2.new(1,-6,0,36),testsPage)
    vaultScan.LayoutOrder=0
    local scanClosed=false
    table.insert(cleanupActions,function() scanClosed=true end)
    local function vaultPartName(value)
        local name=tostring(value or ""):lower():gsub("[^%w]","")
        return name:find("lostpart",1,true)~=nil or name:find("lostvaultpart",1,true)~=nil
            or name:find("vaultpart",1,true)~=nil
    end
    local function objectPosition(object)
        if object:IsA("BasePart") then return object.Position end
        if object:IsA("Attachment") then return object.WorldPosition end
        if object:IsA("Model") then return object:GetPivot().Position end
        if object:IsA("ProximityPrompt") and object.Parent then return objectPosition(object.Parent) end
    end
    connect(vaultScan.Activated,function()
        if scanning or scanClosed then return end
        scanning=true
        status.Text="Scanning loaded vault parts and nearby collection prompts..."
        local ok,result=pcall(function()
            local character=player.Character
            local root=character and character:FindFirstChild("HumanoidRootPart")
            assert(root,"Wait for your character, then scan again.")
            local origin=root.Position
            local candidates,seen={},{}
            local function add(object,reason)
                if not object or seen[object] or #candidates>=300 then return end
                if character and object:IsDescendantOf(character) then return end
                local position=objectPosition(object)
                seen[object]=true
                candidates[#candidates+1]={object=object,reason=reason,position=position,
                    distance=position and (position-origin).Magnitude or math.huge}
            end
            for index,object in ipairs(workspace:GetDescendants()) do
                if index%200==0 then task.wait(); if scanClosed then return nil end end
                if vaultPartName(object.Name) or vaultPartName(object:GetAttribute("ScrambleRole"))
                    or vaultPartName(object:GetAttribute("ScrambleQuestId")) or vaultPartName(object:GetAttribute("ScrambleAssetId")) then
                    add(object,"Vault-part name or attribute")
                elseif object:IsA("ProximityPrompt") then
                    local position=objectPosition(object)
                    local matches=vaultPartName(object.ObjectText) or vaultPartName(object.ActionText)
                    if matches or (position and (position-origin).Magnitude<=25) then
                        add(object,matches and "Lost Vault Part prompt" or "Nearby prompt (unconfirmed)")
                        local parent=object.Parent
                        while parent and parent~=workspace do
                            if parent:IsA("Model") then add(parent,"Model owning collection prompt"); break end
                            parent=parent.Parent
                        end
                    end
                end
            end
            table.sort(candidates,function(a,b)
                if a.distance==b.distance then return a.object:GetFullName()<b.object:GetFullName() end
                return a.distance<b.distance
            end)
            local lines={"AcidHub Tests - Lost Vault Parts", "ServerTime="..workspace:GetServerTimeNow(),
                "Area="..tostring(player:GetAttribute("AreaId")),"PlayerPosition="..tostring(origin),
                "Loaded candidates="..#candidates,"Sorted nearest first; nearby unconfirmed prompts are labeled separately."}
            local function detail(object)
                lines[#lines+1]=inspect(object)
                local position=objectPosition(object)
                if position then lines[#lines+1]="  Position="..tostring(position) end
                if object:IsA("BasePart") then
                    lines[#lines+1]="  Size="..tostring(object.Size).."; CanTouch="..tostring(object.CanTouch).."; CanCollide="..tostring(object.CanCollide)
                elseif object:IsA("ProximityPrompt") then
                    lines[#lines+1]=string.format("  ObjectText=%s; ActionText=%s; Enabled=%s; HoldDuration=%s; MaxActivationDistance=%s; RequiresLineOfSight=%s; Key=%s",
                        object.ObjectText,object.ActionText,tostring(object.Enabled),tostring(object.HoldDuration),tostring(object.MaxActivationDistance),tostring(object.RequiresLineOfSight),tostring(object.KeyboardKeyCode))
                end
            end
            for index,entry in ipairs(candidates) do
                if scanClosed then return nil end
                lines[#lines+1]=string.format("\nCandidate %d | %.1f studs | %s",index,entry.distance,entry.reason)
                detail(entry.object)
                if entry.object.Parent then lines[#lines+1]="Parent context:"; lines[#lines+1]=inspect(entry.object.Parent) end
                local children=entry.object:GetDescendants()
                for childIndex,child in ipairs(children) do
                    if childIndex>160 then lines[#lines+1]="  Descendants truncated at 160."; break end
                    detail(child)
                end
                if index%5==0 then task.wait() end
            end
            if #candidates>=300 then lines[#lines+1]="Candidate limit reached (300)." end
            if #candidates==0 then lines[#lines+1]="No matches loaded. Stand near the visible Collect prompt and scan again." end
            return table.concat(lines,"\n")
        end)
        scanning=false
        if scanClosed then return end
        if not ok then status.Text="Vault scan failed: "..tostring(result); return end
        output.Text=result:sub(1,12000)..(#result>12000 and "\n[Preview shortened; full scan is in the saved file.]" or "")
        local saved=false
        if type(writefile)=="function" then saved=pcall(writefile,"AcidHubTests_VaultPartsScan.txt",result) end
        status.Text=saved and "Saved AcidHubTests_VaultPartsScan.txt. Tell me when it is ready."
            or "Could not save the file; full scan printed to the console."
        if not saved then print(result) end
    end)
    connect(scan.Activated, function()
        if scanning then return end
        scanning = true
        status.Text = "Scanning event objects..."
        local ok, result = pcall(function()
            local lines = {"AcidHub Tests - event discovery", "PlaceId=" .. game.PlaceId}
            local seen, count = {}, 0
            local function add(object)
                if not object or seen[object] or count >= 1500 then return end
                seen[object] = true
                count = count + 1
                lines[#lines+1] = inspect(object)
            end
            add(workspace)
            add(player)
            -- Include event HUD paths and text so next-start timer binding can be verified.
            for _,object in ipairs(playerGui:GetDescendants()) do
                if (object:IsA("TextLabel") or object:IsA("TextButton")) and not object:IsDescendantOf(gui) then
                    local text=object.Text:gsub("<[^>]+>","")
                    if text:match("%d+%s*[ms]") or text:match("%d+:%d%d") or eventName(text) then
                        lines[#lines+1]="HUD "..object:GetFullName().." = "..text
                    end
                end
            end
            for _, root in ipairs({workspace, game:GetService("ReplicatedStorage")}) do
                for _, object in ipairs(root:GetDescendants()) do
                    local health = object:GetAttribute("Health") or object:GetAttribute("HP")
                    local npc = object:IsA("Humanoid") and not Players:GetPlayerFromCharacter(object.Parent)
                    local stateRemote=(object:IsA("RemoteEvent") or object:IsA("RemoteFunction"))
                        and (object.Name:find("Snapshot",1,true) or object.Name:find("State",1,true))
                    if eventName(object.Name) or stateRemote or (root == workspace and (npc or health ~= nil)) then
                        add(object.Parent)
                        add(object)
                        for _, child in ipairs(object:GetChildren()) do add(child) end
                    end
                end
            end
            lines[#lines+1] = count >= 1500 and "Object limit reached; results truncated." or "Scan complete."
            return table.concat(lines, "\n")
        end)
        scanning = false
        if not ok then status.Text = "Scan failed: " .. tostring(result); return end
        output.Text = result
        local saved = false
        if type(writefile) == "function" then
            saved = pcall(writefile, "AcidHubTests_EventScan.txt", result)
        end
        status.Text = saved and "Saved AcidHubTests_EventScan.txt. Tell me when the scan is ready so I can inspect it."
            or "Scan complete. Copy the results below and send them here."
        print(result)
    end)
end

-- testBat: edits live client configuration only; never sends attacks or remotes.
do
    local tab=button("testBat",UDim2.fromOffset(0,44),UDim2.new(1,0,0,36),sidebar)
    local page=make("ScrollingFrame",{Name="testBat",Position=testsPage.Position,Size=testsPage.Size,
        BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,
        CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,Visible=false},panel)
    make("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},page)
    local function selectBat(value)
        page.Visible=value;testsPage.Visible=not value
        tab.TextColor3=value and colors.accent or colors.text
        testsTab.TextColor3=value and colors.text or colors.accent
        pageTitle.Text=value and "testBat" or "Tests"
    end
    connect(tab.Activated,function() selectBat(true) end)
    connect(testsTab.Activated,function() selectBat(false) end)
    local note=label("Load Bat Data to edit live client values. Apply does not prove server damage/range changed. GetHitboxScalar is a function and stays read-only. Changes are not saved.",
        UDim2.new(),UDim2.new(1,-8,0,100),page,true)
    note.LayoutOrder=0;note.TextSize=14
    local load=button("Load Bat Data",UDim2.new(),UDim2.new(1,-8,0,34),page);load.LayoutOrder=1
    local refresh=button("Refresh Current Values",UDim2.new(),UDim2.new(1,-8,0,34),page);refresh.LayoutOrder=2
    local restoreAll=button("Restore All",UDim2.new(),UDim2.new(1,-8,0,34),page);restoreAll.LayoutOrder=3
    local status=label("Ready. Equip or carry your bat before loading.",UDim2.new(),UDim2.new(1,-8,0,60),page,true)
    status.LayoutOrder=4;status.TextSize=14
    local entries={}
    local loaded,loading,dead=false,false,false
    local job
    -- BAT EDIT POLICY BEGIN
    local function parseBatValue(text,kind)
        if kind=="number" then
            local n=tonumber(text)
            if not n or n~=n or math.abs(n)==math.huge then return nil,"Enter a finite number." end
            return n
        elseif kind=="boolean" then
            text=text:lower():match("^%s*(.-)%s*$")
            if text=="true" then return true elseif text=="false" then return false end
            return nil,"Enter true or false."
        elseif kind=="string" then return text end
        return nil,"This value type is read-only."
    end
    local function writeBatValue(entry,value)
        local ok,err=pcall(entry.set,value)
        if not ok then return false,tostring(err) end
        local readOk,current=pcall(entry.get)
        if not readOk or current~=value then return false,"Value did not remain set; refresh to inspect." end
        return true
    end
    local function restoreBatValue(entry)
        if not entry.changed then return true end
        local ok,current=pcall(entry.get)
        if not ok then return false,"Target unavailable." end
        -- Avoid overwriting fresh game state such as an actively changing cooldown.
        if current~=entry.lastApplied then entry.changed=false;return false,"Game changed this value; left it unchanged." end
        local restored,err=writeBatValue(entry,entry.original)
        if restored then entry.changed=false end
        return restored,err
    end
    -- BAT EDIT POLICY END
    local function render(entry,updateEditor)
        local ok,value=pcall(entry.get)
        entry.current.Text="Current: "..(ok and tostring(value) or "unavailable").." | Original: "..tostring(entry.original)
        if updateEditor and ok then entry.box.Text=tostring(value) end
    end
    local function addEntry(name,get,set)
        local ok,value=pcall(get)
        if not ok then return end
        local kind=type(value)
        local row=make("Frame",{Size=UDim2.new(1,-8,0,128),BackgroundColor3=colors.card,BorderSizePixel=0,
            LayoutOrder=10+#entries},page)
        make("UICorner",{CornerRadius=UDim.new(0,7)},row)
        label(name,UDim2.fromOffset(8,3),UDim2.new(1,-16,0,34),row).TextSize=14
        local current=label("",UDim2.fromOffset(8,36),UDim2.new(1,-16,0,36),row,true);current.TextSize=12
        local box=make("TextBox",{Position=UDim2.fromOffset(8,78),Size=UDim2.new(1,-174,0,34),
            Text=tostring(value),ClearTextOnFocus=false,BackgroundColor3=colors.panel,TextColor3=colors.text,
            BorderSizePixel=0,TextSize=14,TextWrapped=true,Font=Enum.Font.Code},row)
        local apply=button("Apply",UDim2.new(1,-158,0,78),UDim2.fromOffset(70,34),row)
        local restore=button("Restore",UDim2.new(1,-82,0,78),UDim2.fromOffset(74,34),row)
        local entry={name=name,get=get,set=set,original=value,kind=kind,current=current,box=box}
        entries[#entries+1]=entry
        render(entry,false)
        if kind~="number" and kind~="string" and kind~="boolean" then
            box.Text="Read-only "..kind;box.TextEditable=false;apply.Visible=false;restore.Visible=false
            current.Text=kind=="function" and "Function implementation is not a configurable value." or "Unsupported value type."
            return
        end
        connect(apply.Activated,function()
            local nextValue,err=parseBatValue(box.Text,kind)
            if err then status.Text=name..": "..err;return end
            local beforeOk=pcall(get)
            if not beforeOk then status.Text=name..": target unavailable.";return end
            local success,message=writeBatValue(entry,nextValue)
            if success then entry.changed=nextValue~=entry.original;entry.lastApplied=nextValue end
            render(entry,false)
            status.Text=success and (name..": applied locally. Test the actual result in-game.") or (name..": "..tostring(message))
        end)
        connect(restore.Activated,function()
            local success,err=restoreBatValue(entry);render(entry,true)
            status.Text=name..(success and ": restored / no local change pending." or ": "..tostring(err))
        end)
    end
    local function restoreEverything()
        local failures=0
        for _,entry in ipairs(entries) do
            local ok=restoreBatValue(entry)
            if not ok then failures+=1 end
            if not dead then render(entry,true) end
        end
        return failures
    end
    connect(refresh.Activated,function()
        for _,entry in ipairs(entries) do render(entry,false) end
        status.Text="Current values refreshed. Typed edits retained. Tool rows refer to the bat loaded in this session."
    end)
    connect(restoreAll.Activated,function()
        local failures=restoreEverything()
        status.Text=failures==0 and "All pending local edits restored." or (failures.." values changed externally or could not be restored; inspect Current values.")
    end)
    connect(load.Activated,function()
        if loaded or loading or dead then return end
        loading=true;status.Text="Loading confirmed configuration modules…"
        job=task.defer(function()
            local errors={}
            local function config(module,prefix)
                if not module or not module:IsA("ModuleScript") then errors[#errors+1]=prefix.." missing";return end
                local ok,data=pcall(require,module)
                if dead then return end
                if not ok or type(data)~="table" then errors[#errors+1]=prefix.." unavailable: "..tostring(data);return end
                local seen={}
                local function visit(target,path,depth)
                    if seen[target] or depth>5 then return end
                    seen[target]=true
                    local keys={}
                    for key in next,target do keys[#keys+1]=key end
                    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
                    for _,key in ipairs(keys) do
                        if #entries>=120 then return end
                        local value=target[key]
                        if type(value)=="table" then visit(value,path.."."..tostring(key),depth+1)
                        else addEntry(path.."."..tostring(key),function() return target[key] end,function(v) target[key]=v end) end
                    end
                end
                visit(data,prefix,0)
            end
            local ok,err=pcall(function()
                local storage=game:GetService("ReplicatedStorage")
                local shared=storage:FindFirstChild("Shared")
                local modules=shared and shared:FindFirstChild("Modules")
                local controller=modules and modules:FindFirstChild("BatController")
                config(controller and controller:FindFirstChild("Config"),"Controller")
                if dead then return end
                local data=storage:FindFirstChild("Data")
                local gears=data and data:FindFirstChild("Gears")
                local configs=gears and gears:FindFirstChild("Configs")
                config(configs and configs:FindFirstChild("Bat"),"Bat")
                if dead then return end
                local tool
                for _,container in pairs({player.Character,player:FindFirstChild("Backpack")}) do
                    for _,obj in ipairs(container:GetChildren()) do
                        if obj:IsA("Tool") and obj:GetAttribute("IsBat")==true then tool=obj;break end
                    end
                    if tool then break end
                end
                if tool then
                    local attributes=tool:GetAttributes()
                    local keys={};for key in pairs(attributes) do keys[#keys+1]=key end;table.sort(keys)
                    for _,key in ipairs(keys) do
                        addEntry("Tool."..key,function() return tool:GetAttribute(key) end,function(v)
                            assert(tool.Parent,"Loaded bat no longer exists; reload Tests for the new tool.")
                            tool:SetAttribute(key,v)
                        end)
                    end
                else errors[#errors+1]="No owned bat found; reload Tests after obtaining one" end
            end)
            if dead then return end
            if not ok then errors[#errors+1]=tostring(err) end
            loading=false;loaded=#entries>0;job=nil
            load.Text=loaded and "Bat Data Loaded" or "Retry Load Bat Data"
            status.Text=#errors>0 and table.concat(errors,"; ") or "Loaded. Edit one value, Apply, and test. Restore before the next experiment."
        end)
    end)
    table.insert(cleanupActions,function()
        dead=true
        if job then pcall(task.cancel,job) end
        local failures=restoreEverything()
        if failures>0 then warn("testBat: "..failures.." values changed externally or could not be restored.") end
    end)
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
        local minimumWidth=540
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

