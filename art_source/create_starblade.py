"""Original Starblade redesign. Blender mesh authoring, playable node rig, PBR export."""
import bpy, math, os, sys
from mathutils import Vector
from math import sin, cos, pi
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT=os.path.join(ROOT,'build','showcase')
os.makedirs(OUT,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)

def mat(name,c,metal=0,rough=.5,emission=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1)
 p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 if emission:p.inputs['Emission Color'].default_value=(*c,1);p.inputs['Emission Strength'].default_value=emission
 return m
steel=mat('Deep petrol enamel',(.035,.115,.16),.65,.36)
silver=mat('Pale tempered steel',(.40,.52,.57),.72,.34)
gold=mat('Warm champagne trim',(.49,.31,.12),.7,.38)
dark=mat('Joint leather',(.025,.032,.042),0,.72)
cloth=mat('Indigo woven mantle',(.024,.060,.14),0,.87)
lining=mat('Mantle warm lining',(.16,.07,.045),0,.83)
light=mat('Star glass',(.06,.65,.85),.25,.28,1.3)
white=mat('Ivory heraldry',(.64,.69,.65),.25,.5)

def mesh(name,vs,fs,material,smooth=False,parent=None):
 me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update()
 o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);me.materials.append(material)
 for p in me.polygons:p.use_smooth=smooth
 if parent:
  bpy.context.view_layer.update();world=o.matrix_world.copy();o.parent=parent;o.matrix_world=world
 return o
def bevel(o,w=.015):
 m=o.modifiers.new('Forged edge','BEVEL');m.width=w;m.segments=3
 o.modifiers.new('Weighted face normals','WEIGHTED_NORMAL');return o
def pivot(name,loc):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=loc;return o
def attach(o,p):
 bpy.context.view_layer.update();w=o.matrix_world.copy();o.parent=p;o.matrix_world=w;return o
def loft(name,rings,material,cx=0,parent=None,n=32):
 # rings = height, half-width, half-depth, depth-offset
 vs=[(cx+w*cos(2*pi*j/n),cy+d*sin(2*pi*j/n),z) for z,w,d,cy in rings for j in range(n)]
 fs=[(i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j) for i in range(len(rings)-1) for j in range(n)]
 fs += [tuple(reversed(range(n))),tuple((len(rings)-1)*n+j for j in range(n))]
 o=mesh(name,vs,fs,material,True,parent);return bevel(o,.009)
def line(name,pts,r,material,parent=None,closed=False):
 c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.bevel_depth=r;c.bevel_resolution=2
 s=c.splines.new('POLY');s.points.add(len(pts)-1)
 for p,co in zip(s.points,pts):p.co=(*co,1)
 s.use_cyclic_u=closed;o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);c.materials.append(material)
 return attach(o,parent) if parent else o
def plate(name,outline,material,depth=.035,ridge=.035,parent=None):
 # planar outline in xyz with a shallow raised central ridge
 center=sum((Vector(p) for p in outline),Vector())/len(outline);center.y-=ridge
 vs=outline+[tuple(center)]+[(x,y+depth,z) for x,y,z in outline]
 n=len(outline);fs=[(i,(i+1)%n,n) for i in range(n)]+[(i,n+1+i,n+1+(i+1)%n,(i+1)%n) for i in range(n)]
 fs.append(tuple(reversed(range(n+1,2*n+1))))
 return bevel(mesh(name,vs,fs,material,False,parent),.008)
def gem(name,x,y,z,size,parent=None):
 return plate(name,[(x,y,z+size),(x+size*.55,y,z),(x,y,z-size),(x-size*.55,y,z)],light,.025,.025,parent)

