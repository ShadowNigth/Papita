shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Shader PBR optimizado de alto rendimiento: proyeccion planar por eje dominante
// en world-space con mipmaps completos (3 lecturas de textura en vez de 5),
// normal map real en paredes y suelos, desgaste, humedad y rim light sutil.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_roughness_g, filter_linear_mipmap, repeat_enable;

uniform vec3 tint : source_color = vec3(1.0);
uniform float uv_scale = 1.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.85;
uniform float roughness_scale : hint_range(0.0, 2.0) = 1.0;
uniform float metallic_scale : hint_range(0.0, 1.0) = 1.0;
uniform float wear : hint_range(0.0, 1.0) = 0.35;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float moss : hint_range(0.0, 1.0) = 0.0;
uniform float detail_scale : hint_range(0.5, 16.0) = 4.0;
uniform float rim_power : hint_range(0.0, 1.0) = 0.12;
uniform vec3 moss_color : source_color = vec3(0.27, 0.33, 0.18);

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 v_color;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_color = COLOR.rgb;
}

void fragment() {
	vec3 an = abs(world_normal);
	vec2 uv = (an.y >= an.x && an.y >= an.z)
		? world_pos.xz
		: ((an.x >= an.z) ? world_pos.zy : world_pos.xy);
	uv *= detail_scale * uv_scale;

	vec3 base_sample = texture(albedo_tex, uv).rgb;
	vec3 micro_sample = texture(albedo_tex, uv * 3.7 + vec2(0.17, 0.31)).rgb;
	float micro = clamp(dot(micro_sample, vec3(0.333)) * 0.36 + 0.82, 0.72, 1.18);
	vec3 albedo = base_sample * micro * tint * v_color;
	vec3 nrm_tex = texture(normal_tex, uv).rgb;
	vec3 nrm_micro = texture(normal_tex, uv * 3.3).rgb;
	nrm_tex = normalize(mix(nrm_tex * 2.0 - 1.0, nrm_micro * 2.0 - 1.0, 0.24)) * 0.5 + 0.5;
	vec3 orm = texture(orm_tex, uv).rgb;

	// Desgaste por altura (polvo) y humedad cerca del suelo.
	float height_factor = clamp(world_pos.y * 0.14, 0.0, 1.0);
	albedo = mix(albedo, albedo * vec3(1.06, 1.02, 0.94), wear * 0.18 * (0.4 + height_factor * 0.6) * (1.0 - orm.b));

	float damp = wetness * (1.0 - smoothstep(0.0, 1.6, world_pos.y));
	albedo *= mix(1.0, 0.64, damp);

	// Musgo en caras superiores.
	float up = smoothstep(0.62, 0.95, world_normal.y);
	albedo = mix(albedo, moss_color, moss * up * 0.48);

	ALBEDO = albedo;
	ROUGHNESS = clamp(mix(orm.g * roughness_scale, 0.16, damp), 0.05, 1.0);
	METALLIC = clamp(orm.b * metallic_scale, 0.0, 1.0);
	AO = mix(1.0, orm.r, 0.72);
	AO_LIGHT_AFFECT = 0.32;
	NORMAL_MAP = nrm_tex;
	NORMAL_MAP_DEPTH = normal_strength;
	RIM = rim_power;
	RIM_TINT = 0.5;
}
