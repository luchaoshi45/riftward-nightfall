"""Editable day expedition props for Ember Watch; Blender 4.5 background build.

Run: blender --background --factory-startup --python art_source/create_day_expedition.py
Blender uses metres/Z-up; glTF conversion supplies Godot Y-up. Both origins sit on ground.
Materials intentionally use portable Principled PBR values, not unbaked procedural nodes.
"""
import bpy
import math
import os
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "art_source", "outpost")
MODELS = os.path.join(ROOT, "assets", "models")
os.makedirs(SOURCE, exist_ok=True)
os.makedirs(MODELS, exist_ok=True)


def material(name, color, metallic=0.0, roughness=0.8, emission=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    if emission:
        shader.inputs["Emission Color"].default_value = (*color, 1)
        shader.inputs["Emission Strength"].default_value = emission
    return mat


steel = material("Expedition oxidized charcoal steel", (.09, .105, .108), .55, .67)
steel_edge = material("Expedition worn silver edges", (.26, .28, .265), .65, .61)
rust = material("Expedition copper rust", (.28, .115, .057), .35, .82)
copper = material("Expedition copper windings", (.36, .19, .09), .7, .48)
rubber = material("Expedition black insulation", (.018, .022, .023), 0, .94)
canvas = material("Refuge faded olive canvas", (.17, .205, .157), 0, .98)
canvas_shade = material("Refuge folded canvas", (.085, .114, .086), 0, .98)
canvas_edge = material("Refuge cloth hem", (.235, .262, .198), 0, .95)
stripe = material("Refuge weathered rescue markings", (.55, .40, .20), 0, .88)
medical = material("Refuge first aid enamel", (.35, .38, .32), .12, .86)
red = material("Refuge first aid red cross", (.41, .065, .047), .05, .78)
amber = material("Expedition standby amber lens", (.56, .24, .035), .07, .4, .4)
signal = material("Refuge signal lens", (.16, .50, .53), .05, .4, .5)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def mesh(name, vertices, faces, mat, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    data.materials.append(mat)
    for polygon in data.polygons:
        polygon.use_smooth = smooth
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def bevel(obj, width=.025, segments=2):
    modifier = obj.modifiers.new("Soft worn edges", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier = obj.modifiers.new("Weighted surface normals", "WEIGHTED_NORMAL")
    return obj


def box(name, location, size, mat, width=.025, rotation=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    if rotation:
        obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return bevel(obj, width) if width else obj


def rod(name, a, b, radius, mat, sides=12):
    a, b = Vector(a), Vector(b)
    direction = b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=direction.length,
                                      location=(a+b)*.5)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = len(polygon.vertices) == 4
    return bevel(obj, min(.009, radius*.15))


def curve(name, points, radius, mat, resolution=2):
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.resolution_u = 2
    data.bevel_depth = radius
    data.bevel_resolution = resolution
    spline = data.splines.new("POLY")
    spline.points.add(len(points)-1)
    for point, coordinates in zip(spline.points, points):
        point.co = (*coordinates, 1)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def generator():
    clear()
    # Wide low skid, protected curved copper coil, and asymmetrical control tower.
    # These are separate primary forms so the generator remains readable from above.
    for side in [-1, 1]:
        box("Generator steel skid", (0, side*.58, .11), (2.65, .16, .16), steel)
        box("Skid end cap", (-1.32, side*.58, .11), (.12, .24, .20), rust)
        box("Skid end cap", (1.32, side*.58, .11), (.12, .24, .20), rust)
    for x in [-1.03, .89]:
        box("Grounded transverse brace", (x, 0, .22), (.17, 1.32, .12), steel)
    rod("Generator dynamo drum", (-.89, 0, .73), (.58, 0, .73), .40, steel, 32)
    rod("Generator recessed coil bed", (-.73, 0, .73), (.45, 0, .73), .425, rubber, 32)
    helix = []
    for i in range(521):
        t = i/520
        angle = t*13*math.tau
        helix.append((-.73+t*1.18, math.cos(angle)*.445, .73+math.sin(angle)*.445))
    curve("Thirteen continuous copper coil turns", helix, .028, copper, 2)
    for x in [-.88, .59]:
        rod("Dynamo protective side collar", (x-.055, 0, .73), (x+.055, 0, .73), .48, steel_edge, 24)
        box("Dynamo load bearing foot", (x, 0, .32), (.25, .73, .20), rust)
        for y in [-.29, .29]:
            rod("Secured bearing bolts", (x-.065, y, .98), (x+.065, y, .98), .036, steel, 8)
    # Open guard bars wrap above the coil without covering its silhouette.
    for y in [-.54, .54]:
        curve("Bent generator cage rail", [(-1.07, y, .31), (-1.07, y, 1.17),
              (-.96, y, 1.28), (.62, y, 1.28), (.74, y, 1.15), (.74, y, .31)], .047, steel)
    for x in [-.96, .66]:
        rod("Top cage cross beam", (x, -.54, 1.25), (x, .54, 1.25), .043, steel)
    box("Generator engine block", (.98, .08, .72), (.56, .93, .90), steel, .065)
    box("Engine worn top cover", (.98, .08, 1.20), (.66, 1.0, .10), rust)
    for y in [-.30, -.15, 0, .15, .30]:
        box("Engine cooling fin", (1.295, y+.08, .78), (.065, .075, .59), steel_edge, .008)
    box("Generator control cabinet", (-1.02, -.59, .75), (.50, .22, .81), steel, .03)
    box("Recessed analog instrument panel", (-1.02, -.715, .98), (.40, .035, .22), rubber, .018)
    rod("Glass ammeter lens", (-1.02, -.742, 1.00), (-1.02, -.767, 1.00), .081, medical, 20)
    curve("Meter needle", [(-1.02, -.787, .96), (-.996, -.787, 1.041)], .008, rubber, 0)
    box("Manual starter lever", (-1.01, -.79, .62), (.11, .11, .09), amber, .01)
    rod("Starter lever stalk", (-1.01, -.68, .64), (-1.01, -.82, .64), .027, steel_edge)
    box("Cable terminal amber band", (-1.02, -.734, .83), (.34, .02, .025), stripe, .005)
    curve("Generator power cable", [(-1.0, -.7, .41), (-.66, -.86, .30), (.09, -.87, .16),
          (.66, -.78, .13), (.99, -.46, .42)], .038, rubber)
    curve("Exhaust pipe", [(1.07, .38, 1.15), (1.08, .40, 1.47), (1.06, .52, 1.56),
          (.89, .61, 1.56)], .055, rust)
    rod("Exhaust black aperture", (.886, .61, 1.56), (.868, .61, 1.56), .043, rubber)
    # Limited structurally meaningful chips and fasteners, rather than noise everywhere.
    for x in [-1.09, 1.11]:
        for y in [-.57, .57]:
            rod("Skid anchor bolt", (x, y, .20), (x, y, .24), .034, steel_edge, 6)
    for x in [-.66, -.15, .39]:
        box("Worn cage stripe", (x, -.545, 1.29), (.20, .09, .023), stripe, .005)


def camp():
    clear()
    # Pitched field tent. Curved/folded roof panels preserve cloth structure and
    # an open entrance instead of a solid triangle prism.
    length = 2.80
    rows = 14
    columns = 9
    for side in [-1, 1]:
        vertices, faces = [], []
        for row in range(rows+1):
            y = -length/2+length*row/rows
            for column in range(columns+1):
                t = column/columns
                x = side*1.23*t
                sag = -.07*math.sin(math.pi*row/rows)*math.sin(math.pi*t)
                wrinkle = .018*math.sin(row*2.1+column*.45)*math.sin(math.pi*t)
                z = 1.52-.96*t+sag+wrinkle
                vertices.append((x, y, z))
        for row in range(rows):
            for column in range(columns):
                p = row*(columns+1)+column
                face = (p, p+1, p+columns+2, p+columns+1)
                faces.append(face if side > 0 else face[::-1])
        roof = mesh("Curved sewn canvas roof", vertices, faces, canvas, True)
        roof.data.materials.append(stripe)
        # The rescue marking is part of the actual cloth surface. A separate
        # coplanar decal mesh can float above folded fabric after export.
        for polygon in roof.data.polygons:
            row, column = divmod(polygon.index, columns)
            if 1 <= column <= 7 and row == 4+column//2:
                polygon.material_index = 1
        solidify = roof.modifiers.new("Canvas thickness", "SOLIDIFY")
        solidify.thickness = .014
        mesh("Tent canvas side wall", [(side*1.23, -1.4, .56), (side*1.23, 1.4, .56),
             (side*1.20, 1.36, .06), (side*1.20, -1.36, .06)],
             [(0, 1, 2, 3) if side < 0 else (3, 2, 1, 0)], canvas_shade)
        # Separate eave seams and patch make the fabric's scale legible.
        curve("Heavy rolled tent eave", [(side*1.24, -.1+i*.2, .55) for i in range(-6, 8)],
              .018, canvas_edge, 1)
        for seam_y in [-.70, .18, .95]:
            curve("Tent roof stitched seam", [(side*1.24*(i/12), seam_y,
                  1.525-.96*(i/12)-.06*math.sin(math.pi*(i/12))) for i in range(13)],
                  .008, canvas_edge, 0)
        curve("Guy rope", [(side*1.23, -.92, .56), (side*1.88, -1.35, .10)], .012, canvas_edge, 0)
        curve("Guy rope", [(side*1.23, .95, .56), (side*1.85, 1.35, .10)], .012, canvas_edge, 0)
        for y in [-1.35, 1.35]:
            rod("Tent metal ground stake", (side*1.84, y, 0), (side*1.84, y, .19), .027, rust, 8)
        # Open triangular front flaps leave a central doorway visibly dark.
        flap = mesh("Folded entrance flap", [(0, -1.415, 1.52), (side*1.23, -1.415, .56),
                    (side*1.20, -1.41, .04), (side*.72, -1.37, .11),
                    (side*.36, -1.35, .94)], [(0, 1, 4), (1, 2, 3, 4)], canvas_shade)
        solidify = flap.modifiers.new("Folded flap thickness", "SOLIDIFY"); solidify.thickness = .015
        curve("Entrance rolled hem", [(0, -1.438, 1.52), (side*.36, -1.385, .94),
              (side*.72, -1.395, .11)], .018, canvas_edge, 1)
    mesh("Canvas closed back", [(0, 1.4, 1.52), (-1.23, 1.4, .56), (-1.20, 1.4, .05),
         (1.20, 1.4, .05), (1.23, 1.4, .56)], [(4, 3, 2, 1, 0)], canvas_shade)
    box("Tent groundsheet", (0, 0, .017), (2.38, 2.7, .033), rubber, .006)
    curve("Ridge pole canvas seam", [(0, -1.42, 1.53), (0, 1.42, 1.53)], .025, canvas_edge, 1)
    # Folded bedroll and open supply box near the entrance.
    rod("Refuge rolled sleeping mat", (-.69, -.92, .20), (.03, -.92, .20), .13, canvas, 16)
    for x in [-.50, -.13]:
        box("Bedroll leather strap", (x, -.92, .20), (.06, .28, .28), rubber, .03)
    box("Survivor medical case", (1.55, -.98, .29), (.69, .50, .50), medical, .055)
    box("Medical case dark seam", (1.55, -.98, .405), (.71, .52, .035), rubber, .012)
    box("Medical case raised lid", (1.55, -.98, .50), (.69, .50, .07), medical, .026)
    box("Medical case red cross", (1.55, -.98, .542), (.30, .095, .014), red, .005)
    box("Medical case red cross", (1.55, -.98, .544), (.10, .30, .014), red, .005)
    curve("Medical case handle", [(1.40, -1.24, .37), (1.40, -1.32, .42),
          (1.70, -1.32, .42), (1.70, -1.24, .37)], .025, steel)
    for x in [1.30, 1.80]:
        box("Medical case latch", (x, -1.246, .40), (.052, .02, .095), steel_edge, .008)
    # Signal mast is attached to a small battery box, for a clear mission landmark.
    box("Camp signal battery", (1.51, .83, .25), (.63, .48, .45), steel, .04)
    box("Battery worn rescue band", (1.51, .58, .29), (.51, .012, .07), stripe, .004)
    rod("Telescoping survivor signal mast", (1.51, .83, .44), (1.51, .83, 2.35), .038, steel_edge)
    rod("Telescoping lower mast", (1.51, .83, .32), (1.51, .83, 1.30), .055, steel)
    rod("Lamp lower housing", (1.51, .83, 2.31), (1.51, .83, 2.43), .14, steel, 16)
    rod("Camp cold signal lens", (1.51, .83, 2.43), (1.51, .83, 2.63), .11, signal, 16)
    rod("Lamp weather cap", (1.51, .83, 2.63), (1.51, .83, 2.69), .155, steel, 16)
    for side in [-1, 1]:
        curve("Radio receiver aerial", [(1.51, .83, 2.20), (1.51+side*.17, .83, 2.28),
              (1.51+side*.29, .83, 2.51)], .014, steel_edge, 1)
    mesh("Camp tied rescue flag", [(1.54, .83, 2.07), (2.10, .81, 2.03),
         (1.99, .84, 1.80), (1.54, .83, 1.85)], [(0, 1, 2, 3)], stripe)


def export(name, build):
    build()
    for obj in list(bpy.context.scene.objects):
        if obj.type == "CURVE":
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.convert(target="MESH")
    # Apply modifiers before static consolidation, so another object's modifier
    # cannot alter all the merged mesh. Keep semantic names for the lenses.
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            continue
        bpy.context.view_layer.objects.active = obj
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    groups = {}
    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH":
            groups.setdefault(tuple(m.name for m in obj.data.materials), []).append(obj)
    for objects in groups.values():
        if len(objects) < 2:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.object.join()
    bpy.context.view_layer.update()
    corners = [obj.matrix_world @ Vector(v) for obj in bpy.context.scene.objects
               if obj.type == "MESH" for v in obj.bound_box]
    minimum = [min(v[i] for v in corners) for i in range(3)]
    maximum = [max(v[i] for v in corners) for i in range(3)]
    triangles = 0
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            obj.data.calc_loop_triangles()
            triangles += len(obj.data.loop_triangles)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE, name+".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(MODELS, name+".glb"), export_format="GLB",
                              export_yup=True, export_cameras=False, export_lights=False)
    print("DAY_PROP_READY", name, "triangles", triangles, "bounds", minimum, maximum)


for name, build in [("day_generator", generator), ("survivor_camp", camp)]:
    export(name, build)
