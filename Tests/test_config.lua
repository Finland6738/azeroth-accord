-- Config (M1.4): defaults, the account token, validation, migrations, newer schema read-only, idempotent reload,
-- damaged data, sizes. Adapted from Azeroth Guild Finder (Tests/test_config.lua), same owner, GPL-3.0 (ADR 0018).
-- Saved data is set up in before_boot: the harness restores it before ADDON_LOADED, like the client.
local function config() return AzerothAccord.Config end
local function issuesText() return table.concat(config().issues, "\n") end
local function debugText()
	Mock.ClearOutput()
	Mock.Slash("/accord debug")
	return table.concat(Mock.PlainOutput(), "\n")
end

describe("defaults", function()
	it("creates both variables with schema 1 and every default", function()
		local C = config()
		eq(AzerothAccordDB.schemaVersion, 1)
		eq(AzerothAccordCharDB.schemaVersion, 1)
		eq(#C.issues, 0)
		deepEq(AzerothAccordDB.chars, {})
		deepEq(AzerothAccordDB.guilds, {})
		eq(C:Get("char.ui.lastView"), "roster")
		isNil(C:Get("char.ui.windowPos"))
		falsy(C:IsReadOnly())
	end)

	it("creates a 16-byte Base64 account token once and keeps it", function()
		local token = AzerothAccordDB.token
		matches(token, "^[A-Za-z0-9+/]+==$")
		eq(#token, 24)
		eq(config():Token(), token)
		Mock.Reload()
		eq(AzerothAccordDB.token, token)
	end)

	it("the pure-Lua Base64 matches the standard", function()
		local B = config().Base64
		eq(B(""), "")
		eq(B("f"), "Zg==")
		eq(B("fo"), "Zm8=")
		eq(B("foo"), "Zm9v")
		eq(B("foobar"), "Zm9vYmFy")
		eq(B(string.char(0, 255, 254)), "AP/+")
	end)

	it("two accounts logging in a moment apart get different tokens", function()
		local first = AzerothAccordDB.token
		T.boot(function(M) M.Advance(0.37) end)
		ne(AzerothAccordDB.token, first)
	end)

	it("the token cannot be changed through Set and is never printed", function()
		local ok, why = config():Set("account.token", "AAAAAAAAAAAAAAAAAAAAAA==")
		falsy(ok)
		eq(why, "protected")
		local text = debugText()
		contains(text, "Saved data")
		contains(text, "token set")
		falsy(text:find(AzerothAccordDB.token, 1, true))
	end)

	it("exposes the growth limits of SPEC-01 §4", function()
		local L = config().LIMITS
		eq(L.COPLAY_DAYS, 90)
		eq(L.BANK_LOG_DAYS, 365)
		eq(L.BANK_REQUEST_CLOSED_DAYS, 60)
	end)
end)

describe("merge", function()
	before_boot(function()
		AzerothAccordDB = { schemaVersion = 1, token = "AAECAwQFBgcICQoLDA0ODw==",
			guilds = { ["Realm/Guild"] = { a = 1 } }, settings = { keep = true } }
		AzerothAccordCharDB = { schemaVersion = 1, ui = { lastView = "bank" } }
	end)

	it("fills what is missing and never overwrites existing values", function()
		local C = config()
		eq(AzerothAccordDB.token, "AAECAwQFBgcICQoLDA0ODw==")
		eq(AzerothAccordDB.guilds["Realm/Guild"].a, 1)
		eq(AzerothAccordDB.settings.keep, true)
		eq(C:Get("char.ui.lastView"), "bank")
		deepEq(C:Get("char.ui.columns"), {})
		eq(#C.issues, 0)
	end)
end)

describe("validation", function()
	before_boot(function()
		AzerothAccordDB = { schemaVersion = 1, token = "not a token",
			guilds = { ["Realm/Good"] = {}, Bad = {}, ["Realm/Worse"] = 3, [4] = {} },
			chars = { Realm = { ["Player-1-A"] = {}, ["Player-1-B"] = "x" }, Other = 5 } }
		AzerothAccordCharDB = { schemaVersion = 1, ui = { lastView = "nowhere", windowPos = { point = "TOP", x = 1, y = 2 },
			windowSize = { w = 10, h = 10 }, columns = 7 } }
	end)

	it("resets bad values to their defaults and lists them", function()
		local C = config()
		eq(C:Get("char.ui.lastView"), "roster")
		eq(C:Get("char.ui.windowPos").point, "TOP", "a valid value is kept")
		isNil(C:Get("char.ui.windowSize"))
		deepEq(C:Get("char.ui.columns"), {})
		eq(#AzerothAccordDB.token, 24)
		contains(issuesText(), "account.token: replaced")
		contains(issuesText(), "char.ui.lastView")
		contains(issuesText(), "char.ui.windowSize")
		eq(#Mock.errors, 0)
	end)

	it("drops malformed guild and character entries", function()
		local guilds, chars = AzerothAccordDB.guilds, AzerothAccordDB.chars
		truthy(guilds["Realm/Good"])
		isNil(guilds.Bad, "a key without a realm")
		isNil(guilds["Realm/Worse"])
		isNil(guilds[4])
		truthy(chars.Realm["Player-1-A"])
		isNil(chars.Realm["Player-1-B"])
		isNil(chars.Other)
	end)

	it("shows the issues in /accord debug", function()
		local text = debugText()
		contains(text, "problem(s)")
		contains(text, "char.ui.lastView")
	end)

	it("Set validates, Get reads, unknown paths are refused", function()
		local C = config()
		truthy(C:Set("char.ui.lastView", "professions"))
		eq(AzerothAccordCharDB.ui.lastView, "professions")
		local ok, why = C:Set("char.ui.lastView", "elsewhere")
		falsy(ok)
		contains(why, "not an allowed value")
		falsy((C:Set("account.nothing", 1)))
		falsy((C:Set("account.schemaVersion", 9)))
		falsy((C:Set("char.ui.windowPos", { point = 1 })))
		truthy(C:Set("char.ui.windowPos", nil), "optional values accept nil")
		truthy(C:Set("char.ui.windowSize", { w = 800, h = 500 }))
		falsy((C:Set("char.ui.windowSize", { w = 800, h = 0 / 0 })), "NaN is refused")
		falsy((C:Set("char.ui.windowSize", { w = math.huge, h = 500 })), "infinity is refused")
	end)
end)

describe("damaged data", function()
	it("replaces a variable that is not a table", function()
		T.boot(function() AzerothAccordDB = "garbage"; AzerothAccordCharDB = 12 end)
		eq(type(AzerothAccordDB), "table")
		eq(AzerothAccordCharDB.schemaVersion, 1)
		contains(issuesText(), "not a table")
		eq(#Mock.errors, 0)
	end)

	it("treats a lost or damaged schemaVersion as 0 and migrates", function()
		T.boot(function()
			AzerothAccordDB = { guilds = { ["R/G"] = { kept = true } } }
			AzerothAccordCharDB = { schemaVersion = "two" }
		end)
		eq(config().loadedVersion.account, 0)
		eq(config().loadedVersion.char, 0)
		eq(AzerothAccordDB.schemaVersion, 1)
		eq(AzerothAccordCharDB.schemaVersion, 1)
		eq(AzerothAccordDB.guilds["R/G"].kept, true, "user data is kept")
		falsy(config():IsReadOnly())
	end)

	it("a negative or fractional version is damaged", function()
		T.boot(function() AzerothAccordDB = { schemaVersion = -3 }; AzerothAccordCharDB = { schemaVersion = 1.5 } end)
		eq(config().loadedVersion.account, 0)
		eq(config().loadedVersion.char, 0)
	end)

	it("clamps a future timestamp to now and resets a malformed one", function()
		local C = config()
		C.rules["account.settings.seenAt"] = { type = "timestamp", optional = true }
		C.rules["account.settings.lastAt"] = { type = "timestamp", optional = true }
		AzerothAccordDB.settings.seenAt = GetServerTime() + 99999
		AzerothAccordDB.settings.lastAt = -5
		C:Load()
		eq(AzerothAccordDB.settings.seenAt, GetServerTime())
		isNil(AzerothAccordDB.settings.lastAt)
		contains(issuesText(), "future time clamped")
	end)
end)

describe("migrations", function()
	it("runs the steps in order from the stored version", function()
		T.boot(function()
			AzerothAccordDB = { schemaVersion = 1, settings = { oldName = 7 } }
		end)
		local C = config()
		local calls = {}
		C.SCHEMA_VERSION = 3
		C.migrations.account[2] = function(db) calls[#calls + 1] = 2; db.settings.newName = db.settings.newName or db.settings.oldName; db.settings.oldName = nil end
		C.migrations.account[3] = function(db) calls[#calls + 1] = 3 end
		C:Load()
		deepEq(calls, { 2, 3 })
		eq(AzerothAccordDB.schemaVersion, 3)
		eq(AzerothAccordDB.settings.newName, 7)
		isNil(AzerothAccordDB.settings.oldName)
		falsy(C:IsReadOnly("account"))
		-- a second load changes nothing and runs no step
		C:Load()
		deepEq(calls, { 2, 3 })
		eq(AzerothAccordDB.settings.newName, 7)
	end)

	it("a failing step leaves the saved data untouched and goes read-only", function()
		T.boot(function() AzerothAccordDB = { schemaVersion = 1, settings = { flag = false } } end)
		local C = config()
		C.SCHEMA_VERSION = 2
		C.migrations.account[2] = function(db) db.settings.flag = true; error("boom") end
		C:Load()
		eq(AzerothAccordDB.schemaVersion, 1)
		eq(AzerothAccordDB.settings.flag, false)
		truthy(C:IsReadOnly("account"))
		contains(issuesText(), "migration")
		eq(#Mock.errors, 0)
	end)
end)

describe("newer schema", function()
	before_boot(function()
		AzerothAccordDB = { schemaVersion = 9, futureField = { keep = true }, guilds = { ["R/G"] = { x = 1 } } }
		AzerothAccordCharDB = { schemaVersion = 9, ui = { lastView = "future" } }
	end)

	it("is loaded read-only: the saved table is never rewritten", function()
		local C = config()
		truthy(C:IsReadOnly("account"))
		truthy(C:IsReadOnly("char"))
		eq(AzerothAccordDB.schemaVersion, 9)
		isNil(AzerothAccordDB.token, "the token is not added in place")
		eq(AzerothAccordCharDB.ui.lastView, "future", "not sanitized in place")
		contains(issuesText(), "newer")
	end)

	it("the addon works on a sanitized copy", function()
		local C = config()
		eq(C:Get("char.ui.lastView"), "roster")
		truthy(C.db.account.futureField.keep)
		ne(C.db.account, AzerothAccordDB)
		local ok, why = C:Set("char.ui.lastView", "bank")
		falsy(ok)
		eq(why, "read-only")
	end)

	it("survives a reload unchanged and is reported in /accord debug", function()
		Mock.Reload()
		eq(AzerothAccordDB.schemaVersion, 9)
		eq(AzerothAccordDB.futureField.keep, true)
		contains(debugText(), "READ-ONLY")
	end)
end)

describe("reload", function()
	it("is idempotent: a second round trip changes nothing", function()
		Mock.Reload()
		local first = Mock.savedText.AzerothAccordDB
		local firstChar = Mock.savedText.AzerothAccordCharDB
		Mock.Reload()
		eq(Mock.savedText.AzerothAccordDB, first)
		eq(Mock.savedText.AzerothAccordCharDB, firstChar)
		eq(#config().issues, 0)
	end)

	it("keeps values changed through Set", function()
		truthy(config():Set("char.ui.lastView", "reputation"))
		truthy(config():Set("char.ui.windowSize", { w = 900, h = 600 }))
		Mock.Reload()
		eq(config():Get("char.ui.lastView"), "reputation")
		eq(config():Get("char.ui.windowSize").w, 900)
	end)
end)

describe("sizes", function()
	it("estimates the saved size and shows it in /accord debug", function()
		local C = config()
		eq(C.EstimateSize("abc"), 5)
		truthy(C.EstimateSize({ a = 1, b = { "x" } }) > 10)
		local text = debugText()
		contains(text, "AzerothAccordDB: schema found 1, current 1, about ")
		contains(text, "KB")
	end)
end)
