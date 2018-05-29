--- Open Computers Drive Tools - BIOS
-- State 0: failure, continue in command-mode (result is some boot error)
-- State 1: failure, exit (result is machine error)
-- State 2: success, execute bootcode (result is the bootcode)

local insert, concat = table.insert, table.concat
local list, proxy = component.list, component.proxy

local eeprom = proxy(list("eeprom", true)())
local state, result

local function pack_int(val, size)
	return ("<I" .. size):pack(val)
end

local function unpack_int(str)
	return ("<I" .. #str):unpack(str)
end

local function encode_address(addr)
	local bytes = { }
	local iter = addr:gmatch("[0-9a-f][0-9a-f]")

	for i = 1, 16 do
		insert(bytes, string.char(tonumber(iter(), 16)))
	end

	return concat(bytes)
end

local function decode_address(str)
	local address = { }

	for i = 1, 16 do
		insert(address, ("%.2x"):format(str:byte(i)))

		if i >= 4 and i <= 10 and i % 2 == 0 then
			insert(address, "-") -- 4-2-2-2-6
		end
	end

	return concat(address)
end

local function get_address(address)
	for drive in list("drive", true) do
		if drive:sub(1, #address) == address then
			return drive
		end
	end
end

do
	local data = eeprom.getData()
	local mode = unpack_int(data:sub(21, 24))

	if mode == 2 then
		state = 0
	elseif mode == 0 or mode == 1 then -- standard boot
		local address = decode_address(data:sub(1, 16))
		local partition = unpack_int(data:sub(17, 20))
		local proxy = proxy(address)

		if proxy and proxy.type == "drive" then
			local ocpt = proxy.readSector(1)

			if ocpt:sub(1, 4) == "OCPT" then
				local entry = unpack_int(ocpt:sub(5, 8))
				if (partitions >> entry)&1 == 1 then
					local offset = 128 + entry*12
					local ocpe = ocpt:sub(offset + 1, offset + 12)

					if entry < 32 and unpack_int(ocpe:sub(11, 12)) == 0 and unpack_int(ocpe:sub(9, 10))&1 == 1 then
						local firstSector = unpack_int(ocpe:sub(1, 4))
						local numSectors = unpack_int(ocpe:sub(5, 8))
						local chunk = { }

						for sector = 1, numSectors do
							insert(chunk, proxy.readSector(firstSector + sector))
						end

						state = 2
						result = concat(chunk)
					else
						result = "partition not bootable"
					end
				else
					result = "unknown partition"
				end
			else
				result = "no partition table"
			end
		else
			result = "drive unavailable"
		end

		if state ~= 2 then
			state = mode == 0 and 0 or 1
		end
	elseif mode == 3 or mode == 4 then
		local url = data:sub(24)
		local card = list("internet", true)()

		if card then
			card = proxy(card)

			local request, reason = card.request(url)

			if request then
				local chunk = { }

				while true do
					local data, reason = request.read()

					if not data then
						request.close()

						if reason then
							result = reason
						else
							state = 2
							result = concat(chunk)
						end

						break
					elseif #data > 0 then
						insert(chunk, data)
					else
						computer.pullSignal(0)
					end
				end
			else
				result = reason
			end
		else
			result = "no internet card"
		end

		if state ~= 2 then
			state = mode == 3 and 0 or 1
		end
	else
		state = 0
		result = "invalid boot mode"
	end
end

if state == 1 or not (list("gpu", true)() and list("screen", true)()) then
	error(result or "unknown error")
elseif state == 2 then
	assert(load(result, "=bios"))()
	return
end

do
	local data = eeprom.getData()
	local gpu = proxy(list("gpu", true)())
	local x, y = 1, 1
	local w, h

	gpu.bind(list("screen", true)(), true)
	gpu.setResolution(gpu.maxResolution())
	w, h = gpu.getResolution()

	local function scroll()
		gpu.copy(1, 4, w, h - 3, 0, -1)
		gpu.fill(1, h, w, 1, " ")
	end

	local function line()
		x = 1
		y = y + 1

		while y >= h do
			scroll()
			y = y - 1
		end
	end

	local function put(str)
		local max, len

		if x > w then
			max = w
			line()
		else
			max = w - x + 1
		end

		len = unicode.len(str)

		if len > max then
			local part = unicode.wtrunc(str, max)
			str = unicode.sub(str, max + 1)
			gpu.set(x, y, part)
			line()
		elseif len > 0 then
			local part = unicode.sub(str, 1, len)
			str = unicode.sub(str, len + 1)
			gpu.set(x, y, part)
			x = x + len
		end

		return str
	end

	local function write(str)
		while #str > 0 do
			str = put(str)
		end
	end

	local function writeln(str)
		write(str)
		line()
	end

	local function back()
		if x == 1 then
			x = w
			y = y - 1
		else
			x = x - 1
		end

		gpu.set(x, y, " ")
	end

	local function read()
		local buffer = { }

		while true do
			local event, _, key = computer.pullSignal()

			if event == "key_down" then
				if key >= 0x20 then
					local data = unicode.char(key)
					write(data)
					insert(buffer, data)
				elseif key == 13 then
					line()
					return concat(buffer)
				elseif key == 8 and #buffer > 0 then
					table.remove(buffer)
					back()
				end
			end
		end
	end

	local function tokenize(str)
		local tokens = { }

		for tkn in str:gmatch("%S+") do
			insert(tokens, tkn)
		end

		return tokens
	end

	gpu.fill(1, 1, w, h, " ")
	writeln("OCDT BIOS - v1.0")
	writeln(("-"):rep(w))
	writeln(("Boot result: %s."):format(result or "none"))
	writeln("Enter ? to view commands.")

	while true do
		local input

		write(">")
		input = tokenize(read())

		if input[1] == "?" then
			writeln("?  Show commands.")
			writeln("a  Get/set boot address.")
			writeln("p  Get/set boot partition.")
			writeln("m  Get/set boot mode.")
			writeln("u  Get/set boot URL.")
			writeln("l  List drives.")
			writeln("x  Shutdown.")
		elseif input[1] == "a" then
			local addr = input[2]

			if not addr then
				writeln("usage: a [address]")
				writeln("Boot address: " .. decode_address(data:sub(1, 16)))
			else
				local address = get_address(addr)

				if address then
					data = encode_address(address) .. data:sub(17)
					eeprom.setData(data)
				else
					writeln("Failed.")
				end
			end
		elseif input[1] == "p" then
			local entry = input[2]

			if not entry then
				writeln("usage: p [partition]")
				writeln("Boot partition: " .. unpack_int(data:sub(17, 20)))
			else
				entry = tonumber(entry)

				if entry and entry >= 0 and entry < 31 and entry%1 == 0 then
					data = data:sub(1, 16) .. pack_int(entry, 4) .. data:sub(21)
					eeprom.setData(data)
				else
					writeln("Failed.")
				end
			end
		elseif input[1] == "m" then
			local mode = input[2]

			if not mode then
				writeln("usage: m [mode]")
				writeln("Boot mode: " .. unpack_int(data:sub(21, 24)))
			else
				mode = tonumber(mode)

				if mode and mode >= 0 and mode < 2^32 then
					data = data:sub(1, 20) .. pack_int(mode, 4) .. data:sub(25)
					eeprom.setData(data)
				else
					writeln("Failed.")
				end
			end
		elseif input[1] == "u" then
			local url = input[2]

			if not url then
				writeln("usage: u [url]")
				writeln("Boot URL: " .. data:sub(25))
			else
				data = data:sub(1, 24) .. url
				eeprom.setData(data)
			end
		elseif input[1] == "l" then
			local iter = list("drive", true)

			for drive in iter do
				writeln("Drive: " .. drive)
			end
		elseif input[1] == "x" then
			computer.shutdown()
		elseif input[1] then
			writeln("Bad command.")
		end
	end
end
