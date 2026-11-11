import re
s=open('app2.html').read()
w=open('war.js').read()
a=s.index('// ================================================================== معركة دهوك')
b=s.index("home();\naddEventListener('resize', home, {once: true});")
s=s[:a]+w.rstrip()+"\n"+s[b:]
open('app2.html','w').write(s)
rd=lambda f: open(f).read()
out=s.replace("/*__MAPDATA__*/","document.documentElement.dir='rtl';document.documentElement.lang='ar';\n"+rd('mapdata.js')+"\n"+rd('bsprites.js')+"\nconst SPR=BSPR;\n"+rd('sounds.js')+"\n"+rd('vfx.js')+"\n"+rd('field.js')+"\n"+rd('extra3.js'),1)
open('command-room.html','w').write(out)
print(len(out))
