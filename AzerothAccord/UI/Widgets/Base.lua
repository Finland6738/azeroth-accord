-- Widgets: the small set of building blocks the panel uses (SPEC-04 §5). Lua 5.1.
-- Adapted from Azeroth Guild Finder (UI/Widgets/Base.lua and Buttons.lua), same owner, GPL-3.0 (ADR 0018): the API
-- shape (W.Name(parent, opts) returning a frame, every string already translated by the caller, tooltips from a string
-- or a function) is kept; the drawing uses the client's templates and font objects (UI/Skin.lua) instead of the custom
-- textures of the original. The other widgets of Guild Finder (chips, switches, cards...) come over when a view needs
-- them.
local ADDON_NAME, ns = ...
ns = ns or {}
local W = {}
ns.Widgets, ns.modules = W, ns.modules or {}
ns.modules.Widgets = W

local Skin = ns.Skin
local type, ipairs, pcall, tostring = type, ipairs, pcall, tostring

-- CreateFrame with the first template of `role` (a Skin.TEMPLATES key, or a list) the client accepts. Returns the
-- frame and the template used ("" for none). CreateFrame raises on an unknown template: each is tried under pcall.
function W.Create(objectType, name, parent, role)
	local list = type(role) == "table" and role or Skin.TEMPLATES[role] or { "" }
	for _, template in ipairs(list) do
		local ok, frame = pcall(CreateFrame, objectType, name, parent, template ~= "" and template or nil)
		if ok and frame then return frame, template end
	end
	return CreateFrame(objectType, name, parent), ""
end

-- A font string in a style of the skin, optional colour name and horizontal justification.
function W.Text(parent, style, color, justify, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	local font = Skin.Font(style)
	if font then fs:SetFontObject(font) end
	if color then fs:SetTextColor(Skin.Color(color)) end
	if justify then fs:SetJustifyH(justify) end
	return fs
end

-- A plain frame of the given size.
function W.Frame(parent, width, height, name)
	local f = CreateFrame("Frame", name, parent)
	if width and height then f:SetSize(width, height) end
	return f
end

-- A solid background in a colour of the skin.
function W.Background(frame, color, alpha, layer)
	local t = frame:CreateTexture(nil, layer or "BACKGROUND")
	t:SetAllPoints(frame)
	t:SetColorTexture(Skin.Color(color or "panel", alpha or 0.95))
	return t
end

-- Shows a tooltip on hover. `source` is a string, a list of lines (the first is the title) or a function returning
-- either.
function W.SetTooltip(frame, source, anchor)
	frame:HookScript("OnEnter", function(self)
		if not GameTooltip then return end
		local content = type(source) == "function" and source(self) or source
		if content == nil then return end
		GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
		if type(content) == "table" then
			GameTooltip:SetText(tostring(content[1] or ""))
			for i = 2, #content do GameTooltip:AddLine(tostring(content[i]), 1, 1, 1, true) end
		else
			GameTooltip:SetText(tostring(content))
		end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- A Blizzard panel button: opts = { text, width, height, onClick, tooltip, disabled }.
function W.Button(parent, opts)
	opts = opts or {}
	local b, template = W.Create("Button", nil, parent, "button")
	b:SetSize(opts.width or 110, opts.height or 22)
	if template == "" then
		b.label = W.Text(b, "heading")
		b.label:SetPoint("CENTER")
		b.SetLabel = function(self, text) self.label:SetText(text) end
	else
		b.SetLabel = function(self, text) self:SetText(text) end
	end
	b:SetLabel(opts.text or "")
	if opts.onClick then b:SetScript("OnClick", function(self, ...) opts.onClick(self, ...) end) end
	if opts.tooltip then W.SetTooltip(b, opts.tooltip) end
	if opts.disabled then b:Disable() end
	return b
end

-- The red close button of Blizzard windows.
function W.CloseButton(parent, onClick)
	local b, template = W.Create("Button", nil, parent, "close")
	if template == "" then
		b:SetSize(22, 22)
		b.label = W.Text(b, "heading", "gold")
		b.label:SetPoint("CENTER")
		b.label:SetText("x")
	end
	b:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
	return b
end

-- A search box (Blizzard's, with its magnifier and clear button when the client has the template).
-- opts = { width, onChange(text) }.
function W.SearchBox(parent, opts)
	opts = opts or {}
	local box = W.Create("EditBox", nil, parent, "search")
	box:SetSize(opts.width or 180, 20)
	box:SetAutoFocus(false)
	box:HookScript("OnTextChanged", function(self, userInput)
		if userInput and opts.onChange then opts.onChange(self:GetText() or "") end
	end)
	box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
	return box
end

-- Adds the frame's global name to UISpecialFrames, so Esc closes it.
function W.CloseOnEscape(frame)
	local name = frame:GetName()
	if not name or type(UISpecialFrames) ~= "table" then return false end
	for _, n in ipairs(UISpecialFrames) do if n == name then return true end end
	table.insert(UISpecialFrames, name)
	return true
end

if ns.addon then ns.addon.Widgets = W end
