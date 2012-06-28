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

local deformat = LibStub("LibDeformat-3.0")

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
        zones = {},
    }
}


local EVENT_MAPPING = {
    CHAT_MSG_LOOT = true,
    CHAT_MSG_SYSTEM = true,
    COMBAT_LOG_EVENT_UNFILTERED = true,
    COMBAT_TEXT_UPDATE = true,
    ITEM_TEXT_BEGIN = true,
    LOOT_OPENED = true,
    MERCHANT_SHOW = "UpdateMerchantItems",
    --    MERCHANT_UPDATE = "UpdateMerchantItems",
    PET_BAR_UPDATE = true,
    PLAYER_TARGET_CHANGED = true,
    QUEST_COMPLETE = true,
    QUEST_DETAIL = true,
    QUEST_LOG_UPDATE = true,
    TRAINER_SHOW = true,
    UNIT_QUEST_LOG_CHANGED = true,
    UNIT_SPELLCAST_FAILED = "HandleSpellFailure",
    UNIT_SPELLCAST_FAILED_QUIET = "HandleSpellFailure",
    UNIT_SPELLCAST_INTERRUPTED = "HandleSpellFailure",
    UNIT_SPELLCAST_SENT = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
}


local AF = private.ACTION_TYPE_FLAGS


local PLAYER_CLASS = _G.select(2, _G.UnitClass("player"))
local PLAYER_GUID = _G.UnitGUID("player")
local PLAYER_RACE = _G.select(2, _G.UnitRace("player"))

-----------------------------------------------------------------------
-- Local variables.
-----------------------------------------------------------------------
local db
local durability_timer_handle
local target_location_timer_handle
local action_data = {}
local currently_drunk
local faction_standings = {}


-----------------------------------------------------------------------
-- Helper Functions.
-----------------------------------------------------------------------
local ActualCopperCost
do
    local BARTERING_SPELL_ID = 83964

    local STANDING_DISCOUNTS = {
        HATED = 0,
        HOSTILE = 0,
        UNFRIENDLY = 0,
        NEUTRAL = 0,
        FRIENDLY = 0.05,
        HONORED = 0.1,
        REVERED = 0.15,
        EXALTED = 0.2,
    }


    function ActualCopperCost(copper_cost, rep_standing)
        if not copper_cost or copper_cost == 0 then
            return 0
        end
        local modifier = 1

        if _G.IsSpellKnown(BARTERING_SPELL_ID) then
            modifier = modifier - 0.1
        end

        if rep_standing then
            if PLAYER_RACE == "Goblin" then
                modifier = modifier - STANDING_DISCOUNTS["EXALTED"]
            elseif STANDING_DISCOUNTS[rep_standing] then
                modifier = modifier - STANDING_DISCOUNTS[rep_standing]
            end
        end
        return math.floor(copper_cost / modifier)
    end
end -- do-block


local function InstanceDifficultyToken()
    local _, instance_type, instance_difficulty, difficulty_name, _, _, is_dynamic = _G.GetInstanceInfo()
    if difficulty_name == "" then
        difficulty_name = "NONE"
    end
    return ("%s:%s:%s"):format(instance_type:upper(), difficulty_name:upper():gsub(" ", "_"), _G.tostring(is_dynamic))
end


local function DBEntry(data_type, unit_id)
    if not data_type or not unit_id then
        return
    end
    local unit = db[data_type][unit_id]

    if not unit then
        db[data_type][unit_id] = {}
        unit = db[data_type][unit_id]
    end
    return unit
end


local function NPCEntry(identifier)
    local npc = DBEntry("npcs", identifier)

    if not npc then
        return
    end
    local instance_token = InstanceDifficultyToken()
    npc.encounter_data = npc.encounter_data or {}
    npc.encounter_data[instance_token] = npc.encounter_data[instance_token] or {}
    npc.encounter_data[instance_token].stats = npc.encounter_data[instance_token].stats or {}
    return npc
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
    local x = _G.floor(x * 1000)
    local y = _G.floor(y * 1000)

    if x % 2 ~= 0 then
        x = x + 1
    end

    if y % 2 ~= 0 then
        y = y + 1
    end
    return _G.GetRealZoneText(), _G.GetCurrentMapAreaID(), x, y, map_level, InstanceDifficultyToken()
end


local function ItemLinkToID(item_link)
    if not item_link then
        return
    end
    return tonumber(item_link:match("item:(%d+)"))
end


local ParseGUID
do
    local UNIT_TYPE_BITMASK = 0x007

    function ParseGUID(guid)
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


