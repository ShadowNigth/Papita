shader_type sky;

// Cielo procedural: degradado atmosferico, sol/luna, estrellas y nubes.
uniform vec3 top_color : source_color = vec3(0.16, 0.32, 0.58);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.72, 0.65);
uniform vec3 ground_color : source_color = vec3(0.18, 0.16, 0.13);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.78);
uniform vec3 sun_dir = vec3(-0.4, 0.55, -0.7);
uniform float sun_size : hint_range(0.001, 0.25) = 0.035;
uniform float sun_energy : hint_range(0.0, 20.0) = 6.0;
uniform float star_strength : hint_range(0.0, 2.0) = 0.0;
uniform float cloud_strength : hint_range(0.0, 1.0) = 0.55;
uniform vec3 cloud_color : source_color = vec3(0.95, 0.94, 0.9);
uniform float cloud_scale : hint_range(0.2, 8.0) = 1.6;
uniform float haze : hint_range(0.0, 1.0) = 0.35;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = clamp(d.y, -1.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.62));
	col = mix(col, ground_color, smoothstep(0.0, -0.25, h));

	// Halo del sol.
	vec3 sd = normalize(sun_dir);
	float sun_dot = max(dot(d, sd), 0.0);
	col += sun_color * pow(sun_dot, 8.0) * haze * 0.55;
	col += sun_color * pow(sun_dot, 220.0) * sun_energy * 0.35;

	// Disco solar / lunar.
	float disk = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.35, sun_dot);
	col = mix(col, sun_color * sun_energy, disk);

	// Nubes en el plano superior.
	if (h > 0.02) {
		vec2 uv = d.xz / (h + 0.08) * cloud_scale;
		float n = vnoise(uv * 1.2) * 0.6 + vnoise(uv * 2.7) * 0.3 + vnoise(uv * 6.1) * 0.1;
		float cl = smoothstep(0.48, 0.85, n) * cloud_strength * smoothstep(0.0, 0.25, h);
		vec3 lit = cloud_color * (0.55 + 0.45 * sun_dot);
		col = mix(col, lit, cl * 0.85);
	}

	// Estrellas.
	if (star_strength > 0.001 && h > 0.02) {
		vec2 sp = d.xz / (h + 0.35) * 240.0;
		vec2 cell = floor(sp);
		float s = step(0.9965, hash21(cell * 1.7));
		float twinkle = 0.55 + 0.45 * sin(hash21(cell) * 40.0 + d.x * 12.0);
		col += vec3(0.9, 0.95, 1.0) * s * star_strength * twinkle * smoothstep(0.05, 0.4, h);
	}

	COLOR = col;
}
