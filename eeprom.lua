--- Open Computers Drive Tools - Drive Editor Script
-- The BIOS partition must be a bootable and raw partition for the standard EEPROM to boot from it.
-- If no active or valid BIOS partition is given, the first possible bootable, raw partition will be executed.

local bootProc

do
	local eeprom = component.proxy(component.list("eeprom", true)())
	local bootAddress, bootEntry

	local function unpack_int(str)
		return string.unpack("<I" .. #str, str)
	end

	local function try_partition(ocpt, entry)
		if entry < 32 then
			local offset = 128 + entry*12
			local ocpe = ocpt:sub(offset + 1, offset + 12)
			local flags = unpack_int(ocpe:sub(9, 10))
			local type = unpack_int(ocpe:sub(11, 12))

			if flags&1 == 1 and type == 0 then -- bootable + raw
				return ocpe
			end
		end
	end

	local function try_boot(address)
		local proxy = component.proxy(address)

		if proxy and proxy.type == "drive" then
			local ocpt = proxy.readSector(1)

			if ocpt:sub(1, 4) == "OCPT" then
				local activePartitions = unpack_int(ocpt:sub(5, 8))
				local biosPartition = unpack_int(ocpt:sub(9, 12))
				local bootPartition

				if (activePartitions >> biosPartition)&1 == 1 then
					bootPartition = try_partition(ocpt, biosPartition)
					bootEntry = biosPartition
				end

				if not bootPartition then
					for entry = 0, 31 do
						if entry ~= biosPartition and (activePartitions >> entry)&1 == 1 then
							bootPartition = try_partition(ocpt, entry)

							if bootPartition then
								bootEntry = entry
								break
							end
						end
					end
				end

				if bootPartition then
					local firstSector = unpack_int(bootPartition:sub(1, 4))
					local numSectors = unpack_int(bootPartition:sub(5, 8))
					local buffer = { }

					for sector = firstSector, firstSector + numSectors - 1 do
						table.insert(buffer, proxy.readSector(sector + 1))
					end

					return true, table.concat(buffer)
				end
			end
		end

		return false
	end

	-- attempt to boot
	bootAddress = eeprom.getData() or ""

	local valid, buffer

	-- boot from boot address
	if #bootAddress > 0 then
		valid, buffer = try_boot(bootAddress)
	end

	-- boot from anything
	if not valid then
		for address in component.list("drive", true) do
			if address ~= bootAddress then
				valid, buffer = try_boot(address)

				if valid then
					eeprom.setData(address)
					bootAddress = address
					break
				end
			end
		end
	end

	if valid then
		local proc, err = load(buffer, "=boot")
		if proc then
			__boot__ = proc
		else
			error(("boot error on %s partition %d: %s"):format(bootAddress, bootEntry, err))
		end
	else
		error("no bootable OCPT drive found!")
	end
end

__boot__()