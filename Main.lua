-----------------------------------------------------------------------
-- Upvalued Lua API.
-----------------------------------------------------------------------
local _G = getfenv(0)

local pairs = _G.pairs
local tonumber = _G.tonumber

local bit = _G.bit
local math = _G.math
local table = _G.table


-----------------------------------------------------------------------
-- AddOn namespace.
-----------------------------------------------------------------------
local ADDON_NAME, private = ...

local LibStub = _G.LibStub
local WDP = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceTimer-3.0")

local DatamineTT = _G.CreateFrame("GameTooltip", "WDPDatamineTT", _G.UIParent, "GameTooltipTemplate")
DatamineTT:SetOwner(_G.WorldFrame, "ANCHOR_NONE")


-----------------------------------------------------------------------
-- Local constants.
-----------------------------------------------------------------------
local DATABASE_DEFAULTS = {
    global = {
        items = {},
        npcs = {},
        objects = {},
        quests = {},
    }
}


local EVENT_MAPPING = {
    LOOT_OPENED = true,
    MERCHANT_SHOW = "UpdateMerchantItems",
    MERCHANT_UPDATE = "UpdateMerchantItems",
    PLAYER_TARGET_CHANGED = true,
    QUEST_COMPLETE = true,
    QUEST_DETAIL = true,
    QUEST_LOG_UPDATE = true,
    QUEST_PROGRESS = true,
    UNIT_QUEST_LOG_CHANGED = true,
    UNIT_SPELLCAST_FAILED = "HandleSpellFailure",
    UNIT_SPELLCAST_FAILED_QUIET = "HandleSpellFailure",
    UNIT_SPELLCAST_INTERRUPTED = "HandleSpellFailure",
    UNIT_SPELLCAST_SENT = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
}


local AF = private.ACTION_TYPE_FLAGS


-----------------------------------------------------------------------
-- Local variables.
-----------------------------------------------------------------------
local db
local durability_timer_handle
local target_location_timer_handle
local action_data = {}


-----------------------------------------------------------------------
-- Helper Functions.
-----------------------------------------------------------------------
local function UnitEntry(unit_type, unit_id)
    if not unit_type or not unit_id then
        return
    end
    local unit = db[unit_type][unit_id]

    if not unit then
        db[unit_type][unit_id] = {}
        unit = db[unit_type][unit_id]
    end
    return unit
end


local function CurrentLocationData()
    local map_level = _G.GetCurrentMapDungeonLevel() or 0
    local x, y = _G.GetPlayerMapPosition("player")

    x = x or 0
    y = y or 0

    if x == 0 and y == 0 then
        for level_index = 1, _G.GetNumDungeonMapLevels() do
            _G.SetDungeonMapLevel(level_index)
            x, y = _G.GetPlayerMapPosition("player")

            if x and y and (x > 0 or y > 0) then
                _G.SetDungeonMapLevel(map_level)
                map_level = level_index
                break
            end
        end
    end

    if _G.DungeonUsesTerrainMap() then
        map_level = map_level - 1
    end
    local _, instance_type = _G.IsInInstance()
    return _G.GetRealZoneText(), ("%.2f"):format(x * 100), ("%.2f"):format(y * 100), map_level or 0, instance_type:upper()
end


local function ItemLinkToID(item_link)
    if not item_link then
        return
    end
    return tonumber(item_link:match("item:(%d+)"))
end


do
    local UNIT_TYPE_BITMASK = 0x007

    function WDP:ParseGUID(guid)
        if not guid then
            return
        end
        local types = private.UNIT_TYPES
        local unit_type = _G.bit.band(tonumber(guid:sub(1, 5)), UNIT_TYPE_BITMASK)

        if unit_type ~= types.PLAYER and unit_type ~= types.PET then
            return unit_type, tonumber(guid:sub(-12, -9), 16)
        end

        return unit_type
    end
end -- do-block


