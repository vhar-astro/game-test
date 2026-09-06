shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	if (radius > 1.0) discard;
	float angle = atan(p.y,p.x);
	float spiral = sin(angle*5.0-radius*24.0+TIME*1.4)*0.5+0.5;
	float rim = pow(radius,6.0);
	ALBEDO = mix(vec3(0.015,0.06,0.11),vec3(0.12,0.8,0.64),rim+spiral*0.15);
	EMISSION = vec3(0.12,0.8,0.64)*(rim*1.8+spiral*0.12);
	ALPHA = 0.90;
}
