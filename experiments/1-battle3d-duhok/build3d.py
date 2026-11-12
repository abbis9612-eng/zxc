s=open('template.html').read(); a=open('assets3d.js').read()
open('battle3d.html','w').write(s.replace('/*ASSETS*/',a,1)); print(len(s)+len(a))
