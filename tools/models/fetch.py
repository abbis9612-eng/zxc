import json, sys, urllib.request, os
for name, uid in [a.split('=') for a in sys.argv[1:]]:
    info = json.load(urllib.request.urlopen(f'https://api.sketchfab.com/v3/models/{uid}', timeout=40))
    d = json.load(urllib.request.urlopen(f'https://api.sketchfab.com/v3/models/{uid}/download', timeout=40))
    k = 'glb' if 'glb' in d else 'gltf'
    os.makedirs(name, exist_ok=True)
    fn = f'{name}/{name}.' + ('glb' if k == 'glb' else 'zip')
    urllib.request.urlretrieve(d[k]['url'], fn)
    lic = info.get('license') or {}
    meta = {'name': info['name'], 'author': info['user']['displayName'], 'username': info['user']['username'], 'url': info['viewerUrl'], 'license': lic.get('label'), 'license_url': lic.get('url'), 'faces': info.get('faceCount')}
    json.dump(meta, open(f'{name}/source.json', 'w'), ensure_ascii=False, indent=1)
    print(name, os.path.getsize(fn), meta['license'], meta['author'])
