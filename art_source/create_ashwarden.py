"""Rebuild the playable outpost guardian from the original knight sculpture.

The hero keeps the accepted closed helm and rounded pauldrons, but gets an
ash-worn silhouette, articulated knees, ankles and elbows, and a shoulder mantle.
All editable source objects remain in the saved .blend files.
"""
import bpy
import bmesh
import math
import os
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'art_source', 'hero_showcase_blue.blend')


def material(name, color, metallic=0.0, roughness=0.65, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*color, 1)
        bsdf.inputs['Emission Strength'].default_value = emission
    return mat


def attach(obj, parent):
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world
    return obj


def pivot(name, location, parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    return attach(obj, parent) if parent else obj


def mesh(name, vertices, faces, mat, parent=None, smooth=True):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    data.materials.append(mat)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    for poly in data.polygons:
        poly.use_smooth = smooth
    return attach(obj, parent) if parent else obj


def loft(name, rings, mat, x=0, parent=None, sides=24):
    # Ring tuple: world height, half-width, half-depth, y offset.
    vertices = [(x + w * math.cos(2 * math.pi * j / sides),
                 y + d * math.sin(2 * math.pi * j / sides), z)
                for z, w, d, y in rings for j in range(sides)]
    faces = [(i * sides + j, i * sides + (j + 1) % sides,
              (i + 1) * sides + (j + 1) % sides, (i + 1) * sides + j)
             for i in range(len(rings) - 1) for j in range(sides)]
    faces += [tuple(reversed(range(sides))),
              tuple((len(rings) - 1) * sides + j for j in range(sides))]
    obj = mesh(name, vertices, faces, mat, parent)
    bevel = obj.modifiers.new('Soft forged edge', 'BEVEL')
    bevel.width = .007
    bevel.segments = 2
    obj.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
    return obj


def plate(name, front, mat, thickness=.026, parent=None):
    # Front outline follows the body; back cap gives a readable side profile.
    n = len(front)
    vertices = list(front) + [(x, y + thickness, z) for x, y, z in front]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n)
              for i in range(n)]
    obj = mesh(name, vertices, faces, mat, parent, False)
    bevel = obj.modifiers.new('Forged rim', 'BEVEL')
    bevel.width = .008
    bevel.segments = 2
    obj.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
    return obj


def line(name, points, radius, mat, parent=None):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new('POLY')
    spline.points.add(len(points) - 1)
    for dst, point in zip(spline.points, points):
        dst.co = (*point, 1)
    curve.materials.append(mat)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    return attach(obj, parent) if parent else obj


def recolor_original(team):
    red = team == 'red'
    colors = {
        'tempered midnight steel': ((.075, .082, .075) if not red else (.11, .066, .061), .58, .68),
        'brushed silver edges': ((.31, .34, .31) if not red else (.34, .27, .25), .62, .57),
        'engraved aged electrum': ((.31, .205, .085), .62, .61),
        'recessed black leather': ((.026, .029, .025), .0, .89),
        'midnight woven mantle': ((.065, .077, .071) if not red else (.14, .054, .052), .0, .95),
        'dim aether glass': ((.85, .28, .045), .18, .31),
        'Aether cyan': ((1.0, .31, .055), .15, .32),
        'Antique brass blue': ((.28, .185, .075), .62, .62),
        'Azure enamel': ((.068, .092, .086) if not red else (.14, .055, .052), .35, .62),
        'Forged silver blue': ((.20, .245, .235) if not red else (.28, .18, .16), .60, .61),
        'Ivory steel': ((.51, .55, .48), .38, .60),
        'Knight leather blue': ((.03, .028, .025), .0, .86),
        'Midnight cloth': ((.085, .084, .07) if not red else (.13, .06, .05), .0, .96),
    }
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        if not bsdf:
            continue
        for key, (color, metallic, roughness) in colors.items():
            if key in mat.name:
                bsdf.inputs['Base Color'].default_value = (*color, 1)
                bsdf.inputs['Metallic'].default_value = metallic
                bsdf.inputs['Roughness'].default_value = roughness
                mat.diffuse_color = (*color, 1)
                if 'aether' in key.lower() or key == 'Aether cyan':
                    bsdf.inputs['Emission Color'].default_value = (*color, 1)
                    bsdf.inputs['Emission Strength'].default_value = 1.65
                break


