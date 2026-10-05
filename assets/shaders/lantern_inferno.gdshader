shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float effect_age = 0.0;
uniform float layer_kind = 0.0;

void fragment() {
	if (layer_kind > 0.5) {
		// Broad, tapered licks rise above the floor without painting an opaque
		// flower over the hero. Pixel derivatives soften their moving edges.
		float edge = max(fwidth(UV.x) * 1.5, 0.035);
		float side = smoothstep(0.0, edge, UV.x) * (1.0 - smoothstep(1.0 - edge, 1.0, UV.x));
		float length_mask = smoothstep(0.02, 0.22, UV.y) * (1.0 - smoothstep(0.62, 1.0, UV.y));
		float flow = 0.62 + 0.38 * sin(UV.y * 6.0 - effect_age * 3.2 + UV.x * 2.0);
		ALBEDO = mix(vec3(0.92, 0.16, 0.025), vec3(1.0, 0.58, 0.19), UV.y);
		ALPHA = side * length_mask * flow * opacity * 0.42;
	} else {
		vec2 p = UV * 2.0 - 1.0;
		float r = length(p);
		float a = atan(p.y, p.x);
		float edge = max(fwidth(r) * 1.5, 0.014);
		float ripple = 0.026 * sin(a * 6.0 + effect_age * 2.1)
			+ 0.014 * sin(a * 9.0 - effect_age * 1.7);
		float mask = 1.0 - smoothstep(0.90 + ripple - edge, 1.0 + ripple + edge, r);
		float tendril = pow(max(0.0, sin(a * 6.0 + effect_age * 2.1 + sin(r * 5.0 - effect_age))), 2.0);
		float outer = smoothstep(0.66, 0.82, r) * (1.0 - smoothstep(0.91 - edge, 1.02 + edge, r));
		float center_clearance = smoothstep(0.09, 0.30, r);
		float fire = mask * center_clearance * (0.08 + tendril * 0.25) + outer * 0.24;
		ALBEDO = mix(vec3(0.83, 0.12, 0.025), vec3(1.0, 0.53, 0.17), outer * 0.60 + tendril * 0.28);
		ALPHA = clamp(fire * opacity, 0.0, 0.50);
	}
}
