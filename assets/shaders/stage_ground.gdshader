shader_type spatial;
render_mode diffuse_burley;
#include "res://assets/shaders/painted_rock.gdshaderinc"

varying vec3 world;
varying vec4 zone;
uniform bool road_mesh = false;
uniform bool desert = false;
uniform float wear_strength = .48;
uniform sampler2D wear_atlas : source_color, filter_linear_mipmap_anisotropic;
uniform bool alpine_terrain = false;
uniform int mountain_section_count = 0;
uniform vec3 mountain_sections[4];
uniform vec3 grass_dark : source_color = vec3(0.60,0.49,0.26);
uniform vec3 grass_light : source_color = vec3(0.81,0.69,0.40);
uniform vec3 film_asphalt : source_color = vec3(0.0);
uniform float film_wetness = 0.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
vec2 cell_point(vec2 id) { return vec2(hash(id),hash(id+vec2(51.3,9.2))); }

vec3 aggregate(vec2 p) {
	vec2 id = floor(p), f = fract(p);
	float first = 8.0, second = 8.0, shade = 0.5;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x),float(y));
			float distance = length(offset+cell_point(id+offset)-f);
			if (distance < first) { second=first; first=distance; shade=hash(id+offset+12.0); }
			else { second=min(second,distance); }
		}
	}
	return vec3(first,second-first,shade);
}
vec3 wear_sample(vec2 uv,vec2 quadrant) {
 // Safe atlas margins avoid mip bleeding between different surfaces.
 vec2 cell=floor(uv), f=fract(uv);
 f=mix(f,vec2(1.0)-f,step(.5,hash(cell)));
 return texture(wear_atlas,(quadrant+.035+f*.93)*.5).rgb;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	zone = COLOR;
}
void fragment() {
	if (road_mesh && mountain_section_count>0) {
		float alpine = 0.0;
		for (int i=0; i<min(mountain_section_count,4); i++) {
			vec3 section = mountain_sections[i];
			alpine = max(alpine,smoothstep(section.x-35.0,section.x,UV.y)*(1.0-smoothstep(section.y-35.0,section.y,UV.y)));
		}
		// Road chunks include a 44 m grass apron in their collision mesh. Hide
		// its outer visual strips to reveal the alpine slopes, retaining the
		// entire driveable road and its collision geometry unchanged.
		if (abs(UV.x)>mix(22.0,UV2.x+3.5,alpine)) { discard; }
	}
	float large = noise(world.xz * 0.07);
	float grit = mix(noise(world.xz * 16.0),0.5,clamp(length(fwidth(world.xz))*12.0,0.0,1.0));
	float fleck = smoothstep(0.75, 0.93, noise(world.xz * 7.0));
	vec3 grass = mix(grass_dark,grass_light,large);
	vec3 earth = mix(vec3(0.26, 0.22, 0.14), vec3(0.39, 0.33, 0.21), noise(world.xz * 0.31));
	vec3 color = mix(grass, earth, smoothstep(0.44, 0.8, noise(world.xz * 0.11)) * 0.25);
	if (!road_mesh) {
		float slope = 1.0-abs((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).y);
		vec3 rock = mix(vec3(.25,.28,.36),vec3(.43,.46,.54),large);
		rock = painted_rock(world,normalize((INV_VIEW_MATRIX*vec4(NORMAL,0)).xyz),rock);
		color = mix(color,rock,smoothstep(.16,.55,slope));
	}
	float road_bump = 0.0;
	float stone_speckle = 1.0;
	if (road_mesh) {
		float half_width = UV2.x;
		float on_road = 1.0 - smoothstep(half_width-0.15, half_width+0.1, abs(UV.x));
		float shoulder = 1.0 - smoothstep(half_width, half_width+1.2, abs(UV.x));
		vec3 gravel = mix(vec3(0.24, 0.23, 0.21), vec3(0.50, 0.43, 0.30), large * 0.45 + 0.35);
		float tracks = exp(-pow((abs(UV.x) - 0.80) * 3.3, 2.0));
		gravel *= 1.0 - tracks * (0.09 + noise(vec2(UV.y * 0.055, 0.0)) * 0.07);
		vec3 stones = aggregate(world.xz*8.0);
		float near_detail = 1.0-smoothstep(0.15,1.1,length(fwidth(world.xz))*8.0);
		float crown = smoothstep(0.018,0.15,stones.y)*(1.0-smoothstep(0.12,0.55,stones.x));
		float grain_shade = mix(0.62,1.28,stones.z);
		gravel *= mix(1.0,grain_shade,near_detail*0.48);
		gravel *= 1.0-(1.0-smoothstep(0.012,0.055,stones.y))*near_detail*0.05;
		road_bump = crown*near_detail*on_road;
		color = mix(color, earth * 1.09, shoulder);
		// Irregular, compacted edges and dragged material break up the straight join.
		float worn_s = UV.y+(noise(vec2(UV.x*1.8,UV.y*0.35))-0.5)*4.5+sin(UV.x*3.1)*0.8;
		float breakup = (noise(vec2(UV.x*1.7,UV.y*.6))-.5)*.18;
		float mud = clamp(zone.b+breakup*4.0*zone.b*(1.0-zone.b),0.0,1.0);
		float asphalt = clamp(zone.r+breakup*4.0*zone.r*(1.0-zone.r),0.0,1.0);
		stone_speckle = mix(1.0,mix(0.15,0.07,asphalt),max(mud,asphalt)*on_road);
		vec3 mud_color = mix(vec3(0.075,0.044,0.021),vec3(0.17,0.10,0.045),noise(world.xz*0.4));
		mud_color *= 1.0-tracks*0.25;
		vec3 tarmac = (film_asphalt.r>0.0 ? film_asphalt : vec3(0.042,0.047,0.051))*(0.9+grit*0.2);
		float edge_mark = smoothstep(half_width-0.32,half_width-0.25,abs(UV.x))*(1.0-smoothstep(half_width-0.17,half_width-0.10,abs(UV.x)));
		// Faded paint, repaired asphalt islands and the occasional fine crack.
		float crack = 1.0-smoothstep(.013,.04,abs(sin(UV.y*.38+noise(world.xz*.6)*5.0+UV.x*1.2)));
		tarmac *= 1.0-crack*.25;
		tarmac *= mix(.82,1.16,smoothstep(.35,.7,noise(world.xz*.7)));
		tarmac = mix(tarmac,vec3(0.56,0.53,0.43),edge_mark*(.45+.55*noise(world.xz*1.4)));
		gravel = mix(mix(gravel,mud_color,mud),tarmac,asphalt);
		road_bump *= 1.0-asphalt*0.93;
		vec2 wear_uv=vec2(UV.x/5.5,UV.y/11.0);
		vec3 painted=wear_sample(wear_uv,vec2(1,0));
		painted=mix(painted,wear_sample(wear_uv,vec2(0,1)),mud);
		painted=mix(painted,wear_sample(wear_uv,vec2(0,0)),asphalt);
		painted=mix(painted,wear_sample(wear_uv,vec2(1,1)),zone.a*.5);
		vec2 seam=abs(fract(wear_uv)-.5)*2.0;
		float patch=(1.0-smoothstep(.78,.99,max(seam.x,seam.y)))*smoothstep(.38,.68,noise(vec2(UV.x*.3,UV.y*.045)));
		float fade=1.0-smoothstep(35.0,95.0,length(VERTEX));
		gravel=mix(gravel,painted,patch*wear_strength*fade);
		color = mix(color, gravel, on_road);
	}
	float wet = road_mesh ? clamp(max(zone.a,film_wetness)*(0.75+0.25*noise(world.xz*1.8)),0.0,1.0) : 0.0;
	color *= 1.0-wet*.35;
	color *= 0.975 + grit * 0.05;
	color += vec3(fleck * 0.005 * stone_speckle);
	ALBEDO = color;
	float muddy_lane = road_mesh && abs(UV.x)<UV2.x ? clamp(zone.b,0.0,1.0) : 0.0;
	ROUGHNESS = mix(mix(0.96,0.76,muddy_lane),0.28,wet);
	SPECULAR = mix(mix(0.08,0.12,muddy_lane),0.38,wet);
	vec2 bumps = vec2(dFdx(road_bump),dFdy(road_bump));
	NORMAL_MAP = vec3(vec2(0.5)+clamp(-bumps*0.55,vec2(-0.20),vec2(0.20)) + vec2(grit-0.5)*0.025,1.0);
	NORMAL_MAP_DEPTH = 0.4;
 if(desert){
  // Two flat sand inks with red drift patches, wind ripples and dark pebble crust.
  float ripple=sin(world.x*.9+world.z*.35+sin(world.z*.05)*3.0);
  float fine=sin(world.x*7.0+world.z*1.8+sin(world.z*.15)*2.0);
  vec3 sand=mix(vec3(.80,.52,.28),vec3(.91,.67,.39),smoothstep(.38,.62,noise(world.xz*.035)));
  sand=mix(sand,vec3(.72,.37,.20),smoothstep(.55,.75,noise(world.xz*.018))*.75);
  sand*=1.0+ripple*.04+fine*.018;
  float crust=smoothstep(.62,.68,noise(world.xz*1.3))*smoothstep(.45,.7,noise(world.xz*.05));
  sand=mix(sand,vec3(.40,.21,.13),crust*.55);
  vec3 desert_color=sand;
  if(!road_mesh){
   float slope=1.0-abs((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).y);
   // Steep dune breaks and the finish escarpment read as layered sandstone.
   float strata=fract((world.y+sin(world.x*.02)*1.5)/5.5);
   vec3 cliff=mix(vec3(.62,.27,.16),vec3(.80,.47,.28),step(.5,fract(floor((world.y+sin(world.x*.02)*1.5)/5.5)*.618)));
   cliff=mix(cliff,vec3(.90,.72,.52),(1.0-smoothstep(.0,.08,strata))*.6);
   float steep=smoothstep(.14,.34,slope);
   desert_color=mix(desert_color,cliff,steep);
   // Sunlit sand bounces warm light into shaded escarpments.
   EMISSION=cliff*vec3(.30,.16,.11)*steep;
  } else {
   float half_width=UV2.x;
   float on_road=1.0-smoothstep(half_width-.15,half_width+.1,abs(UV.x));
   float tracks=exp(-pow((abs(UV.x)-.8)*3.0,2.0));
   vec3 packed=mix(vec3(.50,.29,.17),vec3(.58,.36,.21),noise(world.xz*.4));
   packed*=1.0-tracks*.30;
   packed*=1.0+sin(UV.y*1.7+noise(world.xz*.3)*4.0)*.03;
   // Gravel stretches keep the shared aggregate shading, warmed by red dust.
   vec3 lane=mix(ALBEDO*vec3(1.16,.96,.80),packed,step(3.5,UV2.y));
   float berm=smoothstep(half_width-.1,half_width+.5,abs(UV.x))*(1.0-smoothstep(half_width+.8,half_width+1.9,abs(UV.x)));
   desert_color=mix(sand,lane,on_road);
   desert_color=mix(desert_color,vec3(.95,.72,.44),berm*.5);
  }
  ALBEDO=desert_color;
  ROUGHNESS=.98;
 }

}
