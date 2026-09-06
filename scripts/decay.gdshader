shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensity : hint_range(0.0,1.0) = 0.0;
void fragment() {
	float band = floor(SCREEN_UV.y * 65.0 + TIME * 9.0);
	float jitter = sin(band*71.19) * step(0.82,fract(sin(band*12.97)*437.53));
	vec2 uv = SCREEN_UV + vec2(jitter*0.018*intensity,0.0);
	vec3 col = texture(screen_texture,uv).rgb;
	col.r = texture(screen_texture,uv+vec2(0.005*intensity,0.0)).r;
	col *= 1.0 - intensity*0.35;
	col += vec3(0.02,0.14,0.13)*intensity*step(0.9,fract(SCREEN_UV.y*90.0));
	COLOR = vec4(col,intensity);
}
