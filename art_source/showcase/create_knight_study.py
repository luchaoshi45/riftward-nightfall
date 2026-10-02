"""Original knight bust study, authored as editable Blender geometry. Offline showcase."""
import bpy, math, random, os
from mathutils import Vector
from math import sin, cos, pi
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT=os.path.join(ROOT,'build','showcase')
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
random.seed(71)
def material(name,color,metal=0,rough=.4):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 n=m.node_tree.nodes;l=m.node_tree.links;p=n.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 tex=n.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=180;tex.inputs['Detail'].default_value=2
 bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.08;bump.inputs['Distance'].default_value=.002;l.new(tex.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs['Normal'],p.inputs['Normal'])
 ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=(rough*.65,)*3+(1,);ramp.color_ramp.elements[1].color=(min(.95,rough*1.3),)*3+(1,);l.new(tex.outputs['Fac'],ramp.inputs[0]);l.new(ramp.outputs['Color'],p.inputs['Roughness'])
 return m
steel=material('01 | tempered midnight steel',(.065,.105,.135),.86,.30)
silver=material('02 | brushed silver edges',(.38,.46,.48),.88,.27)
gold=material('03 | engraved aged electrum',(.48,.29,.095),.82,.31)
black=material('04 | recessed black leather',(.011,.017,.018),0,.66)
cloth=material('05 | midnight woven mantle',(.013,.045,.062),0,.83)
stone=material('06 | honed basalt',(.026,.030,.034),.12,.55)
emit=material('07 | dim aether glass',(.015,.18,.22),.4,.25)
p=emit.node_tree.nodes.get('Principled BSDF');p.inputs['Emission Color'].default_value=(.025,.5,.65,1);p.inputs['Emission Strength'].default_value=1.8

def mesh(name,vs,fs,mat,smooth=True):
 me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);me.materials.append(mat)
 for f in me.polygons:f.use_smooth=smooth
 return o

def loft(name,rings,mat,N=64):
 vs=[]
 for z,w,d,cy in rings:
  for j in range(N):
   a=j*2*pi/N;vs.append((cos(a)*w,cy+sin(a)*d,z))
 fs=[(i*N+j,i*N+(j+1)%N,(i+1)*N+(j+1)%N,(i+1)*N+j) for i in range(len(rings)-1) for j in range(N)]
 fs.extend([tuple(reversed(range(N))),tuple((len(rings)-1)*N+j for j in range(N))]);o=mesh(name,vs,fs,mat)
 mod=o.modifiers.new('Crafted continuous surface','SUBSURF');mod.levels=2
 return o

def curve(name,points,r,mat,cyclic=False):
 c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.resolution_u=16;c.bevel_depth=r;c.bevel_resolution=3
 s=c.splines.new('POLY');s.points.add(len(points)-1)
 for p,co in zip(s.points,points):p.co=(*co,1)
 s.use_cyclic_u=cyclic;o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);c.materials.append(mat);return o

def sphere(name,loc,scale,mat):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,location=loc);o=bpy.context.object;o.name=name;o.scale=scale;o.data.materials.append(mat)
 for p in o.data.polygons:p.use_smooth=True
 return o

def cylinder(name,z,r,depth,mat):
 bpy.ops.mesh.primitive_cylinder_add(vertices=96,radius=r,depth=depth,location=(0,0,z));o=bpy.context.object;o.name=name;o.data.materials.append(mat)
 b=o.modifiers.new('Lathed bevel','BEVEL');b.width=.018;b.segments=3;o.modifiers.new('Weighted normals','WEIGHTED_NORMAL');return o
# Bust base and understructure.
cylinder('Museum plinth lower',.12,.63,.24,stone);cylinder('Plinth gold reveal',.25,.59,.025,gold);cylinder('Plinth bevel top',.29,.57,.06,stone)
loft('Hidden leather torso',[(.31,.33,.21,0),(.4,.39,.23,0),(.9,.59,.31,0),(1.2,.67,.30,0),(1.45,.37,.22,0)],black)
loft('Anatomically shaped cuirass',[(.35,.34,.24,-.015),(.4,.38,.25,-.015),(.66,.44,.28,-.01),(.94,.58,.345,0),(1.16,.64,.32,0),(1.33,.47,.245,0),(1.36,.43,.23,0)],steel)
# Swept raised plate borders follow the breast contours.
for s in [-1,1]:
 pts=[]
 for i in range(65):
  t=i/64;x=s*(.04+.51*t);z=.76+.46*t;y=-.34*math.sqrt(max(.1,1-(x/.72)**2))-.018
  pts.append((x,y,z))
 curve('Cuirass sculpted chevron',pts,.014,gold)
 for j in range(3):
  pts=[(s*(.075+.41*t/40),-.338+.09*(t/40)**2,.87+j*.065+.26*t/40) for t in range(41)]
  curve('Recessed radiating breast engraving',pts,.0035,silver)
 # Leaf scroll inlays following plate surface.
 for k in range(5):
  cx=s*(.17+k*.067);cz=1.16-k*.03
  pts=[(cx+s*.035*sin(t*pi/24),-.327+.10*(abs(cx)/.6)**2,cz+.065*t/24) for t in range(25)]
  curve('Hand laid filigree leaf',pts,.004,gold)
