// The building blocks the marble shaders are made of: hashes, the two kinds of
// noise, and the little bit of geometry a ball needs.
//
// Included rather than copied into each skin, so a fix to the hash reaches all
// of them at once and a skin's own file is only the thing that makes it that
// skin.
//
// Everything here is meant to be fed a position in the MARBLE's space, usually
// the direction from its middle out to the surface. That is what makes a
// pattern roll with the marble instead of swimming across it.

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}


vec3 hash33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
			dot(p, vec3(269.5, 183.3, 246.1)),
			dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}


// A random number per lattice corner, smoothed between them.
float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash13(cell);
	float n100 = hash13(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(cell + vec3(1.0, 1.0, 1.0));

	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}


float fbm3(vec3 p) {
	float sum = value_noise(p) * 0.5;
	sum += value_noise(p * 2.03) * 0.25;
	sum += value_noise(p * 4.07) * 0.125;
	return sum / 0.875;
}


float fbm4(vec3 p) {
	float sum = value_noise(p) * 0.5;
	sum += value_noise(p * 2.03) * 0.25;
	sum += value_noise(p * 4.07) * 0.125;
	sum += value_noise(p * 8.11) * 0.0625;
	return sum / 0.9375;
}


// Noise folded about its middle, so the level where it crosses a half becomes a
// crease. Creases are what strands, filaments, cracks and veins are all made of.
float ridged(vec3 p) {
	return 1.0 - abs(fbm3(p) * 2.0 - 1.0);
}


// Scattered points, one per cell, and how far the two nearest of them are.
// x is the distance to the nearest, y to the second nearest -- their difference
// is small only along the boundaries between points, which is what draws cell
// walls, cracked plates and crystal facets. z is a number belonging to the
// nearest point, so a cell can be given a life of its own.
vec3 worley3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);

	float first = 8.0;
	float second = 8.0;
	float id = 0.0;

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 offset = vec3(float(x), float(y), float(z));
				vec3 point = offset + hash33(cell + offset) - f;
				float d = dot(point, point);

				if (d < first) {
					second = first;
					first = d;
					id = hash13(cell + offset);
				} else if (d < second) {
					second = d;
				}
			}
		}
	}

	return vec3(sqrt(first), sqrt(second), id);
}


// The same scatter as worley3, but handing back the way to the nearest point
// rather than only how far off it is. Anything that has to draw INSIDE a cell --
// a flower in it, a flake lying in it -- needs the direction to work in.
// xyz is the vector from p to that point, w is the point's own number.
vec4 worley_near(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);

	float best = 8.0;
	vec3 towards = vec3(0.0);
	float id = 0.0;

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 offset = vec3(float(x), float(y), float(z));
				vec3 point = offset + hash33(cell + offset) - f;
				float d = dot(point, point);

				if (d < best) {
					best = d;
					towards = point;
					id = hash13(cell + offset);
				}
			}
		}
	}

	return vec4(towards, id);
}


// A pair of directions at right angles to `axis` and to each other, for
// measuring an angle around it.
void frame_for(vec3 axis, out vec3 first, out vec3 second) {
	vec3 helper = abs(axis.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	first = normalize(cross(axis, helper));
	second = cross(axis, first);
}


// Rodrigues' rotation. `axis` must already be normalised.
vec3 twist(vec3 p, vec3 axis, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
}


// How far a ray from `p` in direction `dir` runs before it leaves the ball.
float sphere_exit(vec3 p, vec3 dir, float radius) {
	float b = dot(p, dir);
	float c = dot(p, p) - radius * radius;
	return -b + sqrt(max(b * b - c, 0.0));
}


// Per-pixel offset for a ray walk. Even steps through soft edges leave visible
// rings; a little jitter trades those for a grain nobody notices.
float dither(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}
