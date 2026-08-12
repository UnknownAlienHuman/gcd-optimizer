# GCD Optimizer

A lightweight HUD for analyzing global-cooldown timing, input queue use, late presses, server-delay symptoms, and recorded cast-failure causes.

## Installation

Copy the `GCDOptimizer` directory into `World of Warcraft/_retail_/Interface/AddOns/`, then restart the client or use `/reload`. Its optional LibStub, callback, data-broker, and minimap-button dependencies are bundled in `libs/`.

## Compatibility and data

- Interface: `120001`, `120000`
- Version: `0.4.9-midnight-v2`
- Saved variables: `GCDOptimizerDB`

## Usage

The HUD exposes timing and metrics views. Its in-addon menu can start, stop, reset, hide, and configure the view; the detailed workflow and language notes are in [README_MIDNIGHT.md](README_MIDNIGHT.md).

## Development status

No older project tracker was present. The repository now records its release-readiness checks in [todo.md](todo.md); the current source should still be checked in-game on the target client before a release.

## Published addon

[CurseForge: GCD Optimizer](https://www.curseforge.com/wow/addons/gcd-optimizer)

## Developer documentation

- [Architecture](ARCHITECTURE.md)
- [Code index](CODE_INDEX.md)
- [Code graph](CODE_GRAPH.md)
