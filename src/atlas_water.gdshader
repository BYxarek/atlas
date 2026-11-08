shader_type spatial;
render_mode cull_disabled, unshaded;

uniform sampler2D elevation : filter_linear, repeat_disable;
uniform vec4 ocean : source_color;
uniform bool earth = true;
uniform bool detailed = false;
uniform float wave_time = 0.0;

void fragment() {
	float depth = earth ? texture(elevation, UV).g : 0.65;
	float shoal = 1.0 - smoothstep(0.04, 0.54, depth);
	float ripple = sin(dot(UV, vec2(515.0, 803.0)) - wave_time * 2.0);
	ripple *= sin(dot(UV, vec2(-362.0, 681.0)) + wave_time * 1.2);
	if (detailed) {
		ripple = ripple * 0.7 + sin(dot(UV, vec2(1009.0, -1301.0)) - wave_time * 2.8) * 0.3;
	}
	vec3 water = ocean.rgb * (0.79 + ripple * 0.024);
	float foam = smoothstep(0.42, 0.94, ripple) * (1.0 - smoothstep(0.07, 0.27, depth));
	water = mix(water, ocean.rgb * vec3(1.35, 1.72, 1.58) + ripple * 0.014, shoal * 0.85);
	water += foam * vec3(0.025, 0.05, 0.05);
	vec2 edge = min(UV, 1.0 - UV);
	ALBEDO = mix(ocean.rgb, water, smoothstep(0.0, 0.025, min(edge.x, edge.y)));
}
