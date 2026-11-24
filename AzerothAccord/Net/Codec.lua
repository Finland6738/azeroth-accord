-- Codec: message <-> addon-message text (SPEC-02 §2, ADR 0004). Lua 5.1.
-- Adapted from Azeroth Guild Finder (Net/Codec.lua), same owner, GPL-3.0 (ADR 0018); the wire format follows SPEC-02:
--
--   text    = "<version>|<TYPE>|" .. Base64( flag .. (flag == "\1" and Deflate(CBOR(body)) or CBOR(body)) )
--   message = { v = <version>, t = "<TYPE>", ...fields of body }
--
-- The version and the type are plain text, so a client reads them before decoding anything: a higher version or an
-- unknown type is ignored, never an error (NET-01). Decode never raises: it returns the message, or nil plus a reason
-- ("size", "shape", "version", "newer", "type", "base64", "flag", "inflate", "cbor", "depth", "invalid"); the third result
-- is the number of bytes it decoded (the CBOR after decompression, or the text when it stopped before), which the
-- transport counts per sender (SPEC-11 §6.3). Unknown fields are kept untouched; deep validation of records belongs to
-- the modules that own them (Net/Store.lua, Net/Sync.lua, ...).
local ADDON_NAME, ns = ...
ns = ns or {}
local Codec = {}
ns.Codec, ns.modules = Codec, ns.modules or {}
ns.modules.Codec = Codec

local type, pairs, tostring, tonumber, floor = type, pairs, tostring, tonumber, math.floor
local sub, find, match = string.sub, string.find, string.match

Codec.PROTO = 1
Codec.PREFIX = "AzAccord"
Codec.COMPRESS_OVER = 120   -- CBOR longer than this is deflated (when that makes it shorter)
Codec.MAX_DECODED = 16384   -- largest accepted CBOR after decompression
Codec.MAX_DEPTH = 8         -- deepest accepted table of a decoded message, the message itself being level 1 (SPEC-11 §6.1)
Codec.FLAG_RAW, Codec.FLAG_DEFLATE = "\0", "\1"
-- A Base64 body cannot be longer than the encoded largest message plus the flag byte; the header is a few bytes more.
Codec.MAX_BODY = floor((Codec.MAX_DECODED + 1) / 3 + 1) * 4
Codec.MAX_TEXT = Codec.MAX_BODY + 32

Codec.newerSeen = false     -- a message with a newer protocol version was received (shown once by the UI)
Codec.stats = { encoded = 0, decoded = 0, rejected = 0, unknown = 0 }
Codec.lastReject = nil      -- last rejection reason, for /accord debug

-- Required fields per message type (SPEC-02 §2): name -> Lua type. Unlisted fields are optional and never rejected.
-- Modules that add a type register it with Codec:RegisterType.
Codec.SCHEMA = {
	HELLO  = { s = "string" },                -- s = the sync summary (Net/Sync.lua), av = addon version
	OHELLO = { s = "string" },                -- HELLO of the officers' records (the restricted bank tabs), on OFFICER
	DIGEST = { d = "table" },                 -- the answer to a HELLO, by whisper
	REQ    = { s = "string" },                -- records of one data set: the set, then authors / buckets (Net/Sync.lua)
	REC    = { s = "string", r = "table" },   -- one or more records of data set s
	VOTE   = { g = "string" },                -- a like for the notary: g = target GUID, n = nonce (Data/Likes.lua)
	LEDGER = { g = "string", r = "string" },  -- the notary's receipt: target, result, e = the new ledger entry
	SALT   = { k = "string" },                -- the guild secret for the pseudonyms, officers only (Data/Notary.lua)
}

-- Adds a message type (or replaces its required fields). Type names are upper-case letters and digits.
function Codec:RegisterType(name, required)
	if type(name) ~= "string" or not match(name, "^[A-Z][A-Z0-9]*$") then return false end
	Codec.SCHEMA[name] = type(required) == "table" and required or {}
	return true
end

local function compat() return ns.Compat end

local function reject(reason, size)
	Codec.stats.rejected = Codec.stats.rejected + 1
	Codec.lastReject = reason
	return nil, reason, size
end

-- true when no table inside `t` is deeper than `limit` levels (`t` is level 1). Stops as soon as it is too deep.
local function shallow(t, limit)
	if limit < 1 then return false end
	for k, v in pairs(t) do
		if type(v) == "table" and not shallow(v, limit - 1) then return false end
		if type(k) == "table" and not shallow(k, limit - 1) then return false end
	end
	return true
end
Codec.Shallow = shallow

