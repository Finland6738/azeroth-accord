-- Codec (M1.5): the wire format "<version>|<TYPE>|<Base64 body>" of SPEC-02 §2, round trips, compression, and every
-- way a received text can be malformed. Adapted from Azeroth Guild Finder (Tests/test_codec.lua), same owner,
-- GPL-3.0 (ADR 0018).
local function Codec() return AzerothAccord.Codec end

local function body(flag, tbl)
	return C_EncodingUtil.EncodeBase64(flag .. C_EncodingUtil.SerializeCBOR(tbl))
end

local SAMPLES = {
	HELLO = { av = "0.1.0", s = "\1\2\3\4\5\6\7\8\9\10\11" },
	DIGEST = { d = { accounts = "ffffffff" } },
	REQ = { s = "accounts", a = { "Player-1-A" } },
	REC = { s = "accounts", r = { { id = "x", author = "Player-1-A", rev = 3, time = 1767225600 } } },
	VOTE = { target = "Player-1-B" },
	LEDGER = { e = {} },
	SALT = { k = "s", s = { { b = "secret", at = 1767225600 } } },
}

describe("round trips", function()
	for t, fields in pairs(SAMPLES) do
		it("round trips " .. t, function()
			local text = Codec():Encode(t, fields)
			notNil(text)
			eq(text:sub(1, #t + 3), "1|" .. t .. "|")
			local msg = Codec():Decode(text)
			eq(msg.v, 1)
			eq(msg.t, t)
			for k, v in pairs(fields) do deepEq(msg[k], v) end
		end)
	end

	it("covers every type of SPEC-02 §2", function()
		for _, t in ipairs({ "HELLO", "DIGEST", "REQ", "REC", "VOTE", "LEDGER", "SALT" }) do notNil(Codec().SCHEMA[t], t) end
	end)

	it("sends short messages raw and long ones compressed", function()
		local short = Codec():Encode("REQ", { s = "accounts" })
		local _, _, b = Codec().Header(short)
		eq(C_EncodingUtil.DecodeBase64(b):sub(1, 1), "\0")
		local recs = {}
		for i = 1, 40 do recs[i] = { id = "rec" .. i, author = "Player-1-AAAA", rev = i, time = 1767225600 } end
		local long = Codec():Encode("REC", { s = "accounts", r = recs })
		local _, _, b2 = Codec().Header(long)
		eq(C_EncodingUtil.DecodeBase64(b2):sub(1, 1), "\1")
		eq(#Codec():Decode(long).r, 40)
	end)

	it("is ASCII-safe and has no separator after the header", function()
		local text = Codec():Encode("REC", { s = "x", r = { { note = "a|b\0c" } } })
		matches(text, "^1|REC|[A-Za-z0-9+/=]+$")
	end)

	it("does not modify the fields it is given", function()
		local fields = { s = "accounts", r = { 1 } }
		Codec():Encode("REC", fields)
		deepEq(fields, { s = "accounts", r = { 1 } })
	end)

	it("lets a module register its own type", function()
		truthy(Codec():RegisterType("PING", { n = "number" }))
		falsy(Codec():RegisterType("bad type"))
		eq(Codec():Decode(Codec():Encode("PING", { n = 4 })).n, 4)
		isNil(Codec():Encode("PING", {}))
	end)
end)

describe("encode errors", function()
	it("refuses unknown types and missing required fields", function()
		local text, why = Codec():Encode("WHAT", {})
		isNil(text); eq(why, "type")
		text, why = Codec():Encode("REC", { s = "x" })
		isNil(text); eq(why, "invalid")
		text, why = Codec():Encode("REC", "nope")
		isNil(text); eq(why, "shape")
	end)

	it("refuses a message a receiver would reject for its size", function()
		local big = {}
		for i = 1, 3000 do big[i] = ("%08d"):format(i) end
		local text, why = Codec():Encode("REC", { s = "x", r = big })
		isNil(text); eq(why, "size")
	end)
end)

describe("malformed input", function()
	local function decode(text) return select(2, Codec():Decode(text)) end

	it("rejects non-strings, empty and oversized texts", function()
		eq(decode(nil), "size")
		eq(decode(""), "size")
		eq(decode(("A"):rep(Codec().MAX_TEXT + 1)), "size")
	end)

	it("rejects a text without the header", function()
		eq(decode("hello"), "shape")
		eq(decode("1|rec|AAAA"), "shape")
		eq(decode("x|REC|AAAA"), "shape")
	end)

	it("ignores a newer version and an unknown type (NET-01)", function()
		eq(decode("2|REC|" .. body("\0", { s = "x", r = {} })), "newer")
		eq(decode("1|LATER|" .. body("\0", {})), "type")
		eq(decode("0|REC|" .. body("\0", { s = "x", r = {} })), "version")
		eq(Codec().stats.unknown, 1)
	end)

	it("rejects bad Base64, a bad flag and broken compression", function()
		eq(decode("1|REC|###"), "base64")
		eq(decode("1|REC|"), "base64")
		eq(decode("1|REC|" .. body("\9", { s = "x", r = {} })), "flag")
		eq(decode("1|REC|" .. C_EncodingUtil.EncodeBase64("\1not deflate")), "inflate")
	end)

	it("rejects broken or non-table CBOR and missing required fields", function()
		eq(decode("1|REC|" .. C_EncodingUtil.EncodeBase64("\0\255\255")), "cbor")
		eq(decode("1|REC|" .. C_EncodingUtil.EncodeBase64("\0" .. C_EncodingUtil.SerializeCBOR("text"))), "shape")
		eq(decode("1|REC|" .. body("\0", { s = "x" })), "invalid")
	end)

	it("survives random garbage", function()
		local seed = 7
		for _ = 1, 200 do
			local chars = {}
			for i = 1, 1 + seed % 60 do
				seed = (seed * 1103515245 + 12345) % 2147483648
				chars[i] = string.char(seed % 256)
			end
			local text = table.concat(chars)
			local ok = pcall(function() return Codec():Decode(text) end)
			truthy(ok)
			ok = pcall(function() return Codec():Decode("1|REC|" .. C_EncodingUtil.EncodeBase64(text)) end)
			truthy(ok)
		end
		eq(#Mock.errors, 0)
	end)

	it("flags a newer version once and counts rejections for /accord debug", function()
		Codec():Decode("3|HELLO|" .. body("\0", { s = "" }))
		truthy(Codec():ConsumeNewer())
		falsy(Codec():ConsumeNewer())
		contains(table.concat(Codec():DebugLines(), "\n"), "rejected 1")
	end)
end)