# Long legs and tailored torso. All coordinates authored in one space before parenting.
loft('Flexible core',[(1.15,.24,.155,0),(1.42,.22,.15,0),(1.70,.36,.20,0),(1.96,.41,.19,.01),(2.05,.25,.16,.01)],dark)
loft('Continuous tapered cuirass',[(1.48,.225,.16,-.005),(1.58,.27,.20,-.005),(1.78,.375,.235,0),(1.94,.39,.22,0),(2.04,.23,.17,0)],steel)
# Large clear breast facets and a single restrained focal point.
for s in [-1,1]:
 plate('Swept breast plate',[(s*.015,-.242,1.77),(s*.04,-.19,2.005),(s*.29,-.16,2.00),(s*.37,-.14,1.88),(s*.28,-.21,1.80),(s*.07,-.245,1.69)],silver,.023,.022)
 line('Breast gold seam',[(s*.02,-.265,1.72),(s*.22,-.25,1.80),(s*.34,-.18,1.9)],.012,gold)
for i in range(3):
 z=1.43+i*.085
 plate('Overlapping waist lame', [(-.225-i*.009,-.15,z+.07),(0,-.20,z+.10),(.225+i*.009,-.15,z+.07),(.21,-.15,z),(0,-.20,z-.025),(-.21,-.15,z)],steel,.028,.018)
loft('Leather waist belt',[(1.34,.247,.17,0),(1.40,.248,.17,0)],dark)
plate('Belt buckle', [(-.075,-.19,1.4),(.075,-.19,1.4),(.075,-.19,1.31),(-.075,-.19,1.31)],gold,.028,.008)
gem('Breast star',0,-.277,1.88,.065)
for k in range(3):
 z=2.00+k*.045
 loft('Raised gorget',[(z,.205-k*.018,.16,0),(z+.037,.197-k*.018,.15,0)],silver if k==2 else steel)

# Helmet with a long tapered face, wide eyebrow line and swept twin temporal fins.
loft('Helmet cranial shell',[(2.10,.11,.12,0),(2.18,.18,.16,0),(2.37,.195,.175,.01),(2.50,.14,.13,.035),(2.54,.065,.075,.04)],steel,n=40)
plate('Pointed ivory faceplate',[(-.172,-.125,2.36),(-.13,-.20,2.18),(0,-.245,2.095),(.13,-.20,2.18),(.172,-.125,2.36),(0,-.235,2.31)],silver,.035,.045)
for s in [-1,1]:
 line('Dark eye recess',[(s*.018,-.25,2.365),(s*.09,-.227,2.382),(s*.177,-.16,2.398)],.019,dark)
 line('Luminous eye slit',[(s*.025,-.268,2.367),(s*.088,-.243,2.381),(s*.15,-.19,2.391)],.006,light)
 line('Eyebrow blade',[(0,-.26,2.40),(s*.09,-.227,2.415),(s*.19,-.14,2.43)],.014,gold)
 plate('Swept temple wing',[(s*.145,-.06,2.38),(s*.19,.03,2.48),(s*.23,.23,2.56),(s*.205,.205,2.43),(s*.18,.13,2.29)],silver,.025,.008)
line('Face center ridge',[(0,-.28,2.34),(0,-.297,2.23),(0,-.26,2.11)],.009,gold)
plate('Helmet median crest',[(-.027,-.115,2.47),(0,-.09,2.63),(.027,-.115,2.47),(0,-.17,2.42)],gold,.17,.005)

