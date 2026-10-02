"""Run with Blender --background --python art_source/create_assets.py.
All meshes are original procedural low-poly artwork, authored for Riftward.
Coordinates in this source use Blender Z-up; glTF export converts to Godot Y-up.
"""
import bpy, math, os, random
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'models')
os.makedirs(OUT, exist_ok=True)
random.seed(17)

def material(name, color, metallic=0.0, emission=0.0):
    color = tuple(c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4 for c in color)
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metallic
    p.inputs['Roughness'].default_value = .88
    p.inputs['Emission Color'].default_value = (*color, 1)
    p.inputs['Emission Strength'].default_value = emission
    return m

stone = material('Obsidian basalt', (.11, .17, .21))
edge = material('Weathered limestone', (.32, .39, .40))
gold = material('Warm brushed gold', (.69, .45, .17), .65)
steel = material('Ivory steel', (.62, .75, .77), .65)
dark = material('Midnight cloth', (.035, .07, .10))
bark = material('Cedar bark', (.16, .105, .075))
leaf = material('Jade canopy', (.055, .23, .18))
leaf2 = material('Sage canopy', (.11, .34, .24))
blue = material('Azure enamel', (.055, .40, .57), .35)
red = material('Carmine enamel', (.48, .08, .18), .35)
blue_glow = material('Aether cyan', (.12, .83, 1.0), .2, 1.6)
red_glow = material('Ember coral', (1.0, .19, .30), .2, 1.6)

def finish(obj, name, mat, parent=None):
    obj.name = name
    obj.data.materials.append(mat)
    if parent: obj.parent = parent
    return obj

def cube(name, loc, scale, mat, bevel=0, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new('Hand cut edges', 'BEVEL'); mod.width=bevel; mod.segments=3
        bpy.context.view_layer.objects.active=o
        bpy.ops.object.modifier_apply(modifier=mod.name)
        o.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
    return finish(o,name,mat,parent)

def cone(name, loc, r1, r2, depth, mat, verts=8, parent=None):
    bpy.ops.mesh.primitive_cone_add(vertices=max(verts,12), radius1=r1, radius2=r2, depth=depth, location=loc)
    return finish(bpy.context.object,name,mat,parent)

def ico(name, loc, scale, mat, parent=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=loc)
    o=bpy.context.object; o.scale=scale
    if name.startswith('Leaf') or name.startswith('Pauldron'):
        for polygon in o.data.polygons: polygon.use_smooth=True
    return finish(o,name,mat,parent)

def pivot(name, loc):
    o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o); o.location=loc
    return o

def reset():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)

def export(name):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'art_source',name+'.blend'))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,name+'.glb'),export_format='GLB',export_yup=True)

def hero(team, armor, glow):
    reset()
    cone('Torso',(0,0,1.15),.28,.40,.65,armor,6)
    cube('Breastplate',(0,-.22,1.23),(.55,.22,.42),steel,.06)
    ico('Heart sigil',(0,-.37,1.29),(.10,.05,.15),glow)
    cone('Waist',(0,0,.79),.28,.26,.18,gold)
    cone('Helmet',(0,0,1.77),.25,.18,.42,steel,6)
    cube('Visor',(0,-.211,1.79),(.32,.055,.075),glow,.02)
    cone('Crown crest',(0,.05,2.04),.13,0,.25,gold,4)
    for side, sign in [('L',-1),('R',1)]:
        p=pivot('Arm'+side,(sign*.40,0,1.48))
        ico('Pauldron'+side,(0,0,0),(.27,.30,.22),gold,p)
        cube('ArmGuard'+side,(0,0,-.29),(.20,.23,.49),armor,.045,p)
        cube('Gauntlet'+side,(0,-.02,-.53),(.23,.26,.22),steel,.04,p)
        leg=pivot('Leg'+side,(sign*.16,0,.71))
        cube('Greave'+side,(0,0,-.25),(.22,.25,.48),armor,.045,leg)
        cube('Boot'+side,(0,-.08,-.57),(.26,.40,.20),dark,.03,leg)
    arm=bpy.data.objects.get('ArmR')
    cube('Blade',(0,-.07,-1.05),(.13,.12,.91),steel,.035,arm)
    cube('Blade light',(0,-.139,-1.05),(.04,.02,.77),glow,0,arm)
    cube('Crossguard',(0,-.06,-.62),(.44,.19,.10),gold,.025,arm)
    # A broad angular cape reads clearly from the isometric camera.
    cape=cube('Cape',(0,.22,1.0),(.63,.12,.94),armor,.03)
    cape.rotation_euler.x=math.radians(-14)
    # Layered articulated plates, gilded pauldrons and a swept segmented cloak.
    for side in [-1,1]:
        for i in range(3):
            plate=cube('Layered hip plate',(side*(.22+i*.035),.04,.79-i*.095),(.22,.33,.12),steel,.035)
            plate.rotation_euler.y=side*.18
        shoulder=bpy.data.objects.get('ArmL' if side==-1 else 'ArmR')
        for i in range(3):
            piece=cone('Pauldron ridge',(side*(.04+i*.065),.03,.10+i*.035),.12,.045,.26,steel,6,shoulder)
            piece.rotation_euler.y=side*.45
    for i in range(6):
        x=(i-2.5)*.14
        cloth=cube('Cloak fold',(x,.34+abs(x)*.12,.99),(.145,.08,1.03),dark if i%2 else armor,.025)
        cloth.rotation_euler.x=-.23
        cube('Cloak golden hem',(x,.45,.49),(.145,.08,.06),gold,.018)
    export('hero_'+team)

