Open Computers Drive Tools

  Author: Matthew (CntKillMe)
 Version: 1.0
Requires: Lua 5.3

Installing OCDT:
Move or copy all files in the lib directory to /lib or /usr/lib.
Alternatively, add the lib directory to your package.path.

Quick Start:
1. Enable Lua 5.3 on CPU.
2. Flash eeprom.lua to some EEPROM.
3. Create and insert unmanaged floppy.
4. Install OCDT.
5. Run 'parted test ' followed by the address of the unmanaged floppy.
6. Insert EEPROM and floppy, reboot.

Requirements:
- Drives have 512 bytes per sector.
- Drives have a capacity of at least 0.5 KiB (drives larger than 2 TiB will not be fully utilized).
- When utilizing the OCDT libraries, logically-addressed sectors must be in the range [0, numDriveSectors).
- Negative sectors, where supported, denote a sector from the end of the drive (-1 = last sector).
- When applicable, a proper BIOS partition must be both a raw partition and a bootable partition.

If no valid BIOS partition is given, the first possible raw and bootable will be executed.


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
8      | 1 byte    | Last Boot Partition
9      | 1 byte    | BIOS Partition
10     | 118 bytes | BIOS Data
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