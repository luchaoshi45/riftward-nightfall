"""Build editable original assets for the nightfall outpost vertical slice."""
import bpy, math, os, random
from math import sin, cos, pi
from mathutils import Vector

ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT=os.path.join(ROOT,'art_source','outpost')
os.makedirs(OUT,exist_ok=True)

def mat(name,color,metal=0,rough=.85,glow=0):
 m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
 m.diffuse_color=(*color,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF')
 p.inputs['Base Color'].default_value=(*color,1)
 p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 if glow:p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=glow
 return m

soil=mat('Ash compacted earth',(.075,.072,.061))
soil_dark=mat('Scorched earth',(.040,.044,.044))
concrete=mat('Weathered concrete',(.13,.14,.13))
concrete_dark=mat('Concrete fracture',(.060,.075,.074))
steel=mat('Oxidized steel',(.075,.086,.087),.58,.65)
rust=mat('Old iron rust',(.17,.082,.046),.42,.82)
wood=mat('Charred timber',(.070,.046,.031),0,.95)
bone=mat('Night bone',(.16,.18,.17),0,.91)
hide=mat('Shadow hide',(.018,.025,.029),0,.88)
stalker_shell=mat('Ash hound layered carapace',(.043,.066,.067),.16,.72)
stalker_edge=mat('Ash hound pale bone edge',(.21,.24,.21),.04,.83)
stalker_ember=mat('Ash hound molten gaze',(.9,.30,.045),.08,.35,2.8)
stalker_hide=mat('Ash hound smoke hide',(.033,.046,.048),0,.86)
breaker_armor=mat('Breaker scorched iron shell',(.105,.070,.055),.34,.69)
breaker_bone=mat('Breaker impact bone',(.29,.27,.21),.06,.80)
breaker_glow=mat('Breaker furnace fissures',(.82,.10,.035),.06,.39,2.5)
ember=mat('Beacon amber',(.65,.24,.045),.18,.3,1.8)
signal=mat('Signal pale light',(.17,.55,.57),.06,.32,1.1)
blight=mat('Night nest core',(.22,.018,.026),.08,.47,1.25)
charred=mat('Night nest husk',(.025,.023,.029),.04,.93)
shell=mat('Night nest armored shell',(.063,.039,.046),.12,.82)
seal_glow=mat('Sealed nest ward glow',(.065,.31,.32),.04,.4,.7)

def reset():bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def mesh(name,verts,faces,mats,slots=None,smooth=False):
 data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
 for material in mats:data.materials.append(material)
 if slots:
  for face,slot in zip(data.polygons,slots):face.material_index=slot
 for face in data.polygons:face.use_smooth=smooth
 obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj);return obj
def bevel(obj,width=.025):
 modifier=obj.modifiers.new('Worn edges','BEVEL');modifier.width=width;modifier.segments=2
 obj.modifiers.new('Weighted normals','WEIGHTED_NORMAL');return obj
def box(name,loc,size,material,width=.025,rotation=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);obj=bpy.context.object;obj.name=name
 obj.scale=size
 if rotation:obj.rotation_euler=rotation
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 obj.data.materials.append(material)
 return bevel(obj,width) if width else obj
def cone(name,loc,r1,r2,depth,material,segments=12):
 bpy.ops.mesh.primitive_cone_add(vertices=segments,radius1=r1,radius2=r2,depth=depth,location=loc)
 obj=bpy.context.object;obj.name=name;obj.data.materials.append(material);return bevel(obj,.012)
def rod(name,a,b,radius,material,sides=8):
 a,b=Vector(a),Vector(b);mid=(a+b)*.5;direction=b-a
 obj=cone(name,mid,radius,radius*.85,direction.length,material,sides)
 obj.rotation_euler=direction.to_track_quat('Z','Y').to_euler();return obj
def icos(name,loc,scale,material,sub=1):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=loc)
 obj=bpy.context.object;obj.name=name;obj.scale=scale
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 obj.data.materials.append(material);return obj

FORT_HEIGHT=5.0
def plateau_height(x,z):
 edge=max(abs(x),abs(z))
 if z>7.0 and abs(x)<3.2:
  rise=max(0,min(1,(19.0-z)/12.0))
 else:
  rise=max(0,min(1,(9.5-edge)/2.5))
 return FORT_HEIGHT*rise*rise*(3-2*rise)

