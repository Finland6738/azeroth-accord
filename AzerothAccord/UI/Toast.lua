-- Toast: the on-screen box of a notice (SPEC-13 §3.4, M9.3). Lua 5.1.
-- A frame of the addon at the top centre, under the zone where the game writes its errors, in the theme of the addon: one
-- notice at a time for SECONDS, a click opens its view (and marks it read), a right click closes it. At most QUEUE wait;
-- the ones beyond are summed up in one "N more notices" box, which opens the Notices page. The game's own alert frames
-- and warning systems are never used (no taint). The frame is unprotected and is made when the first notice comes out.
--   Toast:Push(entry)   shows an entry of Data/Notify.lua, or queues it
--   Toast:Close()       closes the box on screen and shows the next one; while notices are held (SPEC-13 §4) the
--                       ones waiting stay until Toast:Resume()
--   Toast:Resume()      shows the next waiting one when nothing is on screen
--   Toast:Reset()       drops everything
local ADDON_NAME, ns = ...
ns = ns or {}
local Toast = {}
ns.Toast, ns.modules = Toast, ns.modules or {}
ns.modules.Toast = Toast

local type, remove, max = type, table.remove, math.max

Toast.SECONDS = 6
Toast.QUEUE = 3
Toast.WIDTH = 360
Toast.PAD = 12
Toast.TOP = -180          -- under UIErrorsFrame

Toast.queue = {}
Toast.over = 0
Toast.current = nil       -- the entry on screen, or { more = n } for the summary
local serial = 0

local L, Widgets, Theme = ns.L, ns.Widgets, ns.Theme

local function build()
	local f = CreateFrame("Button", "AzerothAccordToast", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetSize(Toast.WIDTH, 60)
	f:SetPoint("TOP", UIParent, "TOP", 0, Toast.TOP)
	f.fill = Theme.Slice(f, "rr_fill_12", "surface-1", "BACKGROUND")
	f.fill:SetAllPoints(f)
	f.ring = Theme.Slice(f, "rr_ring_12", "accent", "BORDER")
	f.ring:SetAllPoints(f)
	f.title = Widgets.Text(f, "Eyebrow", "text-3", "LEFT")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", Toast.PAD, -Toast.PAD)
	f.text = Widgets.Text(f, "Body", "text-1", "LEFT")
	f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.text:SetWidth(Toast.WIDTH - 2 * Toast.PAD)
	f.text:SetWordWrap(true)
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f:SetScript("OnClick", function(_, button)
		if button ~= "RightButton" then Toast:Open() end
		Toast:Close()
	end)
	f:Hide()
	Toast.frame = f
	return f
end

local function show(item)
	local f = Toast.frame or build()
	Toast.current = item
	serial = serial + 1
	local mine = serial
	if item.more then
		f.title:SetText(L["ADDON_TITLE"])
		f.text:SetText(L["NOTICE_TOAST_MORE"]:format(item.more))
	else
		local def = ns.Notify:Module(item.module)
		f.title:SetText(def and L[def.label] or L["ADDON_TITLE"])
		f.text:SetText((ns.Notify.Text(item):gsub("[\r\n]+", " ")))
	end
	f:SetHeight(max(48, 2 * Toast.PAD + (f.title:GetStringHeight() or 0) + 6 + (f.text:GetStringHeight() or 0)))
	f:Show()
	ns.Compat.After(Toast.SECONDS, function() if mine == serial then Toast:Close() end end)
end

function Toast:Push(entry)
	if type(entry) ~= "table" then return false end
	if not self.current and #self.queue == 0 then
		show(entry)
	elseif #self.queue < Toast.QUEUE then
		self.queue[#self.queue + 1] = entry
	else
		self.over = self.over + 1
	end
	return true
end

-- What a click on the box on screen opens.
function Toast:Open()
	local item = self.current
	if not item then return false end
	if not item.more then return ns.Notify:Open(item) end
	if ns.ActionsView and ns.Shell and ns.Shell:OpenView("actions") then return ns.ActionsView:ShowPage("notices") end
	return false
end

function Toast:Resume()
	if not self.current and (#self.queue > 0 or self.over > 0) then self:Close() end
end

function Toast:Close()
	self.current = nil
	serial = serial + 1
	if ns.Notify:Holding() then   -- nothing pops up now
		if self.frame then self.frame:Hide() end
		return
	end
	local nextOne = remove(self.queue, 1)
	if not nextOne and self.over > 0 then
		nextOne, self.over = { more = self.over }, 0
	end
	if nextOne then
		show(nextOne)
	elseif self.frame then
		self.frame:Hide()
	end
end

function Toast:Reset()
	self.queue, self.over, self.current = {}, 0, nil
	serial = serial + 1
	if self.frame then self.frame:Hide() end
end

if ns.addon then ns.addon.Toast = Toast end
