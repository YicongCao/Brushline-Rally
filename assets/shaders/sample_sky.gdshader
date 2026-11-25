shader_type sky;
render_mode use_half_res_pass;

#include "res://assets/shaders/autumn_sky_palette.gdshaderinc"
#include "res://assets/shaders/anime_clouds.gdshaderinc"
#include "res://assets/shaders/reference_sky.gdshaderinc"
uniform bool painted_banks = false;
uniform vec3 sun_direction = vec3(-0.6, 0.4, -0.6);
uniform float film_disc = 0.0;
uniform bool film_moon = false;

void sky() {
	if (AT_HALF_RES_PASS) {
		vec4 cloud=vec4(0.0);
		if (film_sky>0) cloud=film_clouds(EYEDIR,sun_direction);
		else if (painted_banks) cloud=painted_clouds(EYEDIR,sun_direction);
		COLOR=cloud.rgb;
		ALPHA=cloud.a;
	} else {
		float alignment = max(dot(EYEDIR, normalize(sun_direction)), 0.0);
		COLOR = autumn_sky(EYEDIR, sun_direction);
		float radius = max(0.009,film_disc);
		float disc = smoothstep(cos(radius),cos(radius*0.73),alignment);
		if (film_moon) {
			COLOR -= vec3(0.14,0.085,0.025) * pow(alignment,48.0);
			COLOR += vec3(0.21,0.37,0.77)*pow(alignment,245.0) + vec3(1.8,2.3,3.7)*disc;
			vec2 stars = vec2(atan(EYEDIR.z,EYEDIR.x),EYEDIR.y)*vec2(119.0,164.0);
			float seed = fract(sin(dot(floor(stars),vec2(96.71,47.27)))*43758.54);
			float star = 1.0-smoothstep(0.025,0.16,length(fract(stars)-0.5));
			COLOR += vec3(0.41,0.50,0.74)*star*step(0.984,seed)*smoothstep(0.07,0.25,EYEDIR.y);
		} else {
			COLOR += vec3(2.5,1.8,0.8)*disc;
			if (film_disc>0.0) COLOR += vec3(0.65,0.33,0.10)*pow(alignment,320.0);
		}
		// Reflection radiance uses the stable broad sky illumination, not cloud edges.
		if (painted_banks && !AT_CUBEMAP_PASS) {
			float cover = film_sky>0 ? HALF_RES_COLOR.a*(1.0-0.94*pow(alignment,650.0)) : HALF_RES_COLOR.a;
			COLOR = mix(COLOR,HALF_RES_COLOR.rgb,cover);
		}
		vec3 ground = film_moon ? vec3(0.01,0.017,0.05) : (film_sky>0 ? horizon_away.rgb*0.53 : vec3(0.24,0.18,0.29));
		COLOR = mix(ground,COLOR,smoothstep(-0.12,0.01,EYEDIR.y));
	}
}
