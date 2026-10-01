"""Exercise drone build/refueling events in Factorio, isolated from player saves."""
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
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
info = json.loads((root / "info.json").read_text())


def run(best):
    qa = Path(tempfile.mkdtemp(prefix="companion-tests-"))
    mods = qa / "mods"
    mods.mkdir()
    source = args.mod or root
    (mods / source.name).symlink_to(source.resolve(), target_is_directory=source.is_dir())
    harness = mods / "companion-integration-tests"
    harness.mkdir()
    (harness / "info.json").write_text(json.dumps({
        "name": harness.name, "version": "1.0.0", "title": "Companion integration tests",
        "author": "Luan", "factorio_version": "2.1", "dependencies": [info["name"]],
    }))
    (harness / "data.lua").write_bytes((root / "tests/data.lua").read_bytes())
    (harness / "settings-updates.lua").write_text(
        'data.raw["bool-setting"]["set-fuel-preference"].default_value = ' + str(best).lower())
    scenario = qa / "scenarios/integration"
    scenario.mkdir(parents=True)
    (scenario / "control.lua").write_bytes((root / "tests/control.lua").read_bytes())
    (mods / "mod-list.json").write_text(json.dumps({"mods": [
        {"name": name, "enabled": True} for name in ["base", info["name"], harness.name]
    ] + [{"name": name, "enabled": False} for name in ["space-age", "elevated-rails", "quality", "recycler"]]}))
    config = qa / "config.ini"
    config.write_text("[path]\nread-data=__PATH__system-read-data__\nwrite-data=" + str(qa)
                      + "\n[other]\ncheck-updates=false\nautosave-interval=0\nenable-blueprint-storage-cloud-sync=false\n"
                      + "[graphics]\ngraphics-quality=medium\ntexture-compression-level=none\ncompress-virtual-atlas=false\nfull-screen=false\n")
    command = [str(args.factorio), "--config", str(config), "--mod-directory", str(mods),
               "--load-scenario", "integration", "--disable-audio",
               "--window-size", "1280x720"]
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
    print("Fuel preference:", "best" if best else "worst", "Test artifacts:", qa)
    print("\n".join(line for line in output.splitlines() if any(
        marker in line for marker in ["COMPANION", "Error", "error", "stack traceback", "control.lua:"])))
    if "COMPANION INTEGRATION PASS" not in output:
        print(output[-4000:])
        raise SystemExit(1)


for best in [False, True]:
    run(best)