def ground():
 reset();rng=random.Random(274);verts=[];faces=[];nx=252;ny=220;step=1.0
 for j in range(ny+1):
  z=(j-ny/2)*step
  for i in range(nx+1):
   x=(i-nx/2)*step
   h=-.09+.022*sin(x*.35)*cos(z*.28)+.014*sin(x*1.43+z*.69)
   h*=min(1,math.hypot(x,z)/10)
   h+=plateau_height(x,z)
   verts.append((x,z,h))
 for j in range(ny):
  for i in range(nx):
   p=j*(nx+1)+i;faces.extend([(p,p+1,p+nx+2),(p,p+nx+2,p+nx+1)])
 terrain=mesh('Sculpted ash wasteland',verts,faces,[soil],smooth=True)
 # An irregular concrete yard surrounds the protected beacon.
 for j in range(-5,6):
  for i in range(-5,6):
   if i*i+j*j>33 or rng.random()<.075:continue
   x=i*1.18+rng.uniform(-.08,.08);z=j*1.18+rng.uniform(-.08,.08)
   box('Fractured outpost yard',(x,z,FORT_HEIGHT+.008),(.98,1.0,.10),concrete if rng.random()<.7 else concrete_dark,.018,
       (0,0,rng.uniform(-.09,.09)))
 # Weathered stone facing makes the raised ground readable from the field.
 for side in [-1,1]:
  for offset in [-5.3,-3.2,-1.1,1.1,3.2,5.3]:
   box('Fortress retaining wall',(side*7.65,offset,2.5),(.52,2.04,5.0),concrete_dark,.065)
   box('Light stone parapet lip',(side*7.65,offset,5.03),(.74,2.04,.22),concrete,.025)
   if side>0 or abs(offset)>2.2:
    box('Fortress retaining wall',(offset,-side*7.65,2.5),(2.04,.52,5.0),concrete_dark,.065)
    box('Light stone parapet lip',(offset,-side*7.65,5.03),(2.04,.74,.22),concrete,.025)
 # The single southern entrance is a raised causeway with exposed side faces.
 for z in [8.0+i*1.05 for i in range(11)]:
  h=plateau_height(0,z)
  if h<.16:continue
  for side in [-1,1]:
   box('Causeway stone flank',(side*3.25,z,h*.5),(.48,1.08,h),concrete_dark,.025)
   box('Causeway worn coping',(side*3.25,z,h+.06),(.58,1.08,.12),concrete,.012)
 for arm in range(4):
  direction=arm*pi/2
  for k in range(8,108):
   for side in [-1,0,1]:
    if rng.random()<.16:continue
    dist=k*.92;x=cos(direction)*dist-sin(direction)*side*1.07
    z=sin(direction)*dist+cos(direction)*side*1.07
    box('Broken evacuation road',(x,z,plateau_height(x,z)-.02),(.74,.82,.075),concrete_dark if rng.random()<.57 else concrete,.008,
        (0,0,rng.uniform(-.16,.16)))
 # Small slag heaps interrupt flat outskirts without becoming traversal walls.
 for k in range(520):
  a=rng.random()*2*pi;r=rng.uniform(11,105);x=r*cos(a);z=r*sin(a)
  icos('Half buried slag',(x,z,-.07),(.12+rng.random()*.24,.10+rng.random()*.24,.09+rng.random()*.17),
       concrete_dark if k%3 else rust)

