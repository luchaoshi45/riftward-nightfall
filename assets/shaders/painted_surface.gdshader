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
 float broad=noise(local_pos*3.5),grain=noise(local_pos*32.0);
 vec3 c=base_color.rgb;
 c*=.78+.32*broad+.12*grain;
 if(surface_kind>1.5){
  // Broad leaf planes use painted veins rather than smooth spherical highlights.
  float vein=pow(abs(sin((UV.x-UV.y*.23)*24.0)),12.0);
  c*=.84+.28*UV.y;
  c=mix(c,c*vec3(1.12,1.08,.83),vein*.18);
 }else if(surface_kind>.5){
  float weave=sin(local_pos.x*95.0)*sin(local_pos.y*95.0);
  c*=.98+weave*.025;
 }else{
  float weather=smoothstep(.58,.83,noise(local_pos*7.0));
  c=mix(c,c*vec3(.72,.78,.67),weather*.3);
 }
 ALBEDO=c;
 ROUGHNESS=surface_kind>0.5?.98:.86;
 METALLIC=metal;
 SPECULAR=surface_kind>0.5?.08:.2;
}
