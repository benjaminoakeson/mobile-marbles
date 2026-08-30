shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

// One splinter of glass from an impact burst, tumbling end over end about an
// axis of its own.
//
// The tumble is here rather than in the process material because a
// ParticleProcessMaterial can only spin particles about ONE axis. It randomises
// the rate and the direction along that axis, which is not nothing, but every
// shard still turns in the same plane -- and a burst of debris all rotating the
// same way reads as a sheet of paper cut-outs rather than as broken glass.
//
// So each shard picks its own axis on the unit sphere, its own rate, and its own
// stretch, all hashed out of the one random the process material hands it.

uniform vec4 glass_tint : source_color = vec4(0.68, 0.85, 0.92, 0.55);
uniform vec4 rim_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.65;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.05;

// Turns a second, at the fastest. Each shard takes a random share of this, in a
// random direction, so they never come round together.
uniform float tumble_speed : hint_range(0.0, 4.0) = 1.6;

// How much bigger or smaller than the mesh a shard may be, as a fraction. At
// 0.6 the largest is four times the smallest.
uniform float size_spread : hint_range(0.0, 1.0) = 0.6;

// How far from the mesh's own proportions a shard may be stretched, per axis.
// This is what makes some of them chips and others slivers, which no amount of
// overall scaling can do on its own.
uniform float stretch : hint_range(0.0, 1.0) = 0.55;

varying vec3 shard_normal;


float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}


vec3 hash31(float p) {
	vec3 p3 = fract(vec3(p) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}


// Rodrigues' rotation. `axis` must already be normalised.
vec3 turn(vec3 v, vec3 axis, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}


void vertex() {
	// The particle's own index, which is the one thing about it that is both
	// unique and does not change while it is alive.
	//
	// NOT `INSTANCE_CUSTOM.y`. That is the animation phase, and with no particle
	// animation set up it comes out the same for every shard in the burst -- so
	// every one of them picked the same axis, the same rate and the same
	// stretch, and the whole burst turned as one piece. Which is the thing this
	// shader exists to stop.
	float seed = float(INSTANCE_ID) * 0.6180339887;

	// An axis spread EVENLY over the sphere. Taking three randoms as x, y, z and
	// normalising would bunch them towards the corners of a cube; picking the
	// height first and then an angle around it does not.
	vec3 r = hash31(seed);
	float height = r.x * 2.0 - 1.0;
	float around = r.y * TAU;
	float ring = sqrt(max(1.0 - height * height, 0.0));
	vec3 axis = vec3(ring * cos(around), ring * sin(around), height);

	// Its own rate, and its own way round. Driven off TIME rather than the
	// particle's own angle, so it does not depend on the one axis the process
	// material would have spun it about.
	float rate = tumble_speed * mix(0.35, 1.0, r.z) * (hash11(seed + 3.1) < 0.5 ? -1.0 : 1.0);
	float angle = TIME * rate * TAU + seed * TAU;

	// Sized BEFORE it is turned, so the stretch runs along the shard's own edges
	// rather than shearing it in whatever direction it happens to be facing.
	vec3 shape = 1.0 + (hash31(seed + 7.3) - 0.5) * 2.0 * stretch;
	shape *= 1.0 + (hash11(seed + 13.7) - 0.5) * 2.0 * size_spread;

	VERTEX = turn(VERTEX * shape, axis, angle);
	// The normal goes through the inverse of a non-uniform scale, or a stretched
	// shard lights as though it were still square.
	shard_normal = normalize(turn(NORMAL / shape, axis, angle));
	NORMAL = shard_normal;
}


void fragment() {
	ALBEDO = glass_tint.rgb * COLOR.rgb;
	ALPHA = glass_tint.a * COLOR.a;

	METALLIC = 0.0;
	SPECULAR = 0.85;
	ROUGHNESS = surface_roughness;

	// Glancing angles are where glass turns bright, and with no refraction this
	// and the specular are what sell it.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_tint.rgb * fresnel * rim_strength;
}
