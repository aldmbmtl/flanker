shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.2;
uniform float radius : hint_range(0.1, 2.0) = 1.4;

void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float dist = length(uv) * radius;
	float vignette = smoothstep(0.4, 1.0, dist);
	COLOR = vec4(0.0, 0.0, 0.0, vignette * intensity);
}
