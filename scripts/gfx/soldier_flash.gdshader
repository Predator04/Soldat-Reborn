shader_type canvas_item;
// Graphics Phase B (#271): the classic look's soldier material — nothing but
// the white damage flash (soldier_feel.gd drives the instance uniform for ~2
// frames when a soldier's health drops). The cinematic look gets the same
// uniform inside rim_light.gdshader.
instance uniform float flash = 0.0;

void fragment() {
	vec4 c = COLOR;
	c.rgb = mix(c.rgb, vec3(1.0), flash * 0.85);
	COLOR = c;
}
