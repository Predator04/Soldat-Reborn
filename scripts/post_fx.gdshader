shader_type canvas_item;
// Full-screen post pass over the game world (under the HUD) — gfx.gd quality
// Medium: colour grade + vignette + hit flash; High adds bloom.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float saturation = 1.1;
uniform float contrast = 1.05;
uniform float vignette = 0.32;
uniform vec3 tint = vec3(1.0, 1.0, 1.0);
uniform float bloom = 0.0;          // 0 = off
uniform float bloom_threshold = 0.68;
uniform float bloom_radius = 9.0;   // px
uniform float hit = 0.0;            // 0..1: chromatic split + red edges when you're hit

vec3 bright(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	float l = max(c.r, max(c.g, c.b));
	return c * smoothstep(bloom_threshold, 1.0, l);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c;
	if (hit > 0.002) {
		vec2 off = (uv - 0.5) * 0.014 * hit;
		c = vec3(texture(screen_tex, uv + off).r, texture(screen_tex, uv).g, texture(screen_tex, uv - off).b);
	} else {
		c = texture(screen_tex, uv).rgb;
	}
	if (bloom > 0.0) {
		vec2 px = SCREEN_PIXEL_SIZE * bloom_radius;
		vec3 b = vec3(0.0);
		for (int i = 0; i < 12; i++) {
			float a = float(i) * 0.5235988;
			vec2 d = vec2(cos(a), sin(a));
			b += bright(uv + d * px);
			b += bright(uv + d * px * 2.2) * 0.6;
		}
		c += b / 19.2 * bloom;
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c *= tint;
	float d = distance(uv, vec2(0.5));
	c *= 1.0 - vignette * smoothstep(0.38, 0.9, d);
	c = mix(c, vec3(0.55, 0.02, 0.02), hit * 0.45 * smoothstep(0.32, 0.78, d));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
