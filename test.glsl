#version 460
#ifdef VERTEX_SHADER

in vec3 in_position;
in vec2 in_texcoord_0;

out vec2 uv0;

void main() {
    gl_Position = vec4(in_position, 1);
    uv0 = in_texcoord_0;
}

#elif FRAGMENT_SHADER

out vec4 outColor;
in vec2 uv0;

uniform float iTime;
uniform vec2 iResolution, iMouse;

/*void mainImage(out vec4 fragColor, in vec2 fragCoord) { 
    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = fragCoord / iResolution.xy;
    // Time varying pixel color
    vec3 col = cos(iTime + uv.xyx + vec3(0, 2, 4)) / 2 + 1 / 2;
    // Output to screen
    fragColor = vec4(col, 1);
}*/

/*
 * "Seascape" by Alexander Alekseev aka TDM - 2014
 * License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
 * Contact: tdmaav@gmail.com
 */

const int NUM_STEPS = 8;
const float PI = 3, EPSILON = 1 / 1000;
#define EPSILON_NRM (1 / (10 * iResolution.x))

// sea
const int ITER_GEOMETRY = 3, ITER_FRAGMENT = 5;
const float SEA_HEIGHT = 0.6, SEA_CHOPPY = 4, SEA_SPEED = 0.8,
            SEA_FREQ = 0.16; //0 mola
const vec3 SEA_BASE = vec3(0.1, 0.19, 0.22),
SEA_WATER_COLOR = vec3(0.8, 0.9, 0.6);
#define SEA_TIME (iTime * SEA_SPEED + 1)
const mat2 octave_m = mat2(1.6, 1.2, -1.2, 1.6);

// math
mat3 fromEuler(vec3 ang) {
    vec2 a1 = vec2(sin(ang.x), cos(ang.x)),
         a2 = vec2(sin(ang.y), cos(ang.y)),
         a3 = vec2(sin(ang.z), cos(ang.z));

    return mat3(vec3(a1.y * a3.y + a1.x * a2.x * a3.x, a1.y * a2.x * a3.x + a3.y * a1.x, -a2.y * a3.x),
                vec3(-a2.y * a1.x, a1.y * a2.y, a2.x),
                vec3(a3.y * a1.x * a2.x + a1.y * a3.x, a1.x * a3.x - a1.y * a3.y * a2.x, a2.y * a3.y));
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(in vec2 p) {
    vec2 i = floor(p), f = fract(p), u = f * f * (3 - 2 * f);

    return -1 + 2 * mix(mix(hash(i + vec2(0, 0)), 
           hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), 
           hash(i + vec2(1, 1)), u.x), u.y);
}

// lighting
float diffuse(vec3 n, vec3 l, float p) {
    return pow(2 / 5 * dot(n, l) + 3 / 5, p);
}
float specular(vec3 n, vec3 l, vec3 e, float s) {    
    float nrm = (s + 8) / (8 * PI);
    return pow(max(dot(reflect(e, n), l), 0), s) * nrm;
}

// sky
vec3 getSkyColor(vec3 e) {
    e.y = max(e.y, 0);

    return vec3(pow(1 - e.y, 2), 1 - e.y, 0.4 * (1 - e.y) + 0.6);
}

// sea
float sea_octave(vec2 uv, float choppy) {
    uv += noise(uv);        
    vec2 wv = 1 - abs(sin(uv)), swv = abs(cos(uv));    
    wv = mix(wv, swv, wv);

    return pow(1 - pow(wv.x * wv.y, 0.65), choppy);
}

float map(vec3 p, int iter = ITER_GEOMETRY) {
    float freq = SEA_FREQ, amp = SEA_HEIGHT, choppy = SEA_CHOPPY;
    vec2 uv = p.xz;
    uv.x = 3 * uv.x / 4;
    
    float d, h = 0;    

    for(int i = 0; i < iter; i++) {        
    	d = sea_octave(freq * (uv + SEA_TIME), choppy);
    	d += sea_octave(freq * (uv - SEA_TIME), choppy);
        h += d * amp;        
    	uv *= octave_m;
        freq = 19 * freq / 10;
        amp = 22 * amp / 100;
        choppy = mix(choppy, 1.0, 0.2);
    }

    return p.y - h;
}

float map_detailed(vec3 p) {
    return map(p, ITER_FRAGMENT);
}

vec3 getSeaColor(vec3 p, vec3 n, vec3 l, vec3 eye, vec3 dist) {  
    float fresnel = clamp(1.0 - dot(n,-eye), 0.0, 1.0);
    fresnel = pow(fresnel,3.0) * 0.65;
        
    vec3 reflected = getSkyColor(reflect(eye,n));    
    vec3 refracted = SEA_BASE + diffuse(n,l,80.0) * SEA_WATER_COLOR * 0.12; 
    
    vec3 color = mix(refracted,reflected,fresnel);
    
    float atten = max(1.0 - dot(dist,dist) * 0.001, 0.0);
    color += SEA_WATER_COLOR * (p.y - SEA_HEIGHT) * 0.18 * atten;
    
    color += vec3(specular(n,l,eye,60.0));
    
    return color;
}

// tracing
vec3 getNormal(vec3 p, float eps) {
    vec3 n;
    n.y = map_detailed(p);    
    n.x = map_detailed(vec3(p.x+eps,p.y,p.z)) - n.y;
    n.z = map_detailed(vec3(p.x,p.y,p.z+eps)) - n.y;
    n.y = eps;
    return normalize(n);
}

float heightMapTracing(vec3 ori, vec3 dir, out vec3 p) {  
    float tm = 0.0;
    float tx = 1000.0;    
    float hx = map(ori + dir * tx);
    if(hx > 0.0) return tx;   
    float hm = map(ori + dir * tm);    
    float tmid = 0.0;
    for(int i = 0; i < NUM_STEPS; i++) {
        tmid = mix(tm,tx, hm/(hm-hx));                   
        p = ori + dir * tmid;                   
    	float hmid = map(p);
		if(hmid < 0.0) {
        	tx = tmid;
            hx = hmid;
        } else {
            tm = tmid;
            hm = hmid;
        }
    }
    return tmid;
}

// main
void mainImage( out vec4 fragColor, in vec2 fragCoord ) {
	vec2 uv = fragCoord.xy / iResolution.xy;
    uv = uv * 2.0 - 1.0;
    uv.x *= iResolution.x / iResolution.y;    
    float time = iTime * 0.3 + iMouse.x*0.01;
        
    // ray
    vec3 ang = vec3(sin(time*3.0)*0.1,sin(time)*0.2+0.3,time);    
    vec3 ori = vec3(0.0,3.5,time*5.0);
    vec3 dir = normalize(vec3(uv.xy,-2.0)); dir.z += length(uv) * 0.15;
    dir = normalize(dir) * fromEuler(ang);
    
    // tracing
    vec3 p;
    heightMapTracing(ori,dir,p);
    vec3 dist = p - ori;
    vec3 n = getNormal(p, dot(dist,dist) * EPSILON_NRM);
    vec3 light = normalize(vec3(0.0,1.0,0.8)); 
             
    // color
    vec3 color = mix(
        getSkyColor(dir),
        getSeaColor(p,n,light,dir,dist),
    	pow(smoothstep(0.0,-0.05,dir.y),0.3));
        
    // post
	fragColor = vec4(pow(color,vec3(0.75)), 1.0);
}

void main() {
    mainImage(outColor, gl_FragCoord.xy);
}

#endif