local UpdateNPCLocation
do
    local COORD_MAX = 5

    function UpdateNPCLocation(unit_idnum)
        local zone_name, area_id, x, y, map_level, difficulty_token = CurrentLocationData()
        local npc_data = NPCEntry(unit_idnum).encounter_data[difficulty_token].stats[("level_%d"):format(_G.UnitLevel("target"))]
        local zone_token = ("%s:%d"):format(zone_name, area_id)
        npc_data.locations = npc_data.locations or {}

        local zone_data = npc_data.locations[zone_token]

        if not zone_data then
            zone_data = {}
            npc_data.locations[zone_token] = zone_data
        end

        for location_token in pairs(zone_data) do
            local loc_level, loc_x, loc_y = (":"):split(location_token)
            loc_level = tonumber(loc_level)

            if map_level == loc_level and math.abs(x - loc_x) <= COORD_MAX and math.abs(y - loc_y) <= COORD_MAX then
                return
            end
        end
        zone_data[("%s:%s:%s"):format(map_level, x, y)] = true
    end
end -- do-block


local function UpdateDBEntryLocation(entry_type, identifier, location_label)
    if not identifier then
        return
    end
    local zone_name, area_id, x, y, map_level, difficulty_token = CurrentLocationData()
    local entry = DBEntry(entry_type, identifier)
    local location_field = location_label or "locations"
    entry[difficulty_token] = entry[difficulty_token] or {}
    entry[difficulty_token][location_field] = entry[difficulty_token][location_field] or {}

    local zone_token = ("%s:%d"):format(zone_name, area_id)
    local zone_data = entry[difficulty_token][location_field][zone_token]

    if not zone_data then
        zone_data = {}
        entry[difficulty_token][location_field][zone_token] = zone_data
    end
    local location_token = ("%s:%s:%s"):format(map_level, x, y)
    zone_data[location_token] = zone_data[location_token] or true
    return zone_data
end


local function HandleItemUse(item_link, bag_index, slot_index)
    if not item_link then
        return
    end
    local item_id = ItemLinkToID(item_link)

    if not bag_index or not slot_index then
        for new_bag_index = 0, _G.NUM_BAG_FRAMES do
            for new_slot_index = 1, _G.GetContainerNumSlots(new_bag_index) do
                if item_id == ItemLinkToID(_G.GetContainerItemLink(new_bag_index, new_slot_index)) then
                    bag_index = new_bag_index
                    slot_index = new_slot_index
                    break
                end
            end
        end
    end

    if not bag_index or not slot_index then
        return
    end
    local _, _, _, _, _, is_lootable = _G.GetContainerItemInfo(bag_index, slot_index)

    if not is_lootable then
        return
    end
    DatamineTT:ClearLines()
    DatamineTT:SetBagItem(bag_index, slot_index)

    for line_index = 1, DatamineTT:NumLines() do
        local current_line = _G["WDPDatamineTTTextLeft" .. line_index]

        if not current_line then
            break
        end

        if current_line:GetText() == _G.ITEM_OPENABLE then
            table.wipe(action_data)
            action_data.type = AF.ITEM
            action_data.identifier = item_id
            action_data.label = "contains"
            break
        end
    end
end


local UnitFactionStanding
local UpdateFactionData
do
    local MAX_FACTION_INDEX = 1000

    local STANDING_NAMES = {
        "HATED",
        "HOSTILE",
        "UNFRIENDLY",
        "NEUTRAL",
        "FRIENDLY",
        "HONORED",
        "REVERED",
        "EXALTED",
    }


    function UnitFactionStanding(unit)
        UpdateFactionData()
        DatamineTT:ClearLines()
        DatamineTT:SetUnit(unit)

        for line_index = 1, DatamineTT:NumLines() do
            local faction_name = _G["WDPDatamineTTTextLeft" .. line_index]:GetText()

            if faction_name and faction_standings[faction_name] then
                return faction_name, faction_standings[faction_name]
            end
        end
    end


    function UpdateFactionData()
        for faction_index = 1, MAX_FACTION_INDEX do
            local faction_name, _, current_standing, _, _, _, _, _, is_header = _G.GetFactionInfo(faction_index)

            if faction_name and not is_header then
                faction_standings[faction_name] = STANDING_NAMES[current_standing]
            elseif not faction_name then
                break
            end
        end
    end
end -- do-block


local function GenericLootUpdate(data_type, top_field, inline_drops)
    local entry = DBEntry(data_type, action_data.identifier)

    if not entry then
        return
    end
    local loot_type = action_data.label or "drops"
    local loot_count = ("%s_count"):format(loot_type)
    local loot_data

    if top_field then
        entry[top_field] = entry[top_field] or {}
        entry[top_field][loot_count] = (entry[top_field][loot_count] or 0) + 1
        entry[top_field][loot_type] = entry[top_field][loot_type] or {}
        loot_data = entry[top_field][loot_type]
    else
        entry[loot_count] = (entry[loot_count] or 0) + 1
        entry[loot_type] = entry[loot_type] or {}
        loot_data = entry[loot_type]
    end

    for index = 1, #action_data.loot_list do
        table.insert(loot_data, action_data.loot_list[index])
    end
