"""Editable, authored environment assets for the Riftward arena (Blender 4.5).

Each asset has its own blend and glTF. Geometry is readable from the isometric camera;
PBR parameters are exported explicitly, without relying on unsupported noise nodes.
"""
import bpy, math, random, os
from math import sin,cos,pi
from mathutils import Vector

ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT=os.path.join(ROOT,'art_source','map_props')
os.makedirs(OUT,exist_ok=True)

def mat(name,c,metal=0,rough=.8,emit=0):
 m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
 m.diffuse_color=(*c,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1)
 p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 if emit:p.inputs['Emission Color'].default_value=(*c,1);p.inputs['Emission Strength'].default_value=emit
 return m

bark=mat('Ancient dark bark',(.045,.030,.020),0,.95)
bark_aged=mat('Grey fissured bark',(.085,.07,.045),0,.98)
moss=mat('Forest moss',(.028,.075,.025),0,.98)
leaves=[mat('Oak leaf %d'%i,c,0,.89) for i,c in enumerate([
 (.015,.067,.025),(.025,.090,.032),(.042,.12,.043),(.020,.08,.045),(.062,.13,.035)])]
pine_leaf=[mat('Cedar needles %d'%i,c,0,.92) for i,c in enumerate([
 (.012,.057,.033),(.020,.080,.052),(.034,.104,.059)])]
fern_green=mat('Fern sage',(.038,.095,.042),0,.94)
flower=mat('Ivory and lavender petals',(.35,.30,.21),0,.85)
fern_shade=mat('Fern deep shade',(.018,.058,.027),0,.95)
fern_tip=mat('Fern new growth',(.075,.15,.055),0,.90)
flower_lilac=mat('Wildflower muted lilac',(.20,.12,.24),0,.86)
flower_cream=mat('Wildflower warm ivory',(.36,.29,.16),0,.88)
mush_cap=mat('Mushroom russet cap',(.16,.058,.038),0,.83)
mush_rim=mat('Mushroom cap edge',(.075,.029,.028),0,.91)
mush_gill=mat('Mushroom pale gills',(.23,.18,.13),0,.96)
grass_sage=mat('Grass weathered sage',(.042,.105,.037),0,.96)
reed_green=mat('Reed river green',(.029,.085,.054),0,.93)
reed_seed=mat('Reed dark seed heads',(.09,.068,.036),0,.94)
stone=[mat('Weathered ruin stone %d'%i,c,0,.96) for i,c in enumerate([
 (.075,.095,.081),(.12,.13,.105),(.055,.076,.070)])]
gold=mat('Tarnished bronze',(.25,.16,.055),.6,.47)
dark=mat('Recessed charcoal',(.027,.04,.044),.15,.78)
cyan=mat('Quiet lunar glass',(.06,.33,.39),.12,.36,1.2)
amber=mat('Warm aether flame',(.54,.30,.085),.12,.4,.9)
cloth_blue=mat('Woven cobalt banner',(.014,.055,.11),0,.85)
cloth_red=mat('Woven crimson banner',(.12,.016,.026),0,.85)
team_blue=mat('Cobalt enamel',(.025,.11,.17),.44,.42)
team_red=mat('Wine enamel',(.18,.025,.045),.44,.42)
glass_blue=mat('Azure aether crystal',(.045,.35,.48),.08,.28,1.25)
glass_red=mat('Crimson aether crystal',(.49,.06,.10),.08,.28,1.25)

def reset():bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
def make_mesh(name,vs,fs,mats,slots=None,smooth=False):
 me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update()
 for m in mats:me.materials.append(m)
 if slots:
  for p,s in zip(me.polygons,slots):p.material_index=s
 for p in me.polygons:p.use_smooth=smooth
 o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);return o
def bevel(o,width=.025):
 b=o.modifiers.new('Soft cut stone bevel','BEVEL');b.width=width;b.segments=2
 o.modifiers.new('Weighted face normals','WEIGHTED_NORMAL');return o
def cylinder(name,loc,r1,r2,depth,material,n=12):
 bpy.ops.mesh.primitive_cone_add(vertices=n,radius1=r1,radius2=r2,depth=depth,location=loc)
 o=bpy.context.object;o.name=name;o.data.materials.append(material);return bevel(o,.02)
