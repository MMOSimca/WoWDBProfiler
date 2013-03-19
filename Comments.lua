-- LUA API ------------------------------------------------------------

local _G = getfenv(0)

local table = _G.table

-- ADDON NAMESPACE ----------------------------------------------------

local ADDON_NAME, private = ...

local LibStub = _G.LibStub
local WDP = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local Dialog = LibStub("LibDialog-1.0")

local ParseGUID = private.ParseGUID
local ItemLinkToID = private.ItemLinkToID

-- CONSTANTS ----------------------------------------------------------

local EDIT_MAXCHARS = 3000
local EDIT_DESCRIPTION_FORMAT = "Enter your comment below, being as descriptive as possible. Comments are limited to %s characters, including newlines and spaces."
local LINK_COMMENT_TOOLTIP = "Click here to create a link to the comment page on WoWDB."
local LINK_EDITBOX_DESC_FORMAT = "Copy the highlighted text and paste it into your browser to visit the comments for |cffffd200%s|r."

local URL_BASE = "http://www.wowdb.com/"

local URL_TYPE_MAP = {
    ITEM = "items",
    OBJECT = "objects",
    NPC = "npcs",
    QUEST = "quests",
    SPELL = "spells",
    VEHICLE = "npcs",
}

Dialog:Register("WDP_CommentLink", {
    text = "",
    editboxes = {
        {
            text = _G.UNKNOWN,
            on_escape_pressed = function(self)
                self:ClearFocus()
            end,
        },
    },
    buttons = {
        {
            text = _G.OKAY,
        }
    },
    show_while_dead = true,
    hide_on_escape = true,
    is_exclusive = true,
    on_show = function(self, data)
        local editbox = self.editboxes[1]
        editbox:SetWidth(self:GetWidth() - 20)
        editbox:SetText(("%s%s/%d#related:comments"):format(URL_BASE, URL_TYPE_MAP[data.type_name], data.id))
        editbox:HighlightText()
        editbox:SetFocus()

        self.text:SetJustifyH("LEFT")
        self.text:SetFormattedText(LINK_EDITBOX_DESC_FORMAT:format(data.label))
    end,
})

local comment_subject = {}

-- HELPERS ------------------------------------------------------------

