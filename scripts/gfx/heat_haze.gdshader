shader_type canvas_item;
// unshaded: the re-sampled screen is already lit / ambient-graded — lighting it
// again (explosion lights!) would show the haze as a bright ring.
render_mode unshaded;
// Graphics Phase B (#271): heat haze, drawn by fx_world.gd's Heat layer (High).
// Each quad carries its distortion in the vertex colour:
//   rg = outward direction (0.5, 0.5 = none) — explosion rings push outward,
//   b  = wobble amount (jet shimmer),  a = strength.
// UV.x runs across the band / plume, UV.y along it, so edges fade to zero and
// the haze has no visible border. Cosmetic only: it just re-samples the screen.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

void fragment() {
	vec2 dir = COLOR.rg * 2.0 - 1.0;
	float prof = sin(UV.x * 3.14159) * sin(clamp(UV.y, 0.0, 1.0) * 3.14159);
	float n = sin(SCREEN_UV.y * 340.0 + TIME * 38.0) * 0.6 + sin(SCREEN_UV.x * 230.0 - TIME * 29.0) * 0.4;
	vec2 off = dir * prof * COLOR.a * 0.012 + vec2(n, -n * 0.6) * COLOR.b * prof * 0.0022;
	COLOR = vec4(texture(screen_tex, SCREEN_UV + off).rgb, 1.0);
}
