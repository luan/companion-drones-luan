"""Exercise companion behavior in native Factorio, isolated from player saves."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
from threading import Timer

parser = argparse.ArgumentParser()
parser.add_argument("factorio", type=Path)
parser.add_argument("--mod", type=Path, help="Test a release ZIP instead of the checkout")
parser.add_argument("--space-age", action="store_true")
parser.add_argument("--playground", action="store_true", help="Open the manual Space Age playground and leave it running")
parser.add_argument("--tile-stress", action="store_true")
parser.add_argument("--repair-stress", action="store_true")
parser.add_argument("--upgrade-stress", action="store_true")
parser.add_argument("--crew-stress", action="store_true")
parser.add_argument("--start-planet", choices=["vulcanus", "gleba", "fulgora", "companion-test-planet"])
parser.add_argument("--aps-mod", type=Path, help="Any Planet Start release ZIP")
args = parser.parse_args()
if args.start_planet and not args.aps_mod:
    parser.error("--start-planet requires --aps-mod")
args.space_age = args.space_age or args.playground or bool(args.start_planet)
root = Path(__file__).resolve().parents[1]
info = json.loads((root / "info.json").read_text())


def run(mode):
    qa = Path(tempfile.mkdtemp(prefix="companion-tests-"))
    mods = qa / "mods"
    mods.mkdir()
    source = args.mod or root
    (mods / source.name).symlink_to(source.resolve(), target_is_directory=source.is_dir())
    if args.start_planet:
        (mods / args.aps_mod.name).symlink_to(args.aps_mod.resolve())
    harness = mods / "companion-integration-tests"
    harness.mkdir()
    (harness / "info.json").write_text(json.dumps({
        "name": harness.name, "version": "1.0.0", "title": "Companion integration tests",
        "author": "Luan", "factorio_version": "2.1", "dependencies": [info["name"], "? space-age"] + (["any-planet-start"] if args.start_planet else []),
    }))
    (harness / "data.lua").write_bytes((root / "tests/data.lua").read_bytes())
    if args.crew_stress:
        with (harness / "data.lua").open("a") as data:
            data.write('\ndata.raw.recipe["transport-belt"].energy_required = 4\ndata.raw.recipe["iron-gear-wheel"].energy_required = 4\n')
    (harness / "settings-updates.lua").write_text(
        'data.raw["int-setting"]["set-mode"].default_value = ' + str(mode)
        + '\ndata.raw["double-setting"]["companion-crafting-speed"].default_value = ' + str(4 if mode == 1 else 2)
        + '\ndata.raw["double-setting"]["companion-mini-drone-speed"].default_value = ' + str(0.5 if args.crew_stress else 2))
    if args.start_planet:
        (harness / "aps-planet.lua").write_text("")
        (harness / "control.lua").write_bytes((root / "tests/planet-start.lua").read_bytes())
        with (harness / "settings-updates.lua").open("a") as settings:
            settings.write('\nAPS.add_choice("companion-test-planet")\ndata.raw["string-setting"]["aps-planet"].default_value = "' + args.start_planet + '"\n')
    scenario = qa / "scenarios/integration"
    scenario.mkdir(parents=True)
    if args.start_planet:
        (scenario / "control.lua").write_text('require("__base__/script/freeplay/control.lua")\n')
    else:
        (scenario / "control.lua").write_bytes((root / ("tests/playground.lua" if args.playground else "tests/tile-stress.lua" if args.tile_stress else "tests/repair-stress.lua" if args.repair_stress else "tests/upgrade-stress.lua" if args.upgrade_stress else "tests/crew-stress.lua" if args.crew_stress else "tests/control.lua")).read_bytes())
    (mods / "mod-list.json").write_text(json.dumps({"mods": [
        {"name": name, "enabled": True} for name in ["base", info["name"]] + (["any-planet-start"] if args.start_planet else []) + ([] if args.playground else [harness.name])
    ] + [{"name": name, "enabled": args.space_age} for name in ["space-age", "elevated-rails", "quality", "recycler"]]}))
    config = qa / "config.ini"
    config.write_text("[path]\nread-data=__PATH__system-read-data__\nwrite-data=" + str(qa)
                      + "\n[other]\ncheck-updates=false\npause-when-focus-lost=false\nautosave-interval=0\nenable-blueprint-storage-cloud-sync=false\n"
                      + "[graphics]\ngraphics-quality=medium\ntexture-compression-level=none\ncompress-virtual-atlas=false\nfull-screen=false\n")
    command = [str(args.factorio), "--config", str(config), "--mod-directory", str(mods),
               "--load-scenario", "integration", "--disable-audio",
               "--window-size", "1280x720"]
    if args.playground:
        with (qa / "launch.log").open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True,
                                       env={**os.environ, "SteamAppId": "427520", "SteamGameId": "427520"})
        print("Playground:", qa, "PID:", process.pid)
        return
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, env={**os.environ, "SteamAppId": "427520", "SteamGameId": "427520"})
    timeout = Timer(180, process.kill)
    timeout.start()
    lines = []
    for line in process.stdout:
        lines.append(line)
        if "COMPANION INTEGRATION PASS" in line or "Error" in line:
            process.terminate()
            break
    remaining, _ = process.communicate(timeout=10)
    timeout.cancel()
    output = (qa / "factorio-current.log").read_text() if (qa / "factorio-current.log").exists() else "".join(lines) + remaining
    (qa / "test.log").write_text(output)
    print("Mode:", mode, "Test artifacts:", qa)
    print("\n".join(line for line in output.splitlines() if any(
        marker in line for marker in ["COMPANION", "Error", "error", "stack traceback", "control.lua:"])))
    if "COMPANION INTEGRATION PASS" not in output:
        print(output[-4000:])
        raise SystemExit(1)


for mode in ([0] if args.space_age else [0, 1, 2, 3]):
    run(mode)