def box(name,loc,scale,material,b=.02):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
 o=bpy.context.object;o.name=name;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 o.data.materials.append(material)
 return bevel(o,b) if b>0 else o
def path(name,points,radius,material,closed=False):
 c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.bevel_depth=radius;c.resolution_u=5;c.bevel_resolution=2
 s=c.splines.new('POLY');s.points.add(len(points)-1)
 for p,v in zip(s.points,points):p.co=(*v,1)
 s.use_cyclic_u=closed;o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);c.materials.append(material);return o
def rock(name,center,radius,material,seed=1):
 rng=random.Random(seed);vs=[];fs=[];n=11
 for h,scale in [(.03,.92),(.22,1),(.48,.78),(.65,.35)]:
  for j in range(n):
   a=2*pi*j/n;variation=.84+.20*rng.random()
   vs.append((center[0]+cos(a)*radius[0]*scale*variation,
              center[1]+sin(a)*radius[1]*scale*variation,center[2]+h*radius[2]+rng.uniform(-.025,.025)))
 for i in range(3):
  for j in range(n):
   a=i*n+j;b=i*n+(j+1)%n;fs.append((a,b,b+n,a+n))
 fs.append(tuple(3*n+j for j in range(n)))
 return bevel(make_mesh(name,vs,fs,[material]),.012)
def crystal(name,loc,scale,material):
 x,y,z=loc;w,d,h=scale
 vs=[(x-w,y,z+h*.22),(x,y-d,z+h*.22),(x+w,y,z+h*.22),(x,y+d,z+h*.22),
     (x-w*.7,y,z+h*.74),(x,y-d*.7,z+h*.74),(x+w*.7,y,z+h*.74),(x,y+d*.7,z+h*.74),(x,y,z+h),(x,y,z)]
 fs=[]
 for j in range(4):fs.extend([(j,(j+1)%4,4+(j+1)%4,4+j),(4+j,4+(j+1)%4,8),(9,(j+1)%4,j)])
 return make_mesh(name,vs,fs,[material])
def trunk_and_branches(seed=1,pine=False):
 rng=random.Random(seed)
 vs=[];fs=[];n=13;rings=9;h=3.9 if pine else 3.25
 for k in range(rings):
  t=k/(rings-1);z=.05+t*h
  for j in range(n):
   a=j*2*pi/n
   r=(.31*(1-t)+.12*t)*(1+.09*sin(a*7+seed)+.055*sin(z*4+a*3))
   vs.append((cos(a)*r+.08*sin(t*2),sin(a)*r+.04*cos(t*3),z))
 for k in range(rings-1):
  for j in range(n):
   a=k*n+j;b=k*n+(j+1)%n;fs.append((a,b,b+n,a+n))
 obj=make_mesh('Fluted continuous trunk',vs,fs,[bark],smooth=True)
 for i in range(8 if not pine else 11):
  a=i*2*pi/(8 if not pine else 11)+rng.uniform(-.23,.23)
  z=1.35+i*.19 if not pine else .8+i*.24
  direction=Vector((cos(a),sin(a),.32 if not pine else .15))
  tip=Vector((0,0,z))+direction*(1.2 if not pine else 1.0)
  start=Vector((0,0,z-.12))
  mid=(start+tip)*.5+Vector((0,0,.17))
  path('Tapered mature bough', [start,mid,tip],.07 if not pine else .043,bark)
  if i%2==0:path('Bark split',[(cos(a)*.25,sin(a)*.25,.15), (cos(a)*.18,sin(a)*.18,1.0),
                  (cos(a)*.13,sin(a)*.13,1.8)],.008,bark_aged)
 for j in range(7):
  a=j*2*pi/7
  path('Raised buttress root',[(.05*cos(a),.05*sin(a),.72),(.30*cos(a),.30*sin(a),.27),
                               (.72*cos(a),.72*sin(a),.04)],.065,bark)

