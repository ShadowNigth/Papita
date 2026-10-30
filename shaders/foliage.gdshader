shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley;

// Vegetacion con viento, doble cara y translucidez aproximada.
uniform vec4 albedo_color : source_color = vec4(0.22, 0.32, 0.14, 1.0);
uniform float wind_strength = 0.08;
uniform float wind_speed = 1.2;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * wind_speed + wp.x * 0.7 + wp.z * 0.4) * wind_strength * UV.y;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.5;
}

void fragment() {
	ALBEDO = albedo_color.rgb;
	ROUGHNESS = 0.82;
	BACKLIGHT = albedo_color.rgb * 0.25;
}
