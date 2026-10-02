shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 tint_a : source_color = vec3(.16,.28,.17);
uniform vec3 tint_b : source_color = vec3(.34,.40,.22);
uniform float stone = 0.0;
uniform sampler2D ground_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=world.xz;
 float n=noise(p*.22)*.52+noise(p*.9)*.3+noise(p*3.7)*.18;
 vec3 color=mix(tint_a,tint_b,smoothstep(.18,.82,n));
 float fine=noise(p*19.0);
 color*=.87+fine*.22;
 if(stone<.5){
   vec3 detail=texture(ground_texture,p/12.0,1.5).rgb;
   float luma=dot(detail,vec3(.21,.72,.07));
   detail=mix(vec3(luma*.86,luma,luma*.82),detail,.48);
   color=detail*(.85+n*.32);
 }
 if(stone>.5){
   vec2 warped=p+vec2(noise(p*1.9),noise(p*1.7+8.0))*.13;
   vec2 tile=warped*vec2(.48,.67); tile.x+=floor(tile.y)*.47;
   vec2 f=fract(tile); float seam=min(min(f.x,1.0-f.x),min(f.y,1.0-f.y));
   float brick=noise(floor(tile)*9.1);
   color*=mix(.48,1.02,smoothstep(.009,.05,seam));
   color*=.72+brick*.43;
   float chips=noise(p*11.0);
   color*=1.0-smoothstep(.70,.87,chips)*.16;
   color=mix(color,vec3(.04,.065,.025),smoothstep(.69,.84,noise(p*.7))*.6);
 }
 ALBEDO=color;
 ROUGHNESS=.94;
 NORMAL_MAP=vec3(.5+(noise(p*4.0)-.5)*.035,.5+(noise(p*4.0+2.0)-.5)*.035,1.0);
 NORMAL_MAP_DEPTH=.35;
}
