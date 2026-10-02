"""Authored profile meshes for the playable knight and arcane watchtower.
Blender Z-up. Animation pivots retain the runtime Arm/Leg naming contract.
"""
import bpy, math, bmesh
from mathutils import Vector

def build_assets(api):
    globals().update({k:api[k] for k in ['reset','export','material','cube','cone','ico','pivot','gold','steel','stone','edge','dark']})
    globals()['sphere']=api['ico']

def mesh_obj(name, vertices, faces, mat, parent=None, bevel=0):
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(vertices,[],faces); mesh.update()
    obj=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    if parent: obj.parent=parent
    if bevel:
        mod=obj.modifiers.new('Forged edge radius','BEVEL');mod.width=bevel;mod.segments=2
        obj.modifiers.new('Plate normals','WEIGHTED_NORMAL')
    return obj

def loft(name,rings,mat,parent=None,segments=16):
    # rings: z, width, depth, forward offset. Continuous anatomical shell.
    verts=[]
    for z,w,d,y in rings:
        for j in range(segments):
            a=math.tau*j/segments
            verts.append((math.cos(a)*w,y+math.sin(a)*d,z))
    faces=[]
    for i in range(len(rings)-1):
        for j in range(segments):
            a=i*segments+j;b=i*segments+(j+1)%segments
            faces.append((a,b,b+segments,a+segments))
    faces.extend([tuple(reversed(range(segments))),tuple((len(rings)-1)*segments+j for j in range(segments))])
    obj=mesh_obj(name,verts,faces,mat,parent,.008)
    for poly in obj.data.polygons:poly.use_smooth=True
    return obj

def plate(name,outline,depth,mat,parent=None):
    # Outline is x,z; thickness extends along y. Silhouette remains intentional.
    verts=[(x,y,z) for y in [-depth/2,depth/2] for x,z in outline]
    n=len(outline);faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh_obj(name,verts,faces,mat,parent,.012)

def rod(name,a,b,r,mat,parent=None):
    a,b=Vector(a),Vector(b)
    obj=cone(name,(a+b)*.5,r,r*.75,(b-a).length,mat,12,parent)
    obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    return obj

def torus(name,loc,major,minor,mat,rotation=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major,minor_radius=minor,major_segments=48,minor_segments=8,location=loc)
    obj=bpy.context.object;obj.name=name;obj.data.materials.append(mat)
    if rotation:obj.rotation_euler=rotation
    return obj

def optimize_meshes():
    # Retain articulated pivots and cloth, merge static surfaces by material.
    groups={}
    for obj in list(bpy.context.scene.objects):
        if obj.type!='MESH' or obj.name=='Tailored pleated cape':continue
        bpy.context.view_layer.objects.active=obj
        for mod in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        key=(obj.parent,obj.data.materials[0] if obj.data.materials else None)
        groups.setdefault(key,[]).append(obj)
    for (parent,mat),objects in groups.items():
        if len(objects)<2:continue
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objects:obj.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        bpy.ops.object.join()
        objects[0].name='Forged '+(mat.name if mat else 'mesh')

