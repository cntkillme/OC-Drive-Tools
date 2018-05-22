--- Open Computers Drive Tools - Drive Editor Script

local partman = pcall(require, "partman") and require("partman") or dofile("lib/partman.lua")
local usage = [[Manages drives and partitions.
parted         Shows usage.
parted edit    Enters interactive mode.
parted list    Lists connected drives.
parted read    Reads sectors of a drive.
parted move    Copies sectors of a drive to another drive.
parted fill    Fills sectors of a drive with a repeated string from stdin.
parted dump    Dumps a range of sectors of a drive to a file.
parted load    Loads a range of sectors into a drive from a file.
parted ocpt    Make a drive an OCPT drive.
parted test    Make a test OCPT drive (hardcoded BIOS).]]

local edit_usage = [[Interactive Mode Commands
?    Show commands.
q    Quits interactive mode.
i    List drive information.
p    List drive partitions.
a    Analyze partition table.
z    Clear partition table.
b    Set BIOS partition.
c    Create partition.
r    Remove partition.
f    Toggle partition flag.
t    Edit partition type.
s    Configure partition start sector.
n    Configure partition size.
w    Write partition table.
x    Reload partition table.
cvt  Converts capacity to number of sectors.
]]

function main(args)
	local mode = args[1]
	local commands = { edit = edit, list = list, read = read, move = move, fill = fill, dump = dump, load = load, ocpt = ocpt, test = test }

	if mode then
		local proc = assert(commands[mode], "invalid usage, see `parted`")
		proc(table.unpack(args, 2, args.n))
	else
		print(usage)
	end
end