def leaf_blade(vs,fs,slots,base,tip,width,material,up=.04):
 """Five-segment folded blade: readable in top-down light and not a flat card."""
 base=Vector(base);tip=Vector(tip);axis=tip-base
 side=Vector((-axis.y,axis.x,0))
 if side.length < .0001:side=Vector((1,0,0))
 side.normalize();start=len(vs)
 for t,w in [(0,0),(.20,.66),(.48,1),(.76,.73),(1,0)]:
  mid=base+axis*t+Vector((0,0,up*sin(pi*t)))
  vs.append(tuple(mid-side*width*w));vs.append(tuple(mid+side*width*w))
  vs.append(tuple(mid+Vector((0,0,up*.7))))
 for k in range(4):
  a=start+k*3;b=a+3
  fs.extend([(a,b,b+2,a+2),(a+2,b+2,b+1,a+1)])
  slots.extend([material,material])

def oak():
 reset();rng=random.Random(23);trunk_and_branches(14)
 verts=[];faces=[];slots=[]
 # Separate irregular branch crowns produce a readable silhouette and shaded gaps.
 for cluster in range(27):
  a=cluster*2*pi/27+rng.uniform(-.17,.17)
  radius=rng.uniform(.34,1.68);height=3.34+rng.uniform(-.38,.46)-radius*.10
  anchor=Vector((radius*cos(a),radius*sin(a),height))
  path('Crown fork',[(anchor.x*.48,anchor.y*.48,2.65),
       (anchor.x*.78,anchor.y*.78,height-.20),anchor],.021,bark_aged)
  for i in range(34):
   b=rng.random()*2*pi;d=math.sqrt(rng.random())*rng.uniform(.20,.56)
   base=anchor+Vector((d*cos(b),d*sin(b),rng.uniform(-.27,.27)))
   direction=Vector((cos(b),sin(b),rng.uniform(-.22,.14)))
   tip=base+direction*rng.uniform(.22,.48)
   leaf_blade(verts,faces,slots,base,tip,rng.uniform(.085,.16),rng.randrange(5),.055)
 make_mesh('Oak branching leaf sprays',verts,faces,leaves,slots)
 for i in range(12):
  a=rng.random()*2*pi;r=rng.uniform(.65,1.7)
  path('Subtle canopy twig',[(r*cos(a)*.35,r*sin(a)*.35,2.7),
      (r*cos(a),r*sin(a),3.18+rng.random()*.3)],.012,bark_aged)

def cedar():
 reset();rng=random.Random(39);trunk_and_branches(54,True)
 verts=[];faces=[];slots=[]
 for tier in range(8):
  z=.87+tier*.43;r=1.53-tier*.165
  for branch in range(13):
   a=branch*2*pi/13+tier*.41+rng.uniform(-.08,.08)
   length=r*rng.uniform(.84,1.13)
   stem=Vector((.04*cos(a),.04*sin(a),z+.27))
   tip=Vector((length*cos(a),length*sin(a),z-.13))
   path('Cedar drooping branch',[stem,stem.lerp(tip,.57)+Vector((0,0,.05)),tip],.014,bark)
   side=Vector((-sin(a),cos(a),0))
   for needle in range(9):
    t=(needle+.35)/9;center=stem.lerp(tip,t)
    spread=(.20+.16*sin(pi*t))*(1-t*.38)
    for s in (-1,1):
     endpoint=center+side*s*spread+Vector((cos(a),sin(a),-.12))* .30
     leaf_blade(verts,faces,slots,center,endpoint,.035,rng.randrange(3),.022)
 make_mesh('Layered cedar needle fans',verts,faces,pine_leaf,slots)

def stone_cluster():
 reset();rock('Layered central boulder',(0,0,0),(1.02,.82,.95),stone[2],3)
 rock('Tumbled slab',(.53,.21,0),(.56,.50,.45),stone[0],8)
 rock('Half buried shard',(-.66,-.20,-.04),(.42,.36,.38),stone[1],11)
 for i in range(13):
  a=i*2*pi/13;r=.42+.05*sin(i*3)
  rock('Stone moss patch',(.76*cos(a),.57*sin(a),.31),(.14,.11,.10),moss,i+31)

