"""Original game-scale luminous discoveries for Ember Watch, Blender 4.5.

Background reproduction:
  blender --background --factory-startup --python art_source/create_luminous_discoveries.py
All four assets have a ground origin. Explicit portable PBR materials; no noise
nodes or photographic lights are exported. Editable individual construction
objects remain in each .blend; export copies merge by material for fewer draws.
"""
import bpy
import math
import os
import random
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "art_source", "discoveries")
MODELS = os.path.join(ROOT, "assets", "models")
os.makedirs(SOURCE, exist_ok=True)
os.makedirs(MODELS, exist_ok=True)


def mat(name, rgb, rough=.8, metal=0, emit=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit:
        p.inputs["Emission Color"].default_value = (*rgb, 1)
        p.inputs["Emission Strength"].default_value = emit
    return m


stem = mat("Discoveries soot olive stem", (.055, .10, .067), .94)
leafmat = mat("Discoveries blue green leathery leaf", (.045, .17, .13), .86)
leafback = mat("Discoveries dry leaf underside", (.115, .155, .09), .94)
vein = mat("Discoveries pale leaf vein", (.20, .285, .135), .89)
petalback = mat("Discoveries burnt ochre petal backs", (.37, .10, .022), .83)
petal = mat("Discoveries amber petal lamina", (.78, .285, .035), .54, 0, 1.05)
filament = mat("Discoveries honey luminous filaments", (1.0, .56, .10), .43, 0, 2.4)
soil = mat("Discoveries charred roots", (.06, .052, .041), .98)
stone = mat("Discoveries weathered slate", (.16, .19, .185), .94)
stoneedge = mat("Discoveries pale split rock planes", (.255, .29, .27), .91)
stoneshade = mat("Discoveries dark stone recess", (.065, .087, .084), .97)
crystal = mat("Discoveries petrol teal crystal shell", (.032, .28, .30), .33, .13)
crystaledge = mat("Discoveries frost crystal cut edges", (.095, .46, .46), .29, .08, .35)
crystalglow = mat("Discoveries turquoise memory core", (.12, .8, .76), .31, 0, 2.0)
steel = mat("Discoveries antique steel", (.066, .093, .09), .73, .58)
steeledge = mat("Discoveries polished worn metal edges", (.19, .23, .215), .48, .70)
copper = mat("Discoveries oxidized bronze", (.29, .16, .062), .67, .7)
rust = mat("Discoveries localized oxide", (.225, .076, .025), .95, .16)
canvas = mat("Discoveries faded supply cloth", (.20, .22, .13), .98)
canvashem = mat("Discoveries warm cloth stitches", (.39, .34, .20), .95)
black = mat("Discoveries charcoal rubber", (.012, .021, .022), .98)
enamel = mat("Discoveries rescue ochre enamel", (.54, .29, .066), .84, .12)
lockglow = mat("Discoveries supply lock amber light", (1, .45, .09), .34, 0, 2.5)
lampglow = mat("Discoveries ruined lamp ivory light", (.67, .84, .58), .35, 0, 2.15)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def mesh(name, vertices, faces, material, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    data.materials.append(material)
    for p in data.polygons:
        p.use_smooth = smooth
    o = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(o)
    return o


def bevel(o, size=.02, segments=2):
    b = o.modifiers.new("Physical worn edge bevel", "BEVEL")
    b.width = size
    b.segments = segments
    o.modifiers.new("Weighted broad plane normals", "WEIGHTED_NORMAL")
    return o


def box(name, loc, size, material, edge=.02, rotation=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = size
    if rotation:
        o.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(material)
    return bevel(o, edge) if edge else o


def rod(name, a, b, radius, material, sides=10, tip=None):
    a, b = Vector(a), Vector(b)
    d = b-a
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=radius,
        radius2=radius if tip is None else tip, depth=d.length, location=(a+b)*.5)
    o = bpy.context.object
    o.name = name
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    o.data.materials.append(material)
    for p in o.data.polygons:
        p.use_smooth = len(p.vertices) == 4
    return o


def tube(name, points, radius, material, sides=6):
    """Parallel transported enough for these gentle botanical/architectural arcs."""
    vertices, faces = [], []
    points = [Vector(p) for p in points]
    for i, p in enumerate(points):
        tangent = points[min(i+1, len(points)-1)] - points[max(i-1, 0)]
        tangent.normalize()
        u = tangent.cross(Vector((0, 1, 0)))
        if u.length < .1:
            u = tangent.cross(Vector((1, 0, 0)))
        u.normalize()
        v = tangent.cross(u).normalized()
        for j in range(sides):
            a = math.tau*j/sides
            vertices.append(p+radius*(u*math.cos(a)+v*math.sin(a)))
    for i in range(len(points)-1):
        for j in range(sides):
            a=i*sides+j; b=i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.append(tuple(range(sides-1,-1,-1)))
    faces.append(tuple((len(points)-1)*sides+i for i in range(sides)))
    return mesh(name, vertices, faces, material, True)


def faceted_stone(name, loc, radius, height, material=stone, seed=7):
    rng = random.Random(seed)
    sides=7
    verts=[]
    for k, (rr,z) in enumerate(((.92,0),(1,.38),(.75,1))):
        for i in range(sides):
            a=math.tau*i/sides+.12*k
            r=radius*rr*rng.uniform(.9,1.08)
            verts.append((loc[0]+math.cos(a)*r,loc[1]+math.sin(a)*r,loc[2]+height*z))
    faces=[tuple(range(sides-1,-1,-1))]
    for k in range(2):
        for i in range(sides):
            j=(i+1)%sides
            faces.append((k*sides+i,k*sides+j,(k+1)*sides+j,(k+1)*sides+i))
    faces.append(tuple(2*sides+i for i in range(sides)))
    o=mesh(name,verts,faces,material)
    o.data.materials.append(stoneedge)
    for p in o.data.polygons:
        if p.index in (3,8,12,15):
            p.material_index=1
    return bevel(o,.018,1)


def lamina(name, start, end, width, material, curve=.16, fold=.04, thick=.006):
    """Tapered curved botanical sheet with a longitudinal midrib, not an ellipsoid."""
    a,b=Vector(start),Vector(end)
    d=b-a
    cross=Vector((-d.y,d.x,0)).normalized()
    if cross.length<.5:
        cross=Vector((1,0,0))
    verts=[];faces=[]
    rows=7;cols=2
    for i in range(rows+1):
        t=i/rows
        taper=math.sin(math.pi*t)**.85
        center=a+d*t+Vector((0,0,curve*math.sin(math.pi*t)))
        for j in range(cols+1):
            u=2*j/cols-1
            p=center+cross*(u*width*taper)
            p.z+=fold*(1-abs(u))*taper-.028*abs(u)*taper
            verts.append(p)
    for i in range(rows):
        for j in range(cols):
            k=i*(cols+1)+j
            faces.append((k,k+1,k+cols+2,k+cols+1))
    o=mesh(name,verts,faces,material,True)
    s=o.modifiers.new("Botanical sheet thickness","SOLIDIFY");s.thickness=thick
    return o


def ember_bloom():
    clear()
    # An asymmetric forked plant with a large crown and two lower blossoms.
    # Curving tapered leaves keep its silhouette botanical from the isometric camera.
    tube("Bent ash bloom main stem",[(0,0,.02),(-.08,.025,.28),(-.11,.01,.57),
         (-.03,-.015,.84),(.13,.01,1.08),(.15,.015,1.30)],.035,stem,8)
    crowns=[((.15,.015,1.30),.43,9),((-.41,.15,.94),.30,7),((.39,-.20,.76),.26,6)]
    tube("Left fork stem",[(-.1,.0,.45),(-.29,.07,.66),(-.42,.13,.87),(-.41,.15,.94)],.022,stem)
    tube("Right fork stem",[(-.08,0,.35),(.14,-.12,.53),(.38,-.20,.76)],.021,stem)
    leaves=[((-.07,0,.34),(-.64,-.15,.40),.19,.17),
            ((-.08,.01,.48),(.51,.30,.54),.19,.16),
            ((-.10,0,.61),(-.53,.41,.67),.17,.13),
            ((.04,0,.98),(.49,.27,1.05),.115,.095),
            ((-.33,.1,.79),(-.65,.28,.86),.11,.1)]
    for i,(a,b,w,c) in enumerate(leaves):
        o=lamina("Swept thick leaf %d"%i,a,b,w,leafmat,c,.042,.012)
        o.data.materials.append(leafback)
        o.modifiers[0].material_offset=1
        pts=[]
        for j in range(11):
            t=j/10;p=Vector(a)+(Vector(b)-Vector(a))*t
            p.z+=(c+.046)*math.sin(math.pi*t)
            pts.append(p)
        tube("Leaf continuous midrib %d"%i,pts,.006,vein,5)
    for c,r,n in crowns:
        cx,cy,cz=c
        for i in range(n):
            ang=math.tau*i/n+.22
            # Two staggered petal rings open upwards like a bank of tiny lamps.
            for ring in range(2):
                a=ang+ring*math.pi/n
                radius=r*(1 if ring==0 else .63)
                start=(cx+math.cos(a)*.055,cy+math.sin(a)*.055,cz-.07)
                end=(cx+math.cos(a)*radius,cy+math.sin(a)*radius,
                     cz+(.035 if ring==0 else .17))
                o=lamina("Layered amber bloom petal",start,end,radius*.26,
                    petal if ring else petalback,.065 if ring else .025,.035,.009)
                if ring==0:
                    # A narrower luminous face sits within the curled dark outer petal.
                    lamina("Petal warm interior",(start[0],start[1],start[2]+.016),
                        (end[0]*.93+cx*.07,end[1]*.93+cy*.07,end[2]+.009),
                        radius*.20,petal,.043,.015,.003)
        rod("Bloom ribbed calyx",(cx,cy,cz-.14),(cx,cy,cz-.045),.082,stem,9,tip=.115)
        for i in range(7):
            a=math.tau*i/7
            bx=cx+math.cos(a)*.047;by=cy+math.sin(a)*.047
            tip=(cx+math.cos(a)*.074,cy+math.sin(a)*.074,cz+.17+(.02 if i%2 else 0))
            tube("Luminous blossom filament",[(bx,by,cz-.04),(bx,by,cz+.08),tip],.009,filament,5)
            rod("Faceted pollen head",tip,(tip[0],tip[1],tip[2]+.033),.021,filament,7,tip=.01)
    for i in range(5):
        a=i*math.tau/5+.2
        tube("Exposed ash root",[(0,0,.075),(math.cos(a)*.13,math.sin(a)*.13,.028),
             (math.cos(a)*.31,math.sin(a)*.31,.006)],.025,soil)


def cut_crystal(name, loc, r, h, lean=(0,0), core=False):
    sides=6
    verts=[]
    for k,(z,rr) in enumerate(((0,.73),(.18,1),(.75,.93),(.92,.55))):
        for i in range(sides):
            a=math.tau*i/sides+.15
            verts.append((loc[0]+lean[0]*z+math.cos(a)*r*rr,
                          loc[1]+lean[1]*z+math.sin(a)*r*rr,loc[2]+h*z))
    verts.append((loc[0]+lean[0],loc[1]+lean[1],loc[2]+h))
    faces=[tuple(range(sides-1,-1,-1))]
    for k in range(3):
        for i in range(sides):
            j=(i+1)%sides
            faces.append((k*sides+i,k*sides+j,(k+1)*sides+j,(k+1)*sides+i))
    for i in range(sides):
        faces.append((18+i,18+(i+1)%sides,24))
    o=mesh(name,verts,faces,crystalglow if core else crystal)
    o.data.materials.append(crystaledge)
    o.data.materials.append(crystalglow)
    for p in o.data.polygons:
        if p.index>=19:
            p.material_index=1
        elif p.index in (4,9,14):
            p.material_index=2
    return bevel(o,.008,1)


def memory_crystal():
    clear()
    faceted_stone("Broad split memory stone plinth",(0,0,0),.70,.22,seed=23)
    faceted_stone("Riven upper slate shelf",(-.10,.04,.19),.53,.18,seed=36)
    cut_crystal("Tall split memory crystal",(-.06,.04,.32),.19,1.12,(.07,.09))
    cut_crystal("Counter angled crystal",(-.29,.06,.25),.16,.70,(-.15,-.04))
    cut_crystal("Forward memory shard",(.30,-.11,.22),.145,.60,(.16,-.10))
    cut_crystal("Short luminous core shard",(.00,-.25,.28),.13,.42,(.025,-.09),True)
    cut_crystal("Rear riven crystal",(.22,.23,.29),.12,.66,(.04,.13))
    # Three narrow inlaid channels trace the old plinth; broad slate faces stay calm.
    for a in (.15,2.3,4.4):
        p=[(math.cos(a)*r,math.sin(a)*r,.245) for r in (.33,.43,.57,.65)]
        tube("Etched memory light channel",p,.012,crystalglow,5)
    for i,(x,y) in enumerate(((-.58,-.13),(.53,.32),(.37,-.49))):
        faceted_stone("Broken shelf fragment",(x,y,.005),.14,.105,seed=60+i)
    # Physical cracks are open dark grooves between loose edge slivers.
    tube("Slate fracture groove",[(-.45,-.24,.215),(-.23,-.36,.242),(-.14,-.47,.204)],.016,stoneshade,5)
    rod("Memory bronze keeper",(-.48,.18,.36),(-.42,.23,.69),.032,copper,8,tip=.023)


def cloth_strip():
    verts=[];faces=[]
    for i in range(13):
        t=i/12
        # Drape across lid, then curve over the front edge of the chest.
        if t<.68:
            y=.39-1.0*t;z=.94+.016*math.sin(t*math.pi*7)
        else:
            u=(t-.68)/.32;y=-.32-.16*math.sin(u*math.pi/2);z=.94-.60*u
        for j in range(5):
            u=j/4
            x=-.40+u*.30+.023*math.sin(t*math.pi*2)
            verts.append((x,y,z+.025*math.sin(u*math.pi*2+t*1.7)))
    for i in range(12):
        for j in range(4):
            k=i*5+j;faces.append((k,k+1,k+6,k+5))
    o=mesh("Worn folded supply cloth strap",verts,faces,canvas,True)
    s=o.modifiers.new("Cloth physical thickness","SOLIDIFY");s.thickness=.012
    for side in (0,4):
        tube("Hand sewn cloth hem",[Vector(verts[i*5+side])+Vector((0,0,.007)) for i in range(13)],.005,canvashem,4)


def supply_cache():
    clear()
    for x in (-.50,.50):
        box("Raised chest metal foot",(x,0,.055),(.18,.68,.11),black,.025)
    box("Recessed old supply chest shell",(0,0,.44),(1.37,.86,.69),steel,.06)
    box("Heavy chest upper lid",(0,0,.86),(1.43,.92,.15),steel,.045)
    box("Lid dark continuous seal",(0,0,.765),(1.39,.9,.045),black,.007)
    for x in (-.625,.625):
        for y in (-.39,.39):
            box("Chest copper corner bracket",(x,y,.435),(.17,.15,.67),copper,.024)
            for z in (.24,.64):
                rod("Chest recessed corner bolt",(x,y-.08,z),(x,y-.096,z),.026,steeledge,6)
        # Handle support and sagging three-sided handle sit proud of the sides.
        box("Chest side handle mount",(x*1.13,0,.53),(.07,.34,.12),steeledge,.018)
        tube("Forged rectangular side carry handle",[(x*1.16,-.145,.54),(x*1.24,-.145,.45),
             (x*1.24,.145,.45),(x*1.16,.145,.54)],.027,steel,8)
    for x in (-.43,.43):
        box("Chest lid bronze brace",(x,0,.955),(.105,.89,.048),copper,.012)
        rod("Pinned rear chest hinge",(x-.09,.473,.83),(x+.09,.473,.83),.042,steeledge,12)
        box("Front split chest latch",(x,-.464,.755),(.09,.055,.225),steeledge,.013)
        box("Front latch enamel insert",(x,-.497,.72),(.045,.013,.058),enamel,.005)
    box("Lock recessed black mounting plate",(.105,-.465,.52),(.39,.038,.27),black,.025)
    box("Salvaged bronze lock housing",(.105,-.495,.54),(.32,.048,.19),copper,.022)
    box("Luminous unlock bar",(.105,-.524,.545),(.205,.008,.055),lockglow,.014)
    for x in (-.045,.255):
        rod("Lock assembly screw",(x,-.515,.54),(x,-.533,.54),.015,steeledge,6)
    # Subtle recessed ribbed front and a chipped painted rescue chevron.
    for x in (-.23,-.12,0,.11,.22):
        box("Chest lower ventilation recess",(x,-.438,.27),(.04,.012,.10),black,.007)
    for side in (-1,1):
        box("Painted broken rescue chevron",(side*.11+.10,-.452,.67),(.20,.009,.032),enamel,.004,
            (0,side*-.30,0))
    cloth_strip()
    for x,y,z in ((.55,-.434,.21),(-.55,-.431,.65),(.58,.23,.951)):
        box("Localized weathered oxide chip",(x,y,z),(.13,.011,.037),rust,.005)


def arch_points(y,z,half,height,steps=16):
    # Pointed Gothic arch; a continuous copper rail opens a readable aperture.
    out=[]
    for i in range(steps+1):
        t=i/steps
        x=-half+2*half*t
        zz=z+height*(1-abs(2*t-1)**1.5)
        out.append((x,y,zz))
    return out


def waylight():
    clear()
    faceted_stone("Buried lamp monument footing",(0,0,0),.60,.25,seed=81)
    box("Chamfered narrow lamp pedestal",(0,.02,.49),(.60,.45,.53),stone,.07)
    box("Worn pedestal stepped collar",(0,.02,.76),(.76,.57,.12),stoneedge,.04)
    # Two tapered stone jambs with an open center; no opaque glowing solid block.
    for side in (-1,1):
        x=side*.34
        verts=[(x-.10,-.15,.80),(x+.10,-.15,.80),(x+.10,.17,.80),(x-.10,.17,.80),
               (x-.08,-.12,1.79),(x+.08,-.12,1.79),(x+.08,.14,1.79),(x-.08,.14,1.79)]
        o=mesh("Tapered lamp stone jamb",verts,[(0,1,2,3),(0,4,5,1),(1,5,6,2),
                (2,6,7,3),(3,7,4,0),(4,7,6,5)],stone)
        bevel(o,.025,1)
        tube("Thin recessed jamb bronze rail",[(side*.235,-.155,.87),
             (side*.235,-.155,1.71)],.022,copper,7)
        box("Stone jamb copper collar",(x,.0,1.20),(.235,.37,.075),copper,.012)
    tube("Monument pointed stone arch",arch_points(.015,1.68,.34,.48),.103,stone,6)
    tube("Continuous bronze pointed inner arch",arch_points(-.16,1.66,.235,.38),.024,copper,8)
    rod("Suspended lamp narrow chain",(0,-.015,1.98),(0,-.015,1.72),.012,steeledge,6)
    # A tall six-sided luminous lantern hangs inside the arch, with visible end caps.
    rod("Warm suspended lantern core",(0,-.012,1.17),(0,-.012,1.71),.112,lampglow,8,tip=.095)
    rod("Lantern bronze lower cap",(0,-.012,1.115),(0,-.012,1.20),.149,copper,8,tip=.121)
    rod("Lantern bronze upper cap",(0,-.012,1.70),(0,-.012,1.78),.12,copper,8,tip=.075)
    for i in range(4):
        a=math.tau*i/4+.785
        x=math.cos(a)*.115;y=-.012+math.sin(a)*.115
        rod("Lantern cage fine upright",(x,y,1.17),(x*.83,(y+.012)*.83-.012,1.72),.013,copper,7)
    # A runic slot repeats the core color lower down, acting as a nighttime landmark.
    box("Pedestal dark runic recess",(0,-.218,.49),(.10,.02,.31),stoneshade,.008)
    box("Pedestal luminous narrow memory glyph",(0,-.23,.49),(.024,.009,.24),lampglow,.006)
    for z in (.42,.56):
        box("Glyph broken copper horizontal",(.0,-.239,z),(.09,.012,.015),copper,.003)
    tube("Large physically recessed plinth fracture",[(-.25,-.235,.69),(-.18,-.24,.59),
         (-.22,-.24,.46),(-.11,-.24,.35)],.010,stoneshade,5)
    for i,(x,y) in enumerate(((-.46,-.27),(.40,.34),(.39,-.40))):
        faceted_stone("Loose monument stone chip",(x,y,.003),.10,.07,seed=91+i)
    # The finial deliberately stays dark so only the light chamber blooms.
    mesh("Chipped pointed monument finial",[(-.14,-.13,2.12),(.14,-.13,2.12),
         (.14,.16,2.12),(-.14,.16,2.12),(0,.015,2.33)],
         [(0,3,2,1),(0,1,4),(1,2,4),(2,3,4),(3,0,4)],stoneedge)


def export_asset(name, build):
    build()
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE,name+".blend"))
    originals=[o for o in bpy.context.scene.objects if o.type=="MESH"]
    # Keep the saved editable construction separate from optimized export copies.
    bpy.ops.object.select_all(action="DESELECT")
    copies=[]
    for original in originals:
        clone=original.copy();clone.data=original.data.copy()
        bpy.context.collection.objects.link(clone)
        clone.select_set(True);copies.append(clone)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    # Join only the already evaluated export meshes. Material slots survive.
    bpy.ops.object.join()
    joined=bpy.context.object
    joined.name=name+"_portable_pbr"
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    # glTF keeps per-material primitives but one mesh node avoids many tiny nodes.
    joined.data.calc_loop_triangles()
    triangles=len(joined.data.loop_triangles)
    bpy.ops.export_scene.gltf(filepath=os.path.join(MODELS,name+".glb"),export_format="GLB",
        use_selection=True,export_apply=True,export_cameras=False,export_lights=False,
        export_materials="EXPORT",export_yup=True)
    print("LUMINOUS_ASSET_OK",name,"triangles",triangles,"materials",len(joined.data.materials))


for asset,builder in (("ember_bloom",ember_bloom),("memory_crystal",memory_crystal),
                       ("supply_cache",supply_cache),("waylight",waylight)):
    export_asset(asset,builder)
