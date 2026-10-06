# Computercraft-Quarry
Cc-tweaked-quarry
# CC: Tweaked Quarry Turtle Script (v1.0.0-alpha)

An automated, self-recovering 16x16 quarry mining script written for standard and advanced ComputerCraft / CC: Tweaked Mining Turtles in Minecraft.

## Features
- **Monochrome TUI**: Optimized for standard turtle 39x13 screens without requiring advanced peripherals.
- **State Persistence**: Writes positional state to disk tick-by-tick (`quarry_state.txt`) to seamlessly recover from chunk unloads or server restarts.
- **Alcove Corner Storage**: Digs safe 2-block-tall alcoves in the corner of each depth layer `(1,1,Z)` to store mined items in chests, reusing existing chests dynamically.
- **Chest Safety Checks**: Inspects target walls and ceilings before executing dig commands to prevent accidental destruction of existing storage chests.
- **Fuel Management**: Calculates travel distances dynamically, returns home to refuel when necessary, and pauses with a visual prompt if fuel or chest supplies run out.

## Installation
Run the following command directly on your CC: Tweaked Turtle terminal:

```bash
wget [https://raw.githubusercontent.com/](https://raw.githubusercontent.com/)<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>/main/quarry.lua quarry.lua
