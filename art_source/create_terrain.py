"""Build the Riftward arena as editable, low relief Blender geometry.

The terrain matches BattleMap.route(), BattleMap.FORESTS and the existing flat
navigation plane.  Sculptural relief stays below gameplay foot height.
"""
import bpy, math, random, os
from math import sin, cos, pi, exp

ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
random.seed(741)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)

def material(name,color,roughness=1.0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1)
 p.inputs['Roughness'].default_value=roughness;p.inputs['Metallic'].default_value=0
 return m

earth=material('Moss soil underlay',(.065,.082,.052))
roadbed=material('Compressed lane earth',(.055,.063,.047))
stone=[material('Weathered flagstone '+str(i),c,.98) for i,c in enumerate([
 (.105,.128,.115),(.14,.15,.125),(.088,.107,.099),(.175,.174,.133),(.12,.135,.105)])]
bank=[material('Riverbank limestone '+str(i),c,.97) for i,c in enumerate([
 (.13,.145,.13),(.10,.13,.125),(.18,.175,.14)])]

def object_mesh(name,verts,faces,mats,indices=None):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
 for m in mats:me.materials.append(m)
 if indices:
  for p,index in zip(me.polygons,indices):p.material_index=index
 o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o)
 return o

def height(x,y):
 small=.012*sin(x*1.31+y*.7)+.008*cos(y*1.93-x*.31)+.007*sin(x*2.77-y*1.54)
 broad=.025*sin(x*.17+y*.11)*cos(y*.20)
 mound=0
 for fx,fy in [(-24,-9),(24,-9),(-24,9),(24,9),(-7,-13),(7,-13),(-7,13),(7,13)]:
  d=(x-fx)**2+(y-fy)**2;mound+=.055*exp(-d/11)
 channel=-.18*(1-min(1,abs(x)/4))**2
 lip=.045*exp(-((abs(x)-4.5)/.8)**2)
 return -.045+small+broad+mound+channel+lip

# A continuous triangulated landscape with a depressed river and low forest mounds.
verts=[];faces=[];step=.65;nx=143;ny=103
for iy in range(ny+1):
 y=(iy-ny/2)*step
 for ix in range(nx+1):
  x=(ix-nx/2)*step
  verts.append((x,y,height(x,y)))
for iy in range(ny):
 for ix in range(nx):
  a=iy*(nx+1)+ix;b=a+1;c=a+nx+1;d=c+1
  faces.extend([(a,b,d),(a,d,c)])
ground=object_mesh('Sculpted arena ground',verts,faces,[earth])
for f in ground.data.polygons:f.use_smooth=True

routes=[]
for side in [-1,1]:
 routes.append([(-38,0),(-30,side*16),(-22,side*22),(-12,side*22),(0,side*22),
                (12,side*22),(22,side*22),(30,side*16),(38,0)])
routes.insert(1,[(-38,0),(-28,0),(-12,0),(0,0),(12,0),(28,0),(38,0)])

# Dark compacted earth appears in the irregular gaps between individually modeled stones.
rbv=[];rbf=[]
for route in routes:
 for a,b in zip(route,route[1:]):
  dx=b[0]-a[0];dy=b[1]-a[1];length=math.hypot(dx,dy)
  px=-dy/length;py=dx/length
  index=len(rbv)
  for point,side in [(a,-3.12),(a,3.12),(b,3.12),(b,-3.12)]:
   x=point[0]+px*side;y=point[1]+py*side
   rbv.append((x,y,.055))
  rbf.extend([(index,index+2,index+1),(index,index+3,index+2)])
object_mesh('Compacted road subgrade',rbv,rbf,[roadbed])

# Batched per-material meshes keep roughly 1,200 unique stone volumes economical.
sections=[([],[]) for _ in stone]
def add_cobble(verts,faces,cx,cy,angle,wide,long,top,material_index):
 local=[]
 corners=[(-.5,-.5),(.33,-.53),(.53,-.28),(.5,.39),(.28,.53),(-.42,.49),(-.54,.21)]
 ca=cos(angle);sa=sin(angle)
 for u,v in corners:
  xx=u*wide;yy=v*long
  local.append((cx+xx*ca-yy*sa,cy+xx*sa+yy*ca))
 start=len(verts);h=top+random.uniform(-.011,.012)
 for x,y in local:verts.append((x,y,h-random.uniform(0,.012)))
 for x,y in local:verts.append((x,y,h-.053))
 faces.append(tuple(start+i for i in range(7)))
 for i in range(7):faces.append((start+i,start+(i+1)%7,start+7+(i+1)%7,start+7+i))
 faces.append(tuple(start+7+i for i in reversed(range(7))))

for route in routes:
 for a,b in zip(route,route[1:]):
  dx=b[0]-a[0];dy=b[1]-a[1];length=math.hypot(dx,dy)
  tx=dx/length;ty=dy/length;px=-ty;py=tx
  count=math.ceil(length/1.03)
  for row in range(count):
   along=(row+.5)*length/count
   for col in range(6):
    if random.random()<.055:continue
    along_col=along+random.uniform(-.20,.20)
    lateral=(col-2.5)*1.02+(row%2-.5)*.54
    x=a[0]+tx*along_col+px*lateral+random.uniform(-.11,.11)
    y=a[1]+ty*along_col+py*lateral+random.uniform(-.11,.11)
    if x*x+y*y<.2:continue
    mi=random.choices(range(len(stone)),[4,3,4,2,3])[0]
    width=random.uniform(.72,1.07);depth=random.uniform(.64,1.04)
    add_cobble(*sections[mi],x,y,math.atan2(ty,tx)-pi/2+random.uniform(-.13,.13),width,depth,.073,mi)
for index,(vs,fs) in enumerate(sections):
 object_mesh('Laid flagstones %d'%index,vs,fs,[stone[index]])

# Layered, broken-bank rock shelves frame the flat water without obstructing navigation.
for side in [-1,1]:
 groups=[([],[]) for _ in bank]
 for k in range(-42,43):
  y=k*.77;cx=side*(3.7+random.uniform(-.08,.19))
  mi=random.randrange(3);vs,fs=groups[mi]
  sx=random.uniform(.35,.59);sy=random.uniform(.31,.47)
  level=.045+random.uniform(-.025,.022)
  start=len(vs)
  coords=[(cx+side*sx*cos(i*2*pi/7),y+sy*sin(i*2*pi/7)) for i in range(7)]
  for x,yy in coords:vs.append((x,yy,level+random.uniform(-.015,.018)))
  for x,yy in coords:vs.append((x,yy,level-.10))
  fs.append(tuple(start+i for i in (range(7) if side==1 else reversed(range(7)))))
  for i in range(7):fs.append((start+i,start+(i+1)%7,start+7+(i+1)%7,start+7+i))
 for i,(vs,fs) in enumerate(groups):object_mesh('Riverbank shelves %d %d'%(side,i),vs,fs,[bank[i]])

blend=os.path.join(ROOT,'art_source','arena_terrain.blend')
glb=os.path.join(ROOT,'assets','models','arena_terrain.glb')
bpy.ops.wm.save_as_mainfile(filepath=blend)
bpy.ops.export_scene.gltf(filepath=glb,export_format='GLB',export_yup=True)
print('ARENA_TERRAIN_COMPLETE',sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH'))
