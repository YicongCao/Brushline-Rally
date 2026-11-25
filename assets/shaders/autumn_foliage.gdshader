shader_type spatial;
uniform float cinematic_time = -1.0;
float scene_time() { return cinematic_time >= 0.0 ? cinematic_time : TIME; }
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform bool grass_blades = false;
uniform vec4 film_tint : source_color = vec4(0.0);
varying float canopy;
varying float film_leaves;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	canopy = smoothstep(2.0,5.5,VERTEX.y);
	film_leaves = smoothstep(1.1,2.8,VERTEX.y);
	float weight = grass_blades ? clamp(VERTEX.y / 0.65, 0.0, 1.0) : smoothstep(2.0, 8.0, VERTEX.y);
	float breeze = sin(world.x * 0.42 + world.z * 0.25 + scene_time() * 1.3);
	VERTEX.x += breeze * weight * (grass_blades ? 0.045 : 0.065);
	// Upward-biased blade normals keep a continuous golden carpet between tufts.
	if (!grass_blades) NORMAL = normalize(mix(NORMAL,normalize(vec3(VERTEX.x,1.7,VERTEX.z)),.32*canopy));
	if (grass_blades) NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.82));
}

void fragment() {
	vec3 foliage = COLOR.rgb;
	if (film_tint.a>0.0) {
		float shade = clamp(0.68+dot(COLOR.rgb,vec3(0.2126,0.7152,0.0722))*0.86,0.68,1.24);
		foliage = mix(foliage,film_tint.rgb*shade,film_tint.a*(grass_blades ? 1.0 : film_leaves));
	}
	ALBEDO = foliage;
	ROUGHNESS = 1.0;
	// A small leaf fill retains autumn color inside layered crowns.
	EMISSION = foliage * (grass_blades ? 0.04 : 0.08);
}

void light() {
 float n=dot(NORMAL,LIGHT);
 float tone=.18+.42*smoothstep(-.12,.06,n)+.40*smoothstep(.45,.63,n);
 vec3 shadow=vec3(.27,.43,.66);
 DIFFUSE_LIGHT+=ALBEDO*mix(shadow,vec3(1.0),tone)*LIGHT_COLOR*ATTENUATION/PI;
 if (!grass_blades) {
  // Broad waxy leaf sheen and warm transmitted light, not PBR wet/plastic shine.
  float sheen=smoothstep(.63,.84,dot(normalize(LIGHT+VIEW),NORMAL));
  float back=pow(max(dot(-LIGHT,VIEW),0.0),4.0)*(1.0-max(n,0.0));
  DIFFUSE_LIGHT+=(ALBEDO*vec3(1.2,.78,.30)*back*.38+mix(ALBEDO,vec3(1.0),.32)*sheen*.29)*LIGHT_COLOR*ATTENUATION*canopy/PI;
 }
}
