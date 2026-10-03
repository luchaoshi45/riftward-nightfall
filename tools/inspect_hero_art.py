from pathlib import Path
import bpy
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'art_source' / 'hero_ashwarden_blue.blend'))
bpy.context.view_layer.update()
for obj in bpy.context.scene.objects:
    parent=obj
    in_arm=False
    while parent:
        if parent.name in ('ArmL','ArmR'):
            in_arm=True
        parent=parent.parent
    if not in_arm:
        continue
    bounds=[obj.matrix_world@Vector(co) for co in obj.bound_box] if obj.type=='MESH' else [obj.matrix_world.translation]
    print('ARMOBJ',obj.name,obj.type,'PARENT',obj.parent.name if obj.parent else '-', 'POS',tuple(round(x,3) for x in obj.matrix_world.translation), 'BOUNDS',tuple(round(min(v[i] for v in bounds),3) for i in range(3)), tuple(round(max(v[i] for v in bounds),3) for i in range(3)))
    if obj.type=='MESH':
        adjacency=[set() for v in obj.data.vertices]
        for edge in obj.data.edges:
            a,b=edge.vertices
            adjacency[a].add(b);adjacency[b].add(a)
        seen=set()
        for seed in range(len(adjacency)):
            if seed in seen:
                continue
            stack=[seed];component=[];seen.add(seed)
            while stack:
                i=stack.pop();component.append(i)
                for j in adjacency[i]-seen:
                    seen.add(j);stack.append(j)
            ps=[obj.matrix_world@obj.data.vertices[j].co for j in component]
            lo=tuple(round(min(v[i] for v in ps),3) for i in range(3))
            hi=tuple(round(max(v[i] for v in ps),3) for i in range(3))
            print('PART',len(component),lo,hi)
