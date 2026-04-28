shader_type spatial;
render_mode depth_draw_opaque, depth_prepass_alpha, cull_back, diffuse_lambert, specular_schlick_ggx;

// ── Albedo ────────────────────────────────────────────────────────────────────
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(1.0);

// ── Wind wave ─────────────────────────────────────────────────────────────────
// wind_strength   — peak lateral displacement (metres, canopy tip)
// wind_speed      — how fast the wave front travels (higher = snappier sway)
// wind_direction  — XZ direction the wave travels; normalised in vertex stage
// wave_scale      — spatial frequency: 1/wave_scale = metres per full 2π cycle
//                   small value → long gentle wavelength (more natural)
uniform float wind_strength  : hint_range(0.0, 0.5) = 0.045;
uniform float wind_speed     : hint_range(0.0, 5.0) = 0.9;
uniform vec2  wind_direction                         = vec2(1.0, 0.3);
uniform float wave_scale     : hint_range(0.001, 1.0) = 0.05;

// Micro-variation: tiny high-freq wobble so trees aren't perfectly mechanical.
// Kept very small so it doesn't dominate and break the wave appearance.
uniform float micro_strength : hint_range(0.0, 0.1) = 0.008;
uniform float micro_speed    : hint_range(0.0, 10.0) = 2.2;

// ── Surface ───────────────────────────────────────────────────────────────────
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
// Alpha cutout threshold — pixels below this are discarded (no blending).
// Preserves correct depth writes so foliage doesn't cause sorting artefacts.
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;

void vertex() {
	// World-space tree origin for phase calculation.
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	vec2 wdir = normalize(wind_direction);

	// Phase = distance travelled along the wind direction, scaled by wave_scale.
	// Trees further downwind are at a later phase → the sway visibly propagates
	// across the forest like a real gust front.
	float wave_phase = dot(world_origin.xz, wdir) * wave_scale;

	// Height factor: roots anchored, canopy moves freely.
	float height_factor = smoothstep(0.0, 1.2, VERTEX.y);

	// Primary travelling wave — directional, same wdir for all trees.
	float sway = sin(TIME * wind_speed - wave_phase) * wind_strength * height_factor;

	// Micro-variation — use a small irrational offset per tree so identical
	// variants don't perfectly sync, but keep amplitude tiny.
	float micro_phase = dot(world_origin.xz, vec2(0.137, 0.271)) * 6.28318;
	float micro = sin(TIME * micro_speed + micro_phase) * micro_strength * height_factor;

	vec2 perp = vec2(-wdir.y, wdir.x);
	vec2 disp = wdir * (sway + micro);

	VERTEX.x += disp.x;
	VERTEX.z += disp.y;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO      = tex.rgb * albedo_tint.rgb;
	ALPHA       = tex.a * albedo_tint.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ROUGHNESS   = roughness;
	METALLIC    = 0.0;
}