local function UpdateObjectLocation(identifier)
    if not identifier then
        return
    end
    local zone_name, x, y, map_level, instance_type = CurrentLocationData()
    local object = UnitEntry("objects", identifier)
    object.locations = object.locations or {}

    if not object.locations[zone_name] then
        object.locations[zone_name] = {}
    end
    object.locations[zone_name][("%s:%s:%s:%s"):format(instance_type, map_level, x, y)] = true
end


-----------------------------------------------------------------------
-- Methods.
-----------------------------------------------------------------------
function WDP:OnInitialize()
    db = LibStub("AceDB-3.0"):New("WoWDBProfilerData", DATABASE_DEFAULTS, "Default").global
end


function WDP:OnEnable()
    for event_name, mapping in pairs(EVENT_MAPPING) do
        self:RegisterEvent(event_name, (_G.type(mapping) ~= "boolean") and mapping or nil)
    end
    durability_timer_handle = self:ScheduleRepeatingTimer("ProcessDurability", 30)
    target_location_timer_handle = self:ScheduleRepeatingTimer("UpdateTargetLocation", 0.2)
end


local function RecordDurability(item_id, durability)
    if not durability or durability <= 0 then
        return
    end

    if not db.items[item_id] then
        db.items[item_id] = {}
    end
    db.items[item_id].durability = durability
end


function WDP:ProcessDurability()
    for slot_index = 0, _G.INVSLOT_LAST_EQUIPPED do
        local item_id = _G.GetInventoryItemID("player", slot_index)

        if item_id and item_id > 0 then
            local _, max_durability = _G.GetInventoryItemDurability(slot_index)
            RecordDurability(item_id, max_durability)
        end
    end

    for bag_index = 0, _G.NUM_BAG_SLOTS do
        for slot_index = 1, _G.GetContainerNumSlots(bag_index) do
            local item_id = _G.GetContainerItemID(bag_index, slot_index)

            if item_id and item_id > 0 then
                local _, max_durability = _G.GetContainerItemDurability(bag_index, slot_index)
                RecordDurability(item_id, max_durability)
            end
        end
    end
end


function WDP:UpdateTargetLocation()
    if not _G.UnitExists("target") or _G.UnitPlayerControlled("target") or _G.UnitIsTapped("target") then
        return
    end

    for index = 1, 4 do
        if not _G.CheckInteractDistance("target", index) then
            return
        end
    end

    local unit_type, unit_idnum = self:ParseGUID(_G.UnitGUID("target"))

    if unit_type ~= private.UNIT_TYPES.NPC or not unit_idnum then
        return
    end
    local zone_name, x, y, map_level, instance_type = CurrentLocationData()
    local npc_data = UnitEntry("npcs", unit_idnum).stats[("level_%d"):format(_G.UnitLevel("target"))]
    npc_data.locations = npc_data.locations or {}

    if not npc_data.locations[zone_name] then
        npc_data.locations[zone_name] = {}
    end
    npc_data.locations[zone_name][("%s:%s:%s:%s"):format(instance_type, map_level, x, y)] = true
end


-----------------------------------------------------------------------
-- Event handlers.
-----------------------------------------------------------------------
local re_gold = _G.GOLD_AMOUNT:gsub("%%d", "(%%d+)")
local re_silver = _G.SILVER_AMOUNT:gsub("%%d", "(%%d+)")
local re_copper = _G.COPPER_AMOUNT:gsub("%%d", "(%%d+)")


local function _moneyMatch(money, re)
    return money:match(re) or 0
end


local function _toCopper(money)
    if not money then
        return 0
    end

    return _moneyMatch(money, re_gold) * 10000 + _moneyMatch(money, re_silver) * 100 + _moneyMatch(money, re_copper)
end


