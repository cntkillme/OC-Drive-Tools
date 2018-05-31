--- Open Computers Drive Tools - Partition Manager Framework

local component = component or require("component")
local framework = {
	state = { }, -- partition table class
	partition = { -- partition entry class
		flags = { }, -- registered flags mapped as [bit]=name
		types = { } -- registered types mapped as [entry]=name
	},
	drive = require("drive") -- drive class
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
		
		for address in component.list("drive", true) do
			table.insert(drives, framework.drive.new(address))
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
				unused = "",
				active_partitions = 0
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
			unused = "",
			active_partitions = 0
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

		if header.signature ~= "OCPT" then
			table.insert(errors, "bad signature.")
		end

		if not check_int(header.active_partitions, 4) then
			table.insert(warnings, "invalid active partitions, these will be ignored.")
		elseif header.active_partitions == 0 then
			table.insert(notes, "no active partitions.")
		end

		if #header.unused > 120 then
			table.insert(warnings, "unused section too large, some data will be lost.")
		elseif #header.unused < 120 then
			table.insert(notes, "unused section too small, it will be padded with NULLs.")
		end

		for entry = 0, 31 do
			partitions[entry]:analyze(errors, warnings, notes)
		end

		for i = 0, 30 do
			for j = i + 1, 31 do
				local partition1 = partitions[i]
				local partition2 = partitions[j]

				if partition1:isActive() and partition2:isActive() then
					if partition1:getFirstSector() > partition2:getFirstSector() then
						partition1, partition2 = partition2, partition1
					end

					if partition2:getFirstSector() < partition1:getFirstSector() + partition1:getNumSectors() then
						table.insert(errors, ("partition %d: overlap with partition %d."):format(i, j))
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
	
	function state:setActivePartitions(activePartitions)
		self.header.active_partitions = activePartitions
	end

	function state:activePartitions()
		return self.header.active_partitions
	end

	function state:encode()
		local header = self.header
		local partitions = self.partitions
		local buffer = {
			header.signature:sub(1, 4) .. ("\0"):rep(4 - #header.signature),
			pack_int(header.active_partitions & 0xFFFFFFFF, 4),
			header.unused:sub(1, 120) .. ("\0"):rep(118 - #header.unused)
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
		header.unused = ocptChunk:sub(9, 128)

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
			elseif not check_range(self.first_sector + self.num_sectors - 1, self.first_sector, self.ocpt:getDrive():getSectors()) then
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
	
	function partition:getOCPT()
		return self.ocpt
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

--- initialize partition flags
framework.registerFlag("bootable", 0)
framework.registerFlag("hidden", 1)
framework.registerFlag("readonly", 2)

--- initialize partition types
framework.registerType("raw", 0)
framework.registerType("swap", 1)
framework.registerType("bfs", 2)

return framework
