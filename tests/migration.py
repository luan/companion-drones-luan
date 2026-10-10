"""Upgrade a real 3.2.1 save without replacing its companion or losing cargo."""
import argparse
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('factorio', type=Path)
parser.add_argument('--mod', type=Path, help='Test an unpublished release ZIP')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
qa = Path(tempfile.mkdtemp(prefix='entourage-migration-'))
mods = qa / 'mods'
mods.mkdir()
legacy = mods / 'companion-drones-luan'
legacy.mkdir()
archive = subprocess.check_output(['git', 'archive', 'v3.2.1'], cwd=repo)
with tarfile.open(fileobj=io.BytesIO(archive)) as contents:
    contents.extractall(legacy, filter='data')
# Exercise the retained challenge checkbox from a real old save.
p = legacy / 'settings.lua'
s = p.read_text()
start = s.index('name = "set-challenge-mode"')
s = s[:start] + s[start:].replace('default_value = false', 'default_value = true', 1)
p.write_text(s)
(mods / 'mod-list.json').write_text(json.dumps({'mods': [
    {'name': n, 'enabled': n in ['base', 'companion-drones-luan']}
    for n in ['base', 'companion-drones-luan', 'space-age', 'quality', 'elevated-rails']]}))
config = qa / 'config.ini'
config.write_text(f'[path]\nread-data=__PATH__system-read-data__\nwrite-data={qa}\n'
                  '[other]\ncheck-updates=false\nautosave-interval=0\nenable-blueprint-storage-cloud-sync=false\n'
                  '[graphics]\ngraphics-quality=medium\ntexture-compression-level=none\nfull-screen=false\n')
scenario = qa / 'scenarios/migration'
scenario.mkdir(parents=True)
(scenario / 'control.lua').write_text('''
script.on_init(function()
    game.speed = 1000
    game.surfaces.nauvis.request_to_generate_chunks({0,0},1)
    game.surfaces.nauvis.force_generate_chunk_requests()
end)
script.on_event(defines.events.on_tick, function(event)
    local player = game.get_player(1)
    if not player then return end
    if not player.character then player.create_character() end
    if script.active_mods["companion-drones-luan"] == "3.2.1" then
        local drone = player.surface.find_entities_filtered{name="companion"}[1]
        if not drone then return end
        if not storage.seeded then
            storage.seeded=event.tick;storage.identity=drone.unit_number
            drone.insert{name="iron-plate",count=100}
            drone.insert{name="repair-pack",count=1}
            drone.get_inventory(defines.inventory.spider_trunk).find_item_stack("repair-pack").durability=135
            player.insert{name="companion",count=1}
        elseif event.tick-storage.seeded==60 then
            game.auto_save("legacy-migration")
            log("ENTOURAGE LEGACY SAVE READY")
            game.tick_paused=true
        end
    else
        storage.upgraded=storage.upgraded or event.tick
        if event.tick-storage.upgraded<120 then return end
        local drones=player.surface.find_entities_filtered{name="companion"}
        assert(#drones==1 and drones[1].unit_number==storage.identity,"upgrade preserves companion identity")
        local drone=drones[1]
        assert(not drone.minable and not drone.destructible,"upgraded companion is permanent")
        assert(player.get_item_count("iron-plate")+drone.get_item_count("iron-plate")==100,"upgrade preserves cargo")
        local pack=player.get_main_inventory().find_item_stack("repair-pack") or drone.get_inventory(defines.inventory.spider_trunk).find_item_stack("repair-pack")
        assert(pack and pack.durability==135,"upgrade preserves item durability")
        assert(player.get_item_count("companion")==1,"old drone item remains loadable")
        assert(not player.force.recipes.companion,"obsolete crafting recipe is removed")
        local challenge_port=false
        for _, equipment in pairs(drone.grid.equipment) do if equipment.name=="companion-roboport-mk0" then challenge_port=true end end
        assert(challenge_port and settings.startup["set-challenge-mode"].value,"legacy challenge alias is retained")
        log("ENTOURAGE MIGRATION PASS")
        game.tick_paused=true
    end
end)
''')
base = [str(args.factorio), '--config', str(config), '--mod-directory', str(mods),
        '--disable-audio', '--window-size', '1280x720']
env = {**os.environ, 'SteamAppId': '427520', 'SteamGameId': '427520'}


def run(arguments, marker, save=None):
    log = qa / ('legacy.log' if save else 'upgrade.log')
    with log.open('w') as output:
        process = subprocess.Popen(base + arguments, stdout=output, stderr=subprocess.STDOUT, env=env)
        try:
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                text = log.read_text()
                if any(error in text for error in ['Error while running', 'Exception at tick', 'Failed to load mod']):
                    raise RuntimeError(text[-4000:])
                if marker in text and (save is None or save.is_file()):
                    return
                if process.poll() is not None:
                    raise RuntimeError(text[-4000:])
                time.sleep(.1)
            raise TimeoutError(log)
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)


save = qa / 'saves/_autosave-legacy-migration.zip'
run(['--load-scenario', 'migration'], 'ENTOURAGE LEGACY SAVE READY', save)
# Preserve the old checkout; use the current mod in a new directory for the upgrade.
legacy.rename(qa / 'legacy-source')
source = args.mod or repo
(mods / source.name).symlink_to(source.resolve(), target_is_directory=source.is_dir())
# Saving while paused would keep the upgraded test paused; change only the isolated save's pause state.
# --benchmark runs updates despite the saved pause state and exercises configuration migration.
run(['--benchmark', str(save), '--benchmark-ticks', '300'], 'ENTOURAGE MIGRATION PASS')
print('ENTOURAGE MIGRATION PASS', qa)