local LOOT_VERIFY_FUNCS = {
    [AF.NPC] = function()
        local fishing_loot = _G.IsFishingLoot()

        if not fishing_loot and _G.UnitExists("target") and not _G.UnitIsFriend("player", "target") and _G.UnitIsDead("target") then
            if _G.UnitIsPlayer("target") or _G.UnitPlayerControlled("target") then
                return false
            end
            local unit_type, id_num = WDP:ParseGUID(_G.UnitGUID("target"))
            action_data.id_num = id_num
        end
        return true
    end,
    [AF.OBJECT] = function()
        return true
    end,
}


local LOOT_UPDATE_FUNCS = {
    [AF.NPC] = function()
        local npc = UnitEntry("npcs", action_data.id_num)
        npc.drops = npc.drops or {}

        for index = 1, #action_data.drops do
            table.insert(npc.drops, action_data.drops[index])
        end
    end,
    [AF.OBJECT] = function()
        local object = UnitEntry("objects", action_data.identifier)
        object.drops = object.drops or {}

        for index = 1, #action_data.drops do
            table.insert(object.drops, action_data.drops[index])
        end
    end,
}


function WDP:LOOT_OPENED()
    if not action_data.type then
        action_data.type = AF.NPC
    end
    local verify_func = LOOT_VERIFY_FUNCS[action_data.type]
    local update_func = LOOT_UPDATE_FUNCS[action_data.type]

    if not verify_func or not update_func or not verify_func() then
        return
    end

    local loot_registry = {}
    action_data.drops = {}

    for loot_slot = 1, _G.GetNumLootItems() do
        local icon_texture, item_text, quantity, quality, locked = _G.GetLootSlotInfo(loot_slot)

        if _G.LootSlotIsItem(loot_slot) then
            local item_id = ItemLinkToID(_G.GetLootSlotLink(loot_slot))
            loot_registry[item_id] = (loot_registry[item_id]) or 0 + quantity
        elseif _G.LootSlotIsCoin(loot_slot) then
            table.insert(action_data.drops, ("money:%d"):format(_toCopper(item_text)))
        elseif _G.LootSlotIsCurrency(loot_slot) then
            table.insert(action_data.drops, ("currency:%d:%s"):format(quantity, icon_texture:match("[^\\]+$"):lower()))
        end
    end

    for item_id, quantity in pairs(loot_registry) do
        table.insert(action_data.drops, ("%d:%d"):format(item_id, quantity))
    end
    update_func()
end


local POINT_MATCH_PATTERNS = {
    ("^%s$"):format(_G.ITEM_REQ_ARENA_RATING:gsub("%%d", "(%%d+)")), -- May no longer be necessary
    ("^%s$"):format(_G.ITEM_REQ_ARENA_RATING_3V3:gsub("%%d", "(%%d+)")), -- May no longer be necessary
    ("^%s$"):format(_G.ITEM_REQ_ARENA_RATING_5V5:gsub("%%d", "(%%d+)")), -- May no longer be necessary
    ("^%s$"):format(_G.ITEM_REQ_ARENA_RATING_BG:gsub("%%d", "(%%d+)")),
    ("^%s$"):format(_G.ITEM_REQ_ARENA_RATING_3V3_BG:gsub("%%d", "(%%d+)")),
}


