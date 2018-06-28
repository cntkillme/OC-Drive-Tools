# OCDT - Partition Table
The partition table must be contained on a drive's *first sector*.

## Partition Table Layout
Size: 512 bytes

Offset | Size      | Contents
-------|-----------|---------
0      | 4 bytes   | Signature (4F 43 50 54)
4      | 4 bytes   | Active Partitions
8      | 120 bytes | Unused
128    | 384 bytes | Partition Entries 0-31

## Partition Entry Layout
Size: 12 bytes

Offset | Size    | Contents
-------|---------|---------
0      | 4 bytes | First Sector
4      | 4 bytes | Last Sector
8      | 2 bytes | Partition Flags
10     | 2 bytes | Partition Type

## Partition Flags
Bit | Flag
----|-----
none defined

## Partition Types
Type | Mnemonic
-----|---------
0    | raw
1    | bfs