end


-----------------------------------------------------------------------
-- Methods.
-----------------------------------------------------------------------
function WDP:OnInitialize()
    db = LibStub("AceDB-3.0"):New("WoWDBProfilerData", DATABASE_DEFAULTS, "Default").global

    local raw_db = _G["WoWDBProfilerData"]

    local build_num = tonumber(private.build_num)

    -- TODO: Un-comment this when MoP goes live.
    --    if raw_db.build_num and raw_db.build_num < build_num then
    --        for entry in pairs(DATABASE_DEFAULTS.global) do
    --            db[entry] = {}
    --        end
    --    end
    raw_db.build_num = build_num
end


function WDP:OnEnable()
    for event_name, mapping in pairs(EVENT_MAPPING) do
        self:RegisterEvent(event_name, (_G.type(mapping) ~= "boolean") and mapping or nil)
    end
    durability_timer_handle = self:ScheduleRepeatingTimer("ProcessDurability", 30)
    target_location_timer_handle = self:ScheduleRepeatingTimer("UpdateTargetLocation", 0.5)

    _G.hooksecurefunc("UseContainerItem", function(bag_index, slot_index, target_unit)
        if target_unit then
            return
        end
        HandleItemUse(_G.GetContainerItemLink(bag_index, slot_index), bag_index, slot_index)
    end)

    _G.hooksecurefunc("UseItemByName", function(identifier, target_unit)
        if target_unit then
            return
        end
        local _, item_link = _G.GetItemInfo(identifier)
        HandleItemUse(item_link)
    end)
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
    if currently_drunk or not _G.UnitExists("target") or _G.UnitPlayerControlled("target") or (_G.UnitIsTapped("target") and not _G.UnitIsDead("target")) then
        return
    end

    for index = 1, 4 do
        if not _G.CheckInteractDistance("target", index) then
            return
        end
    end
    local unit_type, unit_idnum = ParseGUID(_G.UnitGUID("target"))

    if not unit_idnum or unit_type ~= private.UNIT_TYPES.NPC then
        return
    end
    UpdateNPCLocation(unit_idnum)
end


-----------------------------------------------------------------------
-- Event handlers.
-----------------------------------------------------------------------
function WDP:CHAT_MSG_LOOT(event, message)
    if action_data.spell_label ~= "EXTRACT_GAS" then
        return
    end
    local item_link, quantity = deformat(message, _G.LOOT_ITEM_PUSHED_SELF_MULTIPLE)

    if not item_link then
        quantity, item_link = 1, deformat(message, _G.LOOT_ITEM_PUSHED_SELF)
    end

    if not item_link then
        return
    end
    local item_id = ItemLinkToID(item_link)

    if not item_id then
        return
    end
    action_data.loot_list = {
        ("%d:%d"):format(item_id, quantity)
    }
    GenericLootUpdate("zones")
    table.wipe(action_data)
end


do
    local SOBER_MATCH = _G.DRUNK_MESSAGE_ITEM_SELF1:gsub("%%s", ".+")

    local DRUNK_COMPARES = {
        _G.DRUNK_MESSAGE_SELF2,
        _G.DRUNK_MESSAGE_SELF3,
        _G.DRUNK_MESSAGE_SELF4,
    }

    local DRUNK_MATCHES = {
        _G.DRUNK_MESSAGE_SELF2:gsub("%%s", ".+"),
        _G.DRUNK_MESSAGE_SELF3:gsub("%%s", ".+"),
        _G.DRUNK_MESSAGE_SELF4:gsub("%%s", ".+"),
    }

    function WDP:CHAT_MSG_SYSTEM(event, message)
        if currently_drunk then
            if message == _G.DRUNK_MESSAGE_SELF1 or message:match(SOBER_MATCH) then
                currently_drunk = nil
            end
            return
        end

        for index = 1, #DRUNK_MATCHES do
            if message == DRUNK_COMPARES[index] or message:match(DRUNK_MATCHES[index]) then
                currently_drunk = true
                break
            end
        end
    end
end

-- do-block

