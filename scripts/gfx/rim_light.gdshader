shader_type canvas_item;
// Rim light on soldiers / vehicles (cinematic look). The sprite's silhouette
// edge is found from the screen-space alpha gradient, so it works on the
// rotated skeletal parts without knowing their transforms. Edges facing the
// key light (the moon / sky) get a cool rim; the far side a faint warm bounce.
// Untextured draws (name labels, HP bars) have a flat alpha and are untouched.
uniform vec2 light_from = vec2(0.55, -0.83);   // screen space, y down: upper right
uniform vec3 rim_col = vec3(0.70, 0.84, 1.0);
uniform vec3 bounce_col = vec3(1.0, 0.62, 0.38);
uniform float rim_strength = 0.6;
uniform float bounce_strength = 0.18;
// Phase B (#271): per-soldier damage flash (soldier_feel.gd sets it for ~2
// frames through set_instance_shader_parameter, so the material stays shared).
instance uniform float flash = 0.0;
// #306: team outline (rgb = team colour, a = strength; 0 = none), set per
// soldier by soldier_art.gd in team modes — painted on every silhouette edge
// whatever the light direction, so friend / foe reads on dark / busy maps.
instance uniform vec4 team_rim = vec4(0.0);

void fragment() {
	// COLOR already carries the texture sample (Godot 4); multiplying it in
	// again squared every sprite colour and made cinematic soldiers too dark.
	vec4 c = COLOR;
	float a = texture(TEXTURE, UV).a;
	vec2 g = vec2(dFdx(a), dFdy(a));
	float e = length(g);
	if (e > 0.001 && c.a > 0.02) {
		vec2 n = -g / e;                  // outward silhouette normal
		float edge = clamp(e * 2.5, 0.0, 1.0);
		float key = clamp(dot(n, normalize(light_from)), 0.0, 1.0);
		float back = clamp(-dot(n, normalize(light_from)), 0.0, 1.0);
		c.rgb += rim_col * edge * key * rim_strength * c.a;
		c.rgb += bounce_col * edge * back * bounce_strength * c.a;
		c.rgb = mix(c.rgb, team_rim.rgb, clamp(e * 2.0, 0.0, 1.0) * team_rim.a);
	}
	c.rgb = mix(c.rgb, vec3(1.0), flash * 0.85);
	COLOR = c;
}