def split_lower_arm(obj, label, ceiling=1.235):
    """Separate the vambrace from a silver mesh joined with shoulder lames.

    The original knight has disconnected armor pieces merged per material.
    A whole-object reparent would bend the shoulder with the elbow, so select
    complete connected pieces using their evaluated world-space height.
    No armor surface is cut and the unposed world geometry is unchanged.
    """
    adjacency = [set() for _ in obj.data.vertices]
    for edge in obj.data.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    seen, lower = set(), set()
    for seed in range(len(adjacency)):
        if seed in seen:
            continue
        component, stack = set(), [seed]
        seen.add(seed)
        while stack:
            vertex = stack.pop()
            component.add(vertex)
            for neighbor in adjacency[vertex] - seen:
                seen.add(neighbor)
                stack.append(neighbor)
        if max((obj.matrix_world @ obj.data.vertices[i].co).z
               for i in component) <= ceiling:
            lower.update(component)
    if not lower or len(lower) == len(obj.data.vertices):
        return None
    forearm = obj.copy()
    forearm.data = obj.data.copy()
    forearm.name = 'Forearm armor ' + label
    bpy.context.collection.objects.link(forearm)
    for target, keep_lower in ((obj, False), (forearm, True)):
        bm = bmesh.new()
        bm.from_mesh(target.data)
        bm.verts.ensure_lookup_table()
        removed = [v for v in bm.verts
                   if (v.index in lower) != keep_lower]
        bmesh.ops.delete(bm, geom=removed, context='VERTS')
        bm.to_mesh(target.data)
        bm.free()
        target.data.update()
    return forearm


def articulate_arms(leather):
    """Add anatomical elbow pivots without changing the accepted rest pose.

    Blender is Z-up, facing -Y. After Y-up glTF conversion each elbow has
    Godot local position (0, -0.395, 0.012); negative local X flexes forward.
    Shoulder lames and upper sleeves stay on ArmL/R. Only the couter,
    vambrace, gauntlet and Sword wrist subtree move with the elbow.
    """
    for sign, label in ((-1, 'L'), (1, 'R')):
        arm = bpy.data.objects['Arm' + label]
        elbow = pivot('Elbow' + label, (sign * .36, -.012, 1.155), arm)
        for child in list(arm.children):
            if child.type != 'MESH':
                continue
            split_lower_arm(child, label)
        bpy.context.view_layer.update()
        for child in list(arm.children):
            if child == elbow:
                continue
            if child.name == 'Sword wrist':
                attach(child, elbow)
            elif child.type == 'MESH':
                upper = max((child.matrix_world @ Vector(co)).z
                            for co in child.bound_box)
                if upper <= 1.235:
                    attach(child, elbow)
        # A recessed leather bellows remains under the couter during flexion.
        # Its narrow waist avoids a visible hard gap behind the metal plate.
        loft('Elbow flexible joint ' + label,
             [(1.115, .077, .082, -.008), (1.135, .084, .09, -.008),
              (1.155, .074, .080, -.008), (1.177, .084, .09, -.008),
              (1.20, .079, .084, -.008)], leather, sign * .36, elbow)
        assert any('Gauntlet' in child.name for child in elbow.children)
        assert any('Forearm armor' in child.name for child in elbow.children)
        assert any('Upper sleeve' in child.name for child in arm.children)
        if label == 'R':
            assert bpy.data.objects['Sword wrist'].parent == elbow


