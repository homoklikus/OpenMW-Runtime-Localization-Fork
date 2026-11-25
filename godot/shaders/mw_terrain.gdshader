shader_type spatial;
// Teren Morrowinda: siatka 16×16 indeksów tekstur na komórkę (każda kafla = 512 jedn.),
// mieszanie dwuliniowe między sąsiednimi kaflami, kolory wierzchołków (VCLR) mnożą albedo.
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2DArray layers : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D index_map : filter_nearest, repeat_disable;  // R8: indeks w palecie (×255)
uniform float tiles = 16.0;       // kafli na komórkę
uniform float uv_repeat = 16.0;   // powtórzeń tekstury na komórkę (raz na kaflę, jak w grze)
uniform float layer_count = 1.0;
// Odbicie wody (OpenMW Reflection: ClipCullNode z płaszczyzną poziomu wody): w przebiegu odbicia (warstwa 20 kamery)
// teren poniżej wody odrzucony – inaczej dno zasłaniałoby odbicie.
global uniform float mw_water_clip_y;

varying vec2 cell_uv;
varying float world_y;

void vertex() {
	cell_uv = UV;  // 0..1 w obrębie komórki: u = +X, v = północ MW (−Z)
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

float layer_at(ivec2 t) {
	t = clamp(t, ivec2(0), ivec2(int(tiles) - 1));
	return floor(texelFetch(index_map, t, 0).r * 255.0 + 0.5);
}

void fragment() {
	if ((CAMERA_VISIBLE_LAYERS & 524288u) != 0u && world_y < mw_water_clip_y)
		discard;
	vec2 t = cell_uv * tiles - 0.5;
	ivec2 i0 = ivec2(floor(t));
	vec2 f = fract(t);
	vec2 tex_uv = cell_uv * uv_repeat;
	vec3 c00 = texture(layers, vec3(tex_uv, layer_at(i0))).rgb;
	vec3 c10 = texture(layers, vec3(tex_uv, layer_at(i0 + ivec2(1, 0)))).rgb;
	vec3 c01 = texture(layers, vec3(tex_uv, layer_at(i0 + ivec2(0, 1)))).rgb;
	vec3 c11 = texture(layers, vec3(tex_uv, layer_at(i0 + ivec2(1, 1)))).rgb;
	vec3 c = mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = 1.0;
}
