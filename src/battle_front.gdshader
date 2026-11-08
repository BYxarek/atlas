shader_type canvas_item;
render_mode unshaded;

uniform vec4 tint : source_color = vec4(1.0);
uniform float front = 0.0;
uniform bool captured = false;
uniform bool striped = false;

void fragment() {
	float distance = UV.x - front;
	float sweep = 1.0 - smoothstep(-0.025, 0.0, distance);
	float edge = 1.0 - smoothstep(0.0, 0.035, abs(distance));
	float fill = striped ? mix(0.36, 0.62, smoothstep(0.25, 0.48, fract(UV.y))) : 0.58;
	float opacity = captured ? 1.0 - sweep : max(sweep * fill, edge * 0.88);
	float fade = captured ? 1.0 : smoothstep(0.0, 0.08, front);
	COLOR = vec4(mix(tint.rgb, vec3(1.0), captured ? 0.0 : edge * 0.5), opacity * fade);
}