# Segmented armor follows the limbs; no detached ornaments.
arms=[];legs=[]
for s,label in [(-1,'L'),(1,'R')]:
 ax=s*.44;arm=pivot('Arm'+label,(ax,0,1.94));arms.append(arm)
 loft('Sleeve '+label,[(1.26,.088,.09,0),(1.50,.10,.105,0),(1.74,.125,.115,0),(1.91,.12,.12,0)],dark,ax,arm)
 loft('Upper arm armor '+label,[(1.62,.11,.115,0),(1.82,.13,.13,0),(1.91,.105,.115,0)],steel,ax,arm)
 loft('Long vambrace '+label,[(1.26,.095,.10,-.01),(1.34,.13,.125,-.01),(1.52,.115,.11,0),(1.56,.09,.09,0)],silver,ax,arm)
 plate('Vambrace tapered insert '+label,[(ax-.055,-.12,1.48),(ax,-.148,1.55),(ax+.055,-.12,1.48),(ax+.06,-.14,1.33),(ax,-.15,1.285),(ax-.06,-.14,1.33)],steel,.025,.015,arm)
 loft('Glove '+label,[(1.10,.072,.065,-.025),(1.16,.09,.095,-.025),(1.27,.08,.085,-.015)],dark,ax,arm)
 for j in range(3):
  plate('Gauntlet knuckle',[(ax-.077,-.112,1.17+j*.027),(ax+.077,-.112,1.17+j*.027),(ax+.065,-.116,1.19+j*.027),(ax-.065,-.116,1.19+j*.027)],silver,.014,0,arm)
 # Leg seam leaves air between the legs at gameplay scale.
 lx=s*.155;leg=pivot('Leg'+label,(lx,0,1.27));legs.append(leg)
 loft('Leg leather '+label,[(.20,.085,.095,.035),(.67,.09,.10,0),(1.0,.13,.13,0),(1.27,.14,.14,0)],dark,lx,leg)
 loft('Thigh armor '+label,[(.77,.095,.115,-.006),(1.05,.14,.14,0),(1.22,.13,.13,0)],steel,lx,leg)
 plate('Knee shield '+label,[(lx-.105,-.105,.77),(lx,-.17,.84),(lx+.105,-.105,.77),(lx+.085,-.12,.65),(lx,-.17,.59),(lx-.085,-.12,.65)],silver,.04,.025,leg)
 loft('Sculpted greave '+label,[(.19,.09,.10,.015),(.30,.105,.115,0),(.51,.115,.12,0),(.65,.085,.09,0)],steel,lx,leg)
 line('Greave highlight '+label,[(lx,-.105,.22),(lx,-.139,.46),(lx,-.105,.59)],.012,silver,leg)
 loft('Sabatons '+label,[(.045,.105,.19,-.075),(.085,.125,.21,-.075),(.16,.115,.175,-.055),(.24,.085,.09,.01)],silver,lx,leg)
 for k in range(3):
  line('Foot articulated seam',[(lx-.09,-.13-k*.045,.15-k*.022),(lx,-.15-k*.045,.17-k*.024),(lx+.09,-.13-k*.045,.15-k*.022)],.008,steel,leg)
 # Floating tassets overlap hips, distinct from the legs below.
 plate('Hip tasset '+label,[(s*.07,-.18,1.31),(s*.235,-.14,1.34),(s*.29,-.135,1.12),(s*.17,-.20,1.06),(s*.07,-.21,1.13)],steel,.04,.025)

# Swept planar shoulder plates, with an elevated ridge and an articulated lower lame.
for s,arm in zip([-1,1],arms):
 big=s<0;cx=s*.44;w=.31 if big else .195
 for layer in range(2 if big else 1):
  z=1.96-layer*.10
  outline=[(cx-s*.18,-.13,z+.08),(cx+s*.015,-.16,z+.16),(cx+s*w,-.11,z+.08),(cx+s*(w+.025),-.07,z-.055),(cx+s*.18,-.17,z-.12),(cx-s*.105,-.17,z-.05)]
  plate('Crescent pauldron '+str(s)+str(layer),outline,steel,.045,.035,arm)
  line('Pauldron rolled edge',outline[2:]+[outline[0]],.010,gold,arm)
 if big:
  plate('Pauldron star crest',[(cx-.14,-.222,2.065),(cx,-.265,2.16),(cx+.14,-.222,2.065),(cx,-.265,1.91)],silver,.025,.015,arm)
  gem('Shoulder aether',cx,-.293,2.045,.054,arm)

# A single flowing diagonal mantle creates a recognizable silhouette and quiet color mass.
cape=pivot('Tailored pleated cape',(-.30,.14,2.02))
vs=[];fs=[];rows=30;cols=32
for i in range(rows+1):
 t=i/rows
 for j in range(cols+1):
  u=j/cols
  x=-.43+u*.66 + t*(-.48+.10*u)
  y=.15+.27*t + .065*sin(u*pi*6+t)*sin(t*pi*.8)
  z=2.01-1.47*t + .20*u*t + .075*sin(u*pi*2)*t*t
  vs.append((x,y,z))
