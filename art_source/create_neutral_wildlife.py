"""Original neutral wildlife. Blender 4.5 source, metre scale, PBR GLB.

The deer uses a continuous shaped body, long neck and branched luminous antlers.
The beetle uses paired layered elytra and six independently articulated legs.
Node pivots are preserved for Godot motion; these are not skinned skeletons.
"""
import bpy
import math
import os
import numpy as np
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "art_source", "outpost")
MODELS = os.path.join(ROOT, "assets", "models")


def material(name, rgb, roughness=.85, metallic=0, glow=0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if glow:
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1)
        bsdf.inputs["Emission Strength"].default_value = glow
    return mat


fur = material("Lantern stag ash blue fur", (.11, .18, .205), .94)
fur_light = material("Lantern stag soft winter underside", (.26, .34, .32), .97)
fur_dark = material("Lantern stag dark muzzle and hooves", (.027, .037, .034), .9)
antler = material("Lantern stag aged ivory antlers", (.39, .37, .24), .8)
stag_glow = material("Lantern stag cyan phosphor tips", (.20, .75, .87), .45, 0, 2.2)
shell = material("Mossback deep jade chitin", (.045, .115, .073), .68, .12)
shell_edge = material("Mossback polished shell ridges", (.13, .25, .13), .6, .14)
under = material("Mossback charcoal segmented abdomen", (.042, .060, .049), .9)
moss = material("Mossback olive moss islands", (.17, .23, .07), .99)
moss_light = material("Mossback amber lichen", (.33, .34, .115), .98)
beetle_glow = material("Mossback living gold fissures", (.72, .58, .13), .45, 0, 2.0)


def portable_surface(mat, hair=False):
    """Packed PBR textures survive glTF; no unbaked Blender Noise/Bump nodes."""
    size = 256
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    u, v = xx/size, yy/size
    broad = (np.sin(u*math.tau*7+np.sin(v*math.tau*3)) + np.sin(v*math.tau*11+np.cos(u*math.tau*5)))*.5
    grain = np.sin(u*math.tau*(65 if hair else 37)+np.sin(v*math.tau*9))*np.sin(v*math.tau*(5 if hair else 29))
    rgba = np.ones((size,size,4), dtype=np.float32)
    base = np.array(mat.diffuse_color[:3])
    rgba[:,:,:3] = base[None,None,:]*(1+.075*broad[:,:,None]+.035*grain[:,:,None])
    image = bpy.data.images.new(mat.name+" packed colour", width=size, height=size)
    image.pixels.foreach_set(rgba.ravel())
    image.pack()
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    rough = np.ones_like(rgba)
    rough[:,:,:3] = np.clip(float(bsdf.inputs["Roughness"].default_value)+.055*grain[:,:,None], .60, 1)
    rough_image = bpy.data.images.new(mat.name+" packed roughness", width=size, height=size)
    rough_image.colorspace_settings.name = "Non-Color"
    rough_image.pixels.foreach_set(rough.ravel()); rough_image.pack()
    rough_node = mat.node_tree.nodes.new("ShaderNodeTexImage"); rough_node.image = rough_image
    mat.node_tree.links.new(rough_node.outputs["Color"], bsdf.inputs["Roughness"])
    normal = np.ones_like(rgba)
    normal[:,:,0] = .5+.035*grain
    normal[:,:,1] = .5+.013*np.sin(v*math.tau*23+u*math.tau*7)
    normal[:,:,2] = 1
    normal_image = bpy.data.images.new(mat.name+" packed micro normal", width=size, height=size)
    normal_image.colorspace_settings.name = "Non-Color"
    normal_image.pixels.foreach_set(normal.ravel()); normal_image.pack()
    normal_node = mat.node_tree.nodes.new("ShaderNodeTexImage"); normal_node.image = normal_image
    normal_map = mat.node_tree.nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = .4
    mat.node_tree.links.new(normal_node.outputs["Color"], normal_map.inputs["Color"])
    mat.node_tree.links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Specular IOR Level"].default_value = .18 if hair else .32


for target in [fur, fur_light, fur_dark]:
    portable_surface(target, True)
for target in [shell, shell_edge, moss, moss_light]:
    portable_surface(target)


def mesh(name, vertices, faces, mat):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    data.materials.append(mat)
    for polygon in data.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def attach(obj, parent):
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world
    return obj


