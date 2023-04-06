# SNES for Analogue Pocket

Ported from the original core developed by [srg320](https://github.com/srg320) ([Patreon](https://www.patreon.com/srg320)). Latest upstream available at https://github.com/MiSTer-devel/SNES_MiSTer.

Please report any issues encountered to this repo. Most likely any problems are a result of my port, not the original core. Issues will be upstreamed as necessary.

> **Warning**: Savestates/Memories/Sleep not supported
>
> Savestates/Memories/Sleep are not supported by any FPGA SNES core. Not this one, not the MiSTer core it's ported from, not the Analogue Super NT one.
> 
> **Support for savestates will _not_ be coming** to any of these cores. Do not ask. If you would like to learn more, see [issue #59](https://github.com/agg23/openfpga-SNES/issues/59) and [this discussion on the MiSTer forums](https://misterfpga.org/viewtopic.php?t=4944).
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

All original expansion chips supported by MiSTer are also supported on the Pocket. The full list is:

* SA-1 (Super Mario RPG)
* Super FX/GSU-1/2 (Star Fox)
* DSP (Super Mario Kart)
* CX4 (Mega Man X 2)
* S-DD1 (Star Ocean)
* SPC7110 (Far East of Eden)
* ST1010 (F1 Roc 2)
* BSX (Satellaview)

The Super Game Boy, ST011 (Hayazashi Nidan Morita Shougi), and ST018 (Hayazashi Nidan Morita Shougi 2) are not supported in the MiSTer core, and therefore are not supported here. Additionally, the homebrew MSU expansion chip is not currently supported.

#### BSX

BSX ROMs must be patched to run without BIOS. The BSX BIOS is not currently supported

### Savestates/Memories/Sleep

> **Warning**: Not supported

Savestates/Memories/Sleep are not supported by any FPGA SNES core. Not this one, not the MiSTer core it's ported from, not the Analogue Super NT one.

**Support for savestates will _not_ be coming** to any of these cores. Do not ask. If you would like to learn more, see [issue #59](https://github.com/agg23/openfpga-SNES/issues/59) and [this discussion on the MiSTer forums](https://misterfpga.org/viewtopic.php?t=4944).

### Video

* `Square Pixels` - The internal resolution of the SNES is a 8:7 pixel aspect ratio (wide pixels), which roughly corresponds to what users would see on 4:3 display aspect ratio CRTs. Some games are designed to be displayed at 8:7 PAR (the core's default), and others at 1:1 PAR (square pixels). The `Square Pixels` option is provided to switch to a 1:1 pixel aspect ratio
* `Pseudo Transparency` - Enable blending of adjacent pixels, used in some games to simulate transparency

### Turbo

* `CPU Turbo` - Applies a speed increase to the main SNES CPU. **NOTE:** This has different compatibility with different games. See the [MiSTer list of games](https://github.com/MiSTer-devel/SNES_MiSTer/blob/master/SNES_Turbo.md) that this feature works with
* `SuperFX Turbo` - Applies a speed increase to the GSU (SuperFX) chip. Can be used in addition to the `CPU Turbo` option in games like Star Fox to maintain a higher frame rate.

### Controller Options

There are several options provided for selecting which type of controller the core will emulate.

* `Gamepad` - The standard SNES controller used with most games.
* `Super Scope` - The Super Scope lightgun that's used with most lightgun games. See Lightguns for more details.
* `Justifier` - The Justifier lightgun that's used with Lethal Enforcers. See Lightguns for more details.
* `Mouse` - The SNES mouse that's used with Mario Paint and several other games. See SNES Mouse for more details.

### Lightguns

Core supports virtual lightguns by selecting the `Super Scope` or `Justifier` options under `Controller Options`. Most lightgun games user the Super Scope but Lethal Enforcers uses the Justifier. The crosshair can be controlled with the D-Pad or left joystick, using the A button to fire and the B button to reload. D-Pad aim sensitivity can be adjusted with the `D-Pad Aim Speed` setting.

**NOTE:** Joystick support for aiming only appears to work when a controller is paired over Bluetooth and not connected to the Analogue Dock directly by USB.

### SNES Mouse

Core supports a virtual SNES mouse by selecting `Mouse` under `Controller Options`. The mouse can be moved with the D-Pad or left joystick and left and right clicks can be performed by pressing the A and B buttons respectively. Mouse D-Pad movement sensitivity can be adjusted with the `D-Pad Aim Speed` setting.

**NOTE:** The dock firmware doesn't currently support a USB mouse.