shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 world_position;

float wave(vec2 p, float time) {
    float long_flow = sin(p.y * 2.7 - time * 1.45 + sin(p.x * 1.8) * .35);
    float cross_flow = sin(p.x * 4.1 + p.y * .65 + time * .72);
    float small = sin(p.x * 8.5 - p.y * 3.2 - time * 2.15);
    return long_flow * .54 + cross_flow * .31 + small * .15;
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 p = world_position.xz;
    float current = wave(p, TIME);
    float left_bank = smoothstep(2.35, 3.42, abs(p.x));
    float broad = sin(p.y * .28 + sin(p.x * .6) * .7) * .5 + .5;
    vec3 deep = vec3(.014, .049, .055);
    vec3 shallow = vec3(.047, .093, .084);
    vec3 water = mix(deep, shallow, left_bank * .49 + broad * .12 + current * .06);
    float streak = pow(max(0.0, sin(p.y * 6.0 - TIME * 2.4 + p.x * 2.3)), 13.0);
    float foam = left_bank * streak * (.18 + .22 * abs(current));
    ALBEDO = water + vec3(.055, .091, .085) * foam;
    EMISSION = vec3(.02, .055, .061) * (foam * .37 + max(0.0, current) * .025);
    ROUGHNESS = .44 + left_bank * .18;
    SPECULAR = .31;
    NORMAL_MAP = vec3(.5 + current * .055, .5 + wave(p + vec2(.27, .14), TIME) * .055, 1.0);
    NORMAL_MAP_DEPTH = .8;
}
