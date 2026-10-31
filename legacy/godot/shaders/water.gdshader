shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.18, 0.33, 0.32);
uniform vec3 deep_color : source_color = vec3(0.05, 0.12, 0.14);
uniform float wave_scale = 3.0;
uniform float wave_speed = 0.35;
uniform float wave_height = 0.06;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin((world_pos.x + TIME * wave_speed) * wave_scale) * 0.5
		+ cos((world_pos.z - TIME * wave_speed * 1.3) * wave_scale * 1.4) * 0.5;
	VERTEX.y += w * wave_height;
}

void fragment() {
	float n = noise(world_pos.xz * 2.4 + vec2(TIME * 0.12, TIME * 0.08));
	float n2 = noise(world_pos.xz * 6.1 - vec2(TIME * 0.2, TIME * 0.15));
	vec2 ripple = vec2(noise(world_pos.xz * 9.0 + TIME * 0.3), noise(world_pos.xz * 9.0 - TIME * 0.26));
	ALBEDO = mix(deep_color, shallow_color, smoothstep(0.25, 0.8, n * 0.65 + n2 * 0.35));
	ROUGHNESS = 0.04 + n2 * 0.05;
	METALLIC = 0.15;
	SPECULAR = 0.65;
	NORMAL_MAP = vec3((ripple - 0.5) * 0.55, 1.0);
	NORMAL_MAP_DEPTH = 0.6;
	ALPHA = 0.86;
	AO = 0.9;
}
