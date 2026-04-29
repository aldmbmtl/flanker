shader_type sky;

uniform sampler2D face_front : filter_linear, hint_default_black;
uniform sampler2D face_back  : filter_linear, hint_default_black;
uniform sampler2D face_left  : filter_linear, hint_default_black;
uniform sampler2D face_right : filter_linear, hint_default_black;
uniform sampler2D face_up    : filter_linear, hint_default_black;
uniform sampler2D face_down  : filter_linear, hint_default_black;
uniform float brightness : hint_range(0.0, 1.0) = 1.0;

// Map a normalised direction to one of the 6 cube faces and a UV.
// Convention matches the jettelly pack: +Z = FRONT, -Z = BACK, -X = LEFT, +X = RIGHT, +Y = UP, -Y = DOWN
vec4 sample_sky(vec3 d) {
	vec3 a = abs(d);
	vec2 uv;
	int face;
	if (a.x >= a.y && a.x >= a.z) {
		if (d.x > 0.0) { face = 3; uv = vec2(-d.z, -d.y) / a.x; } // RIGHT
		else           { face = 2; uv = vec2( d.z, -d.y) / a.x; } // LEFT
	} else if (a.y >= a.x && a.y >= a.z) {
		if (d.y > 0.0) { face = 4; uv = vec2( d.x, d.z) / a.y; } // UP
		else           { face = 5; uv = vec2( d.x,-d.z) / a.y; } // DOWN
	} else {
		if (d.z > 0.0) { face = 0; uv = vec2( d.x, -d.y) / a.z; } // FRONT
		else           { face = 1; uv = vec2(-d.x, -d.y) / a.z; } // BACK
	}
	uv = uv * 0.5 + 0.5;
	if      (face == 0) return texture(face_front, uv);
	else if (face == 1) return texture(face_back,  uv);
	else if (face == 2) return texture(face_left,  uv);
	else if (face == 3) return texture(face_right, uv);
	else if (face == 4) return texture(face_up,    uv);
	else                return texture(face_down,  uv);
}

void sky() {
	COLOR = sample_sky(EYEDIR).rgb * brightness;
}