def hero(team,armor,glow):
    reset()
    leather=material('Knight leather '+team,(.12,.105,.09))
    silver=material('Forged silver '+team,(.44,.53,.57),.35)
    trim=material('Antique brass '+team,(.46,.34,.17),.3)
    # Anatomical torso, breastplate and overlapping abdominal lames.
    loft('Quilted torso',[(1.0,.21,.15,0),(1.18,.24,.16,0),(1.48,.35,.20,0),(1.65,.27,.16,0)],dark)
    loft('Sculpted cuirass',[(1.17,.23,.17,-.025),(1.29,.29,.205,-.025),(1.48,.35,.22,-.01),(1.62,.27,.17,0)],silver)
    for s in [-1,1]:
        p=plate('Swept pectoral',[(s*.025,1.28),(s*.31,1.46),(s*.27,1.59),(s*.06,1.53)],.04,steel)
        p.location.y=-.203
        rod('Breastplate inlay',(s*.035,-.238,1.30),(s*.27,-.216,1.49),.014,trim)
    for i in range(3):
        loft('Articulated abdomen',[(1.05+i*.067,.225+i*.014,.16,-.01),(1.11+i*.067,.24+i*.014,.18,-.01)],silver)
    loft('Leather belt',[(1.00,.24,.17,0),(1.07,.25,.175,0)],leather)
    buckle=plate('Belt heraldry',[(-.075,1.0),(0,.96),(.075,1.0),(.065,1.095),(-.065,1.095)],.035,trim);buckle.location.y=-.19
    loft('Gorget',[(1.57,.18,.14,0),(1.69,.14,.12,0)],trim)
    # Helmet with pointed faceplate, cheek guards and a swept crest.
    loft('Forged helmet',[(1.70,.13,.13,0),(1.79,.18,.155,0),(1.98,.17,.16,.015),(2.08,.095,.11,.035),(2.115,.02,.045,.06)],silver,segments=20)
    face=plate('Visored face',[(-.145,1.95),(-.115,1.78),(0,1.72),(.115,1.78),(.145,1.95),(0,1.99)],.035,steel);face.location.y=-.149
    for s in [-1,1]:
        rod('Eye slit',(s*.025,-.177,1.935),(s*.119,-.164,1.955),.012,glow)
        rod('Cheek engraving',(s*.035,-.175,1.78),(s*.12,-.17,1.89),.01,trim)
    crest=plate('Swept helmet fin',[(0,2.03),(.0,2.29),(.20,2.16),(.28,1.98)],.035,trim)
    crest.rotation_euler.z=math.pi/2;crest.location.y=.015
    # Shoulder, elbow, wrist and shin have separately shaped sections.
    for side,s in [('L',-1),('R',1)]:
        arm=pivot('Arm'+side,(s*.36,0,1.55))
        loft('Upper sleeve',[(0,.13,.14,0),(-.26,.10,.11,0),(-.36,.105,.12,-.02)],dark,arm)
        for i in range(3):
            shoulder=loft('Overlapping shoulder lame',[(-.12-i*.065,.19-i*.024,.20-i*.02,0),(-.04-i*.065,.23-i*.024,.22-i*.02,0),(.07-i*.065,.12,.15,0)],silver,arm)
            shoulder.location.x=s*i*.035
        loft('Elbow couter',[(-.33,.10,.12,0),(-.40,.135,.13,-.01),(-.46,.105,.12,0)],trim,arm)
        loft('Tapered vambrace',[(-.43,.10,.11,0),(-.56,.12,.13,-.01),(-.69,.075,.09,0)],silver,arm)
        loft('Gauntlet',[(-.67,.075,.09,0),(-.78,.085,.105,-.01),(-.84,.065,.08,0)],leather,arm)
        for j in range(3):cube('Gauntlet knuckle',(s*.02,-.096,-.70-j*.035),(.13,.035,.025),steel,.008,arm)
        leg=pivot('Leg'+side,(s*.15,0,1.0))
        loft('Thigh armor',[(0,.13,.145,0),(-.22,.135,.15,0),(-.43,.105,.12,0)],silver,leg)
        ico('Knee poleyn',(0,-.075,-.46),(.12,.115,.12),trim,leg)
        loft('Sculpted greave',[(-.48,.10,.11,0),(-.58,.115,.135,0),(-.82,.07,.09,0),(-.91,.075,.09,0)],silver,leg)
        boot=loft('Pointed sabaton',[(-.98,.105,.21,-.09),(-.90,.105,.21,-.09),(-.84,.075,.115,-.03)],steel,leg)
        for j in range(3):cube('Sabaton articulated ridge',(0,-.13-j*.035,-.865-j*.022),(.19,.024,.025),trim,.005,leg)
        for j in range(3):
            skirt=plate('Flared hip tasset',[(s*.08,.99-j*.09),(s*.28,.99-j*.09),(s*(.34+j*.025),.84-j*.09),(s*.12,.86-j*.09)],.055,silver)
            skirt.location.y=-.10+j*.025
    # Long tapered diamond blade with a raised central spine.
    before_sword=set(bpy.data.objects)
    arm=bpy.data.objects.get('ArmR')
    rod('Sword grip',(0,0,-.76),(0,0,-1.0),.045,leather,arm)
    for j in range(5):cube('Grip binding',(0,-.043,-.78-j*.037),(.075,.012,.014),trim,.003,arm)
    guard=plate('Swept sword guard',[(-.25,-1.04),(-.22,-.95),(0,-1.0),(.22,-.95),(.25,-1.04),(0,-1.09)],.09,trim,arm)
    verts=[(-.105,0,-1.08),(.105,0,-1.08),(-.075,0,-1.76),(.075,0,-1.76),(0,0,-2.03),(0,-.05,-1.10),(0,-.038,-1.78),(0,.05,-1.10),(0,.038,-1.78)]
    faces=[(0,2,6,5),(5,6,3,1),(2,4,6),(6,4,3),(0,7,8,2),(7,1,3,8),(2,8,4),(8,3,4),(0,5,1,7)]
    mesh_obj('Diamond forged sword',verts,faces,steel,arm)
    rod('Blade aether channel',(0,-.053,-1.14),(0,-.04,-1.72),.012,glow,arm)
    weapon=pivot('Sword wrist', (0,0,-.78));weapon.parent=arm
    for obj in set(bpy.data.objects)-before_sword-{weapon}:
        obj.parent=weapon;obj.location.z+=.78
    weapon.rotation_euler.y=-.95
    weapon.rotation_euler.x=.2
    # Continuous pleated cloth with a curved silhouette, not stacked boxes.
    vertices=[];faces=[];cols=16;rows=12
    for j in range(rows+1):
        t=j/rows
        for i in range(cols+1):
            u=i/cols*2-1
            vertices.append((u*(.25+.22*t),.17+.36*t+.06*math.sin(u*math.pi*4)*t,1.61-1.10*t+.045*math.cos(u*math.pi*3)*t*t))
    for j in range(rows):
        for i in range(cols):
            n=j*(cols+1)+i;faces.append((n,n+1,n+cols+2,n+cols+1))
    cape=mesh_obj('Tailored pleated cape',vertices,faces,armor)
    solid=cape.modifiers.new('Cloth thickness','SOLIDIFY');solid.thickness=.012
    for p in cape.data.polygons:p.use_smooth=True
    for i in range(cols):rod('Cloak embroidered hem',vertices[rows*(cols+1)+i],vertices[rows*(cols+1)+i+1],.012,trim)
    optimize_meshes()
    export('hero_'+team)