def rebuild(team):
    bpy.ops.wm.open_mainfile(filepath=SOURCE)
    recolor_original(team)
    charcoal = material('Ash | brushed iron', (.12, .145, .135), .56, .70)
    ridge = material('Ash | aged nickel edge', (.37, .39, .34), .62, .58)
    umber = material('Ash | dark brown leather', (.09, .052, .032), 0, .89)
    mantle_mat = material('Ash | woven weather cloak',
                          (.105, .112, .090) if team == 'blue' else (.16, .065, .054), 0, .97)
    seam = material('Ash | weathered brass stitch', (.46, .28, .085), .47, .68)
    ember = material('Ash | contained ember', (.95, .32, .048), .05, .37, 2.5)
    amber_glass = material('Ash | amber lens', (.30, .11, .035), .18, .28, 1.4)

    articulate_arms(umber)

    # Remove the former single-piece legs and the stiff decorative shoulder cape.
    for label in ('L', 'R'):
        hip = bpy.data.objects['Leg' + label]
        for child in list(hip.children):
            bpy.data.objects.remove(child, do_unlink=True)
    old_cape = bpy.data.objects.get('Tailored pleated cape')
    if old_cape:
        bpy.data.objects.remove(old_cape, do_unlink=True)

    # A grounded boot, independently flexing shin and foot, replaces the old
    # solid swinging leg. Deliberate open stance reads at the gameplay zoom.
    for sign, label in ((-1, 'L'), (1, 'R')):
        x = sign * .16
        hip = bpy.data.objects['Leg' + label]
        loft('Padded thigh ' + label,
             [(.61, .096, .105, .006), (.72, .126, .126, .005),
              (.90, .135, .145, .013), (1.07, .135, .14, .012)], umber, x, hip)
        loft('Upper overlapping cuisse ' + label,
             [(.70, .107, .119, -.008), (.75, .132, .139, -.004),
              (.93, .15, .157, .004), (1.025, .123, .135, .008)], charcoal, x, hip)
        plate('Thigh forged bevel ' + label,
              [(x-sign*.078,-.119,.78),(x-sign*.10,-.143,.96),
               (x,-.160,1.005),(x+sign*.095,-.139,.94),
               (x+sign*.075,-.12,.76),(x,-.151,.71)], ridge, .024, hip)

        knee = pivot('Knee' + label, (x, .006, .63), hip)
        loft('Knee mail ' + label,
             [(.49, .095, .105, .004), (.56, .111, .116, .0),
              (.655, .112, .115, .0)], umber, x, knee)
        plate('Knee shield ' + label,
              [(x-.113,-.119,.642),(x,-.185,.69),(x+.113,-.119,.642),
               (x+.095,-.131,.547),(x,-.178,.485),(x-.095,-.131,.547)],
              ridge, .035, knee)
        loft('Shin greave ' + label,
             [(.15, .092, .12, -.006), (.23, .116, .132, .004),
              (.43, .115, .120, .014), (.55, .09, .109, .018)],
             charcoal, x, knee)
        plate('Shin arrow ridge ' + label,
              [(x-.052,-.126,.47),(x,-.153,.53),(x+.052,-.126,.47),
               (x+.063,-.138,.23),(x,-.175,.16),(x-.063,-.138,.23)],
              ridge, .016, knee)

        foot = pivot('Foot' + label, (x, -.025, .17), knee)
        loft('Leather ankle ' + label,
             [(.105, .075, .107, -.013), (.16, .09, .11, -.012),
              (.255, .105, .117, .014)], umber, x, foot)
        loft('Broad toe boot ' + label,
             [(.045, .122, .18, -.107), (.085, .138, .21, -.106),
              (.16, .129, .19, -.086), (.216, .09, .115, -.027)],
             charcoal, x, foot, 28)
        line('Boot brass toe arc ' + label,
             [(x-.10,-.28,.105),(x,-.302,.113),(x+.10,-.28,.105)],
             .009, seam, foot)

    # A split, wind-caught mantle replaces the rigid skirt and breaks the
    # formerly symmetrical pauldron silhouette in the overhead view.
    cape = pivot('Tailored pleated cape', (-.28, .115, 1.74))
    rows, cols = 24, 20
    vertices = []
    for i in range(rows + 1):
        t = i / rows
        for j in range(cols + 1):
            u = j / cols
            x = -.49 + .57*u - .24*t + .12*u*t
            y = .12 + .12*t + .07*math.sin(u*math.pi*3.0 + t*.6)*t
            z = 1.76 - 1.17*t + .09*u*t + .06*math.sin(u*math.pi*4)*t
            vertices.append((x, y, z))
    faces = []
    for i in range(rows):
        for j in range(cols):
            p = i*(cols+1)+j
            faces.append((p,p+1,p+cols+2,p+cols+1))
    cloth = mesh('Windworn split mantle', vertices, faces, mantle_mat, cape)
    solidify = cloth.modifiers.new('Cloth thickness', 'SOLIDIFY')
    solidify.thickness = .014
    for edge in (0, cols):
        line('Mantle bound edge', [vertices[i*(cols+1)+edge] for i in range(rows+1)],
             .009, seam, cape)
    line('Weighted mantle hem', vertices[-(cols+1):], .012, seam, cape)
    for u in (.27, .58, .79):
        j = int(cols*u)
        line('Faded cape quilting', [vertices[i*(cols+1)+j] for i in range(2,rows,2)],
             .0035, umber, cape)

    # The outpost's last lamp is worn on the back: one broad warm focal point,
    # protected by a cage, rather than many small fluorescent ornaments.
    loft('Lamp forged housing',
         [(1.12,.115,.09,.29),(1.20,.15,.115,.30),
          (1.43,.15,.115,.30),(1.50,.115,.09,.29)], charcoal, 0)
    loft('Lamp amber core',
         [(1.22,.084,.072,.386),(1.28,.105,.081,.39),
          (1.40,.105,.081,.39),(1.45,.082,.071,.386)], ember, 0)
    for x in (-.11,.11):
        line('Lamp wrought cage',[(x,.365,1.21),(x,.405,1.29),
             (x,.405,1.39),(x,.365,1.47)],.012,seam)
    line('Lamp upper handle',[(-.115,.315,1.49),(0,.315,1.565),
                              (.115,.315,1.49)],.016,ridge)

    # The visor and sword already establish the character. Restrained front
    # details now tie them into the fort's salvaged technology.
    plate('Outpost brass insignia',
          [(-.075,-.258,1.48),(0,-.29,1.55),(.075,-.258,1.48),
           (.052,-.275,1.38),(0,-.292,1.34),(-.052,-.275,1.38)],
          seam, .026)
    plate('Insignia ember',
          [(-.025,-.300,1.47),(0,-.307,1.50),(.025,-.300,1.47),
           (0,-.31,1.425)], amber_glass, .008)
    for sign in (-1,1):
        x = sign*.105
        plate('Weathered split tabard',
              [(x-sign*.08,-.205,1.16),(x+sign*.055,-.202,1.155),
               (x+sign*.082,-.24,.79),(x,-.26,.67),
               (x-sign*.085,-.24,.79)], mantle_mat, .01)
        line('Tabard seam',[(x,-.264,.76),(x+sign*.025,-.244,.95),
                            (x+sign*.008,-.216,1.13)],.006,seam)

    # Export only modeled assets. Curves and modifiers become game meshes,
    # while the animation pivots remain separate for Godot's runtime gait.
    for obj in list(bpy.context.scene.objects):
        if obj.type not in {'CURVE', 'MESH'}:
            continue
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target='MESH')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.wm.save_as_mainfile(
        filepath=os.path.join(ROOT,'art_source','hero_ashwarden_'+team+'.blend'))
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(ROOT,'assets','models','hero_ashwarden_'+team+'.glb'),
        export_format='GLB', export_yup=True)
    print('ASHWARDEN_EXPORTED',team,len(bpy.context.scene.objects))


for faction in ('blue','red'):
    rebuild(faction)
