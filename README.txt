Open Computers Drive Tools

  Author: Matthew (CntKillMe)
 Version: 1.0
Requires: Lua 5.3

Installing OCDT:
Move or copy all files in the lib directory to /lib or /usr/lib.
Alternatively, add the lib directory to your package.path.

Quick Start:
1. Ensure Lua 5.3 is being used.
2. Install OCDT.
3. Insert empty EEPROM and unmanaged drive.
4. Run 'parted test <drive>' where drive is the address of the unmanaged drive.
5. Reboot.

Requirements:
- Drives have 512 bytes per sector.
- Drives have a capacity of at least 0.5 KiB (drives larger than 2 TiB will not be fully utilized).
- When utilizing the OCDT libraries and scripts, sectors are indexed logically (0-based).
- Negative sectors, where supported, denote a sector from the end of the drive (-1 = last sector).

Boot Modes:
0 - Standard:   Boot from boot address and boot partition. If booting fails, command mode entered.
1 - Standard-R: Same as standard but if booting fails, error and quit.
2 - Command:    Enter command mode on boot.
3 - Network:    Network boot. Downloads boot code from Boot URL and executes. If this fails, command mode entered.
4 - Network-R:  Same as network but if booting fails, error and quit.

Boot failures do not cover syntax or runtime errors in the boot code. 
When booting from the network, a GET request to the Boot URL is sent and the response message (if successful) is executed.
Command mode is not available if no GPU and screen are connected.


BIOS Data Layout

Offset | Size      | Contents
-------|-----------|---------
0      | 16 bytes  | Boot Address (big-endian)
16     | 4 bytes   | Boot Partition
20     | 4 bytes   | Boot Mode
24     | *         | Boot URL


OCPT Drive Layout

Sector | Contents
-------|---------
0      | Partition Table
1*     | Partition Data...


Partition Table Layout
Size: 512 bytes

Offset | Size      | Contents
-------|-----------|---------
0      | 4 bytes   | Signature ("OCPT" 4F 43 50 54)
4      | 4 bytes   | Active Partitions
8      | 120 bytes | Unused
128    | 384 bytes | Partition Entries 00-31

Partition entries are continuous and consecutive from 0 to 31.
Partition Offset Equation: offset = 128 + entry*12

Partition Entry Layout
Size: 12 bytes

Offset | Size     | Contents
-------|----------|----------
0      | 4 bytes  | First Sector
4      | 4 bytes  | Num Sectors
8      | 2 byte   | Partition Flags
10     | 2 byte   | Partition Type


Partition Types

Type | Mnemonic | Description
-----|----------|------------
0    | raw      | Raw Lua code
1    | swap     | Swap
2    | bfs      | Basic File System


Partition Flags

Bit | Flag
----|-----
0   | bootable
1   | hidden
2   | readonly