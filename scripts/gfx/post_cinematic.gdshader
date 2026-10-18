shader_type canvas_item;
// Full-screen post pass over the game world (under the HUD). Cosmetic only.
//
// Two looks share one pass (Settings.visual_style):
//   classic   — the original grade: light saturation / contrast, vignette.
//   cinematic — dark, gritty, high contrast: filmic toe/shoulder, teal shadows /
//               warm highlights split-tone, neon-friendly bloom, heavier vignette,
//               fine grain. Bright things (muzzle flashes, tracers, explosions,
//               team colours) keep their punch, so action stays readable.
// Both: hit flash (red edges + optional chromatic split), impact aberration.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

uniform float cinematic = 1.0;        // 0 classic … 1 cinematic (blendable)
uniform float saturation = 1.1;
uniform float contrast = 1.05;
uniform float vignette = 0.32;
uniform vec3 tint = vec3(1.0);
// Bloom: two rings of taps on a mip level (cheap wide glow). 0 = off.
uniform float bloom = 0.0;
uniform float bloom_threshold = 0.66;
uniform float bloom_radius = 10.0;     // px
// 0..1 when you're hit: red edge vignette + colour split.
uniform float hit = 0.0;
// 0..1 on nearby explosions / kills: brief radial aberration from screen centre.
uniform float impact = 0.0;
uniform bool aberration_enabled = true;
uniform float grain = 0.035;
// Phase B (#271) slow-mo LOOK on a multi-kill (screen_feel.gd), 0 = off:
// a small zoom punch, a radial time-smear and desaturation. Presentation only.
uniform float punch = 0.0;
uniform float smear = 0.0;
uniform float desat = 0.0;
uniform float time = 0.0;

// Cinematic grade knobs.
uniform vec3 shadow_tint = vec3(0.86, 0.97, 1.04);   // teal-ish shadows
uniform vec3 highlight_tint = vec3(1.05, 1.0, 0.92); // warm highlights
uniform float exposure = 1.04;

vec3 bright(vec2 uv, float lod) {
	vec3 c = textureLod(screen_tex, uv, lod).rgb;
	float l = max(c.r, max(c.g, c.b));
	return c * smoothstep(bloom_threshold, 1.0, l);
}

// ACES-ish filmic curve (Narkowicz fit), keeps blacks deep and whites soft.
vec3 filmic(vec3 x) {
	const float a = 2.51;
	const float b = 0.03;
	const float c = 2.43;
	const float d = 0.59;
	const float e = 0.14;
	return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	if (punch > 0.0) {
		uv = 0.5 + (uv - 0.5) * (1.0 - 0.045 * punch);
	}
	vec2 fromc = uv - 0.5;
	float split = 0.0;
	if (aberration_enabled) {
		split = 0.014 * hit + 0.006 * impact;
	}
	vec3 c;
	if (split > 0.0005) {
		vec2 off = fromc * split;
		c = vec3(texture(screen_tex, uv + off).r, texture(screen_tex, uv).g, texture(screen_tex, uv - off).b);
	} else {
		c = texture(screen_tex, uv).rgb;
	}
	if (smear > 0.0) {
		// Radial streaks toward the centre: the world reads as smeared in time.
		vec3 acc = c;
		for (int i = 1; i <= 6; i++) {
			acc += texture(screen_tex, uv - fromc * smear * 0.028 * float(i)).rgb;
		}
		c = mix(c, acc / 7.0, clamp(smear * 1.4, 0.0, 1.0) * smoothstep(0.05, 0.45, length(fromc)));
	}
	if (bloom > 0.0) {
		vec2 px = SCREEN_PIXEL_SIZE * bloom_radius;
		vec3 b = vec3(0.0);
		for (int i = 0; i < 10; i++) {
			float a = float(i) * 0.6283185 + 0.3;
			vec2 d = vec2(cos(a), sin(a));
			b += bright(uv + d * px, 1.0);
			b += bright(uv + d * px * 2.6, 2.0) * 0.7;
		}
		c += b / 17.0 * bloom;
	}
	// ── classic grade ──
	float l0 = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 classic = mix(vec3(l0), c, saturation);
	classic = (classic - 0.5) * contrast + 0.5;
	classic *= tint;
	// ── cinematic grade ──
	vec3 cine = filmic(c * exposure * 1.25);
	float l1 = dot(cine, vec3(0.2126, 0.7152, 0.0722));
	// Desaturate the mids a touch, keep strong colours (team colours, fire, neon).
	float chroma = max(cine.r, max(cine.g, cine.b)) - min(cine.r, min(cine.g, cine.b));
	cine = mix(vec3(l1), cine, mix(0.94, 1.12, smoothstep(0.12, 0.5, chroma)));
	// Split tone by luminance.
	cine *= mix(shadow_tint, highlight_tint, smoothstep(0.12, 0.75, l1));
	// Crush the deepest shadows slightly for contrast.
	cine = max(cine - 0.018, 0.0) * 1.02;
	c = mix(classic, cine, cinematic);
	// Vignette (heavier in cinematic).
	float d = length(fromc);
	float vig = vignette * mix(1.0, 1.35, cinematic);
	c *= 1.0 - vig * smoothstep(0.36, 0.92, d);
	// Hit flash: red edges.
	c = mix(c, vec3(0.55, 0.02, 0.02), hit * 0.45 * smoothstep(0.32, 0.78, d));
	if (desat > 0.0) {
		float lg = dot(c, vec3(0.2126, 0.7152, 0.0722));
		c = mix(c, vec3(lg) * vec3(0.92, 0.97, 1.06), desat);
	}
	// Film grain — fine, luminance-weighted, only in cinematic.
	if (grain > 0.0 && cinematic > 0.01) {
		float n = hash(uv * vec2(1280.0, 720.0) + fract(time * 7.13) * 91.7) - 0.5;
		c += n * grain * cinematic * (1.0 - l0 * 0.6);
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
