"""Run two native clients against an isolated server, then reload its save."""
import argparse
import json
import os
from pathlib import Path
import socket
import shutil
import struct
import subprocess
import tempfile
from threading import Timer

parser = argparse.ArgumentParser()
parser.add_argument('factorio', type=Path)
parser.add_argument('second_client', type=Path, help='Standalone build, so clients can use different LAN names')
parser.add_argument('--read-data', type=Path, help='Reuse system-installed Factorio data')
parser.add_argument('--keep-running', action='store_true', help='Leave the passed session open for screenshots')
parser.add_argument('--base-only', action='store_true', help='Test crew collaboration without Space Age content')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
read_data = args.read_data or args.factorio.resolve().parents[1] / 'data'
root = Path(tempfile.mkdtemp(prefix='entourage-multiplayer-test-'))
mods = root / 'mods'
mods.mkdir()
shutil.copytree(repo, mods / repo.name, ignore=shutil.ignore_patterns('.git', 'art', 'tests'))
harness = mods / 'entourage-multiplayer-fixture'
harness.mkdir()
(harness / 'info.json').write_text(json.dumps({'name': harness.name, 'version': '1.0.0',
    'title': 'Entourage multiplayer fixture', 'author': 'Luan', 'factorio_version': '2.1',
    'dependencies': [repo.name] + ([] if args.base_only else ['space-age'])}))
(harness / 'data.lua').write_bytes((repo / 'tests/data.lua').read_bytes())
(mods / 'mod-list.json').write_text(json.dumps({'mods': [{'name': name,
    'enabled': not args.base_only or name in ['base', repo.name, harness.name]}
    for name in ['base', repo.name, harness.name, 'space-age', 'quality', 'elevated-rails', 'recycler']]}))
for name in ['server', 'client-a', 'client-b']:
    path = root / name
    path.mkdir()
    (path / 'config.ini').write_text('[path]\nread-data=' + str(read_data)
        + '\nwrite-data=' + str(path) + '\n[other]\ncheck-updates=false\nautosave-interval=0\n'
        + 'enable-blueprint-storage-cloud-sync=false\n[graphics]\ngraphics-quality=medium\nfull-screen=false\n')
    if name != 'server':
        (path / 'player-data.json').write_text(json.dumps({'service-username': 'Entourage-QA-' + name[-1]}))
(root / 'server/saves').mkdir()
scenario = root / 'server/scenarios/multiplayer'
scenario.mkdir(parents=True)
(scenario / 'control.lua').write_bytes((repo / 'tests/multiplayer.lua').read_bytes())
settings = json.loads((read_data / 'server-settings.example.json').read_text())
settings.update(name='Entourage local QA', description='Two-client test', visibility={'public': False, 'lan': False},
    require_user_verification=False, auto_pause=False, auto_pause_when_players_connect=False,
    autosave_interval=0, allow_commands='true', max_players=4)
(root / 'server/server-settings.json').write_text(json.dumps(settings))
processes = {}
port, rcon_port = 34291, 34292
password = 'entourage-local-qa'
env = {**os.environ, 'SteamAppId': '427520', 'SteamGameId': '427520'}


def command(text):
    with socket.create_connection(('127.0.0.1', rcon_port), timeout=15) as connection:
        def send(identifier, kind, payload):
            data = struct.pack('<ii', identifier, kind) + payload.encode() + b'\0\0'
            connection.sendall(struct.pack('<i', len(data)) + data)

        def receive():
            def read(count):
                data = b''
                while len(data) < count:
                    chunk = connection.recv(count - len(data))
                    if not chunk:
                        raise RuntimeError('RCON closed')
                    data += chunk
                return data
            length = struct.unpack('<i', read(4))[0]
            data = read(length)
            return struct.unpack('<ii', data[:8]), data[8:-2].decode()
        send(1, 3, password)
        header, _ = receive()
        assert header[0] == 1
        send(2, 2, text)
        header, response = receive()
        assert header[0] == 2
        return response


def client(name):
    binary = args.factorio if name == 'client-a' else args.second_client
    args_list = [str(binary), '--config', str(root / name / 'config.ini'), '--mod-directory', str(mods),
        '--mp-connect', f'127.0.0.1:{port}', '--disable-audio', '--window-size', '1280x800']
    processes[name] = subprocess.Popen(args_list, stdout=(root / name / 'launch.log').open('w'),
        stderr=subprocess.STDOUT, env=env, start_new_session=True)


def stop():
    for process in processes.values():
        if process.poll() is None:
            process.terminate()
    for process in processes.values():
        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def server(reload=False):
    args_list = [str(args.factorio), '--config', str(root / 'server/config.ini'), '--mod-directory', str(mods),
        '--bind', '127.0.0.1', '--port', str(port), '--rcon-bind', f'127.0.0.1:{rcon_port}',
        '--rcon-password', password, '--server-settings', str(root / 'server/server-settings.json')]
    args_list += ['--start-server', str(root / 'server/saves/multiplayer-qa.zip')] if reload else ['--start-server-load-scenario', 'multiplayer']
    process = subprocess.Popen(args_list, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        env=env, start_new_session=True)
    processes['server'] = process
    timer = Timer(240, process.terminate)
    timer.start()
    joins = 0
    passed = False
    saving = False
    try:
        with (root / 'server' / ('reload.log' if reload else 'launch.log')).open('w') as log:
            for line in process.stdout:
                log.write(line); log.flush()
                if 'Hosting game at' in line:
                    client('client-a')
                if '[JOIN]' in line:
                    joins += 1
                    if joins == 1:
                        client('client-b')
                    elif joins == 2:
                        action = 'verify_reload' if reload else 'start'
                        command('/c remote.call("entourage_multiplayer_qa", "' + action + '")')
                    elif joins == 3:
                        command('/c remote.call("entourage_multiplayer_qa", "reconnect")')
                if 'ENTOURAGE MULTIPLAYER' in line:
                    print(line.strip(), flush=True)
                if 'ready for second client disconnect' in line:
                    processes['client-b'].terminate()
                    processes['client-b'].wait(timeout=15)
                if 'remaining client keeps working' in line:
                    client('client-b')
                if 'ENTOURAGE MULTIPLAYER INTEGRATION PASS' in line or (reload and 'server save, reload and reconnect retain both fleets' in line):
                    assert command('/c rcon.print(#game.connected_players)').strip() == '2', 'Two clients must remain connected'
                    for name in ['client-a', 'client-b']:
                        text = (root / name / 'launch.log').read_text()
                        assert 'Desynchronisation' not in text and 'Desync' not in text, name + ' desynced'
                    if not reload:
                        command('/c game.server_save("multiplayer-qa")')
                        saving = True
                    else:
                        passed = True
                        break
                if saving and 'Saving finished' in line:
                    passed = True
                    break
                if 'Error MainLoop' in line or 'non-recoverable error' in line:
                    raise RuntimeError(line)
    finally:
        timer.cancel()
    assert passed, 'Multiplayer test did not finish; inspect ' + str(root)


print('Artifacts:', root, flush=True)
try:
    server()
    stop()
    server(reload=True)
    if args.keep_running:
        (root / 'processes.json').write_text(json.dumps({name: process.pid for name, process in processes.items()}))
        (root / 'passed').write_text('Two clients, dedicated server, reconnect and save reload passed\n')
        print('Session left running:', root, flush=True)
        with (root / 'server/reload.log').open('a') as log:
            for line in processes['server'].stdout:
                log.write(line); log.flush()
    else:
        stop()
except BaseException:
    stop()
    raise
