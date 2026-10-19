shader_type canvas_item;
// HD terrain fill (#283). One mesh per map holds every drawn polygon in file
// order. COLOR = the polygon's classic colour (classic texture mean x vertex
// colour, graded for readability) with its alpha. Up to three materials per
// map; each VERTEX carries blend weights (UV.x = w1, UV.y = w2, w0 = rest),
// so material changes follow the classic colour gradients and the boundary
// is broken up by the materials' own relief (height blend) instead of
// running along triangle edges. UV.x also carries the background level in
// its integer part (+2 = semi, +4 = background — constant per triangle).
// Materials are mapped in world space so neighbouring triangles line up. The
// normal map gives a fixed upper-left sun (works without lights) and is also
// handed to the 2D lights (NORMAL_MAP).

// Slot 0 comes from the canvas item's CanvasTexture (TEXTURE / NORMAL_TEXTURE).
uniform sampler2D alb1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D nrm1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D alb2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D nrm2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 mean0 = vec3(0.5);
uniform vec3 mean1 = vec3(0.5);
uniform vec3 mean2 = vec3(0.5);
uniform vec3 keep = vec3(0.2);        // material hue kept, per slot
uniform vec3 inv_tile = vec3(0.001);  // 1 / world size of a tile, per slot
uniform float detail = 0.9;           // albedo detail contrast
uniform float chroma = 0.3;           // how much of the albedo's own colour variation survives
uniform float sun_amount = 0.55;
uniform vec3 sun = vec3(-0.45, -0.70, 0.55);   // screen space, y down

varying vec2 wpos;
varying vec4 vcol;   // the vertex colour (fragment COLOR is pre-multiplied by TEXTURE at UV)
varying vec3 wts;
varying float bgl;

void vertex() {
	vcol = COLOR;
	wpos = VERTEX;
	float lvl = floor(UV.x * 0.5 + 0.01);
	bgl = lvl * 0.5;
	float w1 = UV.x - lvl * 2.0;
	float w2 = UV.y;
	wts = vec3(max(0.0, 1.0 - w1 - w2), w1, w2);
}

const vec3 LUM = vec3(0.299, 0.587, 0.114);

void fragment() {
	vec3 w = wts;
	vec4 a0 = vec4(0.0), a1 = vec4(0.0), a2 = vec4(0.0);
	vec3 n0 = vec3(0.5, 0.5, 1.0), n1 = n0, n2 = n0;
	float h0 = 0.0, h1 = 0.0, h2 = 0.0;
	if (w.x > 0.004) {
		vec2 uv = wpos * inv_tile.x;
		a0 = texture(TEXTURE, uv);            // CanvasTexture diffuse = slot 0
		n0 = texture(NORMAL_TEXTURE, uv).rgb; // CanvasTexture normal = slot 0
		h0 = dot(a0.rgb, LUM) / max(dot(mean0, LUM), 0.02);
	}
	if (w.y > 0.004) {
		vec2 uv = wpos * inv_tile.y;
		a1 = texture(alb1, uv);
		n1 = texture(nrm1, uv).rgb;
		h1 = dot(a1.rgb, LUM) / max(dot(mean1, LUM), 0.02);
	}
	if (w.z > 0.004) {
		vec2 uv = wpos * inv_tile.z;
		a2 = texture(alb2, uv);
		n2 = texture(nrm2, uv).rgb;
		h2 = dot(a2.rgb, LUM) / max(dot(mean2, LUM), 0.02);
	}
	// Height blend: the brighter (raised) parts of a material win near the
	// boundary, so transitions look like moss over rock, not a crossfade.
	vec3 s = w + 0.45 * (vec3(h0, h1, h2) - 1.0) * step(vec3(0.004), w);
	float smax = max(s.x, max(s.y, s.z));
	vec3 b = max(s - (smax - 0.22), vec3(0.0)) * step(vec3(0.004), w);
	b /= max(b.x + b.y + b.z, 0.0001);
	float lc = dot(vcol.rgb, LUM);
	vec3 col = vec3(0.0);
	vec3 nn = vec3(0.0);
	float bgk = 1.0 - 0.75 * bgl;   // backdrops: little material detail
	// Per slot: detail = luminance ratio (plus a little of the albedo's own
	// colour variation), base = map colour shifted toward the material hue.
	if (b.x > 0.0) {
		vec3 d = mix(vec3(h0), a0.rgb / max(mean0, vec3(0.02)), chroma);
		d = mix(vec3(1.0), d, detail * bgk);
		vec3 own = mean0 * (lc / max(dot(mean0, LUM), 0.02));
		col += b.x * mix(vcol.rgb, own, keep.x) * d;
		nn += b.x * n0;
	}
	if (b.y > 0.0) {
		vec3 d = mix(vec3(h1), a1.rgb / max(mean1, vec3(0.02)), chroma);
		d = mix(vec3(1.0), d, detail * bgk);
		vec3 own = mean1 * (lc / max(dot(mean1, LUM), 0.02));
		col += b.y * mix(vcol.rgb, own, keep.y) * d;
		nn += b.y * n1;
	}
	if (b.z > 0.0) {
		vec3 d = mix(vec3(h2), a2.rgb / max(mean2, vec3(0.02)), chroma);
		d = mix(vec3(1.0), d, detail * bgk);
		vec3 own = mean2 * (lc / max(dot(mean2, LUM), 0.02));
		col += b.z * mix(vcol.rgb, own, keep.z) * d;
		nn += b.z * n2;
	}
	// Normal maps import as RG (Basis / BC5): rebuild z.
	vec3 N = vec3(nn.xy * 2.0 - 1.0, 0.0);
	N.z = sqrt(max(0.0, 1.0 - dot(N.xy, N.xy)));
	N.xy *= 1.0 - 0.75 * bgl;
	vec3 ns = normalize(vec3(N.x, -N.y, max(N.z, 0.05)));
	vec3 sd = normalize(sun);
	float lit = max(dot(ns, sd), 0.0) / sd.z;
	col *= mix(1.0, clamp(lit, 0.35, 1.6), sun_amount * (1.0 - 0.5 * bgl));
	COLOR = vec4(col, vcol.a);
	NORMAL_MAP = normalize(N) * 0.5 + 0.5;
}