def beacon():
 reset();cone('Generator footing',(0,0,.12),2.7,2.48,.24,concrete,20)
 cone('Mechanical lower housing',(0,0,.60),1.52,1.34,.75,steel,16)
 cone('Burnished service collar',(0,0,1.13),1.56,1.35,.20,rust,16)
 cone('Inner ignition chamber',(0,0,1.90),.68,.54,1.39,steel,12)
 cone('Luminous protected flame',(0,0,2.03),.46,.11,1.40,ember,10)
 cone('Beacon cap',(0,0,2.84),.94,.38,.26,steel,12)
 icos('Exposed signal heart',(0,0,3.43),(.36,.36,.68),ember,2)
 for i in range(6):
  a=i*2*pi/6
  icos('Orbiting ember lens',(.63*cos(a),.63*sin(a),3.22),(.10,.10,.16),signal,1)
 for i in range(8):
  a=i*2*pi/8
  rod('Eight structural struts',(1.15*cos(a),1.15*sin(a),.55),(.73*cos(a),.73*sin(a),2.73),.07,steel)
  box('Signal slit',(1.15*cos(a),1.15*sin(a),.95),(.20,.10,.30),signal,.015,(0,0,a))
 for i in range(4):
  a=i*pi/2
  rod('Grounding cable',(1.5*cos(a),1.5*sin(a),.48),(2.65*cos(a),2.65*sin(a),.11),.08,wood)

def barricade():
 reset()
 for i in range(6):
  x=(i-2.5)*.48
  rod('Reinforced vertical palisade',(x,0,.0),(x+.04*sin(i),0,1.70+sin(i*3)*.1),.115,wood)
  cone('Split sharpened tip',(x+.04*sin(i),0,1.79+sin(i*3)*.1),.13,.015,.30,wood,7)
  box('Bolted armor face',(x,-.13,.70),(.42,.12,.68),steel,.018)
 for z in [.41,1.11]:box('Heavy cross brace',(0,.12,z),(3.2,.22,.17),rust,.02)
 for i in range(9):
  x=(i-4)*.36
  icos('Rubble footing',(x,-.40,.03),(.23,.24,.13),concrete_dark,1)

def salvage():
 reset();box('Salvage crate shell',(0,0,.38),(1.12,.87,.71),steel,.045)
 box('Top folding lid',(0,0,.77),(1.22,.96,.12),rust,.035)
 for x in [-.43,.43]:
  box('Upright corner brace',(x,-.39,.42),(.09,.09,.74),rust,.01)
  box('Upright corner brace',(x,.39,.42),(.09,.09,.74),rust,.01)
 for x in [-.27,.27]:box('Glowing salvage signal',(x,-.48,.46),(.12,.03,.28),signal,.01)
 for i in range(4):
  a=i*pi/2
  icos('Loose machine scrap',((1.02+.08*i)*cos(a),(1.02+.08*i)*sin(a),.08),(.22,.18,.18),rust)

def dead_tree():
 reset();rng=random.Random(83)
 rod('Blackened continuous trunk',(0,0,.03),(.07,.04,3.0),.28,wood,13)
 for i in range(12):
  a=i*2*pi/12+rng.uniform(-.16,.16);z=1.0+i*.17
  mid=(.43*cos(a),.43*sin(a),z+.20)
  tip=(rng.uniform(.90,1.65)*cos(a),rng.uniform(.90,1.65)*sin(a),z+.28+rng.uniform(-.18,.35))
  rod('Twisted dead branch',(.02,.02,z),mid,.075,wood)
  rod('Fine fork',mid,tip,.037,wood)
 for i in range(6):
  a=i*pi/3
  rod('Exposed root',(.0,.0,.46),(.85*cos(a),.85*sin(a),.04),.075,wood)

def ruined_house():
 reset()
 box('Cracked foundation',(0,0,.11),(4.8,4.2,.23),concrete_dark,.03)
 for x in [-2.0,2.0]:
  for y in [-1.7,1.7]:
   box('Broken load column',(x,y,1.07),(0.42,.47,1.91),concrete,.04)
 for x in [-1.1,.35,1.5]:
  box('Partial outer wall',(x,-1.72,.74),(1.16,.35,1.32),concrete,.025)
 box('Collapsed wall',(1.92,.5,.55),(.34,1.62,.82),concrete,.026)
 for i in range(11):
  a=i*2*pi/11;r=2.3+.1*sin(i*3)
  icos('House collapse debris',(r*cos(a),r*sin(a),.13),(.18,.17,.14),concrete if i%3 else rust)
 rod('Exposed roof beam',(-2,-1.6,2.01),(1.1,1.5,1.27),.10,wood)