def pivot(name, point, parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = point
    if parent:
        attach(obj, parent)
    return obj


def ellipsoid(name, point, size, mat, parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, location=point)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.use_smooth = True
    if parent:
        attach(obj, parent)
    return obj


def tube(name, points, radius, mat, parent=None, tip=.35):
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.resolution_u = 7
    data.bevel_depth = radius
    data.bevel_resolution = 2
    spline = data.splines.new("BEZIER")
    spline.bezier_points.add(len(points)-1)
    for i, (bp, p) in enumerate(zip(spline.bezier_points, points)):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
        bp.radius = 1-(1-tip)*i/(len(points)-1)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj.select_set(False)
    if parent:
        attach(obj, parent)
    return obj


def loft(name, profiles, mat, parent=None, sides=32):
    # Rings along Y. Profiles (y, z centre, x radius, z radius) are continuous.
    vertices = []
    for y, z, rx, rz in profiles:
        for i in range(sides):
            angle = math.tau*i/sides
            vertices.append((math.cos(angle)*rx, y, z+math.sin(angle)*rz))
    faces = []
    for j in range(len(profiles)-1):
        for i in range(sides):
            nxt = (i+1)%sides
            faces.append((j*sides+i, j*sides+nxt, (j+1)*sides+nxt, (j+1)*sides+i))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((len(profiles)-1)*sides+i for i in range(sides)))
    obj = mesh(name, vertices, faces, mat)
    uv = obj.data.uv_layers.new(name="Body surface UV")
    for polygon in obj.data.polygons:
        for loop_index in polygon.loop_indices:
            index = obj.data.loops[loop_index].vertex_index
            uv.data[loop_index].uv = ((index % sides)/sides, (index//sides)/(len(profiles)-1))
    sub = obj.modifiers.new("Continuous anatomical surface", "SUBSURF")
    sub.levels = 1
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=sub.name)
    if parent:
        attach(obj, parent)
    return obj


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def save(name):
    # Draw calls are grouped within each animated parent and material only.
    groups = {}
    for obj in tuple(bpy.context.scene.objects):
        if obj.type == "MESH":
            groups.setdefault((obj.parent.name if obj.parent else "", tuple(m.name for m in obj.data.materials)), []).append(obj)
    for objects in groups.values():
        if len(objects) < 2:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.object.join()
    os.makedirs(SOURCE, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE, name+".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(MODELS, name+".glb"), export_format="GLB", export_yup=True)
    print("NEUTRAL_ASSET_READY", name, sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type == "MESH"))


def stag():
    clear()
    body = pivot("BodyPivot", (0, 0, 1.36))
    loft("Swept stag ribcage and tapered haunch", [(-.97, 1.37, .08, .12), (-.75, 1.42, .28, .35), (-.48, 1.43, .33, .38), (-.10, 1.40, .33, .37), (.32, 1.47, .33, .40), (.61, 1.48, .27, .40), (.80, 1.48, .16, .24)], fur, body)
    ellipsoid("Pale breast and lower ribcage", (0, .24, 1.25), (.275, .54, .24), fur_light, body)
    tube("Sculpted rising neck", [(0, .60, 1.50), (0, .83, 1.85), (0, 1.0, 2.08)], .22, fur, body, .69)
    head = pivot("HeadPivot", (0, 1.0, 2.10), body)
    ellipsoid("Tapered noble brow", (0, 1.13, 2.15), (.185, .28, .23), fur, head)
    ellipsoid("Long smooth muzzle", (0, 1.37, 2.04), (.12, .25, .13), fur_light, head)
    ellipsoid("Velvet nose", (0, 1.575, 2.035), (.105, .064, .08), fur_dark, head)
    for side, label in [(-1, "L"), (1, "R")]:
        ellipsoid("Sapphire watchful eye "+label, (side*.161, 1.245, 2.17), (.027, .048, .032), stag_glow, head)
        ear = pivot("Ear"+label, (side*.17, 1.08, 2.29), head)
        outer = ellipsoid("Long leaf shaped ear "+label, (side*.30, 1.08, 2.38), (.20, .07, .09), fur, ear)
        outer.rotation_euler[1] = -side*.35
        inner = ellipsoid("Ear soft inner "+label, (side*.31, 1.095, 2.40), (.13, .058, .025), fur_light, ear)
        inner.rotation_euler[1] = -side*.35
        points = [(side*.12, 1.04, 2.30), (side*.25, .95, 2.57), (side*.37, .86, 2.88), (side*.53, .78, 3.11)]
        tube("Main flowing antler "+label, points, .051, antler, head, .15)
        branches = [([(side*.24, .96, 2.55), (side*.44, 1.09, 2.72), (side*.62, 1.20, 2.88)], .032), ([(side*.35, .87, 2.83), (side*.23, .98, 3.02), (side*.20, 1.02, 3.18)], .031), ([(side*.43, .82, 2.96), (side*.66, .85, 3.07), (side*.74, .80, 3.22)], .025)]
        for index, (branch, radius) in enumerate(branches):
            tube("Branching antler %s%d" % (label,index), branch, radius, antler, head, .12)
            tip = Vector(branch[-1])
            before = tip.lerp(Vector(branch[-2]), .33)
            tube("Living antler phosphor %s%d" % (label,index), [before, tip], radius*.51, stag_glow, head, .30)
        tube("Main luminous antler tip "+label, [points[-2], points[-1]], .022, stag_glow, head, .10)
        for front, code, y in [(True, "F", .52), (False, "B", -.63)]:
            x = side*.225
            hip_point = (x, y, 1.30)
            knee_point = (x, y+(-.045 if front else .12), .69)
            ankle = (x, y+(.025 if front else -.03), .13)
            hip = pivot("StagHip"+label+code, hip_point)
            tube("Shaped upper limb "+label+code, [hip_point, (x,y,1.02), knee_point], .094 if front else .118, fur, hip, .50)
            ellipsoid("Compact hock "+label+code, knee_point, (.067,.073,.085), fur_dark, hip)
            knee = pivot("StagKnee"+label+code, knee_point, hip)
            tube("Tapered lower shin "+label+code, [knee_point, ankle], .047, fur_light, knee, .62)
            ellipsoid("Split hoof "+label+code, (x, ankle[1]+.035, .085), (.06, .10, .07), fur_dark, knee)
    tail = pivot("TailPivot", (0, -.91, 1.54), body)
    tube("Short tapered deer tail", [(0,-.9,1.54),(0,-1.11,1.54),(0,-1.21,1.48)], .08, fur_light, tail, .25)
    for side in [-1,1]:
        for y, z in [(-.55,1.64),(-.31,1.69),(-.05,1.70),(.17,1.73)]:
            ellipsoid("Subtle shoulder star mark", (side*.265, y, z), (.013,.030,.021), fur_light, body)
    save("lantern_stag")


def beetle():
    clear()
    body = pivot("BodyPivot", (0, 0, .68))
    ellipsoid("Continuous beetle abdomen", (0,-.12,.58), (.52,.76,.32), under, body)
    ellipsoid("Broad protective pronotum", (0,.53,.68), (.47,.31,.28), shell, body)
    head = pivot("HeadPivot", (0,.76,.55), body)
    ellipsoid("Compact armored head", (0,.84,.56), (.26,.23,.20), shell_edge, head)
    for side,label in [(-1,"L"),(1,"R")]:
        elytron = ellipsoid("Paired sculpted elytron "+label, (side*.225,-.16,.79), (.31,.66,.24), shell, body)
        elytron.rotation_euler[1] = side*.14
        tube("Elytron raised outer border "+label, [(side*.33,.40,.83),(side*.51,.10,.77),(side*.48,-.42,.72),(side*.20,-.79,.64)], .028, shell_edge, body, .9)
        tube("Golden central light seam "+label, [(side*.055,.43,.93),(side*.064,-.14,1.025),(side*.052,-.71,.75)], .017, beetle_glow, body, .7)
        for j in range(3):
            y=.22-j*.28
            tube("Overlapping shell growth ridge", [(side*.12,y,.997-j*.035),(side*.31,y-.10,.945-j*.035),(side*.45,y-.19,.81-j*.035)], .013, shell_edge, body, .55)
        ellipsoid("Warm compound eye "+label, (side*.20,.96,.62), (.065,.067,.045), beetle_glow, head)
        antenna = pivot("Ear"+label, (side*.15,1.0,.63), head)
        tube("Sensitive club antenna "+label, [(side*.15,1.0,.63),(side*.30,1.20,.77),(side*.37,1.33,.73)], .025, under, antenna, .7)
        ellipsoid("Antenna glow club "+label, (side*.37,1.33,.73), (.049,.071,.031), beetle_glow, antenna)
        for leg in range(3):
            y = .38-leg*.43
            hip_pt=(side*.40,y,.61)
            knee_pt=(side*(.75 if leg!=1 else .86),y+(.18 if leg==0 else -.12),.29)
            foot=(side*.98,y+(.30 if leg==0 else -.22),.035)
            hip=pivot("BeetleHip%s%d"%(label,leg),hip_pt)
            tube("Curved chitin femur", [hip_pt,(side*.63,y,.52),knee_pt], .055, shell_edge, hip, .62)
            ellipsoid("Leg joint", knee_pt, (.055,.058,.056), under, hip)
            knee=pivot("BeetleKnee%s%d"%(label,leg),knee_pt,hip)
            tube("Fine articulated tarsus", [knee_pt,(side*.92,foot[1],.12),foot], .031, under, knee, .36)
    # Arranged islands follow the upper carapace. Their roughness contrasts with chitin.
    for x,y,z,rx,ry in [(-.24,-.3,1.025,.14,.19),(.25,.03,1.048,.14,.13),(.27,-.43,.985,.115,.15),(-.29,.12,1.04,.09,.10)]:
        points = [(x,y,z+.012)]
        sides = 20
        for i in range(sides):
            angle = math.tau*i/sides
            irregular = 1+.15*math.sin(angle*5+1.2)+.12*math.sin(angle*3+.5)
            points.append((x+math.cos(angle)*rx*irregular,y+math.sin(angle)*ry*irregular,z-.012))
        patch = mesh("Irregular raised moss island", points, [(0,i+1,(i+1)%sides+1) for i in range(sides)], moss)
        uv = patch.data.uv_layers.new(name="Moss UV")
        for polygon in patch.data.polygons:
            for loop_index in polygon.loop_indices:
                vertex = patch.data.vertices[patch.data.loops[loop_index].vertex_index].co
                uv.data[loop_index].uv = ((vertex.x-x)/rx*.5+.5,(vertex.y-y)/ry*.5+.5)
        attach(patch, body)
        for i in range(3):
            angle=i*2.15
            ellipsoid("Small pale lichen", (x+math.cos(angle)*rx*.7,y+math.sin(angle)*ry*.7,z+.018), (.027,.036,.008), moss_light, body)
    save("mossback_beetle")


stag()
beetle()