do
    local FLAGS_NPC = bit.bor(_G.COMBATLOG_OBJECT_TYPE_GUARDIAN, _G.COMBATLOG_OBJECT_CONTROL_NPC)
    local FLAGS_NPC_CONTROL = bit.bor(_G.COMBATLOG_OBJECT_AFFILIATION_OUTSIDER, _G.COMBATLOG_OBJECT_CONTROL_NPC)


    local function RecordNPCSpell(sub_event, source_guid, source_name, source_flags, dest_guid, dest_name, dest_flags, spell_id, spell_name)
        if not spell_id then
            return
        end
        local source_type, source_id = ParseGUID(source_guid)

        if not source_id or source_type ~= private.UNIT_TYPES.NPC then
            return
        end

        if bit.band(FLAGS_NPC_CONTROL, source_flags) == FLAGS_NPC_CONTROL and bit.band(FLAGS_NPC, source_flags) ~= 0 then
            local encounter_data = NPCEntry(source_id).encounter_data[InstanceDifficultyToken()]
            encounter_data.spells = encounter_data.spells or {}
            encounter_data.spells[spell_id] = (encounter_data.spells[spell_id] or 0) + 1
        end
    end

    local COMBAT_LOG_FUNCS = {
        SPELL_AURA_APPLIED = RecordNPCSpell,
        SPELL_CAST_START = RecordNPCSpell,
        SPELL_CAST_SUCCESS = RecordNPCSpell,
    }


    function WDP:COMBAT_LOG_EVENT_UNFILTERED(event, time_stamp, sub_event, hide_caster, source_guid, source_name, source_flags, source_raid_flags, dest_guid, dest_name, dest_flags, dest_raid_flags, ...)
        local combat_log_func = COMBAT_LOG_FUNCS[sub_event]

        if not combat_log_func then
            return
        end
        combat_log_func(sub_event, source_guid, source_name, source_flags, dest_guid, dest_name, dest_flags, ...)
    end
end -- do-block


do
    local DIPLOMACY_SPELL_ID = 20599
    local MR_POP_RANK1_SPELL_ID = 78634
    local MR_POP_RANK2_SPELL_ID = 78635

    local REP_BUFFS = {
        [_G.GetSpellInfo(30754)] = "CENARION_FAVOR",
        [_G.GetSpellInfo(24705)] = "GRIM_VISAGE",
        [_G.GetSpellInfo(32098)] = "HONOR_HOLD_FAVOR",
        [_G.GetSpellInfo(39913)] = "NAZGRELS_FERVOR",
        [_G.GetSpellInfo(39953)] = "SONG_OF_BATTLE",
        [_G.GetSpellInfo(61849)] = "SPIRIT_OF_SHARING",
        [_G.GetSpellInfo(32096)] = "THRALLMARS_FAVOR",
        [_G.GetSpellInfo(39911)] = "TROLLBANES_COMMAND",
        [_G.GetSpellInfo(95987)] = "UNBURDENED",
        [_G.GetSpellInfo(100951)] = "WOW_ANNIVERSARY",
    }


    local FACTION_NAMES = {
        CENARION_CIRCLE = _G.GetFactionInfoByID(609),
        HONOR_HOLD = _G.GetFactionInfoByID(946),
        THE_SHATAR = _G.GetFactionInfoByID(935),
        THRALLMAR = _G.GetFactionInfoByID(947),
    }


    local MODIFIERS = {
        CENARION_FAVOR = {
            faction = FACTION_NAMES.CENARION_CIRCLE,
            modifier = 0.25,
        },
        GRIM_VISAGE = {
            modifier = 0.1,
        },
        HONOR_HOLD_FAVOR = {
            faction = FACTION_NAMES.HONOR_HOLD,
            modifier = 0.25,
        },
        NAZGRELS_FERVOR = {
            faction = FACTION_NAMES.THRALLMAR,
            modifier = 0.1,
        },
        SONG_OF_BATTLE = {
            faction = FACTION_NAMES.THE_SHATAR,
            modifier = 0.1,
        },
        SPIRIT_OF_SHARING = {
            modifier = 0.1,
        },
        THRALLMARS_FAVOR = {
            faction = FACTION_NAMES.THRALLMAR,
            modifier = 0.25,
        },
        TROLLBANES_COMMAND = {
            faction = FACTION_NAMES.HONOR_HOLD,
            modifier = 0.1,
        },
        UNBURDENED = {
            modifier = 0.1,
        },
        WOW_ANNIVERSARY = {
            modifier = 0.08,
        }
    }


    function WDP:COMBAT_TEXT_UPDATE(event, message_type, faction_name, amount)
        if message_type ~= "FACTION" then
            return
        end
        UpdateFactionData()

        if not faction_name or not faction_standings[faction_name] then
            return
        end
        local npc = NPCEntry(action_data.identifier)

        if not npc then
            return
        end
        local encounter_data = npc.encounter_data[InstanceDifficultyToken()].stats
        local reputation_data = encounter_data[action_data.npc_level].reputations

        if not reputation_data then
            reputation_data = {}
            encounter_data[action_data.npc_level].reputations = reputation_data
        end
        local modifier = 1

        if _G.IsSpellKnown(DIPLOMACY_SPELL_ID) then
            modifier = modifier + 0.1
        end

        if _G.IsSpellKnown(MR_POP_RANK2_SPELL_ID) then
            modifier = modifier + 0.1
        elseif _G.IsSpellKnown(MR_POP_RANK1_SPELL_ID) then
            modifier = modifier + 0.05
        end

        for buff_name, buff_label in pairs(REP_BUFFS) do
            if _G.UnitBuff("player", buff_name) then
                local modded_faction = MODIFIERS[buff_label].faction

                if not modded_faction or faction_name == modded_faction then
                    modifier = modifier + MODIFIERS[buff_label].modifier
                end
            end
        end
        reputation_data[("%s:%s"):format(faction_name, faction_standings[faction_name])] = math.floor(amount / modifier)
    end
