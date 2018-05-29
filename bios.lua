--- Open Computers Drive Tools - BIOS
-- State 0: failure, continue in command-mode (result is some boot error)
-- State 1: failure, exit (result is machine error)
-- State 2: success, execute bootcode (result is the bootcode)

local eeprom = component.proxy(component.list("eeprom")())
local state, result

local function pack_int(val, size, signed)
	return ("<" .. (signed and "i" or "I") .. size):pack(val)
end

local function unpack_int(str, signed)
	return ("<" .. (signed and "i" or "I") .. #str):unpack(str)
end

local function encode_address(addr)
	local bytes = { }
	local iter = addr:gmatch("([0-9a-f][0-9a-f])")

	for i = 1, 16 do
		table.insert(bytes, string.char(tonumber(iter(), 16)))
	end

	return table.concat(bytes)
end

local function decode_address(str)
	local address = { }
	
	for i = 1, 16 do
		table.insert(address, ("%.2x"):format(str:byte(i)))

		if i >= 4 and i <= 10 and i % 2 == 0 then
			table.insert(address, "-") -- 4-2-2-2-6
		end
	end

	return table.concat(address)
end

local function is_bootable(ocpt, entry)
	local offset = 128 + entry*12
	local ocpe = ocpt:sub(offset + 1, offset + 12)
	
	if entry < 32 and unpack_int(ocpe:sub(11, 12)) == 0 and unpack_int(ocpe:sub(9, 10))&1 == 1 then
		return ocpe
	end

	return false
end

do
	local data = eeprom.getData()
	local mode = unpack_int(data:sub(21, 24))

	if mode == 2 then
		state = 0
	elseif mode == 0 or mode == 1 then -- standard boot
		local address = decode_address(data:sub(1, 16))
		local partition = unpack_int(data:sub(17, 20))
		local proxy = component.proxy(address)

		if proxy and proxy.type == "drive" then
			local ocpt = proxy.readSector(1)

			if ocpt:sub(1, 4) == "OCPT" then
				local partitions = unpack_int(ocpt:sub(5, 8))
				if (partitions >> partition)&1 == 1 then
					local ocpe = is_bootable(ocpt, partition)

					if ocpe then
						local firstSector = unpack_int(ocpe:sub(1, 4))
						local numSectors = unpack_int(ocpe:sub(5, 8))
						local chunk = { }

						for sector = firstSector, firstSector + numSectors - 1 do
							table.insert(chunk, proxy.readSector(sector + 1))
						end

						state = 2
						result = table.concat(chunk)
					else
						result = "boot partition is not bootable"
					end
				else
					result = "boot partition does not exist"
				end
			else
				result = "boot drive does not contain a partition table"
			end
		else
			result = "boot drive unavailable"
		end

		if state ~= 2 then
			state = mode == 0 and 0 or 1
		end
	elseif mode == 3 or mode == 4 then
		local url = data:sub(24)
		local card = component.list("internet")()

		if card then
			card = component.proxy(card)

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
							result = table.concat(chunk)
						end

						break
					elseif #data > 0 then
						table.insert(chunk, data)
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

if state == 1 then
	error(result or "unknown error")
elseif state == 2 then
	assert(load(result, "=bios"))()
end

-- command mode
error(result)