local comment_frame
do
    local panel = _G.CreateFrame("Frame", "WDP_CommentFrame", _G.UIParent, "TranslucentFrameTemplate")
    panel:SetSize(480, 350)
    panel:SetPoint("CENTER", _G.UIParent, "CENTER")
    panel:SetFrameStrata("DIALOG")
    panel.Bg:SetTexture([[Interface\FrameGeneral\UI-Background-Rock]], true, true)
    panel.Bg:SetHorizTile(true)
    panel.Bg:SetVertTile(true)
    panel:Hide()
    comment_frame = panel

    table.insert(_G.UISpecialFrames, panel:GetName())

    local streaks = panel:CreateTexture("$parentTopTileStreaks", "BORDER", "_UI-Frame-TopTileStreaks", -6)
    streaks:SetPoint("TOPLEFT", 13, -13)
    streaks:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -13, -35)

    local header = _G.CreateFrame("Frame", "$parentHeader", panel, "TranslucentFrameTemplate")
    header:SetSize(128, 64)
    header:SetPoint("CENTER", panel, "TOP", 0, -8)
    header.Bg:SetTexture([[Interface\FrameGeneral\UI-Background-Marble]])
    header.Bg:SetHorizTile(true)
    header.Bg:SetVertTile(true)
    panel.header = header

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetTexture([[Interface\AddOns\WoWDBProfiler\wowdb-logo]])
    logo:SetPoint("TOPLEFT", header, 10, -10)
    logo:SetPoint("BOTTOMRIGHT", header, -10, 10)

    local subject_name = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    subject_name:SetPoint("TOP", header, "BOTTOM", 0, -10)
    panel.subject_name = subject_name

    local subject_data = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    subject_data:SetPoint("TOP", subject_name, "BOTTOM", 0, -3)
    panel.subject_data = subject_data

    local close = _G.CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -7, -7)

    local scroll_frame = _G.CreateFrame("ScrollFrame", "$parentScrollFrame", panel)
    scroll_frame:SetSize(435, 150)
    scroll_frame:SetPoint("BOTTOM", 0, 70)

    scroll_frame:SetScript("OnScrollRangeChanged", function(self, x, y)
        _G.ScrollFrame_OnScrollRangeChanged(self, x, y)
    end)

    scroll_frame:SetScript("OnVerticalScroll", function(self, offset)
        local scrollbar = self.ScrollBar
        scrollbar:SetValue(offset)

        local min, max = scrollbar:GetMinMaxValues()

        if offset == 0 then
            scrollbar.ScrollUpButton:Disable()
        else
            scrollbar.ScrollUpButton:Enable()
        end

        if (scrollbar:GetValue() - max) == 0 then
            scrollbar.ScrollDownButton:Disable()
        else
            scrollbar.ScrollDownButton:Enable()
        end
    end)

    scroll_frame:SetScript("OnMouseWheel", function(self, delta)
        _G.ScrollFrameTemplate_OnMouseWheel(self, delta)
    end)

    panel.scroll_frame = scroll_frame

    local edit_container = _G.CreateFrame("Frame", nil, scroll_frame)
    edit_container:SetPoint("TOPLEFT", scroll_frame, -7, 7)
    edit_container:SetPoint("BOTTOMRIGHT", scroll_frame, 7, -7)
    edit_container:SetFrameLevel(scroll_frame:GetFrameLevel() - 1)
    edit_container:SetBackdrop({
        bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
        edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {
            left = 5,
            right = 5,
            top = 5,
            bottom = 5
        }
    })

    edit_container:SetBackdropBorderColor(_G.TOOLTIP_DEFAULT_COLOR.r, _G.TOOLTIP_DEFAULT_COLOR.g, _G.TOOLTIP_DEFAULT_COLOR.b)
    edit_container:SetBackdropColor(0, 0, 0)

    local link_button = _G.CreateFrame("Button", "$parentLinkButton", panel)
    link_button:SetSize(32, 16)
    link_button:SetPoint("TOPRIGHT", edit_container, "BOTTOMRIGHT", 5, 0)

    link_button:SetNormalTexture([[Interface\TradeSkillFrame\UI-TradeSkill-LinkButton]])
    link_button:GetNormalTexture():SetTexCoord(0, 1, 0, 0.5)

    link_button:SetHighlightTexture([[Interface\TradeSkillFrame\UI-TradeSkill-LinkButton]])
    link_button:GetHighlightTexture():SetTexCoord(0, 1, 0.5, 1)

    link_button:SetScript("OnClick", function(self)
        Dialog:Spawn("WDP_CommentLink", { type_name = comment_subject.type_name, id = comment_subject.id, label = comment_subject.label })
    end)

    link_button:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        _G.GameTooltip:SetText(LINK_COMMENT_TOOLTIP, nil, nil, nil, nil, 1)
        _G.GameTooltip:Show()
    end)

    link_button:SetScript("OnLeave", _G.GameTooltip_Hide)

    local edit_description = edit_container:CreateFontString("MUFASA", "ARTWORK", "GameFontHighlight")
    edit_description:SetHeight(36)
    edit_description:SetPoint("BOTTOMLEFT", edit_container, "TOPLEFT", 5, 3)
    edit_description:SetPoint("BOTTOMRIGHT", edit_container, "TOPRIGHT", 5, 3)
    edit_description:SetFormattedText(EDIT_DESCRIPTION_FORMAT, _G.BreakUpLargeNumbers(EDIT_MAXCHARS))
    edit_description:SetWordWrap(true)
    edit_description:SetJustifyH("LEFT")

    local edit_box = _G.CreateFrame("EditBox", nil, scroll_frame)
    edit_box:SetMultiLine(true)
    edit_box:SetMaxLetters(EDIT_MAXCHARS)
    edit_box:EnableMouse(true)
    edit_box:SetAutoFocus(false)
    edit_box:SetFontObject("ChatFontNormal")
    edit_box:SetSize(420, 220)
    edit_box:HighlightText(0)
    edit_box:SetFrameLevel(scroll_frame:GetFrameLevel() - 1)

    edit_box:SetScript("OnCursorChanged", _G.ScrollingEdit_OnCursorChanged)
    edit_box:SetScript("OnEscapePressed", _G.EditBox_ClearFocus)
    edit_box:SetScript("OnShow", function(self)
        _G.EditBox_SetFocus(self)

        if self:GetNumLetters() > 0 then
            panel.submitButton:Enable()
        else
            panel.submitButton:Disable()
        end
    end)

    edit_box:SetScript("OnTextChanged", function(self, user_input)
        local parent = self:GetParent()
        local num_letters = self:GetNumLetters()
        _G.ScrollingEdit_OnTextChanged(self, parent)
        parent.charCount:SetFormattedText(_G.BreakUpLargeNumbers(self:GetMaxLetters() - num_letters))

        if num_letters > 0 then
            panel.submitButton:Enable();
        else
            panel.submitButton:Disable()
        end
    end)

    edit_box:SetScript("OnUpdate", function(self, elapsed)
        _G.ScrollingEdit_OnUpdate(self, elapsed, self:GetParent())
    end)

    edit_container:SetScript("OnMouseUp", function()
        _G.EditBox_SetFocus(edit_box)
    end)

    scroll_frame.edit_box = edit_box
    scroll_frame:SetScrollChild(edit_box)

    local char_count = scroll_frame:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    char_count:SetPoint("BOTTOMRIGHT", -15, 0)
    scroll_frame.charCount = char_count

    local scroll_bar = _G.CreateFrame("Slider", "$parentScrollBar", scroll_frame, "UIPanelScrollBarTemplate")
    scroll_bar:SetPoint("TOPLEFT", scroll_frame, "TOPRIGHT", -13, -16)
    scroll_bar:SetPoint("BOTTOMLEFT", scroll_frame, "BOTTOMRIGHT", -13, 16)
    scroll_frame.ScrollBar = scroll_bar

    _G.ScrollFrame_OnLoad(scroll_frame)

    local submit = _G.CreateFrame("Button", "$parentSubmit", panel, "GameMenuButtonTemplate")
    submit:SetSize(160, 30)
    submit:SetPoint("BOTTOM", 0, 15)
    submit:SetText(_G.SUBMIT)
    submit:Enable(false)

    submit:SetScript("OnClick", function()
    -- TODO: Make this assign the comment to the correct SavedVariables entry.
        edit_box:SetText("")
        _G.HideUIPanel(panel)
    end)
    panel.submitButton = submit
