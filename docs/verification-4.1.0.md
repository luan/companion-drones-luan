# 4.1.0 verification

Tests run in isolated Factorio 2.1.21 instances. The Beast server and its installed mods were not changed.

| Check | Result |
| --- | --- |
| Two connected clients, dedicated Space Age server | Six separated belts and two inserters consume seventeen iron plates and three copper plates from an ordinary electrical-network chest. Crews share final and intermediate surplus while one owner walks away. Finished workers deliver cargo and disappear. |
| Multiplayer ownership and recovery | Private player inventories, force isolation, disconnect/reconnect, full cargo, death/respawn and server save/reload pass. |
| Space Age gameplay integration | Construction, manager batches, parallel crafting, cargo conservation, force changes, planet travel, platform parking and recipe cancellation pass. |
| Crafting surplus and changed demand | One two-belt craft supplies two separated targets. Two separated inserters share spare cable and consume eight iron plates and three copper plates. A furnace built by another builder returns its reserved stone instead of making an extra furnace. |
| Electrical sourcing | A steel chest covered by a connected remote substation supplies crafting without a roboport. A chest on a disconnected network stays untouched. An uncommon furnace from an infinity chest builds an uncommon entity. |
| Floating crafting queue | The active intermediate and upcoming final recipe both appear above the crafter. The player handcraft queue stays empty. |
| Movement and size | The main body renders at half size. Default flight displacement stays within 0.05 tiles/tick for crafters, 0.06 for managers and 0.03 for combat escorts, allowing native position rounding. |
| Distant crafting | The owner moves 100 tiles away. The landed crafter stays put, finishes, returns its output and disappears after delivery. |
| Military research | Military tiers increase squad power; laser damage affects each hit and laser speed increases the native firing rate. |
| Any Planet Start | Fulgora and a modded starting planet pass starter creation, construction, autocrafting, death/respawn and return travel with the release ZIP. |
| Bulk work | 6,400 tile ghosts, 4,096 upgrades with late materials and parallel autocrafting, and 4,096 healthy belts with repairs pass. |

The two-client Space Age test ran on Beast using its existing DRM-free Factorio 2.1.21 installation and Xvfb. Both clients stayed connected through the final assertions and rejoined after server save/reload without a desync. The test used separate temporary configs, saves, mods and loopback ports; production servers were not changed.

The same Beast multiplayer autosave ran for 1,200 benchmark ticks per version, with its server mod archives and settings. It has no active autocrafting. Timings include every mod script and exclude rendering and live networking.

| All mod scripts | 4.0.6 | 4.1.0 |
| --- | ---: | ---: |
| Mean | 0.591 ms | 0.600 ms |
| 99th percentile | 2.888 ms | 2.855 ms |
| Maximum | 16.794 ms | 17.669 ms |
| Ticks above 16.67 ms | 1 / 1,200 | 1 / 1,200 |

The benchmark shows similar routine cost. It does not measure electrical sourcing during a large active crafting workload.

The saved electrical-supply scenario also ran for 2,600 ticks through distant crafter return, military research, intermediate surplus reuse and uncommon construction. All assertions passed after reload. With no other Factorio client running, mod scripts averaged 0.279 ms and peaked at 2.663 ms; whole updates peaked at 13.925 ms. No tick exceeded 16.67 ms.

```sh
python3 tests/run.py /path/to/factorio --space-age --crew-stress
xvfb-run -a python3 tests/multiplayer.py /usr/bin/factorio /usr/bin/factorio --read-data /usr/share/factorio
```

The release does not require manual player testing. The playground includes recursive crafting, electrical-only chest supplies, military research, mixed work and owner movement controls.
