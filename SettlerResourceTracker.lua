-----------------------------------------------------------------------------------------------
-- Client Lua Script for SettlerResourceTracker
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
require "Apollo" 
require "Window"
 
-----------------------------------------------------------------------------------------------
-- SettlerResourceTracker Module Definition
-----------------------------------------------------------------------------------------------
local SettlerResourceTracker = {} 
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-- e.g. local kiExampleVariableMax = 999
local kcrSelectedText = ApolloColor.new("UI_BtnTextHoloPressedFlyby")
local kcrNormalText = ApolloColor.new("UI_TextHoloBody")

function table.find(val, list)
  for _,v in pairs(list) do
    if v == val then
      return true
    end
  end

  return false
end

 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function SettlerResourceTracker:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here
	o.tItems = {} -- keep track of all the list items
	o.wndSelectedListItem = nil -- keep track of which list item is currently selected
	o.tResources = {}
	o.firstRun = true

    return o
end

function SettlerResourceTracker:Init()
	local bHasConfigureFunction = true
	local strConfigureButtonText = "Settler Resource Tracker"
	local tDependencies = {
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- SettlerResourceTracker OnLoad
-----------------------------------------------------------------------------------------------
function SettlerResourceTracker:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("SettlerResourceTracker.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

-----------------------------------------------------------------------------------------------
-- SettlerResourceTracker OnDocLoaded
-----------------------------------------------------------------------------------------------
function SettlerResourceTracker:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "SrtForm", nil, self)
	
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		
		-- Tracked item list
		self.wndItemList = self.wndMain:FindChild("TrackedList")
	    self.wndMain:Show(false, true)
		self:LoadPosition()

		-- if the xmlDoc is no longer needed, you should set it to nil
		-- self.xmlDoc = nil
		
		-- Register handlers for events, slash commands and timer, etc.
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
		Apollo.RegisterSlashCommand("srt", "OnSettlerResourceTrackerOn", self)
		Apollo.RegisterSlashCommand("srtd", "RoverDebug", self)
		Apollo.RegisterSlashCommand("srtr", "Recount", self)
		Apollo.RegisterEventHandler("ChannelUpdate_Loot", "OnLootedItem", self)
		Apollo.RegisterEventHandler("SubZoneChanged", "PopulateItemList", self)
		Apollo.RegisterEventHandler("UpdateInventory", "Recount", self)
		
		if not self.isActive then
			Apollo.RemoveEventHandler("ChannelUpdate_Loot", self)
		end

		if self.firstRun then
			self:ReloadFromBags()
		end
		-- Do additional Addon initialization here
	end
end

function SettlerResourceTracker:RoverDebug()
	SendVarToRover("Settler Resource Tracker", self)
end

function SettlerResourceTracker:InitConfigOptions()
	if self.isActive == nil then
		self.isActive = true
	end
	if self.firstRun == nil then
		self.firstRun = true
	end
end

function SettlerResourceTracker:OnSave(eLevel)
	if eLevel~= GameLib.CodeEnumAddonSaveLevel.Character then
		return nil
	end
	
	local tSaveData = {}
	
	self:StorePosition()
	
	tSaveData.isActive = self.isActive
	tSaveData.tResources = self.tResources
	tSaveData.tLocations = self.tLocations
	tSaveData.fisrtRun = self.firstRun
	
	return tSaveData
end

function SettlerResourceTracker:OnRestore(eLevel, tData)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then
		return nil
	end
	
	if(tData.isActive ~= nil) then
		self.isActive = tData.isActive
	end
	
	if(tData.tResources ~= nil) then
		self.tResources = tData.tResources
	end
	
	if(tData.tLocations ~= nil) then
		self.tLocations = tData.tLocations
	end
	
	if(tData.firstRun ~= nil) then
		self.firstRun = tData.firstRun
	end
end

-- on SlashCommand "/srt"
function SettlerResourceTracker:OnSettlerResourceTrackerOn()
	self.wndMain:Invoke() -- show the window
	self:LoadPosition()
	-- populate the item list
	self:PopulateItemList()
end

function SettlerResourceTracker:OnClose()
	self:StorePosition()
	self.wndMain:Close()
end

-----------------------------------------------------------------------------------------------
-- ItemList Functions
-----------------------------------------------------------------------------------------------
-- populate item list
function SettlerResourceTracker:PopulateItemList()
	-- make sure the item list is empty to start with
	self:DestroyItemList()

	for _,item in pairs(self.tResources) do
		if item.zone == GameLib.GetCurrentZoneMap().id then
			self:AddItem(item)
		end
	end
	
	-- now all the item are added, call ArrangeChildrenVert to list out the list items vertically
	self.wndItemList:ArrangeChildrenVert()
end

-- clear the item list
function SettlerResourceTracker:DestroyItemList()
	-- destroy all the wnd inside the list
	--for idx,wnd in ipairs(self.tItems) do
		--wnd:Destroy()
	--end
	self.wndItemList:DestroyChildren()

	-- clear the list item array
	self.tItems = {}
	self.wndSelectedListItem = nil
end

-- add an item into the item list
function SettlerResourceTracker:AddItem(item)
	local wndEntry = Apollo.LoadForm(self.xmlDoc, "TrackedItem", self.wndItemList, self)
	local itemFound = false
	
	for _, entry in pairs(self.wndItemList:GetChildren()) do
		if entry:FindChild("Name"):GetText() == item.name then
			entry:Destroy()
		end
	end
	
	self.tItems[item.name] = wndEntry
	
	wndEntry:FindChild("Name"):SetText(item.name)
	wndEntry:FindChild("Count"):SetText(item.count)
	wndEntry:FindChild("Icon"):SetSprite(item.icon)
	
	self.wndItemList:ArrangeChildrenVert()	
end

function SettlerResourceTracker:RemoveItem(wndControl) 
	self.tItems[wndControl:GetData().name] = nil
	wndControl:Destroy()
	
	self.wndItemList:ArrangeChildrenVert()
end

function SettlerResourceTracker:Recount()
	self:ReloadFromBags()
	self:PopulateItemList()
end

function SettlerResourceTracker:AddResource(tResource)
	local resId = tResource.itemNew:GetItemId()
	local resName = tResource.itemNew:GetName()
	local resCount = tResource.nCount
	local resIcon = Item.GetIcon(resId)
	local zone = GameLib.GetCurrentZoneMap().id

	if self.tResources[resId] then
		self.tResources[resId].count = self.tResources[resId].count + resCount
	else
		local tTemp = { zone = zone,
						name = resName,
						count = resCount,
						icon = resIcon }
		self.tResources[resId] = tTemp
	end				
	
	if self.tResources[resId].zone == 0 then
		self.tResources[resId].zone = zone
	end
	self:AddItem(self.tResources[resId])
end

function SettlerResourceTracker:ReloadFromBags()
	local tTemp = GameLib.GetPlayerUnit():GetSupplySatchelItems()["Settler Resources"]
	
	for _, item in pairs(tTemp) do
		local itemId = item.itemMaterial:GetItemId()
		local itemName = item.itemMaterial:GetName()
		local itemIcon = Item.GetIcon(itemId)
		local itemCount = item.nCount
		local itemZone = 0
		
		if self.tResources[itemId] then
			if self.tResources[itemId].zone ~= nil then
				itemZone = self.tResources[itemId].zone
			end
		end
		
		self.tResources[itemId] =  { name = itemName, count = itemCount, icon = itemIcon, zone = itemZone }
	end
	
	if self.firstRun then
		self.firstRun = false
	end	
end

-- when a list item is selected
function SettlerResourceTracker:OnListItemSelected(wndHandler, wndControl)
    -- make sure the wndControl is valid
    if wndHandler ~= wndControl then
        return
    end
    
    -- change the old item's text color back to normal color
    local wndItemText
    if self.wndSelectedListItem ~= nil then
        wndItemText = self.wndSelectedListItem:FindChild("Name")
        wndItemText:SetTextColor(kcrNormalText)
    end
    
	-- wndControl is the item selected - change its color to selected
	self.wndSelectedListItem = wndControl
	wndItemText = self.wndSelectedListItem:FindChild("Name")
    wndItemText:SetTextColor(kcrSelectedText)
    
	Print( "item " ..  self.wndSelectedListItem:GetData() .. " is selected.")
end 


---------------------------------------------------------------------------------------------------
-- SrtForm Functions
---------------------------------------------------------------------------------------------------

function SettlerResourceTracker:StorePosition()
	self.tLocations = {
		tMainWindowLocation = self.wndMain and self.wndMain:GetLocation():ToTable(),
		tConfigWindowLocation = self.wndConfig and self.wndConfig:GetLocation():ToTable()
	}
end

function SettlerResourceTracker:LoadPosition()
	if self.tLocations and self.tLocations.tMainWindowLocation and self.wndMain then
		local tLocation = WindowLocation.new(self.tLocations.tMainWindowLocation)
		self.wndMain:MoveToLocation(tLocation)
	end	
	
	if self.tLocations and self.tLocations.tConfigWindowLocation and self.wndConfig then
		local tLocation = WindowLocation.new(self.tLocations.tConfigWindowLocation)
		self.wndConfig:MoveToLocation(tLocation)
	end
end

function SettlerResourceTracker:OnConfigure()
	if self.wndConfig ~= nil then
		self.wndConfig:Destroy()
		self.wndConfig = nil
	end
	
	self.wndConfig = Apollo.LoadForm("SettlerResourceTracker.xml", "ConfigForm", nil, self)
	self:LoadPosition()
	
	self.wndConfig:FindChild("EnableFrame:RadioButton"):SetCheck(self.isActive)
end

function SettlerResourceTracker:OnLootedItem(eType, tEventArgs)
	if tEventArgs.itemNew ~= nil then -- if we really looted an item
		if tEventArgs.itemNew:GetItemType() == 210 then -- Settler Resource Item Type id is 210
			self:AddResource(tEventArgs)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- ConfigForm Functions
---------------------------------------------------------------------------------------------------

function SettlerResourceTracker:OnConfigClose()
	self:StorePosition()
	self.wndConfig:Close()
end

function SettlerResourceTracker:OnIsActiveCheck(wndHandler, wndControl)
	self.isActive = true
	Apollo.RegisterEventHandler("ChannelUpdate_Loot", "OnLootedItem", self)
end

function SettlerResourceTracker:OnIsActiveUncheck(wndHandler, wndControl)
	self.isActive = false
	Apollo.RemoveEventHandler("ChannelUpdate_Loot")
end

-----------------------------------------------------------------------------------------------
-- SettlerResourceTracker Instance
-----------------------------------------------------------------------------------------------
local SettlerResourceTrackerInst = SettlerResourceTracker:new()
SettlerResourceTrackerInst:Init()
