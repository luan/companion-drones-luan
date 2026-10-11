# Entourage 4.0.4 performance

Autocrafting rebuilt the complete recipe list during work searches. Profiling measured 37 to 50 ms per call in this modpack. The fix collects the requested recipe and its ingredients, caches prototype recipe names, and checks current unlocks and crafting permissions. Idle companion work searches are distributed across ticks at the same frequency.

The comparison uses the same two-player multiplayer save, 247 enabled mods, and mod settings on Factorio Space Age 2.1.21 for macOS ARM64. Each version ran three repeats of 1,800 ticks using the native benchmark. These timings measure simulation; rendering and live networking are excluded.

| Timing | 4.0.3 | 4.0.4 |
| --- | ---: | ---: |
| Whole simulation, mean | 6.07 ms | 3.43 ms |
| Whole simulation, 99th percentile | 53.61 ms | 14.50 ms |
| Whole simulation, maximum | 81.87 ms | 39.23 ms |
| Whole simulation, ticks over 16.67 ms | 366 / 5,400 | 22 / 5,400 |
| All mod scripts, mean | 4.05 ms | 1.55 ms |
| All mod scripts, 99th percentile | 49.88 ms | 11.83 ms |
| All mod scripts, maximum | 77.57 ms | 29.16 ms |
| All mod scripts, ticks over 16.67 ms | 360 / 5,400 | 5 / 5,400 |

The release ZIP was benchmarked directly. Native gameplay checks passed for construction, batched managers, parallel crafting, chest salvage, blocked cargo returns, combat, force changes, planet travel, platforms, and permanent companion identity. A recipe disabled before crafting reserves no materials; disabling it during crafting refunds the materials; enabling it again completes the ghost.

Reproduce with the installed mod directory and a save:

```sh
python3 tests/benchmark.py /path/to/factorio /path/to/mods /path/to/save.zip --mod /path/to/companion-drones-luan_4.0.4.zip
```

The runner isolates its mod directory and writes raw timings and results without changing the supplied save or installed mods.