end -- do-block


function WDP:ITEM_TEXT_BEGIN()
    local unit_type, unit_idnum = ParseGUID(_G.UnitGUID("npc"))

    if not unit_idnum or unit_type ~= private.UNIT_TYPES.OBJECT or _G.UnitName("npc") ~= _G.ItemTextGetItem() then
        return
    end
    UpdateDBEntryLocation("objects", unit_idnum)
end


do
    local RE_GOLD = _G.GOLD_AMOUNT:gsub("%%d", "(%%d+)")
    local RE_SILVER = _G.SILVER_AMOUNT:gsub("%%d", "(%%d+)")
    local RE_COPPER = _G.COPPER_AMOUNT:gsub("%%d", "(%%d+)")


    local function _moneyMatch(money, re)
        return money:match(re) or 0
    end


    local function _toCopper(money)
        if not money then
            return 0
        end
        return _moneyMatch(money, RE_GOLD) * 10000 + _moneyMatch(money, RE_SILVER) * 100 + _moneyMatch(money, RE_COPPER)
    end


    local LOOT_VERIFY_FUNCS = {
        [AF.ITEM] = function()
            local locked_item_id

            for bag_index = 0, _G.NUM_BAG_FRAMES do
                for slot_index = 1, _G.GetContainerNumSlots(bag_index) do
                    local _, _, is_locked = _G.GetContainerItemInfo(bag_index, slot_index)

                    if is_locked then
                        locked_item_id = ItemLinkToID(_G.GetContainerItemLink(bag_index, slot_index))
                    end
                end
            end

            if not locked_item_id or (action_data.identifier and action_data.identifier ~= locked_item_id) then
                return false
            end
            action_data.identifier = locked_item_id
            return true
        end,
        [AF.NPC] = function()
            if not _G.UnitExists("target") or _G.UnitIsFriend("player", "target") or _G.UnitIsPlayer("target") or _G.UnitPlayerControlled("target") then
                return false
            end
            local unit_type, id_num = ParseGUID(_G.UnitGUID("target"))
            action_data.identifier = id_num
            return true
        end,
        [AF.OBJECT] = true,
        [AF.ZONE] = function()
            return _G.IsFishingLoot()
        end,
    }


    local LOOT_UPDATE_FUNCS = {
        [AF.ITEM] = function()
            GenericLootUpdate("items")
        end,
        [AF.NPC] = function()
            local npc = NPCEntry(action_data.identifier)

            if not npc then
                return
            end
            local encounter_data = npc.encounter_data[InstanceDifficultyToken()]
            local loot_type = action_data.label or "drops"
            npc.loot_counts = npc.loot_counts or {}
            npc.loot_counts[loot_type] = (npc.loot_counts[loot_type] or 0) + 1
            encounter_data[loot_type] = encounter_data[loot_type] or {}

            for index = 1, #action_data.loot_list do
                table.insert(encounter_data[loot_type], action_data.loot_list[index])
            end
        end,
        [AF.OBJECT] = function()
            GenericLootUpdate("objects", InstanceDifficultyToken())
        end,
        [AF.ZONE] = function()
            local location_token = ("%s:%s:%s"):format(action_data.map_level, action_data.x, action_data.y)

            -- This will start life as a boolean true.
            if _G.type(action_data.zone_data[location_token]) ~= "table" then
                action_data.zone_data[location_token] = {
                    drops = {}
                }
            end
            local loot_count = ("%s_count"):format(action_data.label or "drops")
            action_data.zone_data[location_token][loot_count] = (action_data.zone_data[location_token][loot_count] or 0) + 1

            for index = 1, #action_data.loot_list do
                table.insert(action_data.zone_data[location_token].drops, action_data.loot_list[index])
            end
        end,
    }


    function WDP:LOOT_OPENED()
        if action_data.looting then
            return
        end

        if not action_data.type then
            action_data.type = AF.NPC
        end
        local verify_func = LOOT_VERIFY_FUNCS[action_data.type]
        local update_func = LOOT_UPDATE_FUNCS[action_data.type]

        if not verify_func or not update_func then
            return
        end

        if _G.type(verify_func) == "function" and not verify_func() then
            return
        end
        -- TODO: Remove this check once the MoP client goes live
        local wow_version = private.wow_version
        local loot_registry = {}
        action_data.loot_list = {}
        action_data.looting = true

        if wow_version == "5.0.1" then
            for loot_slot = 1, _G.GetNumLootItems() do
                local icon_texture, item_text, quantity, quality, locked = _G.GetLootSlotInfo(loot_slot)

                local slot_type = _G.GetLootSlotType(loot_slot)

                if slot_type == _G.LOOT_SLOT_ITEM then
                    local item_id = ItemLinkToID(_G.GetLootSlotLink(loot_slot))
                    loot_registry[item_id] = (loot_registry[item_id]) or 0 + quantity
                elseif slot_type == _G.LOOT_SLOT_MONEY then
                    table.insert(action_data.loot_list, ("money:%d"):format(_toCopper(item_text)))
                elseif slot_type == _G.LOOT_SLOT_CURRENCY then
                    table.insert(action_data.loot_list, ("currency:%d:%s"):format(quantity, icon_texture:match("[^\\]+$"):lower()))
                end
            end
        else
            for loot_slot = 1, _G.GetNumLootItems() do
                local icon_texture, item_text, quantity, quality, locked = _G.GetLootSlotInfo(loot_slot)
                if _G.LootSlotIsItem(loot_slot) then
                    local item_id = ItemLinkToID(_G.GetLootSlotLink(loot_slot))
                    loot_registry[item_id] = (loot_registry[item_id]) or 0 + quantity
                elseif _G.LootSlotIsCoin(loot_slot) then
                    table.insert(action_data.loot_list, ("money:%d"):format(_toCopper(item_text)))
                elseif _G.LootSlotIsCurrency(loot_slot) then
                    table.insert(action_data.loot_list, ("currency:%d:%s"):format(quantity, icon_texture:match("[^\\]+$"):lower()))
                end
            end
        end

        for item_id, quantity in pairs(loot_registry) do
            table.insert(action_data.loot_list, ("%d:%d"):format(item_id, quantity))
        end
        update_func()
    end
