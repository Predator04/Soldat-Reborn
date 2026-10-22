shader_type canvas_item;
// Graphics Phase B (#271): the classic look's soldier material — the white
// damage flash (soldier_feel.gd drives the instance uniform for ~2 frames when
// a soldier's health drops) and, #306, the team outline: in team modes every
// soldier gets this material at ANY quality (Low's cheap readability fallback),
// and soldier_art.gd sets `team_rim` (rgb = team colour, a = strength; 0 = off).
// The silhouette edge comes from the screen-space alpha gradient, like the
// cinematic rim_light.gdshader; flat draws (HP bars, labels) are untouched.
instance uniform float flash = 0.0;
instance uniform vec4 team_rim = vec4(0.0);

void fragment() {
	vec4 c = COLOR;
	if (team_rim.a > 0.0 && c.a > 0.02) {
		float a = texture(TEXTURE, UV).a;
		float e = length(vec2(dFdx(a), dFdy(a)));
		float edge = clamp(e * 2.0, 0.0, 1.0) * team_rim.a;
		c.rgb = mix(c.rgb, team_rim.rgb, edge);
	}
	c.rgb = mix(c.rgb, vec3(1.0), flash * 0.85);
	COLOR = c;
}