def tower(team,armor,glow):
    reset()
    masonry=material('Tower cut limestone '+team,(.32,.35,.32))
    trim=material('Tower oxidized bronze '+team,(.36,.29,.17),.2)
    for i in range(3):cone('Octagonal stepped foundation',(0,0,.12+i*.14),1.20-i*.10,1.20-i*.10,.22,stone,8)
    # Individually fitted ashlar blocks with staggered vertical joints.
    for row in range(7):
        for j in range(8):
            a=(j+(row%2)*.5)*math.tau/8
            block=cube('Ashlar course',(math.cos(a)*.59,math.sin(a)*.59,.54+row*.21),(.42,.28,.195),masonry,.022)
            block.rotation_euler.z=a+math.pi/2
    cone('Lower cornice',(0,0,.52),.88,.82,.13,trim,8)
    cone('Upper cornice',(0,0,2.03),.79,.91,.18,masonry,8)
    cone('Crown lip',(0,0,2.18),.93,.93,.07,trim,8)
    for i in range(4):
        a=i*math.pi/2+math.pi/4
        # Architectural flying supports with tapered silhouette.
        outline=[(-.18,.35),(.18,.35),(.15,1.24),(.06,1.9),(-.08,2.04),(-.16,1.48)]
        buttress=plate('Carved buttress',outline,.26,stone)
        buttress.location=(math.cos(a)*.83,math.sin(a)*.83,0);buttress.rotation_euler.z=a
        for z in [.54,1.22,1.85]:
            collar=cube('Buttress collar',(math.cos(a)*.83,math.sin(a)*.83,z),(.4,.35,.10),trim,.025);collar.rotation_euler.z=a
        # Curved spire arms cradle the crystal without forming a solid bucket.
        points=[]
        for j in range(9):
            t=j/8;r=.78-.32*math.sin(t*math.pi*.75)
            points.append((math.cos(a)*r,math.sin(a)*r,2.2+t*1.12))
        for j in range(8):rod('Gothic crown rib',points[j],points[j+1],.09*(1-j*.08),masonry)
        ico('Spire finial',points[-1],(.075,.075,.14),trim)
    for i in range(4):
        a=i*math.pi/2
        # Raised arch traceries on all four elevations.
        def point(x,z):return (math.cos(a)*.78-math.sin(a)*x,math.sin(a)*.78+math.cos(a)*x,z)
        for s in [-1,1]:
            rod('Window jamb',point(s*.20,.82),point(s*.20,1.44),.03,trim)
            for j in range(6):
                t=j/6;tn=(j+1)/6
                rod('Pointed arch',point(s*.20*(1-t),1.44+.32*math.sin(t*math.pi/2)),point(s*.20*(1-tn),1.44+.32*math.sin(tn*math.pi/2)),.028,trim)
        rod('Inset rune',point(0,1.01),point(0,1.40),.025,glow)
    crystal_mat=material('Luminous crystal '+team,(.18,.64,.76) if team=='blue' else (.73,.18,.28),.05,.45)
    torus('Crystal suspension ring',(0,0,2.43),.50,.035,trim)
    loft('Faceted suspended crystal',[(2.43,.02,.02,0),(2.68,.28,.28,0),(3.06,.24,.24,0),(3.51,.0,.0,0)],crystal_mat,segments=6)
    for i in range(3):
        a=i*math.tau/3
        shard=loft('Orbiting shard',[(2.50,.0,.0,0),(2.64,.09,.09,0),(2.92,.0,.0,0)],crystal_mat,segments=5)
        shard.location.x=math.cos(a)*.46;shard.location.y=math.sin(a)*.46
    optimize_meshes()
    export('tower_'+team)