function edit(drive)
	if not drive then
		print("usage: parted edit <drive>")
		print("\tManages partitions of an OCPT drive.")
	else
		local state = partman.state.new()
		local drive = partman.drive.new(drive)
		local flags = { }
		local types = { }
		
		assert(state:load(drive), "not an OCPT drive")

		for i, bitIdx in pairs(partman.getFlags()) do
			table.insert(flags, ("%s (%d)"):format(partman.getFlagName(bitIdx), bitIdx))
		end

		for i, entry in pairs(partman.getTypes()) do
			table.insert(types, ("%s (%d)"):format(partman.getTypeName(entry), entry))
		end

		print("Parted - Interactive Mode")
		print("Enter ? to get help.")
		print()
		print(("Drive: %s%s"):format(drive:getAddress(), drive:getLabel() and " (" .. tostring(drive:getLabel()) .. ")" or ""))
		print()

		while not exit do
			local prompt, command

			io.write(">")
			prompt = io.read()

			if not prompt then
				break
			end

			prompt = tokenize(prompt)
			command = table.remove(prompt, 1)

			if command == "?" then
				print(edit_usage)
			elseif command == "q" then
				break
			elseif command == "i" then
				print(drive_info(drive))
			elseif command == "p" then
				local partitions = state:getActivePartitions()
				
				if #partitions > 0 then
					for i, partition in ipairs(partitions) do
						local startSector, endSector = partition:getSectorRange()
						local numSectors = partition:getNumSectors()
						local flags = partition:getFlags()
						local type = partition:getType()
						local capacity, suffix = partman.formatCapacity(numSectors * 512)
						local knownFlags = { }

						for flag = 0, 15 do
							if partition:hasFlag(flag) then
								table.insert(knownFlags, partman.getFlagName(flag))
							end
						end

						if #knownFlags == 0 then
							table.insert(knownFlags, "no known flags")
						end

						print(([[[ PARTITION %d ]
Sector Range: [%d, %d) (%d sectors)
    Capacity: %.1f%s (%d bytes)
       Flags: %s (0x%.4X)
        Type: %s (%d)]]):format(partition:getEntry(), startSector, endSector, numSectors, capacity, suffix, numSectors*512, table.concat(knownFlags, ", "), flags, partman.getTypeName(type) or "unknown", type))
					end
				else
					print("No partitions.")
				end
			elseif command == "a" then
				local errors, warnings, notes = { }, { }, { }
				state:analyze(errors, warnings, notes)

				if #errors > 0 then
					print("Errors:")
					
					for i, str in ipairs(errors) do
						print(i, str)
					end
				else
					print("No errors.")
				end

				if #warnings > 0 then
					print("Warnings:")
					
					for i, str in ipairs(warnings) do
						print(i, str)
					end
				else
					print("No warnings.")
				end

				if #notes > 0 then
					print("Notes:")
					
					for i, str in ipairs(notes) do
						print(i, str)
					end
				else
					print("No notes.")
				end
			elseif command == "z" then
				state:reset()
				print("Partition table cleared.")
			elseif command == "b" then
				local entry = prompt[1]

				if not entry then
					print("usage: b <partition>")
					print("\tChanging the BIOS partition to an entry greater than 31 will disable the BIOS.")
				else
					local success, error = pcall(function()
						local partition = state:getPartition(check_int("partition", entry, 0, 2^32))

						state:setBIOSPartition(partition:getEntry())
					end)

					if success then
						print("BIOS partition changed.")
					else
						print(error)
						print("Could not change BIOS partition.")
					end
				end
			elseif command == "c" then
				local entry, startSector, numSectors, type, flags = table.unpack(prompt, 1, 5)

				if not (entry and startSector and numSectors) then
					print("usage: c <partition> <startSector> <numSectors> [type=0]")
				else
					local success, error = pcall(function()
						local partition = state:getPartition(check_int("partition", entry, 0, 32))

						assert(not partition:isActive(), "partition already exists")
						startSector = drive:resolveSector(check_int("startSector", startSector))
						numSectors = check_int("numSectors", numSectors, 0)
						type = check_int("type", type or 0, 0, 2^16)
						assert(startSector > 0, "startSector must be greater than 0")

						partition:activate()
						partition:setFirstSector(startSector)
						partition:setNumSectors(numSectors)
						partition:setType(type)
						partition:setFlags(0)
					end)
					
					if success then
						print("Partition created.")
					else
						print(error)
						print("Could not create partition.")
					end
				end
			elseif command == "r" then
				local entry = prompt[1]

				if not entry then
					print("usage: r <partition>")
				else
					local success, error = pcall(function()
						local partition = state:getPartition(check_int("partition", entry, 0, 32))

						assert(partition:isActive(), "partition doesn't exist")
						partition:deactivate()
					end)

					if success then
						print("Partition removed.")
					else
						print(error)
						print("Could not remove partition.")
					end
				end
			elseif command == "f" then
				local entry, flag = prompt[1], prompt[2]

				if not (entry and flag) then
					print("usage: f <partition> <flag>")
					print("flags: " .. table.concat(flags, ", "))
				else
					local success, error = pcall(function()
						local partition = state:getPartition(check_int("partition", entry, 0, 32))

						assert(partition:isActive(), "partition does not exist")
						flag = check_int("flag", flag, 0, 16)
						partition:toggleFlag(flag)
					end)

					if success then
						print("Partition flag toggled.")
					else
						print(error)
						print("Could not toggle partition flag.")
					end
				end
			elseif command == "t" then
				local entry, newType = prompt[1], prompt[2]

				if not (entry and newType) then
					print("usage: t <partition> <type>")
					print("types: " .. table.concat(types, ", "))
				else
					local success, error = pcall(function()
						local partition = state:getPartition(check_int("partition", entry, 0, 32))

						assert(partition:isActive(), "partition does not exist")
						newType = check_int("type", newType, 0, 2^16)
						partition:setType(newType)
					end)

					if success then
						print("Partition type changed.")
					else
						print(error)
						print("Could not change partition type.")
					end
				end
			elseif command == "s" then
				local entry, startSector = prompt[1], prompt[2]

				if not (entry and startSector) then
					print("usage: s <partition> <startSector>")
				else
					local success, error = pcall(function()
						local partition = state:getPartition(check_int("partition", entry, 0, 32))

						assert(partition:isActive(), "partition does not exist")
						startSector = drive:resolveSector(check_int("startSector", startSector))
						assert(startSector > 0, "start sector must be greater than 0")

						partition:setFirstSector(startSector)
					end)

					if success then
						print("Partition start sector changed.")
					else
						print(error)
						print("Could not change partition start sector.")
					end
				end
			elseif command == "n" then
				local entry, numSectors = prompt[1], prompt[2]

				if not (entry and numSectors) then
					print("usage: n <partition> <numSectors>")
				else
					local success, error = pcall(function()
						local partition = state:getPartition(check_int("partition", entry, 0, 32))

						assert(partition:isActive(), "partition does not exist")
						numSectors = check_int("numSectors", numSectors, 0)
						
						partition:setNumSectors(numSectors)
					end)

					if success then
						print("Partition size changed.")
					else
						print(error)
						print("Could not change partition size.")
					end
				end
			elseif command == "w" then
				if confirm("It is highly recommended to analyze the partition table before writing to the disk if you have not already.\nAre you sure you would like to write the partition table?") then
					local errors, ignored = { }, { }
					state:analyze(errors, ignored, ignored)

					if #errors == 0 then
						state:save()
						state:load(drive)
						print("Done. To ensure integrity, please reload (x) and confirm the drive before use.")
					else
						print(("There are %d errors that must be fixed. Run the partition table analysis (a)."):format(#errors))
					end
				end
			elseif command == "x" then
				state:load(drive)
				print("Reloaded.")
			elseif command == "cvt" then
				local scale, suffix = prompt[1], prompt[2] or "B"

				if not scale then
					print("usage: cvt <scale> <suffix>")
					print("suffixes: B (bytes, default), KiB, MiB, GiB, TiB, PiB")
				else
					local exponent = 0

					suffix = suffix:lower()					
					if suffix == "kib" then exponent = 1
					elseif suffix == "mib" then exponent = 2
					elseif suffix == "gib" then exponent = 3
					elseif suffix == "tib" then exponent = 4
					elseif suffix == "pib" then exponent = 4
					end

					local sectors = math.floor((math.abs(tonumber(scale or 0)) * 1024^exponent)/512)
					local capacity, suffix = partman.formatCapacity(sectors * 512)

					print(("Sectors: %d (Capacity: %.1f%s = %d bytes)"):format(sectors, capacity, suffix, sectors * 512))
				end
			elseif command then
				print("Unknown command.")
			end
		end
	end
end

function list()
	local drives = partman.getDrives()

	if #drives == 0 then
		print("No drives.")
	else
		for i, drive in pairs(drives) do
			print(drive_info(drive))
		end
	end
end

function read(src, sector, n, cols, text)
	if not src then
		print("usage: parted read <src> [sector=0] [n=1] [cols=16]")
		print("\tDisplays n sectors from src:sector.")
	else
		local drive = partman.drive.new(src)

		sector = drive:resolveSector(check_int("sector", sector or 0, -drive:getSectors(), drive:getSectors()))
		n = drive:resolveCount(sector, check_int("n", n or 1, 0))
		cols = check_int("cols", cols or 16, 1, 256)

		for i = 0, n - 1 do
			local u = sector + i
			local data = drive:readSector(u)

			print(("[ SECTOR %d ]"):format(u))
			
			io.write("   |")
			for col = 0, cols - 1 do
				io.write((" %.2X"):format(col))
			end
			print()
			print("---|" .. ("-"):rep(cols*3))

			for row = 0, math.ceil(512/cols) - 1 do
				io.write(("%.2X |"):format(row))

				for j = 0, cols - 1 do
					local byte = data:byte(1 + row*cols + j)
					if byte then
						io.write((" %.2X"):format(byte))
					else
						break
					end
				end
				print()
			end
		end
	end
end

function move(src, dest, origin, target, n)
	if not (src and dest and origin and target) then
		print("usage: parted move <src> <dest> <origin> <target> [n=1]")
		print("\tCopies n sectors from src:origin to dest:target.")
	else
		local srcDrive = partman.drive.new(src)
		local destDrive = partman.drive.new(dest)

		origin = srcDrive:resolveSector(check_int("origin", origin, -srcDrive:getSectors(), srcDrive:getSectors()))
		target = destDrive:resolveSector(check_int("target", target, -destDrive:getSectors(), destDrive:getSectors()))
		n = check_int("n", n or 1, 0)

		if confirm(("Are you sure you would like to copy %d sectors from %s:%d to %s:%d?"):format(n, srcDrive:getAddress():sub(1, 8), origin, destDrive:getAddress():sub(1, 8), target)) then
			print("Copying sectors...")
			n = srcDrive:moveSectors(destDrive, origin, target, n)
			print(("%d sectors copied."):format(n))
		end
	end
end

function fill(drive, sector, n, str)
	if not (drive and sector) then
		print("usage: parted fill <drive> <sector> [n=1] [str='\\0']")
		print("\tFills n sectors with a repeated string from src:sector")
	else
		local drive = partman.drive.new(drive)

		str = tostring(str or "\0")
		sector = drive:resolveSector(check_int("sector", sector, -drive:getSectors(), drive:getSectors()))
		n = check_int("n", n or 1, 0)

		if confirm(("Are you sure you would like to fill %d sectors from %s:%d?"):format(n, drive:getAddress():sub(1, 8), sector)) then
			print("Filling sectors...")
			n = drive:fillSectors(sector, str, n)
			print(("%d sectors filled."):format(n))
		end
	end
end

function dump(drive, file, sector, n)
	if not (file and src) then
		print("usage: parted dump <drive> <file> [sector=0] [n=max]")
		print("\tDumps n sectors from drive:sector to a file.")
	else
		local drive = partman.drive.new(drive)

		file = tostring(file)
		sector = drive:resolveSector(check_int("sector", sector or 0, -drive:getSectors(), drive:getSectors()))
		n = drive:resolveCount(sector, check_int("n", n or drive:getSectors(), 0))

		if confirm(("Are you sure you would like to dump %d sectors from %s:%d to the end of the file?"):format(n, drive:getAddress():sub(1, 8), sector)) then
			file = assert(io.open(file, "ab"))

			print("Reading sectors...")

			for i = 0, n - 1 do
				file:write(drive:readSector(sector + i))
			end

			file:close()

			print(("%d sectors read."):format(n))
		end
	end	
end

function load(drive, file, sector, n, fill)
	if not (file and drive) then
		print("usage: parted load <drive> <file> [sector=0] [n=max] [fill='']")
		print("\tWrites at most n sectors to drive:sector from a file.")
		print("\tAny extra space in the last sector is filled when specified.")
	else
		local drive = partman.drive.new(drive)

		file = tostring(file)
		sector = drive:resolveSector(check_int("sector", sector or 0, -drive:getSectors(), drive:getSectors()))
		n = drive:resolveCount(sector, check_int("n", n or drive:getSectors(), 0))
		fill = tostring(fill or "")

		if confirm(("Are you sure you would like to load %d sectors from %q to %s:%d?"):format(n, file, drive:getAddress():sub(1, 8), sector)) then
			local written = 0

			file = assert(io.open(file, "rb"))
			print("Writing sectors...")

			for i = 0, n - 1 do
				local chunk = file:read(512)

				if chunk then
					if #chunk < 512 then
						drive:fillSector(sector + i, fill)
					end
					drive:writeSector(sector + i, chunk)
				else
					n = i
					break
				end
			end

			print(("%d sectors written."):format(n))
		end
	end
end

function ocpt(drive)
	if not drive then
		print("usage: parted ocpt <drive>")
		print("\tNULLs the first sector of the drive and writes the OCPT signature.")
	else
		local drive = partman.drive.new(drive)

		if confirm(("Are you sure you would like to make %s an OCPT drive?"):format(drive:getAddress():sub(1, 6))) then
			print("Writing partition table...")
			drive:makeOCPT()
			print("Done.")
		end
	end
end

function test(drive)
	if not drive then
		print("usage: parted test <drive>")
		print("\tWrites a predefined partition table and BIOS to the drive.")
	else
		local state = partman.state.new()
		local drive = partman.drive.new(drive)
		drive:makeOCPT()
		assert(state:load(drive), "unknown error")

		local biosPartition = state:getPartition(0)
		biosPartition:setFirstSector(1)
		biosPartition:setNumSectors(1)
		biosPartition:setFlag(0) -- bootable
		biosPartition:activate()

		local code = [[local gpu = component.proxy(component.list("gpu", true)())
local width, height
local a = 0
gpu.bind((component.list("screen", true)()))
gpu.set(1, 1, "OCPT Test BIOS")
width, height = gpu.getResolution()

while true do
	for y = 2, height do
		for x = 1, width do
			gpu.set(x, y, tostring((a+(x+y-2))%10))
		end
	end

	a = a + 1
end]]
		drive:writeSectors(1, code, " ")
		state:save()

		print("Done.")
	end
end

function drive_info(drive)
	local label = drive:getLabel() and " (" .. tostring(drive:getLabel()) .. ")" or ""
	local type = drive:isOCPT() and "ocpt drive" or "unknown"
	local capacity, suffix = partman.formatCapacity(drive:getCapacity())

	return(([[Drive: %s%s
	Capacity: %.1f%s (%d bytes)
	 Sectors: %d
	    Type: %s]]):format(drive:getAddress(), label, capacity, suffix, drive:getCapacity(), drive:getSectors(), type))
end

function tokenize(str)
	local tokens = { n = 0 }

	for tkn in str:gmatch("%S+") do
		table.insert(tokens, tkn)
		tokens.n = tokens.n + 1
	end

	return tokens
end

function confirm(msg)
	print(msg)
	io.write("[y/n]: ")

	return (io.read() or "n"):lower() == "y"
end

function check_int(name, val, min, max)
	val = assert(tonumber(val), "expected integer")

	assert(val % 1 == 0, name .. " is not an integer")
	assert((not min or val >= min) and (not max or val < max), name .. " is out of range")
	
	return val
end

main(table.pack(...))
