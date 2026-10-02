shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float ripple = 0.035 * sin(a * 17.0 + TIME * 11.0)
		+ 0.025 * sin(a * 29.0 - TIME * 15.0)
		+ 0.022 * sin(p.x * 25.0 + p.y * 13.0 + TIME * 17.0);
	float mask = 1.0 - smoothstep(0.81 + ripple, 1.01 + ripple, r);
	float tendril = pow(max(0.0, sin(a * 12.0 + TIME * 8.0 + sin(r * 12.0 - TIME * 11.0))), 3.0);
	float outer = smoothstep(0.62, 0.84, r) * (1.0 - smoothstep(0.91, 1.02, r));
	float inner = 1.0 - smoothstep(0.03, 0.40, r);
	float fire = mask * (0.09 + tendril * 0.42) + outer * 0.31 + inner * 0.22;
	ALBEDO = mix(vec3(0.94, 0.18, 0.035), vec3(1.0, 0.78, 0.36), clamp(inner + outer * 0.65 + tendril * 0.30, 0.0, 1.0));
	ALPHA = clamp(fire * opacity, 0.0, 0.83);
}
