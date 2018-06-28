# OCDT - BIOS

## Boot Process
1. The BIOS loads the BIOS settings.
2. The BIOS attempts to boot from the first available drive/network address.
3. If booting fails, the BIOS settings can be manually configured.

*Note*: if the BIOS is unable to interface with a display, then BIOS settings cannot be manually configured. In these cases, either connect a display or eject the EEPROM and edit its settings from another machine.

## BIOS Settings Layout
- A boot drive is specified first by its address, then followed by 1 or more partition numbers. Must be wrapped in a table.
- A network boot is specified by its URL. Must not be wrapped in a table.

### Example
```lua
-- BIOS Settings --
{ "00000000-0000-0000-0000-000000000000", 0, 1 },
"https://pastebin.com/raw/00000000",
{ "00000000-0000-0000-0000-000000000000", 2 },
```
Would attempt to boot in this order:
1. Partition 0 of 00000000-0000-0000-0000-000000000000.
2. Partition 1 of 00000000-0000-0000-0000-000000000000.
3. From https://pastebin.com/raw/00000000.
4. Partition 2 of 00000000-0000-0000-0000-000000000000.

## Boot Failure
If booting fails, the BIOS provides a lightweight text editor to allow for manipulation of the BIOS's settings. However, the problem of a boot failure typically resides in either a misconfigured [partition table](ocpt.md) or an invalid URL.

Booting from a drive's partition fails only if the partition is not active or is not a [raw](ocpt.md#partition-types) partition.
Booting from the network only fails if the GET request to the URL fails.

In the case of syntax errors, the boot is still considered successful but the error message will be propogated via the `error` function.
