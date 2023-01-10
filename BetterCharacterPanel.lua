local addonName, addon = ...;

-- luacheck: globals InspectFrame InspectPaperDollItemsFrame CharacterFrame C_PaperDollInfo C_TooltipInfo TooltipUtil IsLevelAtEffectiveMaxLevel InspectPaperDollFrameTalentsButtonMixin INSPECT_TALENTS_BUTTON InspectFrameTab3

local oPrint = print;
local function print(...)
	if(true)then
		local msg = strjoin(" ",tostringall(...));
		oPrint("|cff6600ccBetterCharacterPanel|r: " .. GetTime() .. " :",msg);
	end
end

local buttonLayout =
{
	[1]	= "left",
	[2]	= "left",
	[3]	= "left",
	[15] = "left",
	[5]	= "left",
	[9]	= "left",

	[10] = "right",
	[6] = "right",
	[7] = "right",
	[8] = "right",
	[11] = "right",
	[12] = "right",
	[13] = "right",
	[14] = "right",

	[16] = "center",
	[17] = "center",
};

local function ColorGradient(perc, ...)
	if perc >= 1 then
		local r, g, b = select(select('#', ...) - 2, ...);
		return r, g, b;
	elseif perc <= 0 then
		local r, g, b = ...;
		return r, g, b;
	end

	local num = select('#', ...) / 3;

	local segment, relperc = math.modf(perc*(num-1));
	local r1, g1, b1, r2, g2, b2 = select((segment*3)+1, ...);

	return r1 + (r2-r1)*relperc, g1 + (g2-g1)*relperc, b1 + (b2-b1)*relperc;
end

local function ColorGradientHP(perc)
	return ColorGradient(perc,1,0,0, 1,1,0, 0,1,0);
end

local enchantReplacementTable =
{
	["Stamina"] = "Stam",
	["Intellect"] = "Int",
	["Agility"] = "Agi",
	["Strength"] = "Str",

	["Mastery"] = "Mast",
	["Versatility"] = "Vers",
	["Critical Strike"] = "Crit",
	["Haste"] = "Haste",
	["Avoidance"] = "Avoid",

	["Minor Speed Increase"] = "Speed",
	["Homebound Speed"] = "Speed & HS Red.",
	["Plainsrunner's Breeze"] = "Speed",
	["Graceful Avoidance"] = "Avoid",
	["Regenerative Leech"] = "Leech",
	["Watcher's Loam"] = "Stam",
	["Rider's Reassurance"] = "Mount Speed",
	["Accelerated Agility"] = "Speed & Agi",
	["Reserve of Intellect"] = "Mana & Int",
	["Sustained Strength"] = "Stam & Str",
	["Waking Stats"] = "Primary Stat",

	-- strip all +, we are starved for space
	["+"] = "",
};

local function ProcessEnchantText(enchantText)
	for seek,replacement in pairs(enchantReplacementTable) do
		enchantText = enchantText:gsub(seek,replacement);
	end
	return enchantText;
end

local function CanEnchantSlot(unit, slot)
	-- all classes have something that increases power or survivability on chest/cloak/weapons/rings/wrist/boots
	if(slot == 5 or slot == 11 or slot == 12 or slot == 15 or slot == 16 or slot == 8 or slot == 9 or slot == 7)then
		return true;
	end

	-- Offhand filtering smile :)
	if(slot == 17)then
		local offHandItemLink = GetInventoryItemLink(unit,slot);
		if(offHandItemLink)then
			local itemEquipLoc = select(4,GetItemInfoInstant(offHandItemLink));
			return itemEquipLoc ~= "INVTYPE_HOLDABLE" and itemEquipLoc ~= "INVTYPE_SHIELD";
		end
		return false;
	end

	-- for other slots, need to check class/spec
	local class = select(2, UnitClass(unit));
	local spec = UnitIsUnit(unit,"player") and GetSpecializationInfo(GetSpecialization()) or GetInspectSpecialization(unit);

	if(class == "MAGE" or class == "WARLOCK" or class == "PRIEST" or class == "EVOKER" or spec == 102 or spec == 105 or spec == 270 or spec == 65 or spec == 262 or spec == 264)then
		-- int classes can get spellthread on legs
		return slot == 7;
	end

	return false;