def stalker():
 reset()
 icos('Shadow lean torso',(0,0,1.00),(.60,.88,.53),hide,2)
 icos('Bony raised shoulders',(0,-.55,1.30),(.63,.42,.54),hide,1)
 head=[]
 head.append(icos('Wedged skull',(0,-1.03,1.11),(.36,.45,.28),bone,2))
 for side in [-1,1]:
  for front in [-1,1]:
   parts=[]
   x=side*.43;y=front*.59
   mid=(x*1.24,y*1.25,.49)
   foot=(x*1.44,y*1.54,.04)
   parts.append(rod('Elongated hooked limb',(x,y,1.05),mid,.11,hide))
   parts.append(rod('Lower split leg',mid,foot,.075,bone))
   for claw in [-1,0,1]:
    parts.append(rod('Curved claw',foot,(foot[0]+claw*.10,foot[1]-.17,.015),.025,bone,6))
   pivot=bpy.data.objects.new(('Front' if front<0 else 'Rear')+('Left' if side<0 else 'Right'),None)
   bpy.context.collection.objects.link(pivot);pivot.location=(x,y,1.05)
   bpy.context.view_layer.update()
   for part in parts:
    matrix=part.matrix_world.copy();part.parent=pivot;part.matrix_world=matrix
 for side in [-1,1]:
  head.append(box('Hollow warning eye',(side*.19,-1.36,1.20),(.09,.025,.055),ember,.008))
  icos('Rib blade',(side*.50,-.19,1.41),(.13,.52,.15),bone,1)
 pivot=bpy.data.objects.new('StalkerHead',None);bpy.context.collection.objects.link(pivot);pivot.location=(0,-.72,1.19)
 bpy.context.view_layer.update()
 for part in head:
  matrix=part.matrix_world.copy();part.parent=pivot;part.matrix_world=matrix

def stalker_refined():
 reset()
 # Continuous, long-backed silhouette. Layered plates break the broad dark body into readable bands.
 icos('Ash hound muscular body',(0,.02,1.02),(.54,.83,.46),stalker_hide,2)
 icos('Deep neck bridge',(0,-.57,1.14),(.48,.46,.43),stalker_hide,2)
 def plate(name,y,width,height,depth,material):
  verts=[(-width,y+depth,height-.12),(width,y+depth,height-.12),
         (0,y+depth*.80,height+.16),(-width*.82,y-depth,height-.10),
         (width*.82,y-depth,height-.10),(0,y-depth*.82,height+.26)]
  return mesh(name,verts,[(0,1,2),(3,5,4),(0,3,4,1),(0,2,5,3),(1,4,5,2)],
              [material],smooth=False)
 for i,y in enumerate([.62,.34,.04,-.26,-.55]):
  width=[.31,.47,.51,.48,.36][i]
  plate('Overlapping dorsal armor %02d'%i,y,width,1.39, .21,stalker_shell)
  rod('Dorsal raised seam %02d'%i,(-width*.75,y+.02,1.48),(width*.75,y+.02,1.48),.022,stalker_edge,8)
 for i,y in enumerate([.48,.14,-.22,-.53]):
  height=[.27,.39,.31,.23][i]
  rod('Backward hooked spine %02d'%i,(0,y,1.52),(0,y+.18,1.52+height),.075,stalker_edge,8)
 for side in [-1,1]:
  icos('High shoulder carapace',(.44*side,-.48,1.37),(.24,.37,.27),stalker_shell,2)
  for rib,y in enumerate([-.32,-.03,.27]):
   rod('Exposed side rib %s %d'%(side,rib),(.38*side,y,1.31),(.52*side,y+.11,1.02),.042,stalker_edge,8)
  rod('Forward shoulder blade',(.43*side,-.61,1.49),(.68*side,-.88,1.32),.09,stalker_edge,8)
 for side in [-1,1]:
  for front in [-1,1]:
   x=side*.43;y=front*.56
   elbow=(side*.56,y+front*.13,.50)
   foot=(side*.63,y+front*.28,.08)
   parts=[]
   parts.append(rod('Jointed upper leg',(x,y,1.04),elbow,.12,stalker_hide,10))
   parts.append(icos('Armored shoulder joint',(x,y,1.04),(.20,.19,.22),stalker_shell,2))
   parts.append(icos('Exposed elbow knot',elbow,(.16,.15,.13),stalker_edge,1))
   parts.append(rod('Tapered lower leg',elbow,foot,.087,stalker_hide,10))
   parts.append(icos('Split hoof base',foot,(.17,.19,.10),stalker_shell,1))
   for claw in [-1,0,1]:
    tip=(foot[0]+claw*.10,foot[1]-.25,.015)
    parts.append(rod('Bone hook claw',foot,tip,.034,stalker_edge,8))
   pivot=bpy.data.objects.new(('Front' if front<0 else 'Rear')+('Left' if side<0 else 'Right'),None)
   bpy.context.collection.objects.link(pivot);pivot.location=(x,y,1.04)
   bpy.context.view_layer.update()
   for part in parts:
    matrix=part.matrix_world.copy();part.parent=pivot;part.matrix_world=matrix
 head=[]
 head.append(icos('Narrow cranial shell',(0,-1.03,1.18),(.34,.39,.27),stalker_shell,2))
 head.append(icos('Lower bone jaw',(0,-1.17,.99),(.31,.42,.13),stalker_edge,1))
 plate('Cranial crown',-1.02,.25,1.40,.21,stalker_edge)
 for side in [-1,1]:
  head.append(box('Inset burning eye',(side*.205,-1.27,1.24),(.09,.034,.075),stalker_ember,.012))
  head.append(rod('Angular brow',(side*.08,-1.37,1.35),(side*.30,-1.19,1.32),.041,stalker_edge,8))
  head.append(rod('Long jaw fang',(side*.19,-1.43,1.00),(side*.20,-1.56,.86),.035,stalker_edge,8))
  head.append(rod('Swept cheek horn',(side*.29,-.94,1.33),(side*.46,-.72,1.48),.065,stalker_edge,8))
 pivot=bpy.data.objects.new('StalkerHead',None);bpy.context.collection.objects.link(pivot);pivot.location=(0,-.72,1.19)
 bpy.context.view_layer.update()
 for part in head:
  matrix=part.matrix_world.copy();part.parent=pivot;part.matrix_world=matrix

