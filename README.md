# SNES for Analogue Pocket

Ported from the original core developed by [srg320](https://github.com/srg320) ([Patreon](https://www.patreon.com/srg320)). Latest upstream available at https://github.com/MiSTer-devel/SNES_MiSTer.

Please report any issues encountered to this repo. Most likely any problems are a result of my port, not the original core. Issues will be upstreamed as necessary.

## Usage

**NOTE:** ROM files must not contain a SMC header. If a ROM isn't loading and you think it should, check if it has a header with a tool like [Advanced SNES ROM Utility](https://www.romhacking.net/utilities/1638/) and remove it if so.

ROMs should be placed in `/Assets/snes/common`

PAL ROMs should boot, but there may be timing issues as the core currently doesn't properly support PAL (proper support coming soon).

## Features

### Dock Support

Core supports four players/controllers via the Analogue Dock. To enable four player mode, turn on "Use Multitap" setting.

### Expansion Chips

The currently supported expansion chips are SA-1 (Super Mario RPG), Super FX (GSU-1/2; Star Fox), DSP (Super Mario Kart), and CX4 (Mega Man X 2). Additional chip support will come in the future once several new firmware features are released.

**NOTE:** The S-DD1 chip was dropped in release 0.2.0 due to sizing and popularity issues. Support will resume in a future release. In the meantime, you can [use this hack to remove the S-DD1 requirement](https://www.romhacking.net/hacks/614/).

### Video Modes

The Analogue Pocket framework doesn't currently allow for customizing video modes directly, so if you dislike the default 8:7 aspect ratio/want to change to 4:3, you can change it by modifying `Cores/agg23.SNES/video.json` and rearranging the config objects.

Proper PAL support also requires editing these files to have an expanded vertical pixel height.

### Lightguns

Core supports virtual lightguns by enabling the "Use Super Scope" or "Use Justifier" settings. Most lightgun games user the Super Scope but Lethal Enforcers uses the Justifier. The crosshair can be controlled with the D-Pad or left joystick, using the A button to fire and the B button to reload. D-Pad aim sensitivity can be adjusted with the "D-Pad Aim Speed" setting.

**NOTE:** Joystick support for aiming only appears to work when a controller is paired over Bluetooth and not connected to the Analogue Dock directly by USB.