for i in range(rows):
 for j in range(cols):
  k=i*(cols+1)+j;fs.append((k,k+1,k+cols+2,k+cols+1))
o=mesh('Sweeping indigo mantle',vs,fs,cloth,True,cape);o.data.materials.append(lining)
sol=o.modifiers.new('Cloth lined thickness','SOLIDIFY');sol.thickness=.012;sol.material_offset=1
line('Mantle pale hem',vs[-(cols+1):],.011,gold,cape)
line('Mantle outer edge',[vs[i*(cols+1)] for i in range(rows+1)],.011,gold,cape)
line('Mantle shoulder chain',[(-.40,-.16,2.02),(-.29,-.255,1.95),(-.15,-.255,1.96),(-.07,-.22,2.025)],.012,gold)
# Split cloth tabard frames the waist without hiding the long legs.
for s in [-1,1]:
 plate('Ivory split tabard',[(s*.02,-.22,1.32),(s*.115,-.205,1.31),(s*.17,-.205,.94),(s*.095,-.245,.83),(s*.035,-.24,.91)],cloth,.009,0)
 line('Tabard embroidery',[(s*.055,-.249,.94),(s*.075,-.243,1.1),(s*.055,-.243,1.26)],.007,gold)

# Long diamond-section sword held point-down; silhouette clear of both legs.
arm=arms[1];sx=.55
line('Sword grip',[(sx,-.04,1.08),(sx,-.04,1.34)],.035,dark,arm)
for k in range(7):
 line('Grip binding',[(sx+.035*cos(a*2*pi/20),-.04+.035*sin(a*2*pi/20),1.10+k*.031) for a in range(21)],.004,gold,arm)
plate('Swept sword crossguard',[(sx-.24,-.05,1.07),(sx-.15,-.06,1.16),(sx,-.06,1.11),(sx+.15,-.06,1.16),(sx+.24,-.05,1.07),(sx+.13,-.06,1.09),(sx,-.06,1.055),(sx-.13,-.06,1.09)],gold,.065,.01,arm)
gem('Sword pommel',sx,-.04,1.37,.055,arm)
plate('Starblade',[(sx-.072,-.04,1.06),(sx-.09,-.04,.89),(sx-.067,-.04,.28),(sx,-.04,.085),(sx+.067,-.04,.28),(sx+.09,-.04,.89),(sx+.072,-.04,1.06)],silver,.05,.065,arm)
line('Blade aether fuller',[(sx,-.108,.25),(sx,-.11,.92),(sx,-.10,1.025)],.009,light,arm)
# Grip hand shifted to sword handle rather than having a floating weapon.
for o in list(bpy.context.scene.objects):
 if o.parent==arm and ('Glove R' in o.name or 'Gauntlet knuckle' in o.name):o.location.x+=.10

scene=bpy.context.scene
# Seat the decorative breast faces on the evaluated cuirass rather than intersecting it.
from mathutils.bvhtree import BVHTree
bpy.context.view_layer.update()
bvh=BVHTree.FromObject(bpy.data.objects['Continuous tapered cuirass'],bpy.context.evaluated_depsgraph_get())
for o in list(scene.objects):
 if o.name.startswith('Swept breast plate'):
  for v in o.data.vertices:
   hit,normal,index,distance=bvh.ray_cast(Vector((v.co.x,-2,v.co.z)),Vector((0,1,0)))
   if hit is not None:v.co.y=hit.y-(.022 if v.index<6 else .047 if v.index==6 else .006)
 if o.type=='CURVE' and o.name.startswith('Breast gold seam'):
  for p in o.data.splines[0].points:
   hit,normal,index,distance=bvh.ray_cast(Vector((p.co.x,-2,p.co.z)),Vector((0,1,0)))
   if hit is not None:p.co.y=hit.y-.04