end

local enchantPattern = ENCHANTED_TOOLTIP_LINE:gsub('%%s', '(.*)');
local enchantAtlasPattern = "(.*) |A:(.*):20:20|a";
local function GetItemEnchantAsText(itemLink)
	local data = C_TooltipInfo.GetHyperlink(itemLink);
	for _,line in ipairs(data.lines) do
		local text = line.args[2].stringVal;
		local enchantText = string.match(text,enchantPattern);
		if (enchantText)then
			-- DF adds an additional smol icon we store in atlas
			local atlas = nil
			if string.find(enchantText, "|A:") then
				enchantText, atlas = string.match(enchantText, enchantAtlasPattern)
			end

			return atlas, ProcessEnchantText(enchantText)
		end
	end

	return nil, nil;
end

local function GetSocketTextures(itemLink)
	local data = C_TooltipInfo.GetHyperlink(itemLink);
	local textures = {};
	for _,line in ipairs(data.lines) do
		TooltipUtil.SurfaceArgs(line);
		if line.gemIcon then
			table.insert(textures, line.gemIcon);
		elseif line.socketType then
			table.insert(textures, string.format("Interface\\ItemSocketingFrame\\UI-EmptySocket-%s", line.socketType));
		end
	end

	return textures;
end

local function AnchorTextureLeftOfParent(parent,textures)
	textures[1]:SetPoint("RIGHT",parent,"LEFT",-3,1);
	for i=2,4 do
		textures[i]:SetPoint("RIGHT",textures[i - 1],"LEFT",-2,0);
	end
end

local function AnchorTextureRightOfParent(parent,textures)
	textures[1]:SetPoint("LEFT",parent,"RIGHT",3,1);
	for i=2,4 do
		textures[i]:SetPoint("LEFT",textures[i - 1],"RIGHT",2,0);
	end
end

local function CreateAdditionalDisplayForButton(button)
	if not InCombatLockdown() then
		local parent = button:GetParent();
		local additionalFrame = CreateFrame("frame",nil,parent);
		additionalFrame:SetWidth(100);

		additionalFrame.ilvlDisplay = additionalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline");

		additionalFrame.enchantDisplay = additionalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline");
		additionalFrame.enchantDisplay:SetTextColor(0,1,0,1);

		additionalFrame.durabilityDisplay = CreateFrame("StatusBar", nil, additionalFrame);
		additionalFrame.durabilityDisplay:SetMinMaxValues(0,1);
		additionalFrame.durabilityDisplay:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar");
		additionalFrame.durabilityDisplay:GetStatusBarTexture():SetHorizTile(false);
		additionalFrame.durabilityDisplay:GetStatusBarTexture():SetVertTile(false);
		additionalFrame.durabilityDisplay:SetHeight(40);
		additionalFrame.durabilityDisplay:SetWidth(2.3);
		additionalFrame.durabilityDisplay:SetOrientation("VERTICAL");

		additionalFrame.socketDisplay = {};

		for i=1,4 do
			additionalFrame.socketDisplay[i] = additionalFrame:CreateTexture();
			additionalFrame.socketDisplay[i]:SetWidth(14);
			additionalFrame.socketDisplay[i]:SetHeight(14);
		end

		return additionalFrame;
	end
end