def fern():
 reset();rng=random.Random(18);vs=[];fs=[];slots=[]
 for j in range(14):
  a=j*2*pi/14+rng.uniform(-.12,.12);length=rng.uniform(.55,1.05)
  stem=Vector((0,0,.10));tip=Vector((cos(a)*length,sin(a)*length,.21))
  mid=stem.lerp(tip,.48)+Vector((0,0,.30+rng.random()*.08))
  path('Arched fern rachis',[stem,mid,tip],.009,bark_aged)
  for k in range(8):
   t=.11+k*.105;center=stem.lerp(tip,t)+Vector((0,0,.30*sin(t*pi)))
   side=Vector((-sin(a),cos(a),0))
   for sign in (-1,1):
    wing=side*sign*(.13+.15*sin(t*pi))
    end=center+wing+Vector((cos(a),sin(a),-.07))* .30
    leaf_blade(vs,fs,slots,center,end,.035,0 if k<4 else 1,.018)
 make_mesh('Fern folded pinnae',vs,fs,[fern_shade,fern_green,fern_tip],slots)
 for i in range(4):
  a=i*pi/2+.35
  path('Unfurling fiddlehead',[(0,0,.08),(.12*cos(a),.12*sin(a),.31),
       (.18*cos(a),.18*sin(a),.37),(.12*cos(a),.12*sin(a),.40)],.018,fern_tip)

def thicket():
 reset();rng=random.Random(91);vs=[];fs=[];slots=[]
 for i in range(17):
  a=i*2*pi/17+rng.uniform(-.2,.2);r=rng.uniform(.30,.98)
  tip=Vector((r*cos(a),r*sin(a),rng.uniform(.45,.87)))
  path('Thicket branched cane',[(0,0,.08),(tip.x*.58,tip.y*.58,.36),tip],.014,bark)
  for j in range(8):
   t=(j+.2)/8;center=Vector((tip.x*t,tip.y*t,.12+tip.z*t*.78))
   for s in (-1,1):
    b=a+s*(.68+rng.random()*.30)
    end=center+Vector((cos(b),sin(b),rng.uniform(-.10,.08)))*rng.uniform(.22,.36)
    leaf_blade(vs,fs,slots,center,end,rng.uniform(.05,.085),rng.randrange(5),.03)
 make_mesh('Thicket layered foliage',vs,fs,leaves,slots)

def wildflowers():
 reset();rng=random.Random(58);vs=[];fs=[];slots=[]
 for i in range(19):
  a=rng.random()*2*pi;r=math.sqrt(rng.random())*.78;x=r*cos(a);y=r*sin(a);h=rng.uniform(.24,.52)
  path('Bent flower stalk',[(x,y,.015),(x+.025,y-.015,h*.62),(x+.055,y,h)],.007,fern_green)
  for s in (-1,1):
   base=Vector((x+.015,y,h*.44));tip=base+Vector((s*.13,.06,.09))
   leaf_blade(vs,fs,slots,base,tip,.036,0,.018)
  for k in range(6):
   b=k*2*pi/6;center=Vector((x+.055,y,h))
   end=center+Vector((.075*cos(b),.075*sin(b),.016))
   leaf_blade(vs,fs,slots,center,end,.025,1+i%2,.012)
  cylinder('Flower pollen disc',(x+.055,y,h+.02),.018,.018,.014,amber,8)
 make_mesh('Flower petals and lanceolate leaves',vs,fs,[fern_green,flower_lilac,flower_cream],slots)

def mushrooms():
 reset();rng=random.Random(36)
 for i in range(11):
  a=i*2*pi/11;r=rng.uniform(.15,.75);x=r*cos(a);y=r*sin(a);h=rng.uniform(.17,.43)
  cap=.075+rng.random()*.08
  cylinder('Tapered mushroom stem',(x,y,h*.52),.022,.033,h*.9,mush_gill,12)
  cylinder('Incurved cap underside',(x,y,h),cap*.84,cap*.65,.045,mush_gill,16)
  cylinder('Dark cap rim',(x,y,h+.028),cap,cap*.94,.028,mush_rim,20)
  cylinder('Domed russet cap',(x,y,h+.076),cap*.94,.018,.082,mush_cap,20)
  for j in range(5):
   b=j*2*pi/5;crystal('Mottled cap spot',(x+cap*.45*cos(b),y+cap*.45*sin(b),h+.10),(.009,.014,.009),flower)

