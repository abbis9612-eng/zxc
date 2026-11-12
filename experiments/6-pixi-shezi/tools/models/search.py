import json, sys, urllib.request, urllib.parse
def q(term, n=8):
    url = 'https://api.sketchfab.com/v3/search?' + urllib.parse.urlencode({'type': 'models', 'q': term, 'downloadable': 'true', 'count': 24, 'sort_by': '-likeCount'})
    d = json.load(urllib.request.urlopen(url, timeout=40))
    out = []
    for m in d['results']:
        lic = (m.get('license') or {}).get('label', '?')
        out.append((m['likeCount'], m['faceCount'], lic, m['name'][:60], m['user']['username'], m['uid']))
    return out[:n]
for term in sys.argv[1:]:
    print('==', term)
    for r in q(term): print('  ', r)
