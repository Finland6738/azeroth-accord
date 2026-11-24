-- The Info page (M6.15): UI/About.lua, the Info page of Settings and `/accord about`.
local function A() return AzerothAccord end
local function About() return AzerothAccord.About end
local function out() return table.concat(Mock.PlainOutput(), "\n") end

local function loadLocale(name)
	local tbl = {}
	local env = { LibStub = function() return { NewLocale = function() return tbl end } end }
	local chunk = assert(loadstring(Mock.ReadSource("AzerothAccord/Locale/" .. name), "@Locale/" .. name))
	setfenv(chunk, env)
	chunk("AzerothAccord")
	return tbl
end

local ME = "Player-1-0000A001"
local function guild() Mock.guild.Set{ name = "Accord", myRank = 3, members = { { name = "Bob", level = 60, class = "MAGE", rank = 3, guid = ME } } } end

local function info()
	Mock.Slash("/accord about")
	return A().SettingsView.frame.info
end

local function shownTexts(frame, out)
	out = out or {}
	if not (frame and frame:IsShown()) then return out end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" and region:IsShown() then
			local t = region:GetText()
			if type(t) == "string" and t ~= "" then out[#out + 1] = t end
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do shownTexts(child, out) end
	return out
end

-- The shown texts of the Info page that are not a string of the locale file (URLs are data).
local function textsNotInLocale(file)
	local want, bad, total = {}, {}, 0
	for _, v in pairs(loadLocale(file)) do want[#want + 1] = v end
	for _, text in ipairs(shownTexts(A().SettingsView.frame.holders.info)) do
		total = total + 1
		local ok = text:find("^https?://") ~= nil
		for _, v in ipairs(want) do
			if ok then break end
			local pat = "^" .. v:gsub("%%[sd]", "<PH>"):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("<PH>", ".*") .. "$"
			ok = text:find(pat) ~= nil
		end
		if not ok then bad[#bad + 1] = text end
	end
	return bad, total
end

describe("the Info page", function()
	before_boot(guild)

	it("is a page of Settings after the Settings and What I share pages, and /accord about opens it", function()
		deepEq({ A().SettingsView.pages[1].id, A().SettingsView.pages[2].id, A().SettingsView.pages[3].id }, { "settings", "share", "info" })
		Mock.Slash("/accord about")
		truthy(A().Shell:IsShown())
		local f = A().SettingsView.frame
		eq(f.pageId, "info")
		truthy(f.holders.info:IsShown())
		falsy(f.holders.settings:IsShown())
		truthy(f.pager)
		eq(#Mock.errors, 0)
	end)

	it("shows the logo, the name, the credits, the permission note, the licence and the disclaimer", function()
		local i = info()
		eq(i.logo:GetTexture(), A().Assets.logos.logo_256.path)
		eq(i.title:GetText(), "Azeroth Accord")
		contains(i.version:GetText(), "Version")
		contains(i.madeBy:GetText(), "Created and designed by Finland")
		contains(i.guild:GetText(), "Made with the Italian guild NEBULA")
		contains(i.permission:GetText(), "NEBULA logo is used with the guild's permission")
		contains(i.license:GetText(), "GPL-3.0")
		contains(i.third:GetText(), "docs/third-party.md")
		contains(i.disclaimer:GetText(), "Blizzard Entertainment")
		contains(i.disclaimer:GetText(), "not affiliated")
	end)

	it("the NEBULA logo follows the theme without a reload", function()
		local i = info()
		local dark, light = A().Assets.logos.nebula_dark.path, A().Assets.logos.nebula_light.path
		for theme, want in pairs({ nebula = dark, aurora = light, accord = dark }) do
			A().Theme.Apply(theme)
			eq(i.nebula:GetTexture(), want, theme)
		end
		A().Theme.Apply("nebula")
		eq(i.nebula:GetTexture(), dark)
	end)

	it("every text of the page is a locale key, in English", function()
		info()
		local bad, total = textsNotInLocale("enUS.lua")
		eq(#bad, 0, table.concat(bad, " | "))
		truthy(total > 10)
	end)

	it("lists the four links as copy boxes that put an edit back and select on focus", function()
		local i = info()
		local want = {
			repo = "https://github.com/Finland6738/azeroth-accord",
			issues = "https://github.com/Finland6738/azeroth-accord/issues",
			site = "https://nebula-community.github.io/giochi/wow-forever/",
			kofi = "https://ko-fi.com/finland6738",
		}
		local n = 0
		for id, url in pairs(want) do
			n = n + 1
			local box = i.links[id]
			truthy(box, id)
			eq(box:GetText(), url)
			box.edit:SetText("typed by hand")
			Mock.RunScript(box.edit, "OnTextChanged", true)
			eq(box:GetText(), url, id .. " is put back")
			box.edit._highlighted = false
			Mock.RunScript(box.edit, "OnEditFocusGained")
			truthy(box.edit._highlighted, id .. " is selected")
		end
		eq(n, 4)
		eq(#About().LINKS, 4)
	end)

	it("prints the credits on /accord about chat and does not open the window", function()
		Mock.Slash("/accord about chat")
		local text = out()
		contains(text, "Created and designed by Finland")
		contains(text, "Made with the Italian guild NEBULA")
		contains(text, "https://ko-fi.com/finland6738")
		contains(text, "https://github.com/Finland6738/azeroth-accord/issues")
		contains(text, "GPL-3.0")
		contains(text, "Blizzard Entertainment")
		falsy(A().Shell:IsShown())
	end)

	it("is in the help and keeps personal data out", function()
		Mock.Slash("/accord help")
		contains(out(), "/accord about")
		for _, text in pairs(About().Lines()) do falsy(text:find("@", 1, true), text) end
		eq(About().AUTHOR, "Finland")
	end)
end)

describe("the Info page of an Italian client", function()
	before_boot(function(M) M.player.locale = "itIT"; guild() end)

	it("speaks Italian", function()
		local t = About().Lines()
		contains(t.madeBy, "Creato e progettato da Finland")
		contains(t.guild, "Realizzato con la gilda italiana NEBULA")
		contains(t.permission, "con il permesso della gilda")
		contains(t.disclaimer, "Blizzard Entertainment")
		eq(info().links.kofi:GetText(), "https://ko-fi.com/finland6738")
		local bad, total = textsNotInLocale("itIT.lua")
		eq(#bad, 0, table.concat(bad, " | "))
		truthy(total > 10)
		Mock.Slash("/accord about chat")
		contains(out(), "Creato e progettato da Finland")
	end)
end)