def grass_tuft():
 reset();rng=random.Random(72);vs=[];fs=[];slots=[]
 for i in range(25):
  a=i*2*pi/25+rng.uniform(-.19,.19)
  base=Vector((rng.uniform(-.08,.08),rng.uniform(-.08,.08),0))
  tip=Vector((cos(a)*rng.uniform(.17,.35),sin(a)*rng.uniform(.17,.35),rng.uniform(.18,.38)))
  leaf_blade(vs,fs,slots,base,tip,rng.uniform(.016,.030),0,.035)
 make_mesh('Wind swept meadow grass',vs,fs,[grass_sage],slots)

def river_reeds():
 reset();rng=random.Random(82);vs=[];fs=[];slots=[]
 for i in range(9):
  a=i*2*pi/9;r=rng.uniform(.04,.30);x=r*cos(a);y=r*sin(a);h=rng.uniform(.55,1.15)
  path('Bending reed stalk',[(x,y,0),(x+.06,y,h*.55),(x+.10,y,h)],.009,reed_green)
  for s in (-1,1):
   base=Vector((x,y,h*.27));end=base+Vector((s*.24,.06,h*.15))
   leaf_blade(vs,fs,slots,base,end,.035,0,.03)
  if i%2==0:cylinder('Reed seed spike',(x+.10,y,h+.055),.027,.018,.11,reed_seed,8)
 make_mesh('Reed leaf blades',vs,fs,[reed_green],slots)

def ruin():
 reset();cylinder('Eroded base',(0,0,.10),.64,.58,.2,stone[2],12)
 cylinder('Old plinth',(0,0,.32),.48,.44,.24,stone[1],12)
 cylinder('Ancient shaft',(0,0,.93),.26,.28,1.0,stone[0],14)
 cylinder('Broken crown',(0,0,1.42),.32,.21,.16,stone[1],12)
 for i in range(10):
  a=i*2*pi/10
  path('Fluted column groove',[(.27*cos(a),.27*sin(a),.49),(.255*cos(a),.255*sin(a),1.13),(.26*cos(a),.26*sin(a),1.39)],.012,dark)
 for i in range(7):
  a=i*2*pi/7;rock('Ruin debris',(.7*cos(a),.7*sin(a),0),(.22,.19,.23),stone[i%3],i+77)
 for i in range(3):
  a=i*2*pi/3;path('Climbing root',[(.4*cos(a),.4*sin(a),.1),(.27*cos(a+.4),.27*sin(a+.4),.6),(.28*cos(a+.7),.28*sin(a+.7),1.1)],.027,bark)

def lantern():
 reset();cylinder('Lantern stepped footing',(0,0,.09),.32,.28,.18,stone[2],10)
 cylinder('Carved square post',(0,0,.68),.13,.12,1.1,stone[0],8)
 cylinder('Bronze collar',(0,0,1.32),.24,.20,.13,gold,10)
 box('Enclosed lamp crystal',(0,0,1.55),(.28,.28,.36),amber,.04)
 cylinder('Lamp dark iron roof',(0,0,1.81),.34,.13,.22,dark,10)
 for i in range(4):
  a=i*pi/2
  path('Lantern frame upright',[(.16*cos(a),.16*sin(a),1.37),(.17*cos(a),.17*sin(a),1.78)],.018,gold)

def moonwell():
 reset();cylinder('Moonwell concentric pedestal',(0,0,.09),1.08,1.04,.18,stone[2],20)
 cylinder('Moonwell carved basin',(0,0,.32),.91,.83,.29,stone[0],20)
 cylinder('Moonwell dark inner bowl',(0,0,.475),.66,.66,.06,dark,24)
 cylinder('Moonwell luminous water',(0,0,.52),.57,.57,.025,cyan,24)
 for i in range(12):
  a=i*2*pi/12
  rock('Petal rim carved stone',(.77*cos(a),.77*sin(a),.46),(.20,.15,.18),stone[i%3],i+100)
 for i in range(3):
  a=i*2*pi/3
  crystal('Moonwell arc crystal',(.94*cos(a),.94*sin(a),.45),(.12,.12,.58),cyan)
  path('Moonwell bronze arc',[(1.04*cos(a),1.04*sin(a),.35),(.87*cos(a),.87*sin(a),.7),(.60*cos(a),.60*sin(a),.82)],.018,gold)