def breaker_refined():
 stalker_refined()
 body=bpy.data.objects.get('Ash hound muscular body')
 body.scale=(1.22,1.06,1.13)
 def attach(obj,parent):
  bpy.context.view_layer.update()
  matrix=obj.matrix_world.copy();obj.parent=parent;obj.matrix_world=matrix
 def wedge(name,cy,width,front,back,top,material):
  verts=[(-width,cy+back,top-.18),(width,cy+back,top-.18),
         (-width*.85,cy-front,top-.15),(width*.85,cy-front,top-.15),
         (0,cy-front*.80,top+.16)]
  return mesh(name,verts,[(0,1,4),(0,4,2),(1,3,4),(2,4,3),(0,2,3,1)],
              [material],smooth=False)
 for i,y in enumerate([.36,.02,-.31]):
  wedge('Overlapping siege plate %d'%i,y,[.48,.57,.59][i],.20,.25,1.63,breaker_armor)
  rod('Iron plate seam %d'%i,(-.33,y+.01,1.56),(.33,y+.01,1.56),.029,breaker_bone,8)
 for side in [-1,1]:
  icos('Heavy ram shoulder',(.56*side,-.52,1.36),(.34,.43,.35),breaker_armor,2)
  wedge('Outward shoulder shield',-.52,.31,.30,.24,1.66,breaker_bone).location.x=.60*side
  rod('Furnace side fissure',(.51*side,-.52,1.40),(.67*side,-.73,1.47),.038,breaker_glow,8)
  for name in [('FrontLeft' if side<0 else 'FrontRight')]:
   pivot=bpy.data.objects.get(name)
   guard=icos('Siege front-leg guard',(.52*side,-.64,.70),(.24,.28,.27),breaker_armor,2)
   attach(guard,pivot)
   brace=rod('Bone foreleg brace',(.58*side,-.76,.78),(.65*side,-.82,.31),.053,breaker_bone,8)
   attach(brace,pivot)
 head=bpy.data.objects.get('StalkerHead')
 crown=wedge('Battering crown',-1.21,.38,.38,.24,1.44,breaker_armor)
 attach(crown,head)
 for side in [-1,1]:
  horn=rod('Forward ram horn',(.31*side,-1.06,1.38),(.56*side,-1.71,1.30),.105,breaker_bone,10)
  attach(horn,head)
  tusk=rod('Lower split tusk',(.23*side,-1.37,1.00),(.36*side,-1.65,.83),.068,breaker_bone,8)
  attach(tusk,head)
 for obj in bpy.context.scene.objects:
  if obj.type=='MESH' and obj.name.startswith('Inset burning eye'):
   obj.data.materials.clear();obj.data.materials.append(breaker_glow)
 fissure=box('Crown heat crack',(0,-1.49,1.47),(.065,.27,.022),breaker_glow,.008)
 attach(fissure,head)

