--- OCDT Quick Install Script
local shell = require("shell")
local fs = require("filesystem")

-- download libraries
fs.makeDirectory("/home/lib/")
shell.execute("wget -fq https://raw.githubusercontent.com/cntkillme/OC-Drive-Tools/v2/lib/drive.lua /home/lib/drive.lua")
shell.execute("wget -fq https://raw.githubusercontent.com/cntkillme/OC-Drive-Tools/v2/lib/partman.lua /home/lib/partman.lua")

-- download binaries
fs.makeDirectory("/home/bin/")
shell.execute("wget -fq https://raw.githubusercontent.com/cntkillme/OC-Drive-Tools/v2/bin/parted.lua /home/bin/parted.lua")