# An open stance leaves clear negative space beside the waist and between the boots.
arms[0].rotation_euler.y=.12;arms[1].rotation_euler.y=-.15
legs[0].rotation_euler.y=.035;legs[1].rotation_euler.y=-.035
legs[0].location.y=-.055;legs[1].location.y=.055
# Freeze modeling modifiers before export so merged materials retain proper normals.
for o in list(scene.objects):
 if o.type in {'CURVE','MESH'}:
  bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH')
hero_objects=list(scene.objects)

def area(name,loc,power,color,size):
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.color=color;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,1.3))-o.location).to_track_quat('-Z','Y').to_euler()
def camera(loc,target,scale):
 scene.camera.location=loc;scene.camera.rotation_euler=(Vector(target)-scene.camera.location).to_track_quat('-Z','Y').to_euler();scene.camera.data.ortho_scale=scale
world=bpy.data.worlds.new('Soft studio');scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.12,.16,.22,1);world.node_tree.nodes['Background'].inputs[1].default_value=.35
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,.0));floor=bpy.context.object;floor.name='Studio floor';floor.data.materials.append(mat('Studio slate',(.025,.035,.055),0,.7))
area('Key',(-3,-4,6),650,(1,.88,.73),4);area('Rim',(3,2,4),850,(.35,.63,1),3);area('Fill',(3,-4,2),260,(.65,.8,1),3)
bpy.ops.object.camera_add();scene.camera=bpy.context.object;scene.camera.data.type='ORTHO'
camera((3,-6,3.4),(0,0,1.35),3.5)
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
scene.render.resolution_x=1000;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
 for d in prefs.devices:d.use=d.type!='CPU'
 scene.cycles.device='GPU'
except Exception:pass

# Compare three genuinely different body envelopes before the beauty pass.
clay=mat('Design study clay',(.28,.32,.36),0,.65)
scene.view_layers[0].material_override=clay
scene.render.resolution_x=540;scene.render.resolution_y=660;scene.cycles.samples=16
for name,xscale,zscale in [('bulwark',1.22,.90),('starblade',1,1),('duelist',.83,1.04)]:
 for o in hero_objects:
  if not o.parent:o.scale.x*=xscale;o.scale.z*=zscale;o.location.x*=xscale;o.location.z*=zscale
 bpy.context.view_layer.update();scene.render.filepath=os.path.join(OUT,'hero-study-'+name+'.png');bpy.ops.render.render(write_still=True)
 for o in hero_objects:
  if not o.parent:o.scale.x/=xscale;o.scale.z/=zscale;o.location.x/=xscale;o.location.z/=zscale
scene.view_layers[0].material_override=None
scene.render.resolution_x=1000;scene.render.resolution_y=1100;scene.cycles.samples=32
scene.render.filepath=os.path.join(OUT,'starblade-beauty.png');bpy.ops.render.render(write_still=True)
camera((3.6,5,3.2),(0,0,1.35),3.5);scene.render.filepath=os.path.join(OUT,'starblade-back.png');bpy.ops.render.render(write_still=True)
camera((3,-6,3.4),(0,0,1.35),3.5)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'art_source','starblade_studio.blend'))

# Export only the playable character with -Z forward in Godot.
for o in list(scene.objects):
 if o not in hero_objects:bpy.data.objects.remove(o,do_unlink=True)
axis=pivot('HeroAxis',(0,0,0))
for o in hero_objects:
 if not o.parent:attach(o,axis)
axis.rotation_euler.z=pi
for team in ['blue','red']:
 if team=='red':
  for m,c in [(steel,(.19,.045,.065)),(cloth,(.14,.022,.045)),(light,(.85,.13,.11))]:
   m.diffuse_color=(*c,1);p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1)
   if m==light:p.inputs['Emission Color'].default_value=(*c,1)
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'art_source','hero_starblade_'+team+'.blend'))
 bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT,'assets','models','hero_starblade_'+team+'.glb'),export_format='GLB',export_yup=True)
print('STARBlade_EXPORT_COMPLETE',sum(len(o.data.polygons) for o in hero_objects if o.type=='MESH'))
