# Upgrade and factory search performance

4.0.5 repeatedly inspected healthy factory entities during work searches. In the original Beast factory autosave, each search took about 10 ms. That snapshot had one connected owner and no active autocrafting, so it does not capture the earlier reported crafting lag.

A controlled scenario reproduces a separate upgrade stall. After managers consumed 64 available fast belts, batching repeatedly scanned the remaining 4,032 upgrades for materials that had already run out. The same path runs when autocrafters deliver small batches.

4.0.6 skips batches once their materials are exhausted. It also rotates through 512 pending entity jobs and 512 routine damage checks per search. Marked jobs are queried every search, and damaged vehicles and military targets receive immediate repair checks.

Both release ZIPs ran against the same Beast autosave, server mod archives and settings for 1,200 native benchmark ticks on Factorio Space Age 2.1.21 for macOS ARM64. Timings include all mod scripts; rendering and live networking are excluded.

| All mod scripts in Beast autosave | 4.0.5 | 4.0.6 |
| --- | ---: | ---: |
| Mean | 1.20 ms | 0.55 ms |
| 99th percentile | 11.75 ms | 2.62 ms |
| Maximum | 16.20 ms | 17.05 ms |
| Ticks over 16.67 ms | 0 / 1,200 | 1 / 1,200 |

The mean and 99th percentile improved; the maximum did not. This measurement does not establish the cause of every hitch in the previous session.

The controlled upgrade comparison runs the same saved scenario for 480 ticks: 4,096 unavailable upgrades, an unrelated supplied construction job, and 64 upgrade items supplied later.

| All mod scripts in upgrade scenario | 4.0.5 | 4.0.6 |
| --- | ---: | ---: |
| Mean | 32.99 ms | 0.64 ms |
| 99th percentile | 58.89 ms | 9.41 ms |
| Maximum | 14,177.39 ms | 10.10 ms |
| Ticks over 16.67 ms | 33 / 480 | 0 / 480 |

An extended 1,500-tick run enables the fast-belt recipe and supplies raw materials after those 64 upgrades. Parallel autocrafting completes more upgrades, uses at most six crafters, and leaves the player's handcraft queue empty. All mod scripts peak at 11.25 ms with no ticks over 16.67 ms.

The release ZIP also passes the full native integration suite, the 6,400-tile stress scenario, and a repair scenario with 4,096 healthy belts. The repair scenario checks immediate turret repairs, eventual furnace repairs beyond the first search slice, construction, and neutral rock deconstruction.

```sh
python3 tests/run.py /path/to/factorio --space-age --upgrade-stress --mod /path/to/companion-drones-luan_4.0.6.zip
python3 tests/run.py /path/to/factorio --space-age --repair-stress --mod /path/to/companion-drones-luan_4.0.6.zip
```
