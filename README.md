# Open Computers Drive Tools (OCDT)

## About
Open Computers Drive Tools (OCDT) is a suite of libraries and binaries for managing unmanaged drives.
The OCDT suite defines a formal partition table (OCPT) and various partition types.

From this point on, the word *drive* is referring to OpenComputer's [unmanaged drive](https://ocdoc.cil.li/component:drive) component.

## Quick Start
1. Ensure Lua 5.3 is selected.
2. Install OCDT (see below).
3. Insert an empty EEPROM and an empty drive.
4. Run `parted test addr` where *addr* is the full address of the drive.

## Installation
1. Download OCDT.
2. Merge OCDT's `lib` directory into `/home/lib`.
3. Merge OCDT's `bin` directory into `/home/bin`.
4. Remove the OCDT directory.

Alternatively `install.lua` can be ran to automate the install process:
```
wget -fq https://raw.githubusercontent.com/cntkillme/OC-Drive-Tools/v2/install.lua && ./install
```

## Requirements
1. All EEPROMs' code section has a capacity of at least 4 KiB (default value).
2. All EEPROMs' data section has a capacity of at least 256 bytes (default value).

*Note:* drives larger than 2 TiB will be underutilized.

## Conventions
1. Sectors are indexed logically, so `sector 0` corresponds to the first sector.
2. Negative sectors indicate a sector from the end of a drive, so `sector -1` corresponds to the last sector.