def obelisk():
 reset();cylinder('Rune stone footing',(0,0,.11),.77,.70,.22,stone[2],12)
 cylinder('Octagonal dark plinth',(0,0,.42),.53,.43,.4,dark,8)
 vs=[];fs=[];n=6
 for z,r in [(.55,.40),(1.12,.34),(1.78,.25),(2.21,.07)]:
  for i in range(n):
   a=i*2*pi/n;vs.append((r*cos(a),r*sin(a),z))
 for j in range(3):
  for i in range(n):
   p=j*n+i;q=j*n+(i+1)%n;fs.append((p,q,q+n,p+n))
 fs.append(tuple(3*n+i for i in range(n)))
 bevel(make_mesh('Swept sculpted monolith',vs,fs,[stone[0]]),.028)
 for i in range(3):
  a=i*2*pi/3
  crystal('Obelisk inset gem',(.27*cos(a),.27*sin(a),1.15),(.10,.10,.37),cyan)
  path('Cut rune branching line',[(.35*cos(a),.35*sin(a),.72),(.33*cos(a),.33*sin(a),.95),(.30*cos(a+.12),.30*sin(a+.12),1.15)],.021,gold)
 for i in range(6):
  a=i*2*pi/6;rock('Obelisk root slab',(.61*cos(a),.61*sin(a),0),(.25,.20,.22),stone[i%3],i+19)

def relic():
 reset();cylinder('Reliquary star dais',(0,0,.09),.61,.56,.18,stone[2],10)
 box('Reliquary chamfered chest',(0,0,.40),(.83,.64,.45),dark,.09)
 box('Reliquary aged bronze band',(0,0,.66),(.92,.73,.10),gold,.045)
 box('Reliquary domed lid',(0,0,.73),(.85,.65,.10),stone[0],.07)
 for side in [-1,1]:
  path('Reliquary shaped clasp',[(side*.31,-.38,.34),(side*.31,-.37,.75),(side*.18,-.36,.80)],.022,gold)
 crystal('Reliquary star seal',(0,-.39,.41),(.16,.07,.29),cyan)

def banner(color):
 reset();fabric=cloth_blue if color=='blue' else cloth_red
 cylinder('Bronze standard socket',(0,0,.10),.29,.25,.2,stone[1],10)
 cylinder('Tall timber standard',(0,0,1.57),.065,.045,2.95,bark,12)
 crystal('Crest finial',(0,0,2.96),(.11,.11,.34),gold)
 vs=[];fs=[];rows=20;cols=12
 for i in range(rows+1):
  t=i/rows
  for j in range(cols+1):
   u=j/cols
   vs.append((.09+u*.79,.07*sin(t*4+u*5)*sin(t*pi),2.58-1.22*t+.10*sin(u*pi)*t))
 for i in range(rows):
  for j in range(cols):
   k=i*(cols+1)+j;fs.append((k,k+1,k+cols+2,k+cols+1))
 o=make_mesh('Wind folded faction cloth',vs,fs,[fabric],smooth=True)
 sol=o.modifiers.new('Woven cloth thickness','SOLIDIFY');sol.thickness=.012
 path('Banner embroidered edge',[vs[i*(cols+1)+cols] for i in range(rows+1)],.011,gold)
 path('Banner lower tassel',[vs[rows*(cols+1)+j] for j in range(cols+1)],.01,gold)

def tower(team):
 reset();enamel=team_blue if team=='blue' else team_red
 glass=glass_blue if team=='blue' else glass_red
 cylinder('Tower weathered octagonal plinth',(0,0,.16),1.21,1.13,.32,stone[2],12)
 cylinder('Tower bronze reveal',(0,0,.39),1.07,1.04,.09,gold,12)
 cylinder('Tower tapered core',(0,0,1.43),.68,.48,2.05,stone[0],8)
 for k in range(3):
  z=.72+k*.52
  cylinder('Tower band course',(0,0,z),.75-k*.045,.72-k*.045,.105,stone[1],8)
 for i in range(8):
  a=i*2*pi/8;rad=.77
  rock('Tower eroded basal block',(rad*cos(a),rad*sin(a),.05),(.33,.28,.35),stone[i%3],i+11)
  path('Tower rising buttress',[(rad*cos(a),rad*sin(a),.14),
       (.68*cos(a),.68*sin(a),.98),(.51*cos(a),.51*sin(a),2.08)],.10,stone[2])
  if i%2==0:
   crystal('Tower exposed rune',(.57*cos(a),.57*sin(a),1.23),(.11,.11,.34),glass)
   path('Tower rune border',[(.60*cos(a),.60*sin(a),1.18),(.56*cos(a),.56*sin(a),1.54)],.014,gold)
 cylinder('Tower sculpted crown',(0,0,2.42),.76,.60,.30,enamel,8)
 cylinder('Tower high gilded collar',(0,0,2.65),.61,.53,.12,gold,8)
 for i in range(4):
  a=i*pi/2
  path('Tower flying horn',[(.45*cos(a),.45*sin(a),2.43),(.71*cos(a),.71*sin(a),2.82),
       (.67*cos(a),.67*sin(a),3.14)],.065,stone[1])
 crystal('Tower aether lantern',(0,0,2.68),(.38,.38,.97),glass)