def tower_pad():
 reset();cone('Reinforced tower socket',(0,0,.13),1.26,1.12,.26,concrete,16)
 cone('Dark mounting ring',(0,0,.31),.99,.86,.13,steel,16)
 for i in range(8):
  a=i*pi/4
  box('Amber alignment notch',(.82*cos(a),.82*sin(a),.40),(.14,.13,.035),ember,.005,(0,0,a))

def auto_turret():
 reset();cone('Defense tower footing',(0,0,.14),1.02,.83,.28,concrete,16)
 cone('Armored tapered shaft',(0,0,1.00),.63,.43,1.58,steel,12)
 cone('Rotating gun cradle',(0,0,1.92),.70,.59,.28,rust,12)
 icos('Searchlight emitter',(0,-.23,2.13),(.46,.42,.31),steel,2)
 cone('Amber targeting lens',(0,-.64,2.14),.19,.10,.08,ember,16)
 for x in [-.34,.34]:
  rod('Twin barrel',(x,-.24,2.08),(x,-1.20,2.08),.11,steel,12)
  cone('Muzzle glow',(x,-1.25,2.08),.12,.09,.09,signal,12)
 for i in range(6):
  a=i*pi/3
  rod('Braced support',(.55*cos(a),.55*sin(a),.35),(.41*cos(a),.41*sin(a),1.70),.065,rust)

def relay_mast():
 reset();box('Relay platform',(0,0,.10),(3.3,3.3,.2),concrete,.06)
 for x in [-.8,.8]:
  rod('Collapsed mast leg',(x,0,.2),(x*.34,0,4.6),.13,steel,10)
 for z in [1.2,2.4,3.5]:box('Cross bracing',(0,0,z),(1.5,.12,.11),rust,.01)
 icos('Dead transmission dish',(0,0,4.8),(.87,.22,.87),steel,2)
 icos('Relay signal core',(0,-.3,4.8),(.22,.12,.22),signal,2)
 for i in range(8):
  a=i*pi/4;icos('Scattered aerial parts',(2*cos(a),2*sin(a),.12),(.30,.18,.15),rust)

def truck_wreck():
 reset();box('Transport chassis',(0,0,.60),(3.7,1.7,.48),rust,.07)
 box('Crushed cabin',(-1.05,0,1.22),(1.35,1.6,1.0),steel,.09)
 box('Empty cargo bed',(.85,0,.87),(2.0,1.52,.28),concrete_dark,.03)
 for x in [-1.05,1.12]:
  for y in [-.82,.82]:cone('Shredded tire',(x,y,.27),.40,.39,.28,hide,12)
 for i in range(5):
  icos('Transport debris',(2.1+.2*i,-.55+i*.31,.10),(.22,.18,.12),rust)

def night_nest():
 reset()
 icos('Sunken infected earth',(0,0,.08),(2.6,2.3,.28),charred,2)
 icos('Armored central mantle',(0,0,.62),(1.45,1.28,.68),shell,2)
 icos('Exposed pulsing heart',(0,-.16,1.11),(.40,.42,.38),blight,2)
 for i in range(7):
  a=i*2*pi/7
  x,y=cos(a),sin(a)
  plate=icos('Overlapping chitin petal',(x*.92,y*.92,.81),(.48,.82,.35),shell,2)
  plate.rotation_euler[2]=a+pi/2
  rod('Shadow hooked rib',(x*.82,y*.82,.74),(x*1.58,y*1.54,1.64),.17,charred,10)
  rod('Pale pointed tip',(x*1.58,y*1.54,1.64),(x*1.74,y*1.68,.62),.065,bone,8)
  rod('Glowing mantle fissure',(x*.30,y*.30,1.11),(x*1.08,y*1.05,.83),.034,blight,7)
 for i in range(12):
  a=i*2*pi/12+.14
  r=1.9+.38*sin(i*2.3)
  rod('Burrowing root',(r*.35*cos(a),r*.35*sin(a),.25),(r*cos(a),r*sin(a),.015),.09,charred)
 for i in range(4):
  a=i*2*pi/4+.3
  icos('Dormant red cyst',(1.72*cos(a),1.62*sin(a),.17),(.14,.13,.16),blight,1)

