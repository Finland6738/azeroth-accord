-- Hash: SHA-256 (FIPS 180-4) and HMAC-SHA-256 (RFC 2104) in pure Lua 5.1 with the client's `bit` library
-- (SPEC-01 §3). Used for the pseudonyms of the likes (ADR 0007) and the short digests of the sync (SPEC-02 §4).
-- Checked against the standard test vectors (FIPS 180-2 examples, RFC 4231) in Tests/test_hash.lua.
--
-- Numbers: `bit` returns signed 32-bit results; sums are taken modulo 2^32 with plain arithmetic, which also turns a
-- signed value back into its unsigned form, so every word kept between steps is in 0 .. 2^32-1.
local ADDON_NAME, ns = ...
ns = ns or {}
local Hash = {}
ns.Hash, ns.modules = Hash, ns.modules or {}
ns.modules.Hash = Hash

local type, tostring = type, tostring
local floor = math.floor
local byte, char, rep, format, sub = string.byte, string.char, string.rep, string.format, string.sub
local concat = table.concat

local MOD = 4294967296

local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
local H0 = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

-- The bit library is read when hashing (not at load time), so a client without it fails one call, not the addon.
local function lib()
	local b = _G.bit
	if type(b) ~= "table" or type(b.bxor) ~= "function" or type(b.ror) ~= "function" then return nil end
	return b
end

-- The 64-byte blocks of `msg` after the standard padding: 0x80, zeros, the length in bits as 8 bytes big-endian.
local function pad(msg)
	local len = #msg
	local zeros = (55 - len) % 64
	local bits = len * 8
	local high, low = floor(bits / MOD), bits % MOD
	local lenBytes = char(floor(high / 16777216) % 256, floor(high / 65536) % 256, floor(high / 256) % 256, high % 256,
		floor(low / 16777216) % 256, floor(low / 65536) % 256, floor(low / 256) % 256, low % 256)
	return msg .. "\128" .. rep("\0", zeros) .. lenBytes
end

local function compress(b, H, block, w)
	local band, bxor, bnot, rshift, ror = b.band, b.bxor, b.bnot, b.rshift, b.ror
	for i = 1, 16 do
		local p = (i - 1) * 4 + 1
		local b1, b2, b3, b4 = byte(block, p, p + 3)
		w[i] = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
	end
	for i = 17, 64 do
		local v15, v2 = w[i - 15], w[i - 2]
		local s0 = bxor(ror(v15, 7), ror(v15, 18), rshift(v15, 3))
		local s1 = bxor(ror(v2, 17), ror(v2, 19), rshift(v2, 10))
		w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % MOD
	end
	local a, bb, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
	for i = 1, 64 do
		local S1 = bxor(ror(e, 6), ror(e, 11), ror(e, 25))
		local ch = bxor(band(e, f), band(bnot(e), g))
		local t1 = (h + S1 + ch + K[i] + w[i]) % MOD
		local S0 = bxor(ror(a, 2), ror(a, 13), ror(a, 22))
		local maj = bxor(band(a, bb), band(a, c), band(bb, c))
		local t2 = (S0 + maj) % MOD
		h, g, f, e, d, c, bb, a = g, f, e, (d + t1) % MOD, c, bb, a, (t1 + t2) % MOD
	end
	H[1], H[2], H[3], H[4] = (H[1] + a) % MOD, (H[2] + bb) % MOD, (H[3] + c) % MOD, (H[4] + d) % MOD
	H[5], H[6], H[7], H[8] = (H[5] + e) % MOD, (H[6] + f) % MOD, (H[7] + g) % MOD, (H[8] + h) % MOD
end

-- The 32-byte SHA-256 digest of the string `msg`, or nil and a reason when the client has no `bit` library.
function Hash.SHA256(msg)
	if type(msg) ~= "string" then msg = tostring(msg) end
	local b = lib()
	if not b then return nil, "no bit library" end
	local H = { H0[1], H0[2], H0[3], H0[4], H0[5], H0[6], H0[7], H0[8] }
	local w = {}
	local data = pad(msg)
	for p = 1, #data, 64 do compress(b, H, sub(data, p, p + 63), w) end
	local out = {}
	for i = 1, 8 do
		local v = H[i]
		out[i] = char(floor(v / 16777216) % 256, floor(v / 65536) % 256, floor(v / 256) % 256, v % 256)
	end
	return concat(out)
end

-- Lower-case hexadecimal of a byte string.
function Hash.ToHex(bytes)
	return (bytes:gsub(".", function(c) return format("%02x", byte(c)) end))
end

function Hash.SHA256Hex(msg)
	local digest, err = Hash.SHA256(msg)
	if not digest then return nil, err end
	return Hash.ToHex(digest)
end

local function xorPad(key, value)
	local out = {}
	for i = 1, 64 do out[i] = char(_G.bit.bxor(byte(key, i), value) % 256) end
	return concat(out)
end

-- HMAC-SHA-256 of `msg` under `key` (both strings): the 32-byte tag, or nil and a reason.
function Hash.HMAC(key, msg)
	if type(key) ~= "string" then key = tostring(key) end
	if type(msg) ~= "string" then msg = tostring(msg) end
	if not lib() then return nil, "no bit library" end
	if #key > 64 then key = Hash.SHA256(key) end
	key = key .. rep("\0", 64 - #key)
	local inner = Hash.SHA256(xorPad(key, 0x36) .. msg)
	return Hash.SHA256(xorPad(key, 0x5c) .. inner)
end

function Hash.HMACHex(key, msg)
	local tag, err = Hash.HMAC(key, msg)
	if not tag then return nil, err end
	return Hash.ToHex(tag)
end

-- A short digest for the sync (SPEC-02 §4): the first `n` hex characters (default 8) of SHA-256(msg).
function Hash.Short(msg, n)
	local hex = Hash.SHA256Hex(msg)
	if not hex then return nil end
	return sub(hex, 1, n or 8)
end

if ns.addon then ns.addon.Hash = Hash end
