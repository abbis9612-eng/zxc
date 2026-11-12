import json, math, os, subprocess
from concurrent.futures import ThreadPoolExecutor
F=json.load(open('../terrain/field.json'))
X0,Y0=F['x0'],F['y0']   # بكسلات z11
jobs=[]
def region(z, fx0, fy0, fx1, fy1):
    s=2**(z-11)                      # z بكسل = z11 بكسل × s
    px0,py0=X0*s+fx0*s/2, Y0*s+fy0*s/2; px1,py1=X0*s+fx1*s/2, Y0*s+fy1*s/2
    return int(px0//256),int(py0//256),int(px1//256),int(py1//256),px0,py0,px1,py1
for z,box in [(12,(0,0,F['w'],F['h'])),(13,(560,380,1960,2180))]:
    tx0,ty0,tx1,ty1,*_=region(z,*box)
    for ty in range(ty0,ty1+1):
        for tx in range(tx0,tx1+1):
            jobs.append((f's{z}_{tx}_{ty}.jpg',f'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2020_3857/default/g/{z}/{ty}/{tx}.jpg'))
            jobs.append((f'e{z}_{tx}_{ty}.png',f'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{tx}/{ty}.png'))
def get(j):
    f,u=j
    if os.path.exists(f) and os.path.getsize(f)>500: return 0
    subprocess.run(['curl','-s','-m','40','-o',f,u]); return 1
with ThreadPoolExecutor(8) as ex: n=sum(ex.map(get,jobs))
bad=[f for f,u in jobs if not os.path.exists(f) or os.path.getsize(f)<500]
print(len(jobs),'fetched',n,'bad',len(bad),bad[:5])
