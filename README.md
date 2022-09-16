# SNES for Analogue Pocket

Ported from the original core developed by [srg320](https://github.com/srg320) ([Patreon](https://www.patreon.com/srg320)). Latest upstream available at https://github.com/MiSTer-devel/SNES_MiSTer.

Please report any issues encountered to this repo. Most likely any problems are a result of my port, not the original core. Issues will be upstreamed as necessary.

## Usage

**NOTE:** ROM files must not contain a SMC header. If a ROM isn't loading and you think it should, check if it has a header with a tool like [Advanced SNES ROM Utility](https://www.romhacking.net/utilities/1638/) and remove it if so.

ROMs should be placed in `/Assets/snes/common`

PAL ROMs are currently not supported

## Features

### Dock Support

Core supports two players/controllers via the Analogue Dock. Multitap and four player support coming soon.

### Expansion Chips

The currently supported expansion chips are SA-1 (Super Mario RPG), Super FX (GSU-1/2; Star Fox), S-DD1 (Streat Fighter Alpha 2), and CX4 (Mega Man X 2). Additional chip support will come in the future as I rearrange memory and wait on several new features from Analogue.

### Video Modes

The Analogue Pocket framework doesn't currently allow for customizing video modes directly, so if you dislike the default 8:7 aspect ratio/want to change to 4:3, you can change it by modifying `Cores/agg23.SNES/video.json` and rearranging the config objects.