shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 foliage_color : source_color = vec4(0.06, 0.18, 0.06, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float sway : hint_range(0.0, 0.5) = 0.12;
uniform float root_height = 0.0;
uniform float tip_height = 3.5;
uniform float wind_speed = 1.0;

void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float height_weight = smoothstep(root_height, tip_height, VERTEX.y);
    float broad_gust = sin(TIME * wind_speed + world.x * 0.19 + world.z * 0.11);
    float secondary = sin(TIME * (wind_speed * 1.73) - world.x * 0.31 + world.z * 0.27);
    float flutter = sin(TIME * (wind_speed * 3.1) + world.x * 1.8 + world.z * 1.4);
    VERTEX.x += sway * height_weight * (broad_gust * 0.72 + secondary * 0.24 + flutter * 0.04);
    VERTEX.z += sway * height_weight * (secondary * 0.48 + broad_gust * 0.20);
}

void fragment() {
    ALBEDO = foliage_color.rgb;
    ROUGHNESS = roughness_value;
}
