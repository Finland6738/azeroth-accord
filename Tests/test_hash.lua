-- Hash (M1.5): SHA-256 against the FIPS 180-2 examples and padding boundaries, HMAC-SHA-256 against RFC 4231.
-- The expected values come from the standards (and were checked with Python's hashlib). The mock's `bit` library is
-- written with plain arithmetic, so these tests are slow-ish but exercise the same signed 32-bit results as the client.
local function H() return AzerothAccord.Hash end
local function bytes(...) return string.char(...) end
local function rangeBytes(from, to)
	local out = {}
	for i = from, to do out[#out + 1] = string.char(i) end
	return table.concat(out)
end

describe("SHA-256", function()
	local VECTORS = {
		{ "", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" },
		{ "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" },
		{ "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1" },
		{ "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
			"cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1" },
		{ "The quick brown fox jumps over the lazy dog", "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592" },
	}

	it("matches the standard examples", function()
		for _, v in ipairs(VECTORS) do eq(H().SHA256Hex(v[1]), v[2], v[1]) end
	end)

	it("pads correctly around the block boundaries", function()
		local BOUNDARIES = {
			[55] = "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
			[56] = "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
			[63] = "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34",
			[64] = "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
			[65] = "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0",
			[119] = "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb",
			[120] = "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c",
			[1000] = "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3",
		}
		for n, hex in pairs(BOUNDARIES) do eq(H().SHA256Hex(("a"):rep(n)), hex, n .. " bytes") end
	end)

	it("handles every byte value", function()
		eq(H().SHA256Hex(rangeBytes(0, 255)), "40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880")
	end)

	it("returns 32 raw bytes and a short digest for the sync", function()
		local d = H().SHA256("abc")
		eq(#d, 32)
		eq(d:byte(1), 0xba)
		eq(H().Short("abc"), "ba7816bf")
		eq(H().Short("abc", 4), "ba78")
		eq(H().ToHex(bytes(0, 15, 255)), "000fff")
	end)

	it("fails one call, never the addon, when the client has no bit library", function()
		bit = nil
		local d, err = H().SHA256("abc")
		isNil(d)
		contains(err, "bit")
		isNil(H().HMAC("k", "m"))
		isNil(H().Short("abc"))
	end)
end)

describe("HMAC-SHA-256 (RFC 4231)", function()
	it("test case 1: 20-byte key", function()
		eq(H().HMACHex(("\11"):rep(20), "Hi There"), "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
	end)

	it("test case 2: a key shorter than the output", function()
		eq(H().HMACHex("Jefe", "what do ya want for nothing?"), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
	end)

	it("test case 3: 50 bytes of data", function()
		eq(H().HMACHex(("\170"):rep(20), ("\221"):rep(50)), "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe")
	end)

	it("test case 4: a 25-byte key", function()
		eq(H().HMACHex(rangeBytes(1, 25), ("\205"):rep(50)), "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b")
	end)

	it("test case 6: a key larger than a block is hashed first", function()
		eq(H().HMACHex(("\170"):rep(131), "Test Using Larger Than Block-Size Key - Hash Key First"),
			"60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
	end)

	it("test case 7: large key and large data", function()
		eq(H().HMACHex(("\170"):rep(131), "This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm."),
			"9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2")
	end)

	it("a key of exactly one block is used as it is", function()
		eq(H().HMACHex(("\1"):rep(64), "exactly block size key"), "0f315fdbed79730cc8fc688308f38bc0f010a64d779a9bcf0df11cb0a46be67a")
	end)

	it("returns the 32-byte tag", function()
		eq(#H().HMAC("key", "message"), 32)
	end)
end)
