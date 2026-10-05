shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Original, texture-free ash-worn concrete. All detail receives the scene lights.
// World projection keeps the joined paving and retaining-wall meshes continuous.
uniform vec4 base_color : source_color = vec4(0.13, 0.14, 0.13, 1.0);
uniform float soot_strength : hint_range(0.0, 0.5) = 0.22;
uniform float crack_strength : hint_range(0.0, 0.8) = 0.42;
uniform float rain_strength : hint_range(0.0, 0.5) = 0.20;
uniform float detail_scale : hint_range(0.25, 4.0) = 1.0;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.85;

varying vec3 world_position;
varying vec3 world_normal;

float hash21(vec2 p) {
	// Integer cell scrambling avoids a transcendental sin for every grain/site.
	uvec2 cell = uvec2(ivec2(p));
	uint value = cell.x * 1597334677u ^ cell.y * 3812015801u;
	value ^= value >> 16u;
	value *= 2246822519u;
	value ^= value >> 13u;
	value *= 3266489917u;
	value ^= value >> 16u;
	return float(value) * (1.0 / 4294967295.0);
}

float stone_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

float fracture_border(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float first = 8.0;
	float second = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 seed = cell + offset;
			vec2 site = 0.18 + 0.64 * vec2(hash21(seed + 41.0), hash21(seed + 93.0));
			vec2 difference = offset + site - local;
			float distance_squared = dot(difference, difference);
			if (distance_squared < first) {
				second = first;
				first = distance_squared;
			} else {
				second = min(second, distance_squared);
			}
		}
	}
	// Equal squared distances form angular branches instead of noise-contour loops.
	return second - first;
}

// x: quiet colour variation, y: physical relief, z: sparse hairline fractures.
vec3 stone_surface(vec2 p, float projected_footprint) {
	float micro_visibility = 1.0 - smoothstep(0.018, 0.070, projected_footprint);
	float coarse = stone_noise(p * 0.47 + vec2(18.0, 7.0));
	float soot = smoothstep(0.48, 0.78, stone_noise(p * 0.76 + vec2(4.0, 31.0)));
	float grain = stone_noise(p * 21.0);
	float pits = smoothstep(0.68, 0.88, stone_noise(p * 8.3 + vec2(49.0, 11.0)));
	float fracture_field = fracture_border(p * 0.94 + vec2(7.0, 29.0));
	// Use the projection footprint computed before the projection branches.
	// Derivatives evaluated inside a divergent branch are not defined reliably.
	float fracture_width = max(projected_footprint * 1.10, 0.0015);
	float hairline = 1.0 - smoothstep(0.002, 0.005 + fracture_width, fracture_field);
	float fracture_patch = smoothstep(0.63, 0.78, stone_noise(p * 0.71 + vec2(62.0, 5.0)));
	float crack = hairline * fracture_patch;
	// Suppress subpixel lines rather than widening every fracture at distant views.
	crack *= 1.0 - smoothstep(0.026, 0.095, projected_footprint);
	float tone = 1.0 + (coarse - 0.5) * 0.16 - soot * soot_strength * 0.78;
	tone += (grain - 0.5) * 0.085 * micro_visibility - pits * 0.04 * micro_visibility;
	float relief = coarse * 0.002 + (grain - 0.5) * 0.0035 * micro_visibility;
	relief -= crack * 0.0018 + pits * 0.002 * micro_visibility;
	return vec3(tone, relief, crack);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 p = world_position * detail_scale;
	vec3 geometric_normal = normalize(world_normal);
	vec3 weights = pow(abs(geometric_normal), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.001);
	vec3 projection_footprint = vec3(
		max(length(dFdx(p.zy)), length(dFdy(p.zy))),
		max(length(dFdx(p.xz)), length(dFdy(p.xz))),
		max(length(dFdx(p.xy)), length(dFdy(p.xy))));
	// Orthographic close-ups must retain grain even when the camera is far
	// away. Planar paving/walls need one projection, not three fracture fields.
	vec3 surface = vec3(0.0);
	if (weights.x > 0.001) {
		surface += stone_surface(p.zy, projection_footprint.x) * weights.x;
	}
	if (weights.y > 0.001) {
		surface += stone_surface(p.xz, projection_footprint.y) * weights.y;
	}
	if (weights.z > 0.001) {
		surface += stone_surface(p.xy, projection_footprint.z) * weights.z;
	}
	float wall = 1.0 - smoothstep(0.30, 0.78, abs(geometric_normal.y));
	// Both vertical projections put world height on the second axis, so the
	// rain tracks travel down walls instead of stretching the ground texture.
	float rain_x = stone_noise(vec2(p.z * 4.0, p.y * 0.20) + vec2(15.0, 8.0));
	float rain_z = stone_noise(vec2(p.x * 4.0, p.y * 0.20) + vec2(31.0, 17.0));
	float rain = (rain_x * weights.x + rain_z * weights.z) * wall;
	rain = smoothstep(0.52, 0.76, rain) * rain_strength;
	float footing = (1.0 - smoothstep(0.06, 0.95, world_position.y)) * wall;
	footing *= 0.70 + 0.30 * stone_noise(p.xz * 2.0);
	vec3 color = base_color.rgb * surface.x;
	color = mix(color, color * vec3(0.82, 0.87, 0.86), rain);
	color = mix(color, base_color.rgb * vec3(1.10, 1.08, 1.02), footing * 0.20);
	// Sparse warm dust ties the yard together without painting over the two
	// imported concrete colours or adding another small-scale checker pattern.
	float yard_dust = smoothstep(0.42, 0.76, stone_noise(p.xz * 0.22 + vec2(27.0, 61.0))) * weights.y;
	color = mix(color, color * vec3(1.08, 1.035, 0.93), yard_dust * 0.28);
	color *= 1.0 - surface.z * crack_strength;
	ALBEDO = color;
	METALLIC = 0.0;
	SPECULAR = 0.17;
	ROUGHNESS = clamp(0.94 + (surface.x - 0.9) * 0.12 - rain * 0.13, 0.86, 0.99);
	AO = clamp(0.98 - surface.z * 0.11 - footing * 0.025, 0.83, 1.0);
	// Derivative bump in view space works on all three projections and on the
	// bevel faces without a UV map or an imported tangent basis.
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 tangent_x = cross(dpdy, NORMAL);
	vec3 tangent_y = cross(NORMAL, dpdx);
	float determinant = dot(dpdx, tangent_x);
	float denominator = (determinant < 0.0 ? -1.0 : 1.0) * max(abs(determinant), 0.000001);
	vec3 relief_gradient = (tangent_x * dFdx(surface.y) + tangent_y * dFdy(surface.y)) / denominator;
	relief_gradient /= max(1.0, length(relief_gradient) / 0.30);
	NORMAL = normalize(NORMAL - relief_gradient * bump_strength);
}