def nexus(team):
 reset();enamel=team_blue if team=='blue' else team_red
 glass=glass_blue if team=='blue' else glass_red
 cylinder('Nexus outer foundation',(0,0,.12),2.00,1.93,.24,stone[2],16)
 cylinder('Nexus inner stone platform',(0,0,.36),1.63,1.57,.24,stone[0],16)
 cylinder('Nexus enamel frieze',(0,0,.56),1.40,1.28,.15,enamel,16)
 cylinder('Nexus bronze socket',(0,0,.70),.78,.61,.25,gold,12)
 cylinder('Nexus dark aether support',(0,0,1.17),.42,.26,.74,dark,10)
 for i in range(8):
  a=i*2*pi/8
  rock('Nexus protective stone leaf',(1.55*cos(a),1.55*sin(a),.45),(.42,.31,.38),stone[i%3],i+83)
  path('Nexus inlaid ring arc',[(1.22*cos(a+t*pi/24),1.22*sin(a+t*pi/24),.61) for t in range(4)],.018,gold)
 for i in range(4):
  a=i*pi/2
  cylinder('Nexus corner pylon',(1.29*cos(a),1.29*sin(a),1.01),.17,.12,.75,stone[1],8)
  crystal('Nexus pylon gem',(1.29*cos(a),1.29*sin(a),1.43),(.15,.15,.30),glass)
  path('Nexus swept guardian rib',[(1.23*cos(a),1.23*sin(a),.78),
       (1.04*cos(a),1.04*sin(a),1.49),(.64*cos(a),.64*sin(a),1.95)],.075,gold)
 crystal('Suspended nexus heart',(0,0,1.38),(.65,.65,1.35),glass)
 crystal('Nexus crown point',(0,0,2.68),(.20,.20,.41),enamel)

def export(name,build):
 build()
 for obj in list(bpy.context.scene.objects):
  if obj.type in {'CURVE','MESH'}:
   bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
   bpy.ops.object.convert(target='MESH')
 groups={}
 for obj in list(bpy.context.scene.objects):
  if obj.type=='MESH':groups.setdefault(tuple(m.name for m in obj.data.materials),[]).append(obj)
 for material_names,items in groups.items():
  if len(items)<2:continue
  bpy.ops.object.select_all(action='DESELECT')
  for obj in items:obj.select_set(True)
  bpy.context.view_layer.objects.active=items[0];bpy.ops.object.join()
  items[0].name=name+' '+(material_names[0] if material_names else 'surface')
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,name+'.blend'))
 bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT,'assets','models',name+'.glb'),export_format='GLB',export_yup=True)
 print('PROP_READY',name,sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH'))

for name,func in [('oak_v2',oak),('cedar_v2',cedar),('rock_v2',stone_cluster),('fern_v2',fern),
                  ('thicket',thicket),('wildflowers',wildflowers),('mushrooms',mushrooms),
                  ('grass_tuft',grass_tuft),('river_reeds',river_reeds),
                  ('ruin_pillar',ruin),('aether_lantern',lantern),('moonwell',moonwell),
                  ('rune_obelisk',obelisk),('star_reliquary',relic),
                  ('standard_blue',lambda: banner('blue')),('standard_red',lambda: banner('red')),
                  ('tower_blue_v2',lambda: tower('blue')),('tower_red_v2',lambda: tower('red')),
                  ('core_blue_v2',lambda: nexus('blue')),('core_red_v2',lambda: nexus('red'))]:
 export(name,func)