end

local function CreateUnitComment(unit_id)
    if not _G.UnitExists(unit_id) then
        WDP:Printf("Unit '%s' does not exist.", unit_id)
        return
    end
    local unit_type, unit_idnum = ParseGUID(_G.UnitGUID(unit_id))

    if not unit_idnum then
        WDP:Printf("Unable to determine unit from '%s'", unit_id)
        return
    end
    local type_name = private.UNIT_TYPE_NAMES[unit_type + 1]
    local unit_name = _G.UnitName(unit_id)
    comment_subject.type_name = type_name
    comment_subject.id = unit_idnum
    comment_subject.label = unit_name

    comment_frame.subject_name:SetText(unit_name)
    comment_frame.subject_data:SetFormattedText("(%s #%d)", type_name, unit_idnum)
    comment_frame.scroll_frame.edit_box:SetText("")
    _G.ShowUIPanel(comment_frame)
end

local DATA_TYPE_MAPPING = {
    merchant = "ITEM",
}

local CURSOR_DATA_FUNCS = {
    item = function(data_type, data, data_subtype)
        local item_name = _G.GetItemInfo(data)
        comment_subject.type_name = data_type
        comment_subject.id = data
        comment_subject.label = item_name

        comment_frame.subject_name:SetText(item_name)
        comment_frame.subject_data:SetFormattedText("(%s #%d)", data_type, data)
    end,
    merchant = function(data_type, data)
        local item_link = _G.GetMerchantItemLink(data)
        local item_name = _G.GetItemInfo(item_link)
        local item_id = ItemLinkToID(item_link)
        comment_subject.type_name = data_type
        comment_subject.id = item_id
        comment_subject.label = item_name

        comment_frame.subject_name:SetText(item_name)
        comment_frame.subject_data:SetFormattedText("(%s #%d)", data_type, item_id)
    end,
    spell = function(data_type, data, data_subtype, subdata)
        local spell_name = _G.GetSpellInfo(subdata)
        comment_subject.type_name = data_type
        comment_subject.id = subdata
        comment_subject.label = spell_name

        comment_frame.subject_name:SetText(spell_name)
        comment_frame.subject_data:SetFormattedText("(%s #%d)", data_type, subdata)
    end,
}

local function CreateCursorComment()
    local data_type, data, data_subtype, subdata = _G.GetCursorInfo()

    if not CURSOR_DATA_FUNCS[data_type] then
        WDP:Print("Unable to determine comment subject from cursor.")
        return
    end
    CURSOR_DATA_FUNCS[data_type](DATA_TYPE_MAPPING[data_type] or data_type:upper(), data, data_subtype, subdata)
    comment_frame.scroll_frame.edit_box:SetText("")
    _G.ShowUIPanel(comment_frame)
end

local function CreateQuestComment()
    local index = _G.GetQuestLogSelection()

    if not index or not _G.QuestLogFrame:IsShown() then
        WDP:Print("You must select a quest from the Quest frame.")
        return
    end
    local title, _, tag, _, is_header, _, _, _, idnum = _G.GetQuestLogTitle(index)

    if is_header then
        WDP:Print("You must select a quest from the Quest frame.")
        return
    end
    comment_subject.type_name = "QUEST"
    comment_subject.id = idnum
    comment_subject.label = title

    comment_frame.subject_name:SetText(title)
    comment_frame.subject_data:SetFormattedText("(%s #%d)", "QUEST", idnum)
    comment_frame.scroll_frame.edit_box:SetText("")
    _G.ShowUIPanel(comment_frame)
end

-- METHODS ------------------------------------------------------------

function private.ProcessCommentCommand(arg)
    if not arg or arg == "" then
        WDP:Print("You must supply a valid comment type.")
        return
    end

    if arg == "cursor" then
        CreateCursorComment()
        return
    elseif arg == "quest" then
        CreateQuestComment()
        return
    end
    CreateUnitComment(arg)
end
