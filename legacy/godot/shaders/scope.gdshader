shader_type canvas_item;

// Mira telescopica: negro fuera del circulo, reticulo fino y viñeta interior.
uniform float radius = 0.44;
uniform float aspect = 1.78;
uniform float reticle_alpha = 0.9;
uniform vec3 tint : source_color = vec3(0.85, 0.9, 0.85);

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= aspect;
	float d = length(uv);
	float outside = smoothstep(radius - 0.003, radius + 0.002, d);
	float inner = smoothstep(radius * 0.55, radius, d) * 0.35;
	vec3 col = vec3(0.0);
	float alpha = outside;
	// Reticulo central.
	float line_w = 0.0012;
	float cross_h = step(abs(uv.y), line_w) * step(abs(uv.x), radius * 0.82);
	float cross_v = step(abs(uv.x), line_w) * step(abs(uv.y), radius * 0.82);
	float thick = step(d, 0.012);
	float reticle = clamp(cross_h + cross_v + thick, 0.0, 1.0);
	// Marcas de distancia.
	float marks = 0.0;
	for (int i = 1; i <= 4; i++) {
		float y = float(i) * 0.07;
		marks += step(abs(uv.y - y), line_w) * step(abs(uv.x), 0.02);
		marks += step(abs(uv.y + y), line_w) * step(abs(uv.x), 0.02);
	}
	reticle = clamp(reticle + marks, 0.0, 1.0);
	col = mix(col, tint, reticle);
	alpha = max(alpha, reticle * reticle_alpha);
	alpha = max(alpha, inner);
	// Borde interior del tubo.
	float ring = smoothstep(radius - 0.012, radius, d) * (1.0 - outside);
	alpha = max(alpha, ring * 0.55);
	COLOR = vec4(col * (1.0 - outside), alpha);
}