# Collar nested steel layers.
for k in range(4):
 z=1.29+k*.047
 loft('Articulated gorget %02d'%k,[(z,.30-k*.017,.225-k*.011,0),(z+.022,.305-k*.017,.23-k*.011,0),(z+.039,.29-k*.017,.22-k*.011,0)],silver if k==3 else steel)
# Pauldrons are nested shells with scalloped perimeter, not spheres.
for s in [-1,1]:
 for layer in range(3):
  vs=[];fs=[];rows=12;cols=40
  for i in range(rows+1):
   t=i/rows;theta=t*1.68
   for j in range(cols+1):
    a=-pi*.92+j/cols*pi*1.84
    r=.37-layer*.027
    x=s*(.58+(r*sin(theta))*cos(a));y=(r*sin(theta))*sin(a)
    z=1.12-layer*.105+r*cos(theta)+.025*cos(a*3)*t**5
    vs.append((x,y,z))
  for i in range(rows):
   for j in range(cols):
    n=i*(cols+1)+j;fs.append((n,n+1,n+cols+2,n+cols+1))
  o=mesh('Forged shoulder shell %s %s'%(s,layer),vs,fs,steel)
  solid=o.modifiers.new('Armor thickness','SOLIDIFY');solid.thickness=.018
  curve('Rolled shoulder brass rim',vs[-(cols+1):],.012,gold)
  if layer==0:
   for j in range(4,cols,5):sphere('Shoulder inset rivet',vs[-(cols+1)+j],(.012,.012,.012),silver)
 # Ornamental band across top shoulder shell.
 pts=[(s*(.58+.35*sin(.45+i/50*.95)),0,1.12+.35*cos(.45+i/50*.95)+.012) for i in range(51)]
 curve('Shoulder central spine',pts,.011,silver)
# Elegant closed helmet: swept cranial shell and angular visor sections.
loft('Helmet crown continuous shell',[(1.48,.20,.18,.0),(1.54,.265,.22,.0),(1.80,.29,.25,.01),(2.03,.24,.215,.015),(2.14,.12,.12,.025),(2.16,.07,.075,.025)],steel)
# Visor loft patch front, shaped around the jaw with a ridged nose.
vs=[];fs=[];rows=20;cols=40
for i in range(rows+1):
 t=i/rows;z=1.48+t*.38;width=.14+.13*sin(t*pi*.58)
 for j in range(cols+1):
  u=j/cols*2-1
  y=-.17-.105*(1-u*u)-.035*(1-abs(u))*(.3+.7*t)
  vs.append((u*width,y,z+.028*abs(u)*t))
for i in range(rows):
 for j in range(cols):
  n=i*(cols+1)+j;fs.append((n,n+1,n+cols+2,n+cols+1))
o=mesh('Sculpted pointed visor',vs,fs,silver);sol=o.modifiers.new('Visor shell','SOLIDIFY');sol.thickness=.018
curve('Visor nose ridge',[(0,-.288-.035*(.3+.7*t/30),1.48+t/30*.38) for t in range(31)],.009,gold)
for s in [-1,1]:
 # Dark eye recess with a restrained luminous slit.
 pts=[(s*(.025+.205*i/30),-.31+.055*(i/30)**2,1.87+.032*i/30) for i in range(31)]
 curve('Recessed eye socket',pts,.014,black)
 curve('Thin luminous eye',[(x,y-.013,z) for x,y,z in pts[2:-3]],.006,emit)
 curve('Heavy sculpted brow',[(x,y+.006,z+.034) for x,y,z in pts],.011,steel)
 for j in range(5):
  x=s*(.055+j*.033);z=1.60+j*.016
  curve('Visor ventilation cut',[(x,-.298+.13*abs(x),z),(x+s*.008,-.296+.13*abs(x),z+.05)],.006,black)
 sphere('Visor hinge',(s*.27,-.075,1.80),(.034,.022,.034),gold)
 for j in range(3):
  pts=[(s*(.14+.025*j+.027*sin(i/30*pi)), -.19+.03*j,1.94+.11*i/30) for i in range(31)]
  curve('Helmet temple engraving',pts,.004,gold)
# Central crest is a swept solid blade from brow over skull.
vs=[]
for x in [-.012,.012]:
 vs += [(x,-.16,2.04),(x,-.05,2.28),(x,.12,2.23),(x,.26,1.94),(x,.15,2.03),(x,.02,2.14)]
