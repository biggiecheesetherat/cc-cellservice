local BRAND={name="mostower",version="v1.0",logo=[[ == Welcome to MeatlyOS Tower Edition ==]]}

term.setTextColor(colors.cyan) print(BRAND.logo) print(BRAND.name.." "..BRAND.version) term.setTextColor(colors.white)
local function prompt() io.write("["..BRAND.name.."]> ") end
if not os.pullEventTimeout then function os.pullEventTimeout(name,timeout) local timer;if timeout then timer=os.startTimer(timeout) end while true do local e={os.pullEvent()}; if e[1]=="timer" and e[2]==timer then return nil end;if not name or e[1]==name then return table.unpack(e) end end end end

local programName = shell.getRunningProgram()..".lua"
local protectedFiles = {[programName]=true,["/startup"]=true,["/disk"]=true}
local hideSource=true
local fs_open_orig=fs.open
fs.open=function(path,mode,...)
  if path==programName and mode=="r" then return fs_open_orig(path,mode,...) end
  if protectedFiles[path] and (mode=="w" or mode=="a") then error("Attempt to modify protected file: "..path) end
  if hideSource and mode=="r" and protectedFiles[path] then error("Attempt to read protected file: "..path) end
  return fs_open_orig(path,mode,...)
end
local fs_delete_orig=fs.delete
fs.delete=function(path,...) if protectedFiles[path] or path=="/" then error("Attempt to delete protected file or root") end return fs_delete_orig(path,...) end
local shell_run_orig=shell.run
shell.run=function(cmd,...) if cmd:match("install") or cmd:match("os") then error("OS install commands are blocked by OEM lock") end return shell_run_orig(cmd,...) end

local DATAFILE="/.tower_registry"
local registry={}
local NAME="Tower1"
local function saveRegistry() local f=fs.open(DATAFILE,"w") f.write(textutils.serialize(registry)) f.close() end
local function loadRegistry() if fs.exists(DATAFILE) then local f=fs.open(DATAFILE,"r") registry=textutils.unserialize(f.readAll()) or {} f.close() else registry={} end end
loadRegistry()

local modemSide=nil
for _,side in ipairs(peripheral.getNames()) do if peripheral.getType(side)=="modem" then modemSide=side; break end end
if not modemSide then print("No modem"); return end
rednet.open(modemSide)

local PROTO_CTRL="cell.ctrl"
local PROTO_DATA="cell.data"

local function beacon()
  while true do
    rednet.broadcast({kind="cell_beacon",tower=NAME,id=os.getComputerID()},65500)
    sleep(5)
  end
end

local function receiver()
  while true do
    local ev,id,msg,proto=os.pullEvent("rednet_message")
    if proto==PROTO_CTRL and type(msg)=="table" then
      if msg.type=="register" and msg.number then
        local phoneID=id
        local requestedNum=msg.number
        local existingNum=nil
        for num,info in pairs(registry) do if info.id==phoneID then existingNum=num break end end
        if existingNum then
          if existingNum==requestedNum then rednet.send(phoneID,{type="reg_ack",tower=NAME},PROTO_CTRL)
          else rednet.send(phoneID,{type="denied",reason="number mismatch"},PROTO_CTRL) end
        else
          registry[requestedNum]={id=phoneID,ts=os.clock()}
          saveRegistry()
          rednet.send(phoneID,{type="reg_ack",tower=NAME},PROTO_CTRL)
        end
      elseif msg.type=="send" and msg.to and msg.body then
        local client=registry[msg.to]
        if client then rednet.send(client.id,{type="deliver",from=msg.to,body=msg.body,ts=os.epoch("utc")},PROTO_DATA) end
      end
    end
  end
end

local function cmdloop()
  local function help() print([[Commands: help setnum <old> <new> list exit]]) end
  help()
  while true do
    prompt()
    local line=read()
    if not line then break end
    local args={} for w in line:gmatch("%S+") do table.insert(args,w) end
    local cmd=args[1]
    if cmd=="help" then help()
    elseif cmd=="list" then for num,info in pairs(registry) do print(("Number: %s  ID: %d"):format(num,info.id)) end
    elseif cmd=="setnum" and args[2] and args[3] then
      local oldNum,newNum=args[2],args[3] local client=registry[oldNum]
      if client then registry[oldNum]=nil registry[newNum]=client saveRegistry() rednet.send(client.id,{type="assign_number",number=newNum},PROTO_CTRL) print(("Reassigned %s -> %s"):format(oldNum,newNum)) else print("Number not found: "..oldNum) end
    elseif cmd=="exit" then return
    else print("Unknown command") end
  end
end

parallel.waitForAny(receiver,beacon,cmdloop)
