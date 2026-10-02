shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 world_pos;
varying vec3 world_normal;
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),
               mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
    world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
    vec2 p=world_pos.xz;
    float broad=noise(p*.18);
    float grit=noise(p*4.6);
    float cracks=smoothstep(.73,.82,noise(p*1.6+vec2(17.0,8.0)));
    float ash=smoothstep(.58,.83,noise(p*.57+vec2(2.0,39.0)));
    vec3 earth=mix(vec3(.045,.049,.045),vec3(.109,.104,.085),broad*.72+grit*.28);
    earth=mix(earth,vec3(.031,.037,.039),ash*.45+cracks*.27);
    float cliff=smoothstep(.27,.68,1.0-abs(world_normal.y));
    float strata=sin(world_pos.y*8.2+noise(p*.83)*2.1)*.5+.5;
    vec3 rock=mix(vec3(.035,.043,.046),vec3(.105,.101,.084),strata*.47+grit*.20);
    rock=mix(rock,vec3(.13,.108,.080),smoothstep(4.4,5.1,world_pos.y)*.16);
    ALBEDO=mix(earth,rock,cliff);
    ROUGHNESS=.98;
    AO=.87+grit*.10;
    NORMAL_MAP=vec3(.5+(grit-.5)*.055,.5+(noise(p*4.6+7.0)-.5)*.055,1.0);
    NORMAL_MAP_DEPTH=.30;
}
