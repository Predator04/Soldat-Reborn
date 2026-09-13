shader_type canvas_item;

// Full-screen death desaturation: greys out the world behind this overlay.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
	vec4 c = texture(screen_texture, SCREEN_UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 desat = mix(c.rgb, vec3(g), 0.85);
	// Faint cold/red death tint.
	desat = mix(desat, desat * vec3(1.15, 0.82, 0.82), 0.25);
	COLOR = vec4(desat, 1.0);
}
