shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(.35,.42,.35,1.0);
varying vec3 world_pos;

float hash21(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float value_noise(vec2 p) {
 vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),
            mix(hash21(i+vec2(0,1)),hash21(i+vec2(1)),f.x),f.y);
}
void vertex() {world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment() {
 vec2 p=world_pos.xz;
 float broad=value_noise(p*.95);
 float grain=value_noise(p*10.0);
 float fleck=value_noise(p*34.0);
 float mottling=.72+broad*.30+grain*.13+fleck*.045;
 float moss=smoothstep(.64,.82,value_noise(p*1.8+vec2(43.0,8.0)))*.23;
 vec3 col=mix(base_color.rgb*mottling,base_color.rgb*vec3(.54,.69,.47),moss);
 ALBEDO=col;
 ROUGHNESS=.98;
 SPECULAR=.12;
 AO=.90+grain*.08;
 NORMAL_MAP=vec3(.5+(grain-.5)*.045,.5+(fleck-.5)*.045,1.0);
 NORMAL_MAP_DEPTH=.32;
}
