-- Read-only bat stats inspection and passive tool activation capture with a local UI.
-- No simulated input, movement, callback invocation, require, remotes, or hooks.
local players=game:GetService("Players")
local player=players.LocalPlayer
local gui=Instance.new("ScreenGui")
gui.Name="AcidHubBatProbe"
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
local parent=player:WaitForChild("PlayerGui")
local prior=parent:FindFirstChild(gui.Name)
if prior then prior:Destroy() end
gui.Parent=parent
local function create(class,props,parentObject)
    local obj=Instance.new(class)
    for key,value in pairs(props) do obj[key]=value end
    obj.Parent=parentObject
    return obj
end
local panel=create("Frame",{AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),
    Size=UDim2.new(0.92,0,0.7,0),BackgroundColor3=Color3.fromRGB(23,26,31),BorderSizePixel=0},gui)
create("UISizeConstraint",{MaxSize=Vector2.new(500,380)},panel)
create("UICorner",{CornerRadius=UDim.new(0,10)},panel)
create("TextLabel",{Position=UDim2.fromOffset(14,8),Size=UDim2.new(1,-62,0,28),BackgroundTransparency=1,
    Text="AcidHub · Bat Inspector",TextColor3=Color3.fromRGB(165,244,117),Font=Enum.Font.GothamBold,
    TextSize=16,TextXAlignment=Enum.TextXAlignment.Left},panel)
local function button(text,pos,size)
    local b=create("TextButton",{Text=text,Position=pos,Size=size,BackgroundColor3=Color3.fromRGB(47,55,65),
        BorderSizePixel=0,TextColor3=Color3.new(1,1,1),TextSize=14,Font=Enum.Font.GothamMedium},panel)
    create("UICorner",{CornerRadius=UDim.new(0,6)},b)
    return b
end
local close=button("×",UDim2.new(1,-40,0,8),UDim2.fromOffset(28,28))
local startButton=button("Start Scan",UDim2.new(0,12,0,45),UDim2.new(0.333,-16,0,36))
local stopButton=button("Stop",UDim2.new(0.333,4,0,45),UDim2.new(0.333,-16,0,36))
local copyButton=button("Copy Report",UDim2.new(0.666,-4,0,45),UDim2.new(0.334,-8,0,36))
local status=create("TextLabel",{Position=UDim2.fromOffset(12,88),Size=UDim2.new(1,-24,0,38),BackgroundTransparency=1,
    Text="Ready. Equip your bat, Start Scan, then Stop and Copy Report.",TextWrapped=true,
    TextColor3=Color3.fromRGB(210,216,224),Font=Enum.Font.Gotham,TextSize=12,TextXAlignment=Enum.TextXAlignment.Left},panel)
local scroll=create("ScrollingFrame",{Position=UDim2.fromOffset(12,133),Size=UDim2.new(1,-24,1,-145),
    BackgroundColor3=Color3.fromRGB(16,19,23),BorderSizePixel=0,ScrollBarThickness=6,
    AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new()},panel)
local reportBox=create("TextBox",{Position=UDim2.fromOffset(6,4),Size=UDim2.new(1,-18,0,0),AutomaticSize=Enum.AutomaticSize.Y,
    BackgroundTransparency=1,Text="Report will appear here.",ClearTextOnFocus=false,TextEditable=false,
    MultiLine=true,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
    TextColor3=Color3.fromRGB(203,215,224),Font=Enum.Font.Code,TextSize=12},scroll)
local session=nil
local destroyed=false
local function report(s) return table.concat(s.output,"\n") end
local function save(s)
    if type(writefile)=="function" then return pcall(writefile,"AcidHub_BatProbe.txt",report(s)) end
    return false
