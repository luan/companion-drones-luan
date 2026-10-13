# Large concrete paste performance

A reconnect snapshot from the multiplayer server reproduces the failure. Entourage 4.0.4 scans the pending list again for every unavailable tile, even after the same item has already failed crafting. Thousands of tiles turn each search into millions of repeated comparisons.

4.0.5 skips further batches after a single-item plan fails, stops searching when crafter slots are full, and rotates through 512 tile candidates per search. Entity construction and repairs are checked on every search. Tile jobs remain pending and become eligible when materials arrive.

Both release ZIPs ran against the same snapshot, server mod archives and settings, for 180 native benchmark ticks on Factorio Space Age 2.1.21 for macOS ARM64. Timings include all mod scripts. The benchmark excludes rendering and live networking.

| All mod scripts | 4.0.4 | 4.0.5 |
| --- | ---: | ---: |
| Mean | 201.47 ms | 1.71 ms |
| 99th percentile | 3093.38 ms | 12.90 ms |
| Maximum | 3115.97 ms | 15.46 ms |
| Ticks over 16.67 ms | 12 / 180 | 0 / 180 |

The native stress scenario pastes 6,400 concrete and refined-concrete ghosts without materials. A supplied belt still builds. Supplying 192 concrete later builds 192 tiles, with at most six managers. The full Space Age integration suite also passes construction, crafting, cargo conservation, combat, force changes, research, platform suspension, planet travel, and companion identity.

Reproduce the stress scenario:

```sh
python3 tests/run.py /path/to/factorio --space-age --tile-stress --mod /path/to/companion-drones-luan_4.0.5.zip
```
