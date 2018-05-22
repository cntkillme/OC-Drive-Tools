Open Computers Drive Tools

  Author: Matthew (CntKillMe)
 Version: 1.0
Requires: Lua 5.3


The OCDT (Open Computers Drive Tools) suite assumes the size per sector of all drives is 512 bytes.

The OCPT (Open Computers Partition Table) requires 1 sector of header data and will not support drives with a capacity greater than 2 TiB. Mo more than 32 partitions are supported by the standard OCPT.

Sectors are marked and utilized logically: they will fall in the range [0, numDriveSectors).
The BIOS data field of the OCPT is used by the standard OCBIOS, use caution when altering.

The BIOS partition must be a bootable and raw partition for the standard EEPROM to boot from it. If no active or valid BIOS partition is given, the first possible bootable, raw partition will be executed.


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