local function positonLeft(button)
	local additionalFrame = button.BCPDisplay;

	additionalFrame:SetPoint("TOPLEFT",button,"TOPRIGHT");
	additionalFrame:SetPoint("BOTTOMLEFT",button,"BOTTOMRIGHT");

	additionalFrame.ilvlDisplay:SetPoint("BOTTOMLEFT",additionalFrame,"BOTTOMLEFT",10,2);
	additionalFrame.enchantDisplay:SetPoint("TOPLEFT",additionalFrame,"TOPLEFT",10,-7);

	additionalFrame.durabilityDisplay:SetPoint("TOPLEFT",button,"TOPLEFT",-6,0);
	additionalFrame.durabilityDisplay:SetPoint("BOTTOMLEFT",button,"BOTTOMLEFT",-6,0);

	AnchorTextureRightOfParent(additionalFrame.ilvlDisplay,additionalFrame.socketDisplay);
end

local function positonRight(button)
	local additionalFrame = button.BCPDisplay;

	additionalFrame:SetPoint("TOPRIGHT",button,"TOPLEFT");
	additionalFrame:SetPoint("BOTTOMRIGHT",button,"BOTTOMLEFT");

	additionalFrame.ilvlDisplay:SetPoint("BOTTOMRIGHT",additionalFrame,"BOTTOMRIGHT",-10,2);
	additionalFrame.enchantDisplay:SetPoint("TOPRIGHT",additionalFrame,"TOPRIGHT",-10,-7);

	additionalFrame.durabilityDisplay:SetWidth(1.2);
	additionalFrame.durabilityDisplay:SetPoint("TOPRIGHT",button,"TOPRIGHT",4,0);
	additionalFrame.durabilityDisplay:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",4,0);

	AnchorTextureLeftOfParent(additionalFrame.ilvlDisplay,additionalFrame.socketDisplay);
end

local function positonCenter(button)
	local additionalFrame = button.BCPDisplay;

	additionalFrame:SetPoint("BOTTOMLEFT",button,"BOTTOMLEFT",-100,0);
	additionalFrame:SetPoint("TOPRIGHT",button,"TOPRIGHT",0,-100);

	additionalFrame.durabilityDisplay:SetHeight(2);
	additionalFrame.durabilityDisplay:SetWidth(40);
	additionalFrame.durabilityDisplay:SetOrientation("HORIZONTAL");
	additionalFrame.durabilityDisplay:SetPoint("BOTTOMLEFT",button,"BOTTOMLEFT",0,-2);
	additionalFrame.durabilityDisplay:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",0,-2);

	additionalFrame.ilvlDisplay:SetPoint("BOTTOM",button,"TOP",0,7);

--left center
	if(button:GetID() == 16)then
		additionalFrame.enchantDisplay:SetPoint("BOTTOMRIGHT",button,"BOTTOMLEFT",-5,0);

		AnchorTextureLeftOfParent(additionalFrame.ilvlDisplay,additionalFrame.socketDisplay);
	else
		additionalFrame.enchantDisplay:SetPoint("BOTTOMLEFT",button,"BOTTOMRIGHT",5,0);

		AnchorTextureRightOfParent(additionalFrame.ilvlDisplay,additionalFrame.socketDisplay);
	end
end

local function AnchorAdditionalDisplay(button)
	local layout = buttonLayout[button:GetID()];
	if(layout == "left")then
		positonLeft(button);
	elseif(layout == "right")then
		positonRight(button);
	elseif(layout == "center")then
		positonCenter(button);
	end
end

