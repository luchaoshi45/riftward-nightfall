from pathlib import Path
p=Path('art_source/create_assets.py')
s=p.read_text(encoding='utf-8-sig').replace("p.inputs['Roughness'].default_value = .64", "p.inputs['Roughness'].default_value = .88")
a=s.index('for i in range(26):')
b=s.index("export('oak')",a)
s=s[:a]+'''# Angular overlapping leaf sprays: a layered silhouette instead of bubble spheres.
verts=[]; faces=[]; slots=[]
for i in range(180):
    a=random.random()*math.tau
    r=math.sqrt(random.random())*1.65
    z=3.5-r*.42+random.uniform(-.35,.3)
    cx,cy=math.cos(a)*r,math.sin(a)*r
    angle=a+random.uniform(-.8,.8)
    length=random.uniform(.28,.57); width=length*random.uniform(.4,.7)
    start=len(verts)
    for x,y,h in [(0,-length,.0),(-width,-length*.25,-.08),(-width*.7,length*.55,-.1),(0,length,.0),(width*.7,length*.55,-.1),(width,-length*.25,-.08),(0,0,.08)]:
        verts.append((cx+x*math.cos(angle)-y*math.sin(angle),cy+x*math.sin(angle)+y*math.cos(angle),z+h))
    for j in range(6):
        faces.append((start+6,start+j,start+(j+1)%6)); slots.append(min(4,int((z-2.3)*2.5))%5)
mesh=bpy.data.meshes.new('Layered leaf sprays'); mesh.from_pydata(verts,[],faces); mesh.update()
obj=bpy.data.objects.new('Leaf sprays',mesh); bpy.context.collection.objects.link(obj)
for mat in foliage: mesh.materials.append(mat)
for poly,slot in zip(mesh.polygons,slots): poly.material_index=slot
uv=mesh.uv_layers.new(name='Leaf UV')
for poly in mesh.polygons:
    for j,li in enumerate(poly.loop_indices): uv.data[li].uv=[(.5,.5),(0,0),(1,1)][j]
''' + s[b:]
p.write_text(s,encoding='utf-8')
