shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(.2,.3,.2,1.0);
uniform float surface_kind = 0.0;
uniform float metal = 0.0;
varying vec3 local_pos;
float hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float noise(vec3 p){vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);}
void vertex(){local_pos=VERTEX;}
void fragment(){
 // Filter in the model's own coordinates, including its on-screen scale.
 // Subpixel fibres should retain their average tone instead of crawling as
 // the fixed-angle camera follows a moving unit.
 float footprint=max(length(dFdx(local_pos)),length(dFdy(local_pos)));
 float grain_visibility=1.0-smoothstep(.008,.026,footprint);
 float broad=noise(local_pos*3.5);
 float grain=mix(.5,noise(local_pos*32.0),grain_visibility);
 vec3 c=base_color.rgb;
 c*=.78+.32*broad+.12*grain;
 if(surface_kind>1.5){
  // Broad leaf planes use painted veins rather than smooth spherical highlights.
  float vein_phase=(UV.x-UV.y*.23)*24.0;
  float vein_footprint=max(abs(dFdx(vein_phase)),abs(dFdy(vein_phase)));
  float vein_visibility=1.0-smoothstep(.35,1.25,vein_footprint);
  float vein=mix(.226,pow(abs(sin(vein_phase)),12.0),vein_visibility);
  c*=.84+.28*UV.y;
  c=mix(c,c*vec3(1.12,1.08,.83),vein*.18);
 }else if(surface_kind>.5){
  vec2 weave_phase=local_pos.xy*95.0;
  vec2 weave_dx=dFdx(weave_phase),weave_dy=dFdy(weave_phase);
  float weave_visibility=exp(-.5*(dot(weave_dx,weave_dx)+dot(weave_dy,weave_dy)));
  float weave=sin(weave_phase.x)*sin(weave_phase.y)*weave_visibility;
  c*=.98+weave*.025;
 }else{
  float weather=smoothstep(.58,.83,noise(local_pos*7.0));
  c=mix(c,c*vec3(.72,.78,.67),weather*.3);
 }
 ALBEDO=c;
 ROUGHNESS=surface_kind>0.5?.98:.89;
 METALLIC=clamp(metal,0.0,.25);
 SPECULAR=surface_kind>0.5?.08:.17;
}
