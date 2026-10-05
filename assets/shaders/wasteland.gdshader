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
    vec3 geometric_normal=normalize(world_normal);
    vec3 weights=pow(abs(geometric_normal),vec3(4.0));
    weights/=max(dot(weights,vec3(1.0)),.001);
    float footprint=max(length(dFdx(world_pos)),length(dFdy(world_pos)));
    float grit_visibility=1.0-smoothstep(.055,.18,footprint);
    // Keep the steep embankment at the same physical grain scale as the
    // ground. XZ-only projection stretched the grit down vertical walls.
    float grit_x=noise(world_pos.zy*4.6);
    float grit_y=noise(world_pos.xz*4.6);
    float grit_z=noise(world_pos.xy*4.6);
    float grit=mix(.5,dot(vec3(grit_x,grit_y,grit_z),weights),grit_visibility);
    float rock_coarse=dot(vec3(noise(world_pos.zy*.55),
        noise(world_pos.xz*.55),noise(world_pos.xy*.55)),weights);
    float broad=noise(p*.18);
    float compacted=smoothstep(.73,.86,noise(p*1.6+vec2(17.0,8.0)));
    float ash=smoothstep(.58,.83,noise(p*.57+vec2(2.0,39.0)));
    vec3 earth=mix(vec3(.051,.055,.047),vec3(.116,.108,.089),broad*.78+grit*.22);
    earth=mix(earth,vec3(.044,.052,.052),ash*.36+compacted*.20);
    float cliff=smoothstep(.27,.68,1.0-abs(geometric_normal.y));
    // Broad, irregular deposits describe the five-metre rise without the
    // tight, evenly spaced contour stripes of the previous material.
    float layer_phase=world_pos.y*4.2+rock_coarse*1.8;
    float layer_footprint=max(abs(dFdx(layer_phase)),abs(dFdy(layer_phase)));
    float layer_visibility=exp(-.5*layer_footprint*layer_footprint);
    float strata=.5+.5*sin(layer_phase)*layer_visibility;
    vec3 rock=mix(vec3(.050,.056,.058),vec3(.128,.118,.099),
        strata*.34+rock_coarse*.31+grit*.12);
    float rim_dust=smoothstep(4.25,5.10,world_pos.y);
    rock=mix(rock,vec3(.130,.118,.095),rim_dust*.11);
    ALBEDO=mix(earth,rock,cliff);
    METALLIC=0.0;
    SPECULAR=.10;
    ROUGHNESS=.98-cliff*.03;
    AO=.93+grit*.045;
    // A shallow derivative bump is valid on every projection, including
    // meshes without a usable tangent basis. It never changes the terrain.
    float relief=(grit-.5)*.0017+rock_coarse*.0008+cliff*strata*.0012;
    vec3 dpdx=dFdx(VERTEX),dpdy=dFdy(VERTEX);
    vec3 tangent_x=cross(dpdy,NORMAL),tangent_y=cross(NORMAL,dpdx);
    float determinant=dot(dpdx,tangent_x);
    float denominator=(determinant<0.0?-1.0:1.0)*max(abs(determinant),.000001);
    vec3 gradient=(tangent_x*dFdx(relief)+tangent_y*dFdy(relief))/denominator;
    gradient/=max(1.0,length(gradient)/.12);
    NORMAL=normalize(NORMAL-gradient);
}
