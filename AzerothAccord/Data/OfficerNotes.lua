-- OfficerNotes: the extended notes the officers write about a character (SPEC-12 §5, ONT-01..ONT-04, M8.5). Lua 5.1.
--
-- A record of the set `onotes` is { id = GUID of the character, author, rev, time, char = the same GUID, text }: one note per
-- character, `author` the officer who wrote the latest version. The highest `rev` wins (the store's rule). `text = ""` is a
-- deletion: a new revision, so it reaches every officer, and the empty record expires after DELETE_DAYS.
-- The note of a character who left the guild is kept forever (SPEC-10 Q14): nothing here looks at the roster to delete it.
-- Only the officers and the GM see and write them (Officer.VISIBLE_TO.notes); they travel on OFFICER only, once the channel
-- is proven (the sync of the officer tools, Net/Sync.lua); a demoted officer's client deletes them (Officer:Purge, OFF-10).
--
--   OfficerNotes.Clean(text)         the text as it is saved: line ends as "\n", tabs as spaces, other control characters
--                                    dropped, spaces trimmed at both ends
--   OfficerNotes.Check(text)         true, or nil plus "chars" | "bytes" | "lines" | "control" (ONT-02)
--   OfficerNotes.Length(text)        the number of UTF-8 characters
--   OfficerNotes.ValidRecord(rec)    the owner rule of the set (OFF-03)
--   OfficerNotes:Get(guid)           the record of a character with a non-empty text, for whoever may see the notes; else nil
--   OfficerNotes:Set(guid, text)     an officer writes (or, with "", deletes) the note; returns the record or nil plus a reason
--   OfficerNotes:Delete(guid)        the same as Set(guid, "") for a note that exists
--   OfficerNotes:OfAccount(guid)     the notes of the other proved characters of the account: { { guid, name, rec } }
--   OfficerNotes:AnyOf(guids)        true when one of the characters has a note (the mark on the Inactive page and the review)
local ADDON_NAME, ns = ...
ns = ns or {}
local Notes = {}
ns.OfficerNotes, ns.modules = Notes, ns.modules or {}
ns.modules.OfficerNotes = Notes

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local DAY = 86400

Notes.SET = "onotes"
Notes.MAX_CHARS = 500          -- ONT-02: characters, the limit of the edit box (maxLetters)
Notes.MAX_BYTES = 1000         -- bytes of UTF-8, checked when saving
Notes.MAX_LINES = 20
Notes.DELETE_DAYS = 60         -- an empty record (a deletion) is removed this long after it was written
Notes.GROUPS = 32              -- the groups of the summary `m` of OHELLO (SPEC-12 §1.5)

local function store() return ns.Store end
local function now() return ns.Compat.ServerTime() end

---------------------------------------------------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------------------------------------------------
-- The number of UTF-8 characters of `text` (continuation bytes are not counted).
function Notes.Length(text)
	if type(text) ~= "string" then return 0 end
	local n = 0
	for i = 1, #text do
		local b = text:byte(i)
		if b < 0x80 or b >= 0xC0 then n = n + 1 end
	end
	return n
end

function Notes.Clean(text)
	text = tostring(text or "")
	text = text:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\t", " ")
	text = text:gsub("[%z\1-\9\11-\31\127]", "")
	-- explicit spaces, not %s: on Windows %s matches byte 0xA0, the last byte of "à" in UTF-8
	text = text:gsub("^[ \n]+", ""):gsub("[ \n]+$", "")
	return text
end

-- The number of lines of a text ("" has none).
local function lines(text)
	if text == "" then return 0 end
	local n = 1
	for _ in text:gmatch("\n") do n = n + 1 end
	return n
end
Notes.Lines = lines

function Notes.Check(text)
	if type(text) ~= "string" then return nil, "control" end
	if text:find("[%z\1-\9\11-\31\127]") then return nil, "control" end
	if Notes.Length(text) > Notes.MAX_CHARS then return nil, "chars" end
	if #text > Notes.MAX_BYTES then return nil, "bytes" end
	if lines(text) > Notes.MAX_LINES then return nil, "lines" end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------------------------------------------------
local ALLOWED = { id = true, author = true, rev = true, time = true, char = true, text = true }

function Notes.ValidRecord(rec)
	if type(rec) ~= "table" then return false end
	for key in pairs(rec) do if not ALLOWED[key] then return false end end
	if type(rec.char) ~= "string" or rec.id ~= rec.char then return false end
	if not (#rec.char <= 40 and rec.char:find(store().GUID_PATTERN)) then return false end
	return Notes.Check(rec.text) == true
end

function Notes.Expired(rec, t)
	return type(rec) ~= "table" or (rec.text == "" and (rec.time or 0) < t - Notes.DELETE_DAYS * DAY)
end

-- The group of the summary `m` (SPEC-12 §1.5): "onotes:<n>", n = Hash.Fast(GUID) % 32.
function Notes.Group(rec)
	return "onotes:" .. (ns.Hash.Fast(tostring(rec.char)) % Notes.GROUPS)
end

local function canSee() return ns.Officer ~= nil and ns.Officer.CanSee("notes") end

function Notes:Get(guid)
	if not canSee() or type(guid) ~= "string" then return nil end
	local rec = store():Get(Notes.SET, guid)
	if rec and type(rec.text) == "string" and rec.text ~= "" then return rec end
	return nil
end

-- An officer writes the note of `guid`. Returns the record (or the one held, when the text is the same), or nil plus
-- "officer" | "unknown" | "chars" | "bytes" | "lines" | "control" | a reason of Store:Put.
function Notes:Set(guid, text)
	if not (ns.Role and ns.Role:IsOfficer() and canSee()) then return nil, "officer" end
	if type(guid) ~= "string" or not guid:find(store().GUID_PATTERN) then return nil, "unknown" end
	text = Notes.Clean(text)
	local ok, why = Notes.Check(text)
	if not ok then return nil, why end
	local held = store():Get(Notes.SET, guid)
	if held and held.text == text then return held end
	if not held and text == "" then return nil, "empty" end
	return store():Put(Notes.SET, guid, { char = guid, text = text })
end

function Notes:Delete(guid)
	if not self:Get(guid) then return nil, "empty" end
	return self:Set(guid, "")
end

-- The name of a character: the roster's, else the one its account lists, else "?".
function Notes.NameOf(guid)
	local entry = ns.Roster and ns.Roster:ByGUID(guid)
	if entry then return entry.short or entry.name end
	local g = ns.Accounts and ns.Accounts:GroupOf(guid)
	local m = g and g.byGUID and g.byGUID[guid]
	if m and type(m.name) == "string" then return m.name end
	return "?"
end

function Notes:OfAccount(guid)
	local out = {}
	if not canSee() or type(guid) ~= "string" then return out end
	local chars = ns.Accounts and ns.Accounts:ProvedChars(guid) or { guid }
	for _, g in ipairs(chars) do
		if g ~= guid then
			local rec = self:Get(g)
			if rec then out[#out + 1] = { guid = g, name = Notes.NameOf(g), rec = rec } end
		end
	end
	table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return out
end

function Notes:AnyOf(guids)
	if not canSee() then return false end
	for _, g in ipairs(guids or {}) do if self:Get(g) then return true end end
	return false
end

-- The number of notes with a text that this character wrote (the What I share panel: a count, never a text).
function Notes:WrittenBy(guid)
	local n = 0
	for _, rec in pairs(store():Records(Notes.SET)) do
		if rec.author == guid and rec.text ~= "" then n = n + 1 end
	end
	return n
end

function Notes.ErrorText(why, text)
	local L = ns.L
	if why == "bytes" then return L["ONT_ERR_BYTES"]:format(#tostring(text or ""), Notes.MAX_BYTES) end
	if why == "chars" then return L["ONT_ERR_CHARS"]:format(Notes.MAX_CHARS) end
	if why == "lines" then return L["ONT_ERR_LINES"]:format(Notes.MAX_LINES) end
	if why == "officer" then return L["ONT_ERR_OFFICER"] end
	return L["ABS_ERR_OTHER"]:format(tostring(why))
end

if ns.addon then
	ns.addon.OfficerNotes = Notes
end