local function UpdateAdditionalDisplay(button,unit)
	local additionalFrame = button.BCPDisplay;
	local slot = button:GetID();
	local itemLink = GetInventoryItemLink(unit,slot);

	if(not additionalFrame.prevItemLink or itemLink ~= additionalFrame.prevItemLink)then
		local itemiLvlText = "";
		if(itemLink)then
			local ilvl = GetDetailedItemLevelInfo(itemLink);
			local quality = GetInventoryItemQuality(unit, slot);
			local hex = select(4,GetItemQualityColor(quality));
			itemiLvlText = "|c"..hex..ilvl.."|r";
		end
		additionalFrame.ilvlDisplay:SetText(itemiLvlText);

		local atlas, enchantText
		if itemLink then
			atlas, enchantText = GetItemEnchantAsText(itemLink)
		end
		local canEnchant = CanEnchantSlot(unit, slot);

		if(not enchantText)then
			local shouldDisplayEchantMissingText = canEnchant and IsLevelAtEffectiveMaxLevel(UnitLevel(unit));
			additionalFrame.enchantDisplay:SetText(shouldDisplayEchantMissingText and "|cffff0000No Enchant|r" or "");
		else
			enchantText = string.sub(enchantText,0,18)
			local enchantQuality = ""
			if atlas then
				enchantQuality = "|A:" .. atlas .. ":12:12|a"
				-- color enchant text as green/blue/epic based on quality
				if atlas == "Professions-Icon-Quality-Tier3-Small" then
					enchantText = "|cffa335ee" .. enchantText .. "|r"
				elseif atlas == "Professions-Icon-Quality-Tier2-Small" then
					enchantText = "|cff0070dd" .. enchantText .. "|r"
				else
					enchantText = "|cff1eff00" .. enchantText .. "|r"
				end
			end

			-- for symmetry, put quality on the left of offhand
			if slot == 17 then
				additionalFrame.enchantDisplay:SetText(enchantQuality .. enchantText)
			else
				additionalFrame.enchantDisplay:SetText(enchantText .. enchantQuality);
			end
		end

		local textures = itemLink and GetSocketTextures(itemLink) or {};
		for i=1,4 do
			if(#textures >= i)then
				additionalFrame.socketDisplay[i]:SetTexture(textures[i]);
				additionalFrame.socketDisplay[i]:Show();
			else
				additionalFrame.socketDisplay[i]:Hide();
			end
		end

		additionalFrame.prevItemLink = itemLink;
	end

	local currentDurablity, maxDurability = GetInventoryItemDurability(slot);
	local percDurability = currentDurablity and currentDurablity/maxDurability;

	if(not additionalFrame.prevDurability or additionalFrame.prevDurability ~= percDurability)then
		if(UnitIsUnit("player",unit) and percDurability and percDurability < 1)then
			additionalFrame.durabilityDisplay:Show();
			additionalFrame.durabilityDisplay:SetValue(percDurability);
			additionalFrame.durabilityDisplay:SetStatusBarColor(ColorGradientHP(percDurability));
		else
			additionalFrame.durabilityDisplay:Hide();
		end
		additionalFrame.prevDurability = percDurability;
	end
end

local function CreateInspectIlvlDisplay()
	local parent = InspectPaperDollItemsFrame;
	if(not parent.ilvlDisplay)then
		parent.ilvlDisplay = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline22");
		parent.ilvlDisplay:SetPoint("TOPRIGHT",parent,"TOPRIGHT",0,-20);
		parent.ilvlDisplay:SetPoint("BOTTOMLEFT",parent,"TOPRIGHT",-80,-67);
	end
end

local function UpdateInspectIlvlDisplay(unit)
	local ilvl = C_PaperDollInfo.GetInspectItemLevel(unit);
	local color;
	if(ilvl <= 380)then
		color = "1eff00";
	elseif(ilvl <= 395)then
		color = "0070dd";
	elseif(ilvl <= 408)then
		color = "a335ee";
	elseif(ilvl <= 420)then
		color = "ff8000";
	else
		color = "e6cc80";
	end

	local parent = InspectPaperDollItemsFrame;
	parent.ilvlDisplay:SetText(string.format("|cff%s%d|r",color,ilvl));
end

hooksecurefunc("PaperDollItemSlotButton_Update",function(button)
	if(not buttonLayout[button:GetID()])then return; end

	if(not button.BCPDisplay)then
		button.BCPDisplay = CreateAdditionalDisplayForButton(button);
		AnchorAdditionalDisplay(button);
	end

	UpdateAdditionalDisplay(button,"player");
end);

function addon:ADDON_LOADED(addonName)
	if(addonName == "Blizzard_InspectUI")then
		InspectPaperDollItemsFrame.InspectTalents:ClearAllPoints();
		InspectPaperDollItemsFrame.InspectTalents:Hide();

		local newTalentInspectButton = CreateFrame("Button",nil,InspectFrame,"PanelTabButtonTemplate");
		Mixin(newTalentInspectButton,InspectPaperDollFrameTalentsButtonMixin);
		for _,i in ipairs({1,2,3,7,8,9}) do
			newTalentInspectButton.TabTextures[i]:Hide();
		end

		newTalentInspectButton:SetScript("OnEnter",function(self)
			for _,v in ipairs({"MiddleHighlight","LeftHighlight","RightHighlight"}) do
				self[v]:Show();
			end

			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(self.Text:GetText(), 1.0, 1.0, 1.0);
			newTalentInspectButton:OnEnter();
		end);

		newTalentInspectButton:SetScript("OnLeave",function(self)
			for _,v in ipairs({"MiddleHighlight","LeftHighlight","RightHighlight"}) do
				self[v]:Hide();
			end

			GameTooltip_Hide();
			newTalentInspectButton:OnLeave();
		end);

		newTalentInspectButton:SetScript("OnClick",newTalentInspectButton.OnClick);

		newTalentInspectButton:ClearAllPoints();
		newTalentInspectButton:SetText(INSPECT_TALENTS_BUTTON);
		newTalentInspectButton:SetPoint("LEFT",InspectFrameTab3,"RIGHT",3,0);

		InspectPaperDollItemsFrame.InspectTalents = newTalentInspectButton;

		hooksecurefunc("InspectPaperDollItemSlotButton_Update",function(button)
			if(not button.BCPDisplay)then
				button.BCPDisplay = CreateAdditionalDisplayForButton(button);
				AnchorAdditionalDisplay(button);
			end
			UpdateAdditionalDisplay(button,InspectFrame.unit);
		end);

		hooksecurefunc("InspectPaperDollFrame_SetLevel",function()
			if(not InspectFrame.unit)then return; end
			CreateInspectIlvlDisplay();
			UpdateInspectIlvlDisplay(InspectFrame.unit);
		end);

		InspectFrame:UnregisterEvent("GROUP_ROSTER_UPDATE");
		InspectFrame:UnregisterEvent("PLAYER_TARGET_CHANGED");
	end
end

local characterSlots = {
	"CharacterHeadSlot",
	"CharacterNeckSlot",
	"CharacterShoulderSlot",
	"CharacterChestSlot",
	"CharacterWaistSlot",
	"CharacterLegsSlot",
	"CharacterFeetSlot",
	"CharacterWristSlot",
	"CharacterHandsSlot",
	"CharacterFinger0Slot",
	"CharacterFinger1Slot",
	"CharacterTrinket0Slot",
	"CharacterTrinket1Slot",
	"CharacterBackSlot",
	"CharacterMainHandSlot",
	"CharacterSecondaryHandSlot",
};

local function updateAllCharacterSlots()
	for _,slot in ipairs(characterSlots) do
		local button = _G[slot];
		if(button)then
			UpdateAdditionalDisplay(button,"player");
		end
	end
end

local lastUpdate = 0;
function addon:SOCKET_INFO_UPDATE()
	if(CharacterFrame:IsShown())then
		local time = GetTime();
		if(time ~= lastUpdate)then
			updateAllCharacterSlots();
			lastUpdate = time;
		end
	end
end

-- fired when enchants are applied
function addon:UNIT_INVENTORY_CHANGED(unit)
	if(unit == "player")then
		addon:SOCKET_INFO_UPDATE()
	end
end

local eventListener = CreateFrame("frame");
eventListener:SetScript("OnEvent",function (self,event,...)
	addon[event](addon,...);
end);
eventListener:RegisterEvent("ADDON_LOADED");
eventListener:RegisterEvent("SOCKET_INFO_UPDATE");
eventListener:RegisterEvent("UNIT_INVENTORY_CHANGED");