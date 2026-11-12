import json, sys, urllib.request, os, zipfile
for name, uid in [a.split('=') for a in sys.argv[1:]]:
    if os.path.exists(f'{name}/source.json'): print('skip', name); continue
    try:
        info = json.load(urllib.request.urlopen(f'https://api.sketchfab.com/v3/models/{uid}', timeout=40))
        d = json.load(urllib.request.urlopen(f'https://api.sketchfab.com/v3/models/{uid}/download', timeout=40))
        os.makedirs(name, exist_ok=True)
        if 'glb' in d: urllib.request.urlretrieve(d['glb']['url'], f'{name}/{name}.glb')
        else:
            urllib.request.urlretrieve(d['gltf']['url'], f'{name}/m.zip'); zipfile.ZipFile(f'{name}/m.zip').extractall(name)
        lic = info.get('license') or {}
        json.dump({'name': info['name'], 'author': info['user']['displayName'], 'url': info['viewerUrl'], 'license': lic.get('label'), 'faces': info.get('faceCount')}, open(f'{name}/source.json', 'w'), ensure_ascii=False)
        print('ok', name, lic.get('label'))
    except Exception as e: print('FAIL', name, str(e)[:100])