function WDP:UpdateMerchantItems()
    local unit_type, unit_idnum = self:ParseGUID(_G.UnitGUID("target"))

    if unit_type ~= private.UNIT_TYPES.NPC or not unit_idnum then
        return
    end
    local merchant = UnitEntry("npcs", unit_idnum)
    merchant.sells = merchant.sells or {}

    for item_index = 1, _G.GetMerchantNumItems() do
        local _, _, copper_price, stack_size, num_available, _, extended_cost = _G.GetMerchantItemInfo(item_index)
        local item_id = ItemLinkToID(_G.GetMerchantItemLink(item_index))

        if item_id and item_id > 0 then
            local price_string = copper_price

            if extended_cost then
                local bg_points = 0
                local personal_points = 0

                DatamineTT:ClearLines()
                DatamineTT:SetMerchantItem(item_index)

                for line_index = 1, DatamineTT:NumLines() do
                    local current_line = _G["WDPDatamineTTTextLeft" .. line_index]

                    if not current_line then
                        break
                    end
                    local breakout

                    for match_index = 1, #POINT_MATCH_PATTERNS do
                        local match1, match2 = current_line:GetText():match(POINT_MATCH_PATTERNS[match_index])
                        personal_points = personal_points + (match1 or 0)
                        bg_points = bg_points + (match2 or 0)

                        if match1 or match2 then
                            breakout = true
                            break
                        end
                    end

                    if breakout then
                        break
                    end
                end
                local currency_list = {}

                price_string = ("%s:%s:%s"):format(price_string, bg_points, personal_points)

                for cost_index = 1, _G.GetMerchantItemCostInfo(item_index) do
                    local icon_texture, amount_required, currency_link = _G.GetMerchantItemCostItem(item_index, cost_index)
                    local currency_id = currency_link and ItemLinkToID(currency_link) or nil

                    if not currency_id or currency_id < 1 then
                        if not icon_texture then
                            return
                        end
                        currency_id = icon_texture:match("[^\\]+$"):lower()
                    end
                    currency_list[#currency_list + 1] = ("(%s:%s)"):format(amount_required, currency_id)
                end

                for currency_index = 1, #currency_list do
                    price_string = ("%s:%s"):format(price_string, currency_list[currency_index])
                end
            end
            merchant.sells[("%s:%s:[%s]"):format(item_id, stack_size, price_string)] = num_available
        end
    end
end


local GENDER_NAMES = {
    "UNKNOWN",
    "MALE",
    "FEMALE",
}


local REACTION_NAMES = {
    "HATED",
    "HOSTILE",
    "UNFRIENDLY",
    "NEUTRAL",
    "FRIENDLY",
    "HONORED",
    "REVERED",
    "EXALTED",
}


local POWER_TYPE_NAMES = {
    ["0"] = "MANA",
    ["1"] = "RAGE",
    ["2"] = "FOCUS",
    ["3"] = "ENERGY",
    ["6"] = "RUNIC_POWER",
}


function WDP:PLAYER_TARGET_CHANGED()
    if not _G.UnitExists("target") or _G.UnitPlayerControlled("target") then
        return
    end
    local unit_type, unit_idnum = self:ParseGUID(_G.UnitGUID("target"))

    if unit_type ~= private.UNIT_TYPES.NPC or not unit_idnum then
        return
    end
    local npc = UnitEntry("npcs", unit_idnum)
    local _, class_token = _G.UnitClass("target")
    npc.class = class_token
    -- TODO: Add faction here
    npc.gender = GENDER_NAMES[_G.UnitSex("target")] or "UNDEFINED"
    npc.is_pvp = _G.UnitIsPVP("target") and true or nil
    npc.reaction = ("%s:%s:%s"):format(_G.UnitLevel("player"), _G.UnitFactionGroup("player"), REACTION_NAMES[_G.UnitReaction("player", "target")])
    npc.stats = npc.stats or {}

    local npc_level = ("level_%d"):format(_G.UnitLevel("target"))

    if not npc.stats[npc_level] then
        npc.stats[npc_level] = {
            max_health = _G.UnitHealthMax("target"),
        }

        local max_power = _G.UnitManaMax("target")

        if max_power > 0 then
            local power_type = _G.UnitPowerType("target")
            npc.stats[npc_level].power = ("%s:%d"):format(POWER_TYPE_NAMES[_G.tostring(power_type)] or power_type, max_power)
        end
    end
    action_data.type = AF.NPC -- This will be set as appropriate below
end


function WDP:QUEST_COMPLETE()
end


function WDP:QUEST_DETAIL()
    local unit_name = _G.UnitName("questnpc")

    if not unit_name then
        return
    end
    local unit_type, unit_id = self:ParseGUID(_G.UnitGUID("questnpc"))

    if unit_type == private.UNIT_TYPES.OBJECT then
        UpdateObjectLocation(unit_id)
    end
    local quest = UnitEntry("quests", _G.GetQuestID())
    quest.begin = quest.begin or {}
    quest.begin[("%s:%d"):format(private.UNIT_TYPE_NAMES[unit_type + 1], unit_id)] = true
end


function WDP:QUEST_LOG_UPDATE()
    self:UnregisterEvent("QUEST_LOG_UPDATE")
end


function WDP:QUEST_PROGRESS()
end

function WDP:UNIT_QUEST_LOG_CHANGED(event, unit_id)
    if unit_id ~= "player" then
        return
    end
    self:RegisterEvent("QUEST_LOG_UPDATE")
end


function WDP:UNIT_SPELLCAST_SENT(event_name, unit_id, spell_name, spell_rank, target_name, spell_line)
    if private.tracked_line or unit_id ~= "player" then
        return
    end
    local spell_label = private.SPELL_LABELS_BY_NAME[spell_name]

    if not spell_label then
        return
    end
    action_data.type = nil -- This will be set as appropriate below

    local tt_item_name, tt_item_link = _G.GameTooltip:GetItem()
    local tt_unit_name, tt_unit_id = _G.GameTooltip:GetUnit()

    if not tt_unit_name and _G.UnitName("target") == target_name then
        tt_unit_name = target_name
        tt_unit_id = "target"
    end
    local spell_flags = private.SPELL_FLAGS_BY_LABEL[spell_label]

    if not tt_item_name and not tt_unit_name then
        if target_name == "" then
            return
        end

        local zone_name, x, y, map_level, instance_type = CurrentLocationData()

        if bit.band(spell_flags, AF.OBJECT) == AF.OBJECT then
            local identifier = ("%s:%s"):format(spell_label, target_name)
            UpdateObjectLocation(identifier)

            action_data.instance_type = instance_type
            action_data.map_level = map_level
            action_data.name = target_name
            action_data.type = AF.OBJECT
            action_data.x = x
            action_data.y = y
            action_data.zone = zone_name
            action_data.identifier = identifier
            print(("Found spell flagged for OBJECT: %s (%s, %s)"):format(zone_name, x, y))
        elseif bit.band(spell_flags, AF.ZONE) == AF.ZONE then
            print("Found spell flagged for ZONE")
        end
    elseif tt_unit_name and not tt_item_name then
        if bit.band(spell_flags, AF.NPC) == AF.NPC then
            print("Found spell flagged for NPC")
        end
    elseif bit.band(spell_flags, AF.ITEM) == AF.ITEM then
        print("Found spell flagged for ITEM")
    else
        print(("%s: We have an issue with types and flags."), event_name)
    end

    print(("%s: '%s', '%s', '%s', '%s', '%s'"):format(event_name, unit_id, spell_name, spell_rank, target_name, spell_line))
    private.tracked_line = spell_line
end


function WDP:UNIT_SPELLCAST_SUCCEEDED(event_name, unit_id, spell_name, spell_rank, spell_line, spell_id)
    if unit_id ~= "player" then
        return
    end

    if action_data.type == AF.OBJECT then
    end

    if private.SPELL_LABELS_BY_NAME[spell_name] then
        print(("%s: '%s', '%s', '%s', '%s', '%s'"):format(event_name, unit_id, spell_name, spell_rank, spell_line, spell_id))
    end
    private.tracked_line = nil
end

function WDP:HandleSpellFailure(event_name, unit_id, spell_name, spell_rank, spell_line, spell_id)
    if unit_id ~= "player" then
        return
    end

    if private.tracked_line == spell_line then
        private.tracked_line = nil
    end
end
