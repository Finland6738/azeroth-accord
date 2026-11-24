-- Widget kit, part 6: the provenance label (SPEC-11 §1.3, M7.2): a small `text-3` text beside a value that says where it
-- comes from ("game", an age such as "3 d ago", "you", "note"), with a tooltip that says who reported it. A `shared` value
-- older than its threshold is dimmed (Provenance.DIM_DAYS). The words come from UI/Provenance.lua. Lua 5.1.
--   local label = Widgets.Provenance(parent)
--   label:SetSource(info)   info as in UI/Provenance.lua; nil hides the label
--   label:GetInfo() / label:IsDim()
local ADDON_NAME, ns = ...
ns = ns or {}
local Widgets, Theme = ns.Widgets, ns.Theme

function Widgets.Provenance(parent)
	local f = CreateFrame("Button", nil, parent)
	f.text = Theme.NewText(f, "Small", "text-3")
	f.text:SetJustifyH("RIGHT")
	f.text:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f:SetSize(1, 14)
	f.info = nil
	f.dim = false
	function f:SetSource(info)
		self.info = info
		local d = ns.Provenance and ns.Provenance.Describe(info)
		if not d then
			self.dim = false
			self.text:SetText("")
			self:Hide()
			return
		end
		self.dim = d.dim
		self.lines = d.lines
		self.text:SetText(d.label)
		Theme.Text(self.text, "text-3")   -- the label is already text-3; a dim value dims the value beside it (IsDim)
		self:SetWidth((self.text:GetStringWidth() or 40) + 2)
		self:Show()
	end
	function f:GetInfo() return self.info end
	function f:IsDim() return self.dim end
	Widgets.Tooltip.Attach(f, function(self) return self.lines end, "TOP")
	f:Hide()
	return f
end