end
local function stop(reason)
    local s=session
    if not s or not s.active then return end
    s.active=false
    for _,c in ipairs(s.connections) do c:Disconnect() end
    if s.worker then pcall(task.cancel,s.worker) end
    s.output[#s.output+1]="Capture stopped: "..reason
    save(s)
    if not destroyed then
        reportBox.Text=report(s)
        status.Text="Stopped. "..#report(s).." characters ready to copy."
    end
end
local function start()
    if destroyed or (session and session.active) then return end
    local s={active=true,output={"AcidHub bat inspection v2"},connections={},bytes=0,started=os.clock()}
    session=s
    status.Text="Reading owned bat stats and weapon scripts. No weapon changes."
    reportBox.Text="Scan running…"
    local function add(value)
        if not s.active then return end
        local text=tostring(value)
        if s.bytes+#text>1200000 then
            if not s.limit then s.limit=true;s.output[#s.output+1]="Report size limit reached." end
            return
        end
        s.bytes+=#text+1;s.output[#s.output+1]=text
    end
    local function watch(signal,fn)
        s.connections[#s.connections+1]=signal:Connect(function(...)
            if s.active then
                local ok,err=pcall(fn,...)
                if not ok then add("Observer error: "..tostring(err)) end
            end
        end)
    end
    s.worker=task.defer(function()
    local ok,err=pcall(function()
local function path(obj)
    local ok,value=pcall(function() return obj:GetFullName() end)
    return ok and value or tostring(obj)
end
local seen={}
local sourceCount=0
local function inspectScript(obj)
    if not s.active or seen[obj] then return end
    seen[obj]=true
    add("SCRIPT "..path(obj).." ["..obj.ClassName.."]")
    if sourceCount>=20 then add("Source inspection limit reached.");return end
    sourceCount+=1
    local ok,source=pcall(function() return obj.Source end)
    -- Decompile only an identified weapon script, when locally available.
    if (not ok or type(source)~="string" or source=="") and type(decompile)=="function" then
        ok,source=pcall(decompile,obj)
    end
    if ok and type(source)=="string" and (source:find("decompilation panicked",1,true)
        or source:find("Bytecode version",1,true) and source:find("unhandled",1,true)) then
        add("Decompiler failed: "..source)
    elseif ok and type(source)=="string" and source~="" then
        add("SOURCE BEGIN\n"..source:sub(1,150000).."\nSOURCE END")
    else add("Source unavailable: "..tostring(source)) end
    if s.active then save(s) end
    task.wait()
end
local function inspectSignal(label,signal)
    add("SIGNAL "..label)
    if type(getconnections)~="function" then add("getconnections unavailable");return end
    local ok,list=pcall(getconnections,signal)
    if not ok then add("Connection metadata unavailable: "..tostring(list));return end
    add("Connection count: "..tostring(#list))
    for i,connection in ipairs(list) do
        if not s.active then return end
        if i>40 then add("Connection limit reached");break end
        local readOk,fn=pcall(function() return connection.Function end)
        if readOk and type(fn)=="function" then
            local infoOk,source,line,name=pcall(function() return debug.info(fn,"sln") end)
            add(infoOk and string.format("Callback %d: %s:%s %s",i,tostring(source),tostring(line),tostring(name))
                or "Callback metadata unavailable")
        else add("Callback function unavailable") end
    end
end
add("Capabilities: getconnections="..type(getconnections)..", decompile="..type(decompile))
local function attributes(obj)
    local ok,values=pcall(function() return obj:GetAttributes() end)
    if not ok then add("Attributes unavailable: "..tostring(values));return end
    local keys={}
    for key in pairs(values) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do add("  @"..key.."="..tostring(values[key])) end
end
local function describe(obj)
    add("OBJECT "..path(obj).." ["..obj.ClassName.."]")
    attributes(obj)
    if obj:IsA("BasePart") then
        add("  Size="..tostring(obj.Size).." CanTouch="..tostring(obj.CanTouch).." CanCollide="..tostring(obj.CanCollide))
    elseif obj:IsA("ValueBase") then
        local ok,value=pcall(function() return obj.Value end)
        if ok then add("  Value="..tostring(value)) end
    elseif obj:IsA("Attachment") then add("  Position="..tostring(obj.Position))
    elseif obj:IsA("Animation") then add("  AnimationId="..obj.AnimationId) end
end
local found=false
for _,container in pairs({player.Character,player:FindFirstChild("Backpack")}) do
    for _,tool in ipairs(container:GetChildren()) do
        if tool:IsA("Tool") and (tool:GetAttribute("IsBat")==true or tool.Name:lower():find("bat",1,true)) then
            found=true;describe(tool)
            add("  Enabled="..tostring(tool.Enabled).." RequiresHandle="..tostring(tool.RequiresHandle).." Grip="..tostring(tool.Grip))
            inspectSignal(path(tool)..".Activated",tool.Activated)
            watch(tool.Activated,function() add(string.format("%.3f | Bat activated manually | %s",os.clock()-s.started,path(tool))) end)
            watch(tool.AttributeChanged,function(key) add("Bat attribute changed: "..key.."="..tostring(tool:GetAttribute(key))) end)
            for _,obj in ipairs(tool:GetDescendants()) do
                if not s.active then return end
                describe(obj)
                if obj:IsA("LocalScript") or obj:IsA("ModuleScript") then inspectScript(obj) end
            end
        end
    end
end
if not found then add("No owned bat found. Equip it before restarting the scan.") end
local roots={game:GetService("ReplicatedStorage")}
local playerScripts=player:FindFirstChild("PlayerScripts")
if playerScripts then roots[#roots+1]=playerScripts end
local count=0
-- Inspect the confirmed controller subtree before broad name discovery.
local storage=game:GetService("ReplicatedStorage")
local shared=storage:FindFirstChild("Shared")
local modules=shared and shared:FindFirstChild("Modules")
local controller=modules and modules:FindFirstChild("BatController")
if controller then
    describe(controller)
    if controller:IsA("ModuleScript") then inspectScript(controller) end
    local children=controller:GetDescendants()
    for index,obj in ipairs(children) do
        if not s.active then return end
        if index>250 then add("Controller object limit reached");break end
        describe(obj)
        if obj:IsA("ModuleScript") or obj:IsA("LocalScript") then inspectScript(obj) end
        if index%25==0 then task.wait() end
    end
else add("Confirmed Shared.Modules.BatController path unavailable") end
for _,root in ipairs(roots) do
    for index,obj in ipairs(root:GetDescendants()) do
        if not s.active then return end
        if index%150==0 then task.wait() end
        local name=obj.Name:lower()
        local relevant=name=="bat" or name=="bats" or name:match("^batcontroller") or name:match("^batconfig")
            or name:match("^batclient") or name:find("weapon",1,true)
            or name:find("combat",1,true) or name:find("melee",1,true)
        if relevant and count<80 and not (controller and (obj==controller or obj:IsDescendantOf(controller))) then
            count+=1;describe(obj)
            if obj:IsA("LocalScript") or obj:IsA("ModuleScript") then inspectScript(obj)
            elseif obj:IsA("Folder") or obj:IsA("Configuration") then
                for _,child in ipairs(obj:GetChildren()) do
                    if child:IsA("ValueBase") then describe(child) end
                end
            end
        end
    end
end
add("Bat scan complete. No weapon values were changed and no attacks were sent. Press Stop to freeze report.")
    end)
    if not s.active then return end
    if not ok then add("Scan error: "..tostring(err)) end
    save(s)
    reportBox.Text=report(s)
    status.Text=ok and "Bat scan complete. Stop and Copy Report; manual bat activations are logged until Stop."
        or "Bat scan encountered an error. Stop and copy the partial report."
    s.worker=nil
    end)
end
startButton.Activated:Connect(start)
stopButton.Activated:Connect(function() stop("Stop button") end)
copyButton.Activated:Connect(function()
    if not session then status.Text="Start Scan first to create a report.";return end
    local text=report(session)
    local copy=setclipboard or toclipboard
    local ok=type(copy)=="function" and pcall(copy,text)
    if ok then status.Text="Copied "..#text.." characters. Paste the report into our chat."
    else reportBox.Text=text;status.Text="Clipboard unavailable. Select and copy the report from the box below." end
end)
close.Activated:Connect(function() gui:Destroy() end)
gui.Destroying:Connect(function() destroyed=true;stop("UI closed or reloaded") end)
