shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D politics : source_color, filter_linear, repeat_disable;
uniform sampler2D land_cover : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D inland_water : filter_linear_mipmap, repeat_disable;
uniform sampler2D forest_cover : filter_linear, repeat_disable;
uniform bool natural = false;
uniform float river_detail = 0.0;

void fragment() {
	vec4 overlay = texture(politics, UV);
	if (overlay.a < 0.45) { discard; }
	vec3 map_color = overlay.rgb / overlay.a;
	float height = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	vec3 soil = mix(vec3(0.28, 0.39, 0.31), vec3(0.52, 0.47, 0.40), smoothstep(1.0, 9.0, height));
	soil = mix(soil, vec3(0.80, 0.83, 0.83), smoothstep(9.0, 16.0, height));
	if (natural) {
		vec3 satellite = texture(land_cover, UV).rgb;
		vec2 cover = texture(forest_cover, UV).rg;
		vec3 ground = pow(max(satellite, vec3(0.0)), vec3(0.84));
		ground = mix(soil, ground, smoothstep(0.025, 0.15, max(satellite.r, max(satellite.g, satellite.b))));
		ground = mix(ground, vec3(0.21, 0.37, 0.16), min(cover.r + cover.g, 1.0) * 0.29);
		vec3 channels = texture(inland_water, UV).rgb;
		float lake = smoothstep(0.08, 0.80, channels.r);
		float river = min(1.0, max(channels.g * 1.4, channels.b * river_detail));
		float fresh_water = max(lake, river);
		ground = mix(ground, mix(vec3(0.16, 0.32, 0.36), vec3(0.09, 0.23, 0.30), lake), fresh_water * 0.96);
		// Neutral territory supplies only a land mask. Color and ink remain readable over imagery.
		float brightest = max(map_color.r, max(map_color.g, map_color.b));
		float chroma = brightest - min(map_color.r, min(map_color.g, map_color.b));
		float ink = 1.0 - smoothstep(0.27, 0.39, brightest);
		float glow = smoothstep(0.73, 0.95, brightest);
		float tint = max(smoothstep(0.035, 0.24, chroma) * 0.61 * (1.0 - fresh_water * 0.48), max(ink * 0.88, glow * 0.78));
		ground *= 1.0 + (brightest - 0.5) * (1.0 - smoothstep(0.025, 0.12, chroma)) * 0.8;
		float ground_light = dot(ground, vec3(0.22, 0.71, 0.07));
		vec3 ink_color = mix(vec3(0.44, 0.48, 0.35), map_color, smoothstep(0.14, 0.36, ground_light));
		ALBEDO = mix(ground, mix(map_color, ink_color, ink), tint);
	} else {
		ALBEDO = mix(map_color, soil, 0.19);
	}
	ROUGHNESS = 1.0;
}