def sealed_nest():
 reset()
 icos('Collapsed infected soil',(0,0,.055),(2.55,2.34,.19),charred,2)
 cone('Buried seal foundation',(0,0,.18),1.24,1.10,.28,concrete_dark,16)
 cone('Weathered upper seal',(0,0,.32),1.04,.92,.12,concrete,16)
 for i in range(12):
  a=i*2*pi/12+.07;b=(i+1)*2*pi/12+.07
  rod('Inlaid pale ward arc',(.82*cos(a),.82*sin(a),.405),(.82*cos(b),.82*sin(b),.405),.033,seal_glow,7)
 for i in range(4):
  a=i*pi/2+.18
  stone=box('Four tilted binding stones',(1.48*cos(a),1.48*sin(a),.38),(.55,.39,.76),concrete,.055,(.12*sin(a),-.13*cos(a),a))
  box('Seal light on binding stone',(1.48*cos(a),1.48*sin(a),.79),(.25,.09,.035),seal_glow,.012,(0,0,a))
 for i in range(7):
  a=i*2*pi/7+.14
  start=(1.28*cos(a),1.28*sin(a),.13)
  end=(2.18*cos(a+.16),2.02*sin(a+.16),.10)
  rod('Split remains of chitin rib',start,end,.08,shell,8)
  icos('Broken husk plate',(1.86*cos(a),1.82*sin(a),.15),(.29,.19,.12),shell,1)
 icos('Quiet sealed heart',(0,0,.46),(.46,.42,.17),seal_glow,2)
 for a in [pi/4,3*pi/4]:
  rod('Crossed ward line',(-.42*cos(a),-.42*sin(a),.58),(.42*cos(a),.42*sin(a),.58),.035,seal_glow,8)

def export(name,build):
 build()
 for obj in list(bpy.context.scene.objects):
  if obj.type!='CURVE':continue
  bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
  bpy.ops.object.convert(target='MESH')
 groups={}
 for obj in list(bpy.context.scene.objects):
  if obj.type!='MESH':continue
  parent_key=obj.parent.name if name in ('night_stalker_v2','night_breaker_v2') and obj.parent else ''
  groups.setdefault((parent_key,tuple(m.name for m in obj.data.materials)),[]).append(obj)
 for items in groups.values():
  if name=='night_stalker':continue
  if len(items)<2:continue
  bpy.ops.object.select_all(action='DESELECT')
  for item in items:item.select_set(True)
  bpy.context.view_layer.objects.active=items[0];bpy.ops.object.join()
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,name+'.blend'))
 bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT,'assets','models',name+'.glb'),export_format='GLB',export_yup=True)
 print('OUTPOST_READY',name,sum(len(obj.data.polygons) for obj in bpy.context.scene.objects if obj.type=='MESH'))

for name,build in [('outpost_ground',ground),('watch_beacon',beacon),('barricade',barricade),
                   ('salvage_crate',salvage),('dead_tree',dead_tree),('ruined_house',ruined_house),
                   ('night_stalker',stalker),('night_stalker_v2',stalker_refined),('night_breaker_v2',breaker_refined),('tower_pad',tower_pad),('auto_turret',auto_turret),
                   ('relay_mast',relay_mast),('truck_wreck',truck_wreck),('night_nest',night_nest),('sealed_nest',sealed_nest)]:
 if os.environ.get('OUTPOST_ONLY') and name not in os.environ['OUTPOST_ONLY'].split(','):continue
 export(name,build)
