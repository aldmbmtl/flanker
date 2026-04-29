shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, depth_test_disabled;

// Up to 32 vision sources packed as vec4(x, z, radius, unused)
uniform vec4 sources[64];
uniform int source_count = 0;
uniform float edge_softness = 4.0;
uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 0.88);

void fragment() {
	// Reconstruct world XZ from vertex position passed via UV2
	vec2 world_xz = UV2;

	float min_dist_over_radius = 1.0;
	for (int i = 0; i < source_count; i++) {
		vec2 src_xz = sources[i].xy;
		float radius = sources[i].z;
		if (radius <= 0.0) continue;
		float d = distance(world_xz, src_xz);
		float t = d / radius;
		if (t < min_dist_over_radius) {
			min_dist_over_radius = t;
		}
	}

	// Smooth edge: fully clear inside radius, fade over edge_softness units
	float alpha = smoothstep(1.0 - (edge_softness / 35.0), 1.0, min_dist_over_radius);
	ALBEDO = fog_color.rgb;
	ALPHA = alpha * fog_color.a;
}
