-- LUA API ------------------------------------------------------------

local _G = getfenv(0)

local table = _G.table

-- ADDON NAMESPACE ----------------------------------------------------

local ADDON_NAME, private = ...

local LibStub = _G.LibStub
local WDP = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local ParseGUID = private.ParseGUID

-- CONSTANTS ----------------------------------------------------------

local EDIT_MAXCHARS = 3000
local EDIT_DESCRIPTION_FORMAT = [[Enter your comment below, being as descriptive as possible. Comments are limited to %s characters, including newlines and spaces.]]

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

local function CreateUnitComment(unit_id, unit_type, unit_idnum)
    comment_frame.subject_name:SetText(_G.UnitName(unit_id))
    comment_frame.subject_data:SetFormattedText("(%s #%d)", private.UNIT_TYPE_NAMES[unit_type + 1], unit_idnum)
    comment_frame.scroll_frame.edit_box:SetText("")
    comment_frame:Show()
end

local function CreateCursorComment()
    -- TODO: Implement!
end

-- METHODS ------------------------------------------------------------

function private.ProcessCommentCommand(arg)
    if not arg or arg == "" then
        WDP:Print("You must supply a valid comment type.")
        return
    end

    if arg == "cursor" then
        WDP:Print("Not yet implemented.")
        return
    end

    if not _G.UnitExists(arg) then
        WDP:Printf("Unit '%s' does not exist.", arg)
        return
    end
    local unit_type, unit_idnum = ParseGUID(_G.UnitGUID(arg))

    if not unit_idnum then
        WDP:Printf("Unable to determine unit from '%s'", arg)
        return
    end
    CreateUnitComment(arg, unit_type, unit_idnum)
end
