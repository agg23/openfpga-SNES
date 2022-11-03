# SNES for Analogue Pocket

Ported from the original core developed by [srg320](https://github.com/srg320) ([Patreon](https://www.patreon.com/srg320)). Latest upstream available at https://github.com/MiSTer-devel/SNES_MiSTer.

Please report any issues encountered to this repo. Most likely any problems are a result of my port, not the original core. Issues will be upstreamed as necessary.

## Installation

### Easy mode

I highly recommend the updater tools by [@mattpannella](https://github.com/mattpannella) and [@RetroDriven](https://github.com/RetroDriven). If you're running Windows, use [the RetroDriven GUI](https://github.com/RetroDriven/Pocket_Updater), or if you prefer the CLI, use [the mattpannella tool](https://github.com/mattpannella/pocket_core_autoupdate_net). Either of these will allow you to automatically download and install openFPGA cores onto your Analogue Pocket. Go donate to them if you can

### Manual mode
To install the core, copy the `Assets`, `Cores`, and `Platform` folders over to the root of your SD card. Please note that Finder on macOS automatically _replaces_ folders, rather than merging them like Windows does, so you have to manually merge the folders.

## Usage

ROMs should be placed in `/Assets/snes/common`. Both headered and unheadered ROMs are now supported.

## Features

### Dock Support

Core supports four players/controllers via the Analogue Dock. To enable four player mode, turn on `Use Multitap` setting.

### Expansion Chips

All original expansion chips supported by MiSTer are also supported on the Pocket. The full list is: SA-1 (Super Mario RPG), Super FX/GSU-1/2 (Star Fox), DSP (Super Mario Kart), CX4 (Mega Man X 2), S-DD1 (Star Ocean), SPC7110 (Far East of Eden), ST1010 (F1 Roc 2), and BSX (Satellaview). The Super Game Boy, ST011 (Hayazashi Nidan Morita Shougi), and ST018 (Hayazashi Nidan Morita Shougi 2) are not supported in the MiSTer core, and therefore are not supported here. Additionally, the homebrew MSU expansion chip is not currently supported.

#### BSX

BSX ROMs must be patched to run without BIOS. The BSX BIOS is not currently supported

### Video

* `Use 4:3 Video` - The internal resolution of the SNES is a 8:7 aspect ratio, which is much taller than the 4:3 CRTs that were used at the time. Some games are designed to be displayed at 8:7, and others at 4:3. The `Use 4:3 Video` option is provided to switch to a 4:3 aspect ratio.
* `Pseudo Transparency` - Enable blending of adjacent pixels, used in some games to simulate transparency

### Turbo

* `CPU Turbo` - Applies a speed increase to the main SNES CPU. **NOTE:** This has different compatibility with different games. See the [MiSTer list of games](https://github.com/MiSTer-devel/SNES_MiSTer/blob/master/SNES_Turbo.md) that this feature works with
* `SuperFX Turbo` - Applies a speed increase to the GSU (SuperFX) chip. Can be used in addition to the `CPU Turbo` option in games like Star Fox to maintain a higher frame rate.

### Lightguns

Core supports virtual lightguns by enabling the `Use Super Scope` or `Use Justifier` settings. Most lightgun games user the Super Scope but Lethal Enforcers uses the Justifier. The crosshair can be controlled with the D-Pad or left joystick, using the A button to fire and the B button to reload. D-Pad aim sensitivity can be adjusted with the "D-Pad Aim Speed" setting.

**NOTE:** Joystick support for aiming only appears to work when a controller is paired over Bluetooth and not connected to the Analogue Dock directly by USB.