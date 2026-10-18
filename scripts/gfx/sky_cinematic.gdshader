shader_type canvas_item;
// Animated sky behind everything (screen space, on its own CanvasLayer).
// Gradient from the map's own colours (graded darker in cinematic), stars that
// twinkle, a moon with a soft halo, two layers of fbm clouds that drift and
// parallax with the camera, and a faint horizon glow. Cosmetic only.
uniform vec3 top_col = vec3(0.03, 0.04, 0.11);
uniform vec3 mid_col = vec3(0.10, 0.14, 0.26);
uniform vec3 bot_col = vec3(0.34, 0.24, 0.28);
uniform float night = 1.0;            // 0 day … 1 night (stars + moon)
uniform vec2 cam = vec2(0.0);         // camera centre (world px) for parallax
uniform float time = 0.0;
uniform float cloud_amount = 0.55;
uniform vec3 cloud_col = vec3(0.62, 0.66, 0.78);
uniform vec2 moon_pos = vec2(0.78, 0.2); // screen UV
uniform vec3 moon_col = vec3(0.92, 0.95, 1.0);
uniform vec2 view = vec2(1280.0, 720.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 3.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float aspect = view.x / max(view.y, 1.0);
	// Gradient (two segments).
	vec3 col = uv.y < 0.5 ? mix(top_col, mid_col, uv.y * 2.0) : mix(mid_col, bot_col, (uv.y - 0.5) * 2.0);
	// Horizon glow.
	col += bot_col * 0.35 * smoothstep(0.55, 1.0, uv.y);
	// Stars: grid-hashed points, parallax 2 %, twinkle.
	if (night > 0.01) {
		vec2 sp = (uv * vec2(aspect, 1.0)) * 140.0 + cam * 0.002;
		vec2 cell = floor(sp);
		vec2 f = fract(sp) - 0.5;
		float h = hash(cell);
		if (h > 0.965) {
			vec2 o = vec2(hash(cell + 7.1), hash(cell + 3.3)) - 0.5;
			float d = length(f - o * 0.6);
			float tw = 0.65 + 0.35 * sin(time * (1.5 + h * 3.0) + h * 40.0);
			float s = smoothstep(0.09, 0.0, d) * tw * (h - 0.965) / 0.035;
			col += vec3(0.85, 0.9, 1.0) * s * night * (1.0 - smoothstep(0.35, 0.7, uv.y));
		}
		// Moon + halo.
		vec2 md = (uv - moon_pos) * vec2(aspect, 1.0);
		float mr = length(md);
		float disc = smoothstep(0.034, 0.03, mr);
		float crater = fbm(md * 60.0) * 0.25;
		col = mix(col, moon_col * (0.85 - crater), disc * night);
		col += moon_col * night * (0.22 * exp(-mr * 9.0) + 0.06 * exp(-mr * 2.5));
	}
	// Clouds: far layer (slow, 3 % parallax) and near layer (6 %).
	vec2 cuv = uv * vec2(aspect, 1.0);
	float far_c = fbm(cuv * vec2(2.2, 5.0) + vec2(time * 0.006 + cam.x * 0.00004, cam.y * 0.00002));
	float near_c = fbm(cuv * vec2(1.4, 3.2) + vec2(time * 0.012 + cam.x * 0.00008, 5.0 + cam.y * 0.00004));
	float band = smoothstep(0.05, 0.25, uv.y) * (1.0 - smoothstep(0.55, 0.85, uv.y));
	float cf = smoothstep(1.0 - cloud_amount, 1.05 - cloud_amount * 0.5, far_c) * band;
	float cn = smoothstep(1.0 - cloud_amount * 0.9, 1.1 - cloud_amount * 0.4, near_c) * band;
	// Moonlit rims: clouds near the moon catch light.
	float lit = night * exp(-length((uv - moon_pos) * vec2(aspect, 1.0)) * 3.0);
	vec3 cloud_far = mix(col, cloud_col * 0.55 + moon_col * lit * 0.3, cf * 0.55);
	col = mix(col, cloud_far, 1.0);
	col = mix(col, cloud_col * 0.75 + moon_col * lit * 0.45, cn * 0.5);
	COLOR = vec4(col, 1.0);
}
