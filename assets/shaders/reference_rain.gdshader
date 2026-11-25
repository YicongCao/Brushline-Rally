shader_type canvas_item;
render_mode unshaded;

uniform float film_time;
uniform float headlights;

float random(vec2 cell) {
	return fract(sin(dot(cell,vec2(127.1,311.7)))*43758.5453);
}

float streaks(vec2 p, vec2 grid, float speed, float width, float span) {
	vec2 sample_at = p * grid - vec2(0.0, film_time * speed);
	vec2 id = floor(sample_at);
	vec2 at = fract(sample_at);
	float seed = random(id);
	float line = 1.0 - smoothstep(width * 0.3, width, abs(at.x - mix(0.16,0.84,seed)));
	float drop = smoothstep(0.0,0.07,at.y) * (1.0-smoothstep(span*0.55,span,at.y));
	return line * drop * smoothstep(0.35,0.8,seed);
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = vec2(UV.x * aspect - UV.y * 0.11, UV.y);
	float rain = 0.20*streaks(p,vec2(68.0,13.0),19.0,0.036,0.40);
	rain += 0.13*streaks(p,vec2(27.0,6.0),12.0,0.024,0.30);
	float light = 1.0-smoothstep(0.03,0.43,length((UV-vec2(0.52,0.69))*vec2(1.3,0.8)));
	COLOR = vec4(mix(vec3(0.51,0.63,0.84),vec3(0.90,0.93,1.0),light),rain*(0.58+headlights*light));
}