-- true, or false plus a reason. msg must be a table with a known `t` and the required fields of that type.
function Codec:Validate(msg)
	if type(msg) ~= "table" then return false, "shape" end
	local schema = type(msg.t) == "string" and Codec.SCHEMA[msg.t]
	if not schema then return false, "type" end
	for field, kind in pairs(schema) do
		if type(msg[field]) ~= kind then return false, "invalid" end
	end
	return true
end

-- Builds the text for message type `t` with `fields` (the fields `v` and `t` are set here). Returns the string, or nil
-- plus a reason.
function Codec:Encode(t, fields)
	local C = compat()
	if not C then return nil, "nocompat" end
	if fields ~= nil and type(fields) ~= "table" then return nil, "shape" end
	local msg = { t = t }
	for k, v in pairs(fields or {}) do msg[k] = v end
	msg.t = t
	local ok, reason = Codec:Validate(msg)
	if not ok then return nil, reason end
	local body = {}
	for k, v in pairs(msg) do
		if k ~= "t" and k ~= "v" then body[k] = v end
	end
	local cbor, err = C.CBOR.Encode(body)
	if not cbor then return nil, "cbor: " .. tostring(err) end
	if #cbor > Codec.MAX_DECODED then return nil, "size" end   -- a receiver would reject it
	local flag, packed = Codec.FLAG_RAW, cbor
	if #cbor > Codec.COMPRESS_OVER then
		local deflated = C.Compress.Deflate(cbor)
		if deflated and #deflated < #cbor then flag, packed = Codec.FLAG_DEFLATE, deflated end
	end
	local text, err2 = C.Base64.Encode(flag .. packed)
	if not text then return nil, "base64: " .. tostring(err2) end
	Codec.stats.encoded = Codec.stats.encoded + 1
	return Codec.PROTO .. "|" .. t .. "|" .. text
end

-- version, type, body of a text, or nil plus a reason. Reads only the plain-text header.
function Codec.Header(text)
	if type(text) ~= "string" or text == "" then return nil, "size" end
	local version, t, body = match(text, "^(%d+)|([A-Z][A-Z0-9]*)|(.*)$")
	if not version then return nil, "shape" end
	return tonumber(version), t, body
end

-- Returns the message table, nil and the decoded size; or nil, a reason and the size. Never raises.
function Codec:Decode(text)
	local C = compat()
	if not C then return nil, "nocompat", 0 end
	local size = type(text) == "string" and #text or 0
	if type(text) ~= "string" or text == "" or #text > Codec.MAX_TEXT then return reject("size", size) end
	local version, t, body = Codec.Header(text)
	if not version then return reject(t, size) end
	if version < 1 then return reject("version", size) end
	if version > Codec.PROTO then
		Codec.newerSeen = true
		return reject("newer", size)
	end
	if not Codec.SCHEMA[t] then
		Codec.stats.unknown = Codec.stats.unknown + 1
		return reject("type", size)
	end
	if body == "" or #body > Codec.MAX_BODY or find(body, "[^A-Za-z0-9+/=]") then return reject("base64", size) end
	local raw = C.Base64.Decode(body)
	if type(raw) ~= "string" or raw == "" then return reject("base64", size) end
	local flag, packed = sub(raw, 1, 1), sub(raw, 2)
	if flag == Codec.FLAG_DEFLATE then
		packed = C.Compress.Inflate(packed)
		if type(packed) ~= "string" then return reject("inflate", size) end
	elseif flag ~= Codec.FLAG_RAW then
		return reject("flag", size)
	end
	size = math.max(size, #packed)
	if #packed == 0 or #packed > Codec.MAX_DECODED then return reject("size", size) end
	local msg = C.CBOR.Decode(packed)
	if type(msg) ~= "table" then return reject(msg == nil and "cbor" or "shape", size) end
	if not shallow(msg, Codec.MAX_DEPTH) then return reject("depth", size) end
	msg.v, msg.t = version, t
	local ok, reason = Codec:Validate(msg)
	if not ok then return reject(reason, size) end
	Codec.stats.decoded = Codec.stats.decoded + 1
	return msg, nil, size
end

-- One-shot: true the first time after a newer version was seen, then false until another one arrives.
function Codec:ConsumeNewer()
	local seen = Codec.newerSeen
	Codec.newerSeen = false
	return seen
end

function Codec:DebugLines()
	local s = Codec.stats
	return { ("Codec: proto %d, encoded %d, decoded %d, rejected %d (unknown type %d, last: %s), newer seen: %s"):format(
		Codec.PROTO, s.encoded, s.decoded, s.rejected, s.unknown, Codec.lastReject or "-", Codec.newerSeen and "yes" or "no") }
end

if ns.addon then
	ns.addon.Codec = Codec
	if ns.addon.AddDebugSection then ns.addon:AddDebugSection("Codec", function() return Codec:DebugLines() end) end
end