def minion(team,armor,glow):
    reset()
    cone('Body',(0,0,.54),.22,.28,.6,armor,6)
    ico('Helmet',(0,0,1.0),(.27,.25,.27),steel)
    cube('Eye',(0,-.235,1.01),(.26,.04,.07),glow)
    for s in [-1,1]:
        cube('Boot',(s*.13,-.035,.13),(.18,.24,.24),dark,.025)
    cube('Shield',(-.32,-.05,.59),(.13,.40,.50),gold,.045)
    cone('Spear shaft',(.33,0,.85),.035,.035,1.25,bark)
    cone('Spear head',(.33,0,1.55),.13,0,.28,glow,4)
    export('minion_'+team)

def tower(team,armor,glow):
    reset()
    cone('Foundation',(0,0,.16),1.12,1.12,.32,stone)
    cone('Pedestal',(0,0,.38),.91,.75,.20,gold)
    cone('Pillar',(0,0,1.32),.69,.46,1.70,edge,6)
    cone('Capital',(0,0,2.23),.63,.83,.28,gold,6)
    cone('Crown',(0,0,2.53),.60,.52,.40,armor,6)
    for i in range(4):
        a=i*math.pi/2
        cube('Buttress',(math.cos(a)*.65,math.sin(a)*.65,.86),(.25,.25,1.30),stone,.045)
        cone('Prong',(math.cos(a)*.56,math.sin(a)*.56,2.94),.14,.055,.64,gold,4)
    ico('Crystal',(0,0,3.12),(.40,.40,.77),glow)
    export('tower_'+team)

def core(team,armor,glow):
    reset()
    cone('Dais',(0,0,.17),1.95,1.95,.34,stone,12)
    cone('Ring',(0,0,.4),1.62,1.42,.16,gold,12)
    cone('Socket',(0,0,.68),.94,.64,.5,armor)
    ico('Nexus crystal',(0,0,1.70),(.78,.78,1.32),glow)
    for i in range(4):
        a=i*math.pi/2
        cone('Pylon',(math.cos(a)*1.34,math.sin(a)*1.34,1.02),.25,.10,1.45,edge,5)
        ico('Rune',(math.cos(a)*1.34,math.sin(a)*1.34,1.84),(.18,.18,.25),glow)
    export('core_'+team)

import sys
sys.path.insert(0, os.path.dirname(__file__))
import refined_models
refined_models.build_assets(globals())
hero = refined_models.hero
tower = refined_models.tower
minion = refined_models.minion

for team,armor,glow in [('blue',blue,blue_glow),('red',red,red_glow)]:
    hero(team,armor,glow); minion(team,armor,glow); tower(team,armor,glow); core(team,armor,glow)
reset()
cone('Trunk',(0,0,.70),.24,.15,1.4,bark,6)
for i in range(3):
    cone('Canopy',(0,0,1.35+i*.65),1.0-i*.22,.05,1.5,leaf if i%2 else leaf2,7)
export('pine')
reset()
ico('Basalt',(0,0,.48),(1.0,.77,.85),edge)
ico('Basalt shard',(.54,.24,.19),(.56,.53,.48),stone)
export('rock')
reset()
amber = material('Ancient amber', (.95, .55, .13), .15, 1.2)
refined_models.golem()
reset()
trunkmat = material('Oak umber',(.22,.16,.10))
foliage = [material('Oak foliage '+str(i),c) for i,c in enumerate([(.12,.24,.14),(.19,.33,.17),(.28,.40,.20),(.36,.44,.22),(.16,.30,.20)])]
cone('Oak trunk',(0,0,1.2),.32,.16,2.4,trunkmat,12)
for i in range(7):
    a=i*math.tau/7
    branch=cone('Twisted bough',(math.cos(a)*.48,math.sin(a)*.48,1.7),.13,.055,1.5,trunkmat,8)
    branch.rotation_euler=(math.sin(a)*.65,math.cos(a)*.65,0)
# Angular overlapping leaf sprays: a layered silhouette instead of bubble spheres.
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
        faces.append((start+6,start+(j+1)%6,start+j)); slots.append(min(4,int((z-2.3)*2.5))%5)
mesh=bpy.data.meshes.new('Layered leaf sprays'); mesh.from_pydata(verts,[],faces); mesh.update()
obj=bpy.data.objects.new('Leaf sprays',mesh); bpy.context.collection.objects.link(obj)
for mat in foliage: mesh.materials.append(mat)
for poly,slot in zip(mesh.polygons,slots): poly.material_index=slot
uv=mesh.uv_layers.new(name='Leaf UV')
for poly in mesh.polygons:
    for j,li in enumerate(poly.loop_indices): uv.data[li].uv=[(.5,.5),(0,0),(1,1)][j]
export('oak')
reset()
for i in range(8):
    a=i*math.tau/8
    for j in range(4):
        leafpart=ico('Fern frond',(math.cos(a)*(.12+j*.1),math.sin(a)*(.12+j*.1),.12+j*.06),(.15,.055,.035),foliage[(i+j)%5])
        leafpart.rotation_euler.z=a
export('fern')
print('RIFTWARD: all 13 original models exported successfully')

