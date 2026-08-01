shader_type sky;
// Dramatic clouded sunset sky: warm gradient + scrolling fbm clouds + sun glow.

uniform vec3 zenith_color : source_color = vec3(0.55, 0.18, 0.12);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.62, 0.28);
uniform vec3 haze_color : source_color = vec3(1.0, 0.85, 0.55);
uniform vec3 cloud_dark : source_color = vec3(0.32, 0.16, 0.12);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.78, 0.45);
uniform float cloud_cover = 0.48;
uniform float cloud_speed = 0.008;
uniform float sun_glow = 0.018;
uniform float sun_core = 0.07;   // bright tight sun disk; animated for the entry flare

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p *= 2.02;
		amp *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = clamp(dir.y, 0.0, 1.0);

	// Base sunset gradient (bright at the horizon, deep up high).
	vec3 base = mix(horizon_color, zenith_color, pow(up, 0.55));
	base = mix(haze_color, base, smoothstep(0.0, 0.28, dir.y)); // hot band on the horizon

	// Sun disk + warm halo.
	float sd = max(dot(dir, LIGHT0_DIRECTION), 0.0);
	float halo = pow(sd, 18.0) * sun_glow + pow(sd, 460.0) * sun_core;
	vec3 col = base + LIGHT0_COLOR.rgb * halo;

	// Scrolling clouds, projected onto a plane above; denser toward the horizon.
	if (dir.y > 0.001) {
		vec2 uv = dir.xz / (dir.y + 0.12);
		uv *= 1.1;
		uv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.5);
		float n = fbm(uv * 1.3);
		n = mix(n, fbm(uv * 3.1 + 7.0), 0.4);
		float horizon_bias = 1.0 - smoothstep(0.0, 0.6, dir.y);
		float cover = cloud_cover + horizon_bias * 0.22;
		float cloud = smoothstep(cover, cover + 0.28, n);
		// Light clouds from the sun side.
		float lit = pow(sd, 2.0);
		vec3 cloud_col = mix(cloud_dark, cloud_lit, lit * 0.9 + 0.15);
		float fade = smoothstep(0.0, 0.12, dir.y); // hide the projection seam at the horizon
		col = mix(col, cloud_col, cloud * 0.85 * fade);
	}

	COLOR = col;
}
