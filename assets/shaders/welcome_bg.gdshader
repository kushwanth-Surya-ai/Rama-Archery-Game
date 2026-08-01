shader_type canvas_item;
// Varanasi-at-dusk backdrop for the title card. A layered sunset sky over the
// Ganga: deep indigo zenith melting into a fiery horizon, a low sun disk with a
// rippling reflection running down the river, and drifting aarti smoke. The
// ghat/temple silhouettes and the floating diyas are drawn on top in code
// (WelcomeCard.gd) so they stay crisp.

uniform float horizon = 0.60;                                   // screen-y where the river meets the sky
uniform vec2  sun_pos = vec2(0.5, 0.45);
uniform vec3  sky_top : source_color     = vec3(0.09, 0.05, 0.16);
uniform vec3  sky_mid : source_color     = vec3(0.42, 0.15, 0.22);
uniform vec3  sky_horizon : source_color = vec3(1.00, 0.52, 0.22);
uniform vec3  sun_color : source_color   = vec3(1.00, 0.86, 0.55);
uniform vec3  river_deep : source_color  = vec3(0.05, 0.04, 0.09);

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
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec3 col;

	if (uv.y < horizon) {
		// --- sky ---
		float t = uv.y / horizon;                              // 0 zenith .. 1 at the horizon
		vec3 sky = mix(sky_top, sky_mid, smoothstep(0.0, 0.7, t));
		sky = mix(sky, sky_horizon, pow(t, 2.2));              // hot band hugging the horizon

		// sun disk + warm halo
		float d = distance(uv, sun_pos);
		float halo = exp(-d * 6.0) * 0.9 + exp(-d * 22.0) * 0.7;
		float disk = smoothstep(0.085, 0.068, d);
		sky += sun_color * halo;
		sky = mix(sky, sun_color, disk);

		// drifting aarti smoke / haze, denser toward the horizon
		float smoke = fbm(vec2(uv.x * 3.0 + TIME * 0.02, uv.y * 4.0 - TIME * 0.05));
		float band = smoothstep(0.2, 1.0, t);
		sky += vec3(0.12, 0.07, 0.05) * smoke * 0.25 * band;
		col = sky;
	} else {
		// --- river: mirror the hot sky near the shore + a rippling sun column ---
		float rt = (uv.y - horizon) / (1.0 - horizon);        // 0 at the shore .. 1 at the bottom
		vec3 refl = mix(sky_horizon, river_deep, smoothstep(0.0, 0.55, rt));

		float column = exp(-abs(uv.x - sun_pos.x) * 7.0);      // the sun's reflected lane
		float ripple = sin(uv.y * 60.0 - TIME * 1.5 + sin(uv.x * 40.0) * 0.6) * 0.5 + 0.5;
		float glints = fbm(vec2(uv.x * 22.0, uv.y * 40.0 - TIME * 0.8));
		refl += sun_color * column * (0.35 + ripple * 0.5) * (1.0 - rt * 0.7);
		refl += sun_color * smoothstep(0.72, 1.0, glints) * column * 0.4;
		refl = mix(refl, river_deep, rt * 0.6);
		col = refl;
	}

	// gentle vignette to seat the title
	float vig = smoothstep(1.15, 0.35, distance(uv, vec2(0.5)));
	col *= mix(0.68, 1.0, vig);
	COLOR = vec4(col, 1.0);
}
