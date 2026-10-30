shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Material de superficie "reforzado": albedo con triplanar, normal map,
// rugosidad/metalicidad, desgaste por bordes, humedad a ras de suelo y
// un rim light sutil que realza la silueta de los objetos.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
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
uniform float rim_power : hint_range(0.0, 1.0) = 0.14;
uniform vec3 moss_color : source_color = vec3(0.27, 0.33, 0.18);

varying vec3 world_pos;
varying vec3 world_normal;

vec3 triplanar(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 blend = pow(abs(n), vec3(4.0));
	blend /= (blend.x + blend.y + blend.z + 1e-4);
	vec3 x = texture(tex, p.zy * scale).rgb;
	vec3 y = texture(tex, p.xz * scale).rgb;
	vec3 z = texture(tex, p.xy * scale).rgb;
	return x * blend.x + y * blend.y + z * blend.z;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float scale = detail_scale * uv_scale;
	vec3 albedo = triplanar(albedo_tex, world_pos, world_normal, scale) * tint;
	vec2 nrm_sample = texture(normal_tex, world_pos.xz * scale).rg * 2.0 - 1.0;
	vec3 orm = texture(orm_tex, world_pos.xz * scale).rgb;

	// Detalle de grano fino en world space para romper la repeticion.
	float grain = hash(floor(world_pos * 38.0));
	albedo *= 0.9 + grain * 0.2;

	// Desgaste en zonas altas (polvo) y bordes.
	float height_factor = clamp(world_pos.y * 0.18, 0.0, 1.0);
	vec3 dust = vec3(0.75, 0.7, 0.58);
	albedo = mix(albedo, dust, wear * 0.18 * (0.4 + height_factor * 0.6) * (1.0 - orm.b));

	// Humedad: oscurece y alisa cerca del suelo.
	float damp = wetness * (1.0 - smoothstep(0.0, 1.8, world_pos.y));
	albedo *= mix(1.0, 0.55, damp);
	vec3 rough = vec3(mix(orm.g * roughness_scale, 0.18, damp));

	// Musgo en superficies horizontales.
	float up = smoothstep(0.6, 0.95, world_normal.y);
	albedo = mix(albedo, moss_color, moss * up * 0.55);

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough.r, 0.04, 1.0);
	METALLIC = clamp(orm.b * metallic_scale, 0.0, 1.0);
	AO = mix(1.0, orm.r, 0.65);
	AO_LIGHT_AFFECT = 0.25;
	NORMAL_MAP = vec3(nrm_sample.x, nrm_sample.y, 1.0) * normal_strength;
	NORMAL_MAP_DEPTH = 1.1;
	RIM = rim_power;
	RIM_TINT = 0.55;
}