o=mesh('Swept metal crest',vs,[(0,1,2,3,4,5),(11,10,9,8,7,6)]+[(i,(i+1)%6,(i+1)%6+6,i+6) for i in range(6)],gold,False)
b=o.modifiers.new('Crest bevel','BEVEL');b.width=.008;b.segments=3
# Woven mantle flows behind the armor in asymmetric folds.
vs=[];fs=[];rows=44;cols=64
for i in range(rows+1):
 t=i/rows
 for j in range(cols+1):
  u=j/cols*2-1
  x=u*(.46+.27*t)
  y=.14+.25*t+.07*sin(u*pi*5+t*1.3)*sin(pi*t*.8)+.12*u*t
  z=1.34-1.02*t+.06*sin(u*6)*t*t
  vs.append((x,y,z))
for i in range(rows):
 for j in range(cols):
  n=i*(cols+1)+j;fs.append((n,n+1,n+cols+2,n+cols+1))
o=mesh('Woven asymmetric mantle',vs,fs,cloth);sol=o.modifiers.new('Tailored cloth thickness','SOLIDIFY');sol.thickness=.008
curve('Mantle embroidered hem',vs[-(cols+1):],.009,gold)
for s in [-1,1]:
 sphere('Mantle clasp',(s*.34,-.14,1.35),(.055,.025,.055),gold)
 curve('Mantle chain',[(s*.34*(1-t/30),-.26-.045*sin(t/30*pi),1.35-.10*sin(t/30*pi/2)) for t in range(31)],.009,gold)
# Chest insignia concentric metal bezel and cut gemstone.
for radius,mat in [(.072,gold),(.057,black)]:
 curve('Heraldic pendant bezel',[(cos(a*2*pi/64)*radius,-.375,1.16+sin(a*2*pi/64)*radius) for a in range(64)],.008,mat,True)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=(0,-.375,1.16));o=bpy.context.object;o.name='Cut aether gemstone';o.scale=(.043,.025,.055);o.data.materials.append(emit)
# Seat ornamental wires on the evaluated curved armor surface.
from mathutils.bvhtree import BVHTree
bpy.context.view_layer.update()
bvh=BVHTree.FromObject(bpy.data.objects['Anatomically shaped cuirass'],bpy.context.evaluated_depsgraph_get())
for obj in bpy.context.scene.objects:
 if obj.type=='CURVE' and any(obj.name.startswith(tag) for tag in ['Cuirass sculpted chevron','Recessed radiating breast engraving','Hand laid filigree leaf']):
  for spline in obj.data.splines:
   for point in spline.points:
    hit,normal,idx,dist=bvh.ray_cast(Vector((point.co.x,-2,point.co.z)),Vector((0,1,0)))
    if hit is not None:point.co.y=hit.y-.007
# Quiet exhibition stage, no image backplate.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.012));floor=bpy.context.object;floor.name='Studio floor';floor.data.materials.append(material('Studio charcoal',(.012,.019,.022),.15,.48))
world=bpy.data.worlds.new('Studio environment');bpy.context.scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.08,.12,.16,1);world.node_tree.nodes['Background'].inputs[1].default_value=.3

def area(name,loc,power,color,size,target):
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.color=color;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
area('Warm large key',(-3,-4,5),650,(1,.83,.65),3,(0,0,1.2))
area('Cool edge',(2,1.3,3.6),850,(.43,.72,1),2,(0,0,1.3))
area('Frontal softbox',(1,-4,2.2),180,(.75,.88,1),2.5,(0,0,1.2))
area('Brass contour',(-2,1.8,2.5),500,(1,.54,.25),1.8,(0,0,1.1))
bpy.ops.object.camera_add(location=(3.1,-6.3,3.0));cam=bpy.context.object;cam.name='Portrait camera';cam.rotation_euler=(Vector((0,0,1.15))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=2.8;bpy.context.scene.camera=cam
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
 for d in prefs.devices:d.use=d.type!='CPU'
 scene.cycles.device='GPU'
except Exception:pass
scene.render.resolution_x=1200;scene.render.resolution_y=1400;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
scene.render.image_settings.file_format='PNG';scene.render.filepath=os.path.join(OUT,'knight_beauty.png')
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'art_source','showcase','knight_study.blend'))
bpy.ops.render.render(write_still=True)
# A neutral material pass lets the user judge actual geometry.
clay=material('Inspection clay',(.30,.34,.35),0,.65)
scene.view_layers[0].material_override=clay
scene.render.filepath=os.path.join(OUT,'knight_geometry.png');scene.cycles.samples=24
bpy.ops.render.render(write_still=True)
print('KNIGHT_SHOWCASE_COMPLETE')
