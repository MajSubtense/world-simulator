shader_type canvas_item;
render_mode unshaded;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	COLOR = vcol;
}