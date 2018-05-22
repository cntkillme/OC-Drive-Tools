--- Open Computers Drive Tools - Partition Manager Framework

local component = component or require("component")
local framework = {
	state = { }, -- partition table class
	partition = { -- partition entry class
		flags = { }, -- registered flags mapped as [bit]=name
		types = { } -- registered types mapped as [entry]=name
	},
	drive = { } -- drive class
}

--- helper functions (pack_int, unpack_int, check_int, check_range)
do
	function pack_int(val, size, signed)
		return ("<" .. (signed and "i" or "I") .. size):pack(val)
	end

	function unpack_int(str, signed)
		return ("<" .. (signed and "i" or "I") .. #str):unpack(str)
	end

	function check_int(val, size, signed)
		local min, max

		size = size or 8

		if signed then
			max = 2^(8*(size - 1))
			min = -max
		else
			max = 2^(8*size)
			min = 0
		end

		return check_range(val, min, max)
	end

	function check_range(val, min, max)
		val = tonumber(val)

		if val and val % 1 == 0 then
			if (not min or val >= min) and (not max or val < max) then
				return val
			else
				return nil, "value out of range"
			end
		else
			return nil, "value not an integer"
		end
	end
end

--- framework functions
do
	local flags = framework.partition.flags
	local types = framework.partition.types

	function framework.formatCapacity(capacity)
		local suffixes = { "B", "KiB", "MiB", "GiB", "TiB", "PiB" }
		local exponent = capacity ~= 0 and math.floor(math.log(capacity, 1024)) or 0

		return capacity/(1024^exponent), suffixes[exponent + 1]
	end

	function framework.registerFlag(name, bitIdx) -- keep bitIdx in [0, 16)
		assert(not flags[bitIdx], "flag by the given bit index already exists")
		flags[bitIdx] = name
	end

	function framework.registerType(name, entry) -- keep entry in [0, 2^16)
		assert(not types[entry], "type by the given entry already exists")
		types[entry] = name
	end

	function framework.getFlagName(bitIdx)
		return flags[bitIdx]
	end

	function framework.getTypeName(entry)
		return types[entry]
	end

	function framework.getFlags()
		local flags = { n = 0 }

		for i, bitIdx in pairs(flags) do
			table.insert(flags, bitIdx)
			flags.n = flags.n + 1
		end

		return flags
	end

	function framework.getTypes()
		local types = { n = 0 }

		for i, entry in pairs(types) do
			table.insert(types, entry)
			types.n = types.n + 1
		end

		return types
	end

	function framework.getDrives()
		local drives = { }
		for driveAddress in component.list("drive", true) do
			table.insert(drives, framework.drive.new(driveAddress))
		end

		return drives
	end
end

--- state class implementation
do
	local state = framework.state
	local metatable = { __index = state }

	function state.new()
		local ocpt = setmetatable({
			drive = nil,

			header = {
				signature = "OCPT",
				active_partitions = 0,
				last_boot_partition = 0,
				bios_partition = 0,
				bios_data = ""
			},

			partitions = { },
		}, metatable)

		for entry = 0, 31 do
			ocpt.partitions[entry] = framework.partition.new(entry, ocpt)
		end

		return ocpt
	end
	
	function state:reset()
		self.header = {
			signature = "OCPT",
			active_partitions = 0,
			last_boot_partition = 0,
			bios_partition = 0,
			bios_data = ""
		}
		
		for entry = 0, 31 do
			self.partitions[entry]:reset()
		end
	end

	function state:load(drive)
		local ocptChunk = drive:readSector(0)

		if ocptChunk:sub(1, 4) == "OCPT" then
			self.drive = drive
			self:decode(ocptChunk)

			return true
		else
			return false
		end
	end

	function state:save()
		self.drive:writeSector(0, self:encode())
	end

	function state:dump()
		return self:encode()
	end

	function state:analyze(errors, warnings, notes)
		local header = self.header
		local partitions = self.partitions

		-- check types
		assert(check_range(header.active_partitions, 0), "active partitions is not an unsigned integer")
		assert(check_range(header.last_boot_partition, 0), "last boot partition is not an unsigned integer")
		assert(check_range(header.bios_partition, 0), "BIOS partitions is not an unsigned integer")
		assert(type(header.bios_data) == "string", "BIOS data is not a string")

		if header.signature ~= "OCPT" then
			table.insert(errors, "bad signature.")
		end

		if not check_int(header.active_partitions, 4) then
			table.insert(warnings, "invalid active partitions, these will be ignored.")
		elseif header.active_partitions == 0 then
			table.insert(notes, "no active partitions.")
		end

		if not check_range(header.bios_partition, 0, 32) then
			table.insert(notes, "bad BIOS partition.")
		elseif not partitions[header.bios_partition]:isActive() then
			table.insert(warnings, "BIOS partition inactive.")
		else
			if not partitions[header.bios_partition]:hasFlag(0) then
				table.insert(warnings, "BIOS partition is not bootable.")
			end

			if partitions[header.bios_partition]:getType() ~= 0 then
				table.insert(warnings, "BIOS partition is not a raw partition.")
			end
		end

		if #header.bios_data > 118 then
			table.insert(warnings, "BIOS data too large, data passed position 112 will be dropped.")
		elseif #header.bios_data < 118 then
			table.insert(notes, "BIOS data too small, it will be padded with NULLs.")
		end

		for entry = 0, 31 do
			partitions[entry]:analyze(errors, warnings, notes)
		end

		for i = 0, 30 do
			for j = i + 1, 31 do
				if i ~= j then
					local partition1 = partitions[i]
					local partition2 = partitions[j]

					if partition1:isActive() and partition2:isActive() then
						if partition1:getFirstSector() > partition2:getFirstSector() then
							partition1, partition2 = partition2, partition1
						end

						if partition2:getFirstSector() < partition1:getFirstSector() + partition1:getNumSectors() then
							table.insert(errors, ("overlap between partition %d and partition %d."):format(i, j))
						end
					end
				end
			end
		end

		return errors, warnings, notes
	end

	function state:getDrive()
		return self.drive
	end

	function state:getPartition(entry)
		return self.partitions[entry]
	end

	function state:getSignature()
		return self.header.signature
	end

	function state:getActivePartitions()
		local partitions = { }
		local activePartitions = self.header.active_partitions

		for entry = 0, 31 do
			local partition = self.partitions[entry]

			if partition:isActive() then
				table.insert(partitions, partition)
			end
		end

		return partitions
	end

	function state:getLastBootPartition()
		return self.partitions[self.header.last_boot_partition]
	end

	function state:getBIOSPartition()
		return self.partitions[self.header.bios_partition]
	end

	function state:getBIOSData()
		return self.header.bios_data
	end

	function state:setBIOSPartition(entry)
		self.header.bios_partition = entry
	end

	function state:setBIOSData(data)
		self.header.bios_data = data
	end
	
	function state:setActivePartitions(activePartitions)
		self.header.active_partitions = activePartitions
	end

	function state:activePartitions()
		return self.header.active_partitions
	end
	
	function state:lastBootPartition()
		return self.header.last_boot_partition
	end

	function state:biosPartition()
		return self.header.bios_partition
	end

	function state:encode()
		local header = self.header
		local partitions = self.partitions
		local buffer = {
			header.signature:sub(1, 4) .. ("\0"):rep(4 - #header.signature),
			pack_int(header.active_partitions & 0xFFFFFFFF, 4),
			pack_int(header.last_boot_partition & 0xFF, 1),
			pack_int(header.bios_partition & 0xFF, 1),
			header.bios_data:sub(1, 118) .. ("\0"):rep(118 - #header.bios_data)
		}

		for entry = 0, 31 do
			table.insert(buffer, partitions[entry]:encode())
		end

		return table.concat(buffer)
	end

	function state:decode(ocptChunk)
		local header = self.header
		local partitions = self.partitions

		header.signature = ocptChunk:sub(1, 4)
		header.active_partitions = unpack_int(ocptChunk:sub(5, 8))
		header.last_boot_partition = unpack_int(ocptChunk:sub(9, 9))
		header.bios_partition = unpack_int(ocptChunk:sub(10, 10))
		header.bios_data = ocptChunk:sub(11, 128)

		for entry = 0, 31 do
			local entryOffset = 128 + entry*12
			local ocpe = ocptChunk:sub(entryOffset + 1, entryOffset + 12)

			partitions[entry]:decode(ocpe)
		end
	end
end

--- partition class implementation
do
	local partition = framework.partition
	local metatable = { __index = partition }

	function partition.new(entry, ocpt)
		return setmetatable({
			ocpt = ocpt,
			entry = entry,
			first_sector = 0,
			num_sectors = 0,
			flags = 0,
			type = 0
		}, metatable)
	end

	function partition:reset()
		self.first_sector = 0
		self.num_sectors = 0
		self.flags = 0
		self.type = 0
	end

	function partition:isActive()
		return (self.ocpt:activePartitions() >> self.entry)&1 == 1
	end

	function partition:getOCPT()
		return self.ocpt
	end

	function partition:getEntry()
		return self.entry
	end

	function partition:getFirstSector()
		return self.first_sector
	end

	function partition:getNumSectors()
		return self.num_sectors
	end

	function partition:getSectorRange()
		return self.first_sector, self.first_sector + self.num_sectors
	end

	function partition:getFlags()
		return self.flags
	end

	function partition:hasFlag(bit)
		return (self.flags >> bit)&1 == 1
	end

	function partition:getType()
		return self.type
	end

	function partition:activate()
		self.ocpt:setActivePartitions(self.ocpt:activePartitions() | (1 << self.entry))
	end

	function partition:deactivate()
		self.ocpt:setActivePartitions(self.ocpt:activePartitions() & ~(1 << self.entry))
	end

	function partition:setFirstSector(firstSector)
		self.first_sector = firstSector
	end

	function partition:setNumSectors(numSectors)
		self.num_sectors = numSectors
	end

	function partition:setFlags(flags)
		self.flags = flags
	end

	function partition:setFlag(bit)
		self.flags = self.flags | (1 << bit)
	end

	function partition:clearFlag(bit)
		self.flags = self.flags & ~(1 << bit)
	end

	function partition:toggleFlag(bit)
		self.flags = self.flags ~ (1 << bit)
	end

	function partition:clearFlags()
		self.flags = 0
	end

	function partition:setType(type)
		self.type = type
	end

	function partition:analyze(errors, warnings, notes)
		-- check types
		assert(check_range(self.entry, 0), "entry is not an unsigned integer")
		assert(check_range(self.first_sector, 0), "first sector is not an unsigned integer")
		assert(check_range(self.num_sectors, 0), "num sectors is not an unsigned integer")
		assert(check_range(self.flags, 0), "flags is not an unsigned integer")
		assert(check_range(self.type, 0), "type is not an unsigned integer")
		
		-- check partition number
		if not check_range(self.entry, 0, 32) then
			table.insert(errors, ("bad partition number (%d)."):format(self.entry))
		end

		if self:isActive() then
			-- check first sector
			if not check_range(self.first_sector, 1, self.ocpt:getDrive():getSectors()) then
				table.insert(errors, ("partition %d: first sector out of range."):format(self.entry))
			-- check last sector
			elseif not check_range(self.first_sector + self.num_sectors, self.first_sector, self.ocpt:getDrive():getSectors()) then
				table.insert(errors, ("partition %d: partition too large."):format(self.entry))
			end

			-- check unstorable flags
			if not check_int(self.flags, 2) then
				table.insert(warnings, ("partition %d: contains unstorable flags and will be ignored."):format(self.entry))
			end

			-- check non-standard flags
			for bit = 0, 15 do
				local set = self:hasFlag(bit)

				if set and not partition.flags[bit] then
					table.insert(notes, ("partition %d: non-standard flag (%d) set."):format(self.entry, bit))
				end
			end

			-- check type
			local storedType = self.type & 0xFFFF

			if not check_int(self.type, 2) then
				table.insert(warning, ("partition %d: unstorable type, assumed %d"):format(self.entry, storedType))
			end

			-- check non-standard type
			if not partition.types[storedType] then
				table.insert(notes, ("partition %d: non-standard type %d"):format(self.entry, storedType))
			end
		end
	end

	function partition:encode()
		local buffer = {
			pack_int(self.first_sector & 0xFFFFFFFF, 4),
			pack_int(self.num_sectors & 0xFFFFFFFF, 4),
			pack_int(self.flags & 0xFFFF, 2),
			pack_int(self.type & 0xFFFF, 2)
		}

		return table.concat(buffer)
	end

	function partition:decode(ocpe)
		self.first_sector = unpack_int(ocpe:sub(1, 4))
		self.num_sectors = unpack_int(ocpe:sub(5, 8))
		self.flags = unpack_int(ocpe:sub(9, 10))
		self.type = unpack_int(ocpe:sub(11, 12))
	end
end

--- drive class implementation
do
	local drive = framework.drive
	local metatable = { __index = drive }

	function drive.new(driveAddress)
		local proxy = drive.getDrive(driveAddress)
		local capacity = proxy.getCapacity()

		return setmetatable({
			address = proxy.address,
			proxy = proxy,
			capacity = capacity,
			sectors = capacity // 512
		}, metatable)
	end

	function drive.getDrive(address)
		local proxy = component.proxy(assert(component.get(address)))
		assert(proxy.type == "drive", "component is not a drive")

		return proxy
	end

	function drive:makeOCPT()
		self:writeSector(0, "OCPT" .. ("\0"):rep(512 - 4))
	end

	function drive:isAvailable()
		return component.get(self.address) ~= nil
	end

	function drive:isOCPT()
		return self.proxy.readSector(1):sub(1, 4) == "OCPT"
	end

	function drive:getAddress()
		return self.address
	end

	function drive:getProxy()
		return self.proxy
	end

	function drive:getCapacity()
		return self.capacity
	end

	function drive:getSectors()
		return self.sectors
	end
	
	function drive:getLabel()
		return self.proxy.getLabel()
	end

	function drive:setLabel(label)
		self.proxy.setLabel(label)
	end

	function drive:resolveSector(sector)
		if sector < 0 then
			sector = sector + self.sectors
		end

		return math.max(0, sector)
	end

	function drive:resolveCount(sector, count)
		return math.max(0, math.min(count, self.sectors - self:resolveSector(sector)))
	end

	function drive:readSector(sector)
		return self.proxy.readSector(self:resolveSector(sector) + 1)
	end

	function drive:readSectors(sector, count)
		sector = self:resolveSector(sector)
		count = count or self.sectors

		local n = self:resolveCount(sector, count)
		local read = { n = 0 }

		for i = 0, n - 1 do
			table.insert(read, self.proxy.readSector(sector + i + 1))
		end

		return read
	end

	function drive:writeSector(sector, buffer)
		self.proxy.writeSector(self:resolveSector(sector) + 1, buffer)
	end

	function drive:writeSectors(sector, buffer, fill, count)
		sector = self:resolveSector(sector)
		fill = fill or ""
		count = count or self.sectors

		local size = math.ceil(#buffer/512)
		local n = self:resolveCount(sector, math.min(count, size))
		
		for i = 0, n - 1 do
			local u = sector + i
			local p = 512*i
			local data = buffer:sub(p + 1, p + 512)

			if #data == 512 then
				self.proxy.writeSector(u + 1, data)
			else
				local fillBuff = #fill > 0 and fill:rep(math.ceil((512-#data)/#fill)) or ""
				self.proxy.writeSector(u + 1, data .. fillBuff)
			end
		end

		return n
	end
	
	function drive:moveSector(other, src, dest)
		src = self:resolveSector(src)
		dest = other:resolveSector(dest)

		other.proxy.writeSector(dest + 1, self.proxy.readSector(src + 1))
	end

	function drive:moveSectors(other, src, dest, count)
		src = self:resolveSector(src)
		dest = other:resolveSector(dest)
		count = count or self.sectors
		
		local n = math.min(self:resolveCount(src, count), other:resolveCount(dest, count))

		for i = 0, n - 1 do
			other.proxy.writeSector(dest + i + 1, self.proxy.readSector(src + i + 1))
		end

		return n
	end

	function drive:fillSector(sector, fill)
		sector = self:resolveSector(sector)
		fill = fill or "\0"

		if #fill > 0 then
			self:writeSector(sector, fill:rep(math.ceil(512/#fill)))
		end
	end

	function drive:fillSectors(sector, fill, count)
		sector = self:resolveSector(sector)
		fill = fill or "\0"
		count = count or self.sectors

		local n = self:resolveCount(sector, count)
		local buff = fill:rep(512/#fill)

		for i = 0, n - 1 do
			local fillBuff = #fill > 0 and fill:rep(math.ceil(512/#fill)) or ""
			self.proxy.writeSector(sector + i + 1, fillBuff)
		end

		return n
	end
end

--- initialize partition flags
framework.registerFlag("bootable", 0)
framework.registerFlag("hidden", 1)
framework.registerFlag("readonly", 2)

--- initialize partition types
framework.registerType("raw", 0)
framework.registerType("swap", 1)
framework.registerType("bfs", 2)

return framework
