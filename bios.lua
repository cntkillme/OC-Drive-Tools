--- OCDT - BIOS
-- A minified version of this file is contained in the `parted` binary.

local last_error
local settings
local bootcode

-- load settings
do
	local eeprom = component.list("eeprom", true)()
	local settings = component.invoke(eeprom, "getData")
	local chunk, error = load(("return {%s}"):format(settings), "bios", nil, { })

	if chunk then
		settings = chunk()
	else
		last_error = "could not load bios settings"
	end
end

-- attempt to boot
if settings then
	function try_boot_drive(ocpt, drive, partition)
	end
	
	function try_network_boot(url)
	end

	for _, entry in ipairs(settings) do
		if type(entry) == "table" then -- boot drive
			local drive = component.proxy(entry[1])
			local ocpt = drive.readSector(1)

			if ocpt:sub(1, 4) == "OCPT" then
				for idx = 2, #entry do
					if try_boot_drive(ocpt, drive, entry[idx]) then
						goto loopend
					end
				end
			end
		elseif type(entry) == "string" then -- network boot
			if try_network_boot(entry) then
				break
			end
		end
	end
	::loopend::
end

-- boot
if bootcode then
	assert(not last_error, last_error)
	bootcode()
	return
end

-- manual BIOS configuration
-- interface with display
do
	local gpu = component.list("gpu", true)()
	local screen = component.list("screen", true)()

	if gpu and screen then
		local w, h
		display = component.proxy(gpu)
		w, h = 
		display.bind(screen)
		display.setResolution(display.maxResolution())
	end
end