end -- do-block


do
    local POINT_MATCH_PATTERNS = {
        ("^%s$"):format(_G.ITEM_REQ_ARENA_RATING:gsub("%%d", "(%%d+)")), -- May no longer be necessary
        ("^%s$"):format(_G.ITEM_REQ_ARENA_RATING_3V3:gsub("%%d", "(%%d+)")), -- May no longer be necessary
        ("^%s$"):format(_G.ITEM_REQ_ARENA_RATING_5V5:gsub("%%d", "(%%d+)")), -- May no longer be necessary
        ("^%s$"):format(_G.ITEM_REQ_ARENA_RATING_BG:gsub("%%d", "(%%d+)")),
        ("^%s$"):format(_G.ITEM_REQ_ARENA_RATING_3V3_BG:gsub("%%d", "(%%d+)")),
    }

    function WDP:UpdateMerchantItems(event)
        local unit_type, unit_idnum = ParseGUID(_G.UnitGUID("target"))

        if unit_type ~= private.UNIT_TYPES.NPC or not unit_idnum then
            return
        end
        local _, merchant_standing = UnitFactionStanding("target")
        local merchant = NPCEntry(unit_idnum)
        merchant.sells = merchant.sells or {}

        local num_items = _G.GetMerchantNumItems()

        for item_index = 1, num_items do
            local _, _, copper_price, stack_size, num_available, _, extended_cost = _G.GetMerchantItemInfo(item_index)
            local item_id = ItemLinkToID(_G.GetMerchantItemLink(item_index))

            if item_id and item_id > 0 then
                local price_string = ActualCopperCost(copper_price, merchant_standing)

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
                    local item_count = _G.GetMerchantItemCostInfo(item_index)

                    -- Keeping this around in case Blizzard makes the two points diverge at some point.
                    --                    price_string = ("%s:%s:%s"):format(price_string, bg_points, personal_points)
                    price_string = ("%s:%s"):format(price_string, personal_points)

                    for cost_index = 1, item_count do
                        local icon_texture, amount_required, currency_link = _G.GetMerchantItemCostItem(item_index, cost_index)
                        local currency_id = currency_link and ItemLinkToID(currency_link) or nil

                        if (not currency_id or currency_id < 1) and icon_texture then
                            currency_id = icon_texture:match("[^\\]+$"):lower()
                        end

                        if currency_id then
                            currency_list[#currency_list + 1] = ("(%s:%s)"):format(amount_required, currency_id)
                        end
                    end

                    for currency_index = 1, #currency_list do
                        price_string = ("%s:%s"):format(price_string, currency_list[currency_index])
                    end
                end
                merchant.sells[("%s:%s:[%s]"):format(item_id, stack_size, price_string)] = num_available
            end
        end

        if _G.CanMerchantRepair() then
            merchant.can_repair = true
        end
    end
end -- do-block

function WDP:PET_BAR_UPDATE()
    if not action_data.label or not action_data.label == "mind_control" then
        return
    end
    local unit_type, unit_idnum = ParseGUID(_G.UnitGUID("pet"))

    if unit_type ~= private.UNIT_TYPES.NPC or not unit_idnum then
        return
    end
    NPCEntry(unit_idnum).mind_control = true
    table.wipe(action_data)
end


do
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
        if not _G.UnitExists("target") or _G.UnitPlayerControlled("target") or currently_drunk then
            return
        end
        local unit_type, unit_idnum = ParseGUID(_G.UnitGUID("target"))

        if unit_type ~= private.UNIT_TYPES.NPC or not unit_idnum then
            return
        end
        local npc = NPCEntry(unit_idnum)
        local _, class_token = _G.UnitClass("target")
        npc.class = class_token
        npc.faction = UnitFactionStanding("target")
        npc.genders = npc.genders or {}
        npc.genders[GENDER_NAMES[_G.UnitSex("target")] or "UNDEFINED"] = true
        npc.is_pvp = _G.UnitIsPVP("target") and true or nil
        npc.reaction = ("%s:%s:%s"):format(_G.UnitLevel("player"), _G.UnitFactionGroup("player"), REACTION_NAMES[_G.UnitReaction("player", "target")])

        local encounter_data = npc.encounter_data[InstanceDifficultyToken()].stats
        local npc_level = ("level_%d"):format(_G.UnitLevel("target"))

        if not encounter_data[npc_level] then
            encounter_data[npc_level] = {
                max_health = _G.UnitHealthMax("target"),
            }

            local max_power = _G.UnitManaMax("target")

            if max_power > 0 then
                local power_type = _G.UnitPowerType("target")
                encounter_data[npc_level].power = ("%s:%d"):format(POWER_TYPE_NAMES[_G.tostring(power_type)] or power_type, max_power)
            end
        end
        table.wipe(action_data)
        action_data.type = AF.NPC
        action_data.identifier = unit_idnum
        action_data.npc_level = npc_level

        self:UpdateTargetLocation()
    end
end -- do-block

do
    local function UpdateQuestJuncture(point)
        local unit_name = _G.UnitName("questnpc")

        if not unit_name then
            return
        end
        local unit_type, unit_id = ParseGUID(_G.UnitGUID("questnpc"))

        if unit_type == private.UNIT_TYPES.OBJECT then
            UpdateDBEntryLocation("objects", unit_id)
        end
        local quest = DBEntry("quests", _G.GetQuestID())
        quest[point] = quest[point] or {}
        quest[point][("%s:%d"):format(private.UNIT_TYPE_NAMES[unit_type + 1], unit_id)] = true

        return quest
    end


    function WDP:QUEST_COMPLETE()
        UpdateQuestJuncture("end")
    end


    function WDP:QUEST_DETAIL()
        local quest = UpdateQuestJuncture("begin")

        if not quest then
            return
        end
        quest.classes = quest.classes or {}
        quest.classes[PLAYER_CLASS] = true

        local _, race = _G.UnitRace("player")
        quest.races = quest.races or {}
        quest.races[race] = true
    end
end -- do-block


function WDP:QUEST_LOG_UPDATE()
    local selected_quest = _G.GetQuestLogSelection() -- Save current selection to be restored when we're done.
    local entry_index, processed_quests = 1, 0
    local _, num_quests = _G.GetNumQuestLogEntries()

    while processed_quests <= num_quests do
        local _, _, _, _, is_header, _, _, _, quest_id = _G.GetQuestLogTitle(entry_index)

        if not is_header then
            _G.SelectQuestLogEntry(entry_index);

            local quest = DBEntry("quests", quest_id)
            quest.timer = _G.GetQuestLogTimeLeft()
            quest.can_share = _G.GetQuestLogPushable() and true or nil
            processed_quests = processed_quests + 1
        end
        entry_index = entry_index + 1
    end
    _G.SelectQuestLogEntry(selected_quest)
    self:UnregisterEvent("QUEST_LOG_UPDATE")
end


function WDP:UNIT_QUEST_LOG_CHANGED(event, unit_id)
    if unit_id ~= "player" then
        return
    end
    self:RegisterEvent("QUEST_LOG_UPDATE")
end


function WDP:TRAINER_SHOW()
    if not _G.IsTradeskillTrainer() then
        return
    end
    local unit_type, unit_idnum = ParseGUID(_G.UnitGUID("target"))
    local npc = NPCEntry(unit_idnum)
    npc.teaches = npc.teaches or {}

    -- Get the initial trainer filters
    local available = _G.GetTrainerServiceTypeFilter("available")
    local unavailable = _G.GetTrainerServiceTypeFilter("unavailable")
    local used = _G.GetTrainerServiceTypeFilter("used")

    -- Clear the trainer filters
    _G.SetTrainerServiceTypeFilter("available", 1)
    _G.SetTrainerServiceTypeFilter("unavailable", 1)
    _G.SetTrainerServiceTypeFilter("used", 1)

    for index = 1, _G.GetNumTrainerServices(), 1 do
        local spell_name, rank_name, _, _, required_level = _G.GetTrainerServiceInfo(index)

        if spell_name then
            DatamineTT:ClearLines()
            DatamineTT:SetTrainerService(index)

            local _, _, spell_id = DatamineTT:GetSpell()

            if spell_id then
                local profession, min_skill = _G.GetTrainerServiceSkillReq(index)
                profession = profession or "General"

                local class_professions = npc.teaches[PLAYER_CLASS]
                if not class_professions then
                    npc.teaches[PLAYER_CLASS] = {}
                    class_professions = npc.teaches[PLAYER_CLASS]
                end

                local profession_skills = class_professions[profession]
                if not profession_skills then
                    class_professions[profession] = {}
                    profession_skills = class_professions[profession]
                end
                profession_skills[spell_id] = ("%d:%d"):format(required_level, min_skill)
            end
        end
    end

    -- Reset the filters to what they were before
    _G.SetTrainerServiceTypeFilter("available", available or 0)
    _G.SetTrainerServiceTypeFilter("unavailable", unavailable or 0)
    _G.SetTrainerServiceTypeFilter("used", used or 0)
end


function WDP:UNIT_SPELLCAST_SENT(event_name, unit_id, spell_name, spell_rank, target_name, spell_line)
    if private.tracked_line or unit_id ~= "player" then
        return
    end
    local spell_label = private.SPELL_LABELS_BY_NAME[spell_name]

    if not spell_label then
        return
    end
    table.wipe(action_data)

    local tt_item_name, tt_item_link = _G.GameTooltip:GetItem()
    local tt_unit_name, tt_unit_id = _G.GameTooltip:GetUnit()

    if not tt_unit_name and _G.UnitName("target") == target_name then
        tt_unit_name = target_name
        tt_unit_id = "target"
    end
    local spell_flags = private.SPELL_FLAGS_BY_LABEL[spell_label]
    local zone_name, area_id, x, y, map_level, instance_token = CurrentLocationData()

    action_data.instance_token = instance_token
    action_data.map_level = map_level
    action_data.x = x
    action_data.y = y
    action_data.zone = ("%s:%d"):format(zone_name, area_id)

    if tt_unit_name and not tt_item_name then
        if bit.band(spell_flags, AF.NPC) == AF.NPC then
            if not tt_unit_id or tt_unit_name ~= target_name then
                return
            end
            action_data.type = AF.NPC
            action_data.label = spell_label:lower()
            action_data.unit_name = tt_unit_name
        end
    elseif bit.band(spell_flags, AF.ITEM) == AF.ITEM then
        action_data.type = AF.ITEM
        action_data.label = spell_label:lower()

        if tt_item_name and tt_item_name == target_name then
            action_data.identifier = ItemLinkToID(tt_item_link)
        elseif target_name and target_name ~= "" then
            local _, target_item_link = _G.GetItemInfo(target_name)
            action_data.identifier = ItemLinkToID(target_item_link)
        end
    elseif not tt_item_name and not tt_unit_name then
        action_data.name = target_name

        if bit.band(spell_flags, AF.OBJECT) == AF.OBJECT then
            if target_name == "" then
                return
            end
            local identifier = ("%s:%s"):format(spell_label, target_name)
            UpdateDBEntryLocation("objects", identifier)

            action_data.type = AF.OBJECT
            action_data.identifier = identifier
        elseif bit.band(spell_flags, AF.ZONE) == AF.ZONE then
            local identifier = ("%s:%s"):format(spell_label, _G["GameTooltipTextLeft1"]:GetText() or "NONE") -- Possible fishing pool name.
            action_data.zone_data = UpdateDBEntryLocation("zones", identifier, (spell_label == "FISHING") and "fishing_locations" or nil)
            action_data.type = AF.ZONE
            action_data.identifier = identifier
            action_data.spell_label = spell_label
        end
    end
    private.tracked_line = spell_line
end


function WDP:UNIT_SPELLCAST_SUCCEEDED(event_name, unit_id, spell_name, spell_rank, spell_line, spell_id)
    if unit_id ~= "player" then
        return
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
