shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

uniform sampler2D politics : filter_linear, repeat_disable;
uniform sampler2D inland_water : filter_linear, repeat_disable;
varying vec2 ground_uv;
varying vec3 leaves;
varying float local_height;

void vertex() {
	ground_uv = MODEL_MATRIX[3].xz / vec2(1000.0, 450.0);
	local_height = VERTEX.y;
	leaves = COLOR.rgb;
}

void fragment() {
	if (texture(politics, ground_uv).a < 0.55 || texture(inland_water, ground_uv).r > 0.5) { discard; }
	ALBEDO = mix(vec3(0.21, 0.15, 0.09), leaves, smoothstep(0.36, 0.57, local_height));
	ROUGHNESS = 1.0;
}
