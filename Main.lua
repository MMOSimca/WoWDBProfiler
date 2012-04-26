-----------------------------------------------------------------------
-- Upvalued Lua API.
-----------------------------------------------------------------------
local _G = getfenv(0)

local pairs = _G.pairs

-----------------------------------------------------------------------
-- AddOn namespace.
-----------------------------------------------------------------------
local ADDON_NAME, private = ...

local LibStub = _G.LibStub
local WDP = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceTimer-3.0")

-----------------------------------------------------------------------
-- Function declarations.
-----------------------------------------------------------------------
local HandleSpellFailure
local HandleZoneChange

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


local EVENT_MAPPING = {--    ARTIFACT_COMPLETE = true,
    --    ARTIFACT_HISTORY_READY = true,
    --    AUCTION_HOUSE_SHOW = true,
    --    BANKFRAME_OPENED = true,
    --    BATTLEFIELDS_SHOW = true,
    --    CHAT_MSG_ADDON = true,
    --    CHAT_MSG_MONSTER_EMOTE = true,
    --    CHAT_MSG_MONSTER_SAY = true,
    --    CHAT_MSG_MONSTER_WHISPER = true,
    --    CHAT_MSG_MONSTER_YELL = true,
    --    CHAT_MSG_SYSTEM = true,
    --    COMBAT_LOG_EVENT_UNFILTERED = true,
    --    COMBAT_TEXT_UPDATE = true,
    --    CONFIRM_BINDER = true,
    --    CONFIRM_PET_UNLEARN = true,
    --    CONFIRM_TALENT_WIPE = true,
    --    CURRENCY_DISPLAY_UPDATE = true,
    --    GOSSIP_ENTER_CODE = true,
    --    GOSSIP_SHOW = true,
    --    ITEM_TEXT_BEGIN = true,
    --    LOCALPLAYER_PET_RENAMED = true,
    --    LOOT_CLOSED = true,
    --    LOOT_OPENED = true,
    --    MAIL_SHOW = true,
    --    MERCHANT_SHOW = true,
    --    MERCHANT_UPDATE = true,
    --    OPEN_TABARD_FRAME = true,
    --    PET_BAR_UPDATE = true,
    --    PET_STABLE_SHOW = true,
    --    PLAYER_ALIVE = true,
    --    PLAYER_ENTERING_WORLD = HandleZoneChange,
    --    PLAYER_LOGIN = true,
    --    PLAYER_LOGOUT = true,
    --    PLAYER_TARGET_CHANGED = true,
    --    QUEST_COMPLETE = true,
    --    QUEST_DETAIL = true,
    --    QUEST_LOG_UPDATE = true,
    --    QUEST_PROGRESS = true,
    --    TAXIMAP_OPENED = true,
    --    TRADE_SKILL_SHOW = true,
    --    TRADE_SKILL_UPDATE = true,
    --    TRAINER_SHOW = true,
    --    UNIT_QUEST_LOG_CHANGED = true,
    --    UNIT_SPELLCAST_FAILED = HandleSpellFailure,
    --    UNIT_SPELLCAST_FAILED_QUIET = HandleSpellFailure,
    --    UNIT_SPELLCAST_INTERRUPTED = HandleSpellFailure,
    --    UNIT_SPELLCAST_SENT = true,
    --    UNIT_SPELLCAST_SUCCEEDED = true,
    --    ZONE_CHANGED = HandleZoneChange,
    --    ZONE_CHANGED_NEW_AREA = HandleZoneChange,
}


-----------------------------------------------------------------------
-- Local variables.
-----------------------------------------------------------------------
local db
local durability_timer_handle


-----------------------------------------------------------------------
-- Methods.
-----------------------------------------------------------------------
function WDP:OnInitialize()
    db = LibStub("AceDB-3.0"):New("WoWDBProfilerData", DATABASE_DEFAULTS, "Default").global
end


function WDP:OnEnable()
    for event_name, mapping in pairs(EVENT_MAPPING) do
        self:RegisterEvent(event_name, (type(mapping) ~= "boolean") and mapping or nil)
    end
    durability_timer_handle = self:ScheduleRepeatingTimer("ProcessDurability", 30)
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
        local item_id = _G.GetInventoryItemID("player", slot_index);

        if item_id and item_id > 0 then
            local _, max_durability = _G.GetInventoryItemDurability(slot_index);
            RecordDurability(item_id, max_durability)
        end
    end

    for bag_index = 0, _G.NUM_BAG_SLOTS do
        for slot_index = 1, _G.GetContainerNumSlots(bag_index) do
            local item_id = _G.GetContainerItemID(bag_index, slot_index);

            if item_id and item_id > 0 then
                local _, max_durability = _G.GetContainerItemDurability(bag_index, slot_index);
                RecordDurability(item_id, max_durability)
            end
        end
    end
end


-----------------------------------------------------------------------
-- Event handlers.
-----------------------------------------------------------------------
function WDP:AUCTION_HOUSE_SHOW()
end


function WDP:CHAT_MSG_MONSTER_EMOTE()
end


function WDP:CHAT_MSG_MONSTER_SAY()
end


function WDP:CHAT_MSG_MONSTER_WHISPER()
end


function WDP:CHAT_MSG_MONSTER_YELL()
end


function WDP:CHAT_MSG_SYSTEM(event, message, sender_name, language)
end


function WDP:GOSSIP_SHOW()
end


function WDP:ADDON_ALIVE()
end


function WDP:PLAYER_LOGIN()
end


function WDP:PLAYER_LOGOUT()
end


function WDP:PLAYER_TARGET_CHANGED()
end


function WDP:QUEST_LOG_UPDATE()
end


function WDP:TRADE_SKILL_UPDATE()
end
