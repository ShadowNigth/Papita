shader_type spatial;
// Material de la geometria de los .bsp: textura original (paleta de 1999) por el
// lightmap de radiosidad horneado en el propio mapa. Sin luces dinamicas: el
// juego original tampoco las tenia, toda la iluminacion esta en el .bsp.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D lightmap_tex : source_color, filter_linear, repeat_disable;
uniform float intensidad_luz = 2.2;
uniform float brillo = 1.0;

void fragment() {
	vec4 albedo = texture(albedo_tex, UV);
	// Las texturas de GoldSrc llevan el color "quemado" (sin gamma); se pasa a
	// espacio lineal para que el tonemap de Godot no las lave.
	vec3 base = pow(albedo.rgb, vec3(2.2));
	vec3 luz = texture(lightmap_tex, UV2).rgb * intensidad_luz;
	ALBEDO = base * luz * brillo;
}

void light() {
	// unshaded: no participa en el calculo de luces
}
