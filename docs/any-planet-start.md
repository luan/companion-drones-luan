# Any Planet Start compatibility

Entourage 4.0.4 was tested with Any Planet Start 1.2.5 on native Factorio Space Age 2.1.21. The released ZIP passes actual freeplay starts on Vulcanus, Gleba, Fulgora, and a planet registered through the Any Planet Start API.

Each start checks one automatic companion on the selected surface, construction, private autocrafting, character death and respawn, travel to another planet and back, preserved companion identity, and upgrade prerequisites without hidden discovery research.

These checks run in isolated single-player freeplay sessions. They do not change installed mods, player saves, or the multiplayer server. No production code change was required.

Reproduce each start:

```sh
python3 tests/run.py /path/to/factorio --mod /path/to/companion-drones-luan_4.0.4.zip --aps-mod /path/to/any-planet-start_1.2.5.zip --start-planet fulgora
```

Other tested values are `gleba`, `vulcanus`, and `companion-test-planet`. The last is the harness planet registered with Any Planet Start, with its own discovery research and dedicated lab.