def golem():
    reset()
    import random
    rng=random.Random(192)
    basalt=material('Guardian fractured basalt',(.20,.245,.25))
    face_stone=material('Guardian worn granite',(.38,.425,.40))
    recess=material('Guardian deep fissures',(.045,.064,.065))
    moss=material('Guardian old moss',(.18,.24,.12))
    energy=material('Guardian inner amber',(.87,.39,.055),.0,.65)
    def rock(name,loc,scale,mat=basalt,seed=0):
        obj=cube(name,loc,scale,mat,0)
        # Actual chipped geometry, rounded only along fractured edges.
        for v in obj.data.vertices:
            v.co.x+=rng.uniform(-.07,.07)*scale[0]
            v.co.y+=rng.uniform(-.06,.06)*scale[1]
            v.co.z+=rng.uniform(-.08,.08)*scale[2]
        bevel=obj.modifiers.new('Eroded fracture edges','BEVEL');bevel.width=min(scale)*.14;bevel.segments=3
        bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=bevel.name)
        subdiv=obj.modifiers.new('Surface topology','SUBSURF');subdiv.subdivision_type='SIMPLE';subdiv.levels=1
        bpy.ops.object.modifier_apply(modifier=subdiv.name)
        texture=bpy.data.textures.new(name+' stone grain',type='CLOUDS');texture.noise_scale=.085;texture.noise_depth=2
        dis=obj.modifiers.new('Sculpted stone erosion','DISPLACE');dis.texture=texture;dis.strength=.009;dis.mid_level=.5
        bpy.ops.object.modifier_apply(modifier=dis.name)
        obj.modifiers.new('Weighted stone normals','WEIGHTED_NORMAL')
        return obj
    loft('Inner torso',[(.85,.35,.23,0),(1.25,.52,.31,0),(1.73,.60,.30,0),(1.98,.38,.25,0)],recess)
    # Thorax broken into interlocking plates around a recessed core.
    for s in [-1,1]:
        chest=plate('Carved breast slab',[(s*.07,1.89),(s*.53,1.87),(s*.62,1.55),(s*.34,1.40),(s*.20,1.62)],.22,face_stone)
        chest.location.y=-.27
        for j in range(3):
            rib=rock('Layered rib',(s*(.36-j*.035),-.23,1.34-j*.15),(.32,.30,.125),basalt)
            rib.rotation_euler.y=s*.18
        shoulder=rock('Broken shoulder cap',(s*.77,0,1.82),(.66,.61,.40),face_stone)
        shoulder.rotation_euler.y=s*.20
        for j in range(3):
            rock('Shoulder strata',(s*(.78+j*.035),.02,1.65-j*.075),(.60-j*.055,.54,.10),basalt)
        ico('Recessed elbow',(s*.91,.01,1.30),(.16,.18,.19),recess)
        rock('Forearm monolith',(s*1.01,-.03,1.03),(.38,.43,.50),basalt)
        rock('Wrist rim',(s*1.02,-.05,.80),(.42,.46,.12),face_stone)
        rock('Palm',(s*1.02,-.10,.64),(.41,.35,.29),basalt)
        for finger in range(3):
            x=s*(.88+finger*.13)
            rock('Finger knuckle',(x,-.29,.66),(.115,.16,.17),face_stone)
            rock('Curled finger',(x,-.30,.52),(.105,.14,.12),basalt)
        rock('Opposed thumb',(s*.78,-.13,.60),(.14,.26,.20),face_stone)
        rock('Hip armor',(s*.29,.0,.79),(.36,.40,.30),basalt)
        ico('Knee socket',(s*.30,-.01,.54),(.13,.15,.13),recess)
        knee=plate('Knee shield',[(-.14,.10),(0,.18),(.14,.10),(.10,-.13),(0,-.19),(-.10,-.13)],.13,face_stone)
        knee.location=(s*.30,-.20,.54)
        rock('Shin pillar',(s*.31,0,.30),(.26,.30,.34),basalt)
        rock('Heel',(s*.31,.02,.12),(.37,.44,.20),basalt)
        for j in range(3):rock('Stone toe',(s*(.19+j*.12),-.24,.11),(.105,.25,.17),face_stone)
        # Narrow energy seams between rock plates rather than solid yellow ornaments.
        rod('Shoulder seam',(s*.52,-.31,1.78),(s*.83,-.32,1.73),.014,energy)
    core=torus('Recessed heart socket',(0,-.338,1.47),.215,.065,recess,(math.pi/2,0,0))
    torus('Chiseled heart surround',(0,-.367,1.47),.205,.025,face_stone,(math.pi/2,0,0))
    ico('Recessed amber heart',(0,-.36,1.47),(.143,.058,.16),energy)
    for i in range(8):
        a=i*math.tau/8
        chip=rock('Socket segment',(math.cos(a)*.235,-.35,1.47+math.sin(a)*.235),(.09,.10,.07),face_stone)
        chip.rotation_euler.y=-a
    rock('Neck vertebra',(0,.015,1.97),(.25,.28,.21),recess)
    rock('Cranium',(0,.02,2.20),(.50,.43,.42),basalt)
    for s in [-1,1]:
        brow=rock('Angular brow',(s*.13,-.23,2.26),(.24,.18,.11),face_stone);brow.rotation_euler.y=s*.15
        rock('Cheek plane',(s*.19,-.19,2.09),(.12,.20,.22),face_stone)
        rod('Inset eye',(s*.045,-.239,2.19),(s*.15,-.235,2.20),.017,energy)
        horn=loft('Broken crown outcrop',[(0,.11,.10,0),(.19,.09,.08,.02),(.33,.04,.04,.06),(.39,0,0,.075)],face_stone,segments=7)
        horn.location=(s*.20,.03,2.37);horn.rotation_euler.y=s*.30
    jaw=plate('Angular stone jaw',[(-.17,2.05),(0,1.98),(.17,2.05),(.14,2.11),(-.14,2.11)],.17,face_stone);jaw.location.y=-.14
    # Chips and sediment collect on upward-facing ledges.
    for i in range(24):
        s=-1 if i%2 else 1
        rock('Moss encrusted shoulder chip',(s*rng.uniform(.55,.97),rng.uniform(-.20,.19),2.02+rng.uniform(0,.045)),(rng.uniform(.045,.10),rng.uniform(.06,.13),.025),moss)
    for j in range(5):rock('Dorsal spine',(0,.31,1.06+j*.17),(.22,.17,.12),face_stone)
    optimize_meshes()
    triangles=sum(len(p.vertices)-2 for obj in bpy.context.scene.objects if obj.type=='MESH' for p in obj.data.polygons)
    print('REFINED_GOLEM_TRIANGLES',triangles)
    export('golem')

