shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

void fragment() {
	ALBEDO = vec3(0.025, 0.06, 0.085);
	ALPHA = (1.0 - smoothstep(0.20, 0.5, length(UV - 0.5))) * 0.42;
}
