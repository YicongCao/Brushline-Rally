// Film cloud banks are soft billows in world directions, not camera overlays.
uniform int film_sky = 0;

float film_hash(vec2 p) {
	return fract(sin(dot(p,vec2(113.19,257.71)))*43758.54);
}

float film_noise(vec2 p) {
	vec2 id = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(film_hash(id),film_hash(id+vec2(1,0)),f.x),
		mix(film_hash(id+vec2(0,1)),film_hash(id+vec2(1,1)),f.x),f.y);
}

vec4 film_clouds(vec3 ray,vec3 sun) {
	vec2 direction = normalize(sun.xz);
	float yaw = atan(dot(ray.xz,vec2(-direction.y,direction.x)),dot(ray.xz,direction));
	float height = asin(clamp(ray.y,-1.0,1.0));
	float drift = cloud_drift * 2.2;
	vec2 p = vec2((yaw+drift)*2.1,height*9.0);
	float w = film_noise(p*0.63 + 5.0);
	float billow = film_noise(p+vec2(0,w)*0.92)*0.76 + film_noise(p*2.1+1.1)*0.24;
	float edge = smoothstep(0.008,0.053,height);
	if (film_sky==3) {
		float bank = 1.0-smoothstep(0.024,0.107,abs(height-0.095-(w-0.5)*0.12));
		float high = smoothstep(0.48,0.7,billow)*smoothstep(0.22,0.38,height)*0.52;
		float alpha = (smoothstep(0.33,0.60,billow)*bank+high)*edge;
		return vec4(mix(cloud_shadow.rgb,cloud_light.rgb,smoothstep(0.45,0.74,billow)),alpha);
	}
	if (film_sky==2) {
		float mask = billow*0.68 + w*0.32;
		float alpha = smoothstep(0.29,0.69,mask)*edge*0.92;
		float light = 0.65*pow(max(dot(ray,normalize(sun)),0.0),8.0) + 0.35*smoothstep(0.53,0.75,billow);
		return vec4(mix(cloud_shadow.rgb,cloud_light.rgb,light),alpha);
	}
	float bank = 1.0-smoothstep(0.12,0.34,abs(height-0.17));
	float alpha = smoothstep(0.44,0.67,billow)*bank*edge;
	return vec4(mix(cloud_shadow.rgb,cloud_light.rgb,smoothstep(0.42,0.68,billow)),alpha);
}
