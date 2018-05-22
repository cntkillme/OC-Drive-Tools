--- Open Computers Drive Tools - Drive Class
--- drive class implementation
local component = component or require("component")
local drive = { }
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

return drive