def minion(team,armor,glow):
    reset()
    linen=material('Tabard ivory '+team,(.64,.57,.38))
    cloth=material('Tabard enamel '+team,(.07,.29,.37) if team=='blue' else (.43,.075,.11),.12)
    iron=material('Minion forged iron '+team,(.15,.20,.21),.22)
    trim=material('Minion brass '+team,(.52,.37,.16),.5)
    darkleather=material('Minion leather '+team,(.055,.047,.034))
    def follow_hand(obj,parent):
        bpy.context.view_layer.update()
        world=obj.matrix_world.copy()
        obj.parent=parent
        obj.matrix_world=world
        return obj
    # Compact, forward leaning silhouette with a visible cloth tail.
    loft('Chain mail body',[(.38,.16,.13,0),(.53,.21,.15,0),(.88,.245,.17,0),(1.10,.22,.16,0),(1.17,.16,.135,0)],darkleather,segments=20)
    loft('Enamel lamellar cuirass',[(.53,.205,.16,-.008),(.63,.245,.185,-.008),(.94,.25,.18,0),(1.08,.215,.16,0)],cloth,segments=24)
    for z in [.63,.69]:
        curve_points=[]
        for i in range(25):
            x=-.21+.42*i/24
            y=-.18*math.sqrt(max(.2,1-(x/.27)**2))-.012
            curve_points.append((x,y,z+.035*(1-(x/.21)**2)))
        # thin chased bronze seams across overlapping torso plates
        rod('Breastplate piping L',(-.20,-.14,z),(-.025,-.19,z+.025),.009,trim)
        rod('Breastplate piping R',(.025,-.19,z+.025),(.20,-.14,z),.009,trim)
    loft('Leather belt',[(.49,.215,.165,0),(.55,.22,.17,0)],darkleather,segments=24)
    plate('Belt clasp',[(-.055,.48),(0,.45),(.055,.48),(.055,.56),(0,.59),(-.055,.56)],.025,trim).location.y=-.18
    # Helmet has brow, raised nasal guard and a readable colored eye slit.
    loft('Visored kettle helm',[(1.08,.13,.12,0),(1.14,.18,.155,0),(1.32,.19,.16,.008),(1.39,.13,.13,.02),(1.40,.0,.0,.03)],iron,segments=24)
    plate('Nasal guard',[(-.035,1.34),(.035,1.34),(.025,1.13),(0,1.10),(-.025,1.13)],.035,trim).location.y=-.164
    for side in [-1,1]:
        rod('Eye opening',(side*.035,-.161,1.27),(side*.13,-.14,1.275),.016,glow)
        ico('Helmet rivet',(side*.16,-.04,1.20),(.025,.025,.025),trim)
    # Crest plume and cloth tails break the rank-and-file symmetry.
    plume=loft('Short plume',[(1.35,.07,.055,.06),(1.45,.09,.06,.06),(1.57,.05,.04,.07),(1.62,0,0,.08)],trim,segments=8)
    for side in [-1,1]:
        pivot_arm=pivot('Arm'+('L' if side<0 else 'R'),(side*.27,0,1.02))
        loft('Padded sleeve',[(0,.10,.11,0),(-.20,.085,.09,0),(-.34,.07,.075,0)],darkleather,pivot_arm,segments=12)
        shoulder=plate('Shoulder plate',[(side*.02,.24),(side*.19,.28),(side*.32,.17),(side*.29,.035),(side*.10,.02)],.19,iron)
        shoulder.location.y=0
        for x in [.11,.19,.27]:sphere('Shoulder rivet',(side*x,-.102,1.19),(.014,.012,.014),trim)
        loft('Bracer',[( -.32,.075,.078,0),(-.40,.095,.10,0),(-.52,.062,.07,0)],iron,pivot_arm,segments=12)
        # articulated legs retain expected runtime node names
        leg=pivot('Leg'+('L' if side<0 else 'R'),(side*.125,0,.47))
        loft('Trousers',[(0,.105,.11,0),(-.18,.095,.10,0),(-.31,.075,.08,0)],darkleather,leg,segments=12)
        loft('Greave', [(-.22,.084,.09,0),(-.31,.09,.1,0),(-.44,.065,.075,0)],iron,leg,segments=12)
        loft('Boot', [(-.40,.07,.09,-.03),(-.48,.075,.13,-.06),(-.54,.07,.13,-.08)],darkleather,leg,segments=12)
        # Three individually modeled toes on the sabaton front.
        for j in range(3):
            rock_toe=plate('Sabaton toe',[(side*.125-.034+j*.034,.02),(side*.125-.03+j*.034,-.10),(side*.125-.02+j*.034,-.15),(side*.125+.006+j*.034,-.10)],.035,iron,leg)
    # Polearm fixed into the right hand, with guard and two stage spear head.
    arm_r=bpy.data.objects['ArmR']
    shaft=cone('Ash polearm shaft',(.31,-.025,1.33),.034,.027,1.25,darkleather,12)
    shaft.rotation_euler.y=-.12
    for z in [.84,.91,1.55]:
        torus('Polearm ferrule',(.31,-.025,z),.036,.009,trim)
    cone('Tempered spear point',(.31,-.04,2.02),.115,.008,.42,iron,8)
    rod('Spear luminous fuller',(.31,-.132,1.87),(.31,-.132,2.12),.009,glow)
    for side in [-1,1]:
        rod('Spear side barb',(.31,-.04,1.96),(.31+side*.12,-.04,1.86),.018,iron)
    # Shield attached to left forearm; raised boss catches light from camera side.
    arm_l=bpy.data.objects['ArmL']
    shield=plate('Heater shield',[( -.21, .88),(-.48, .96),(-.49,1.30),(-.32,1.37),(-.17,1.30),(-.16,1.00)],.075,iron)
    shield.location.y=-.115
    for j in range(3):
        rod('Shield raised ribs',(-.43+j*.085,-.16,.99),(-.36+j*.085,-.16,1.29),.012,trim)
    ico('Shield radiant boss',(-.325,-.18,1.17),(.065,.035,.075),glow)
    # Split tabard has shaped edges and layered panels.
    for side in [-1,1]:
        panel=plate('Tabard skirt',[(side*.04,.53),(side*.21,.56),(side*.24,.34),(side*.15,.24),(side*.08,.34)],.035,linen)
        panel.location.y=-.13
        emblem=rod('Tabard enamel stripe',(side*.14,-.156,.32),(side*.18,-.156,.50),.012,trim)
    export('minion_'+team)

