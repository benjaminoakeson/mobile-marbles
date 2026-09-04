shader_type sky;

// forest_sky.gdshader with the valley baked into it as a cubemap.
//
// The whole environment -- chasm, cliffs, rim forest, distant hills -- is six
// 1024px faces rendered out of Blender from the middle of the level at eye
// height. Alpha is its silhouette, so the procedural dome, the drifting clouds
// and the sun still show above and through it exactly as before.
//
// A cubemap rather than an equirectangular panorama: hardware samples it
// natively, there is no wrap seam to work around and no pole where the texels
// bunch up, and the sampler picks its own mip without needing the derivative
// fixes a panorama's atan() wrap forces on you.
//
// It costs one texture fetch and no geometry at all -- no draw calls, no
// triangles, no shadow work. The trade is that a sky cannot parallax: roll the
// length of a long level and the valley will not shift. It was baked from the
// origin, so the further a level strays from there, the more that shows.

group_uniforms Valley;

// Six-face bake. Alpha 1 on the terrain and trees, 0 where the sky shows.
uniform samplerCube valley : source_color, filter_linear_mipmap;

// The bake is tonemapped a second time by the Environment, so a little over
// 1.0 usually matches the procedural sky it sits against.
uniform float valley_brightness : hint_range(0.0, 3.0) = 1.1;

// Turns the whole environment around, to put the chasm's waterfall or a heavier
// stand of trees behind a particular level.
uniform float valley_yaw_degrees : hint_range(-180.0, 180.0) = 0.0;

// Fades the valley out, for levels that want the bare sky.
uniform float valley_opacity : hint_range(0.0, 1.0) = 1.0;

group_uniforms Sky;
uniform vec4 zenith : source_color = vec4(0.30, 0.56, 0.92, 1.0);
uniform vec4 horizon : source_color = vec4(0.80, 0.90, 0.98, 1.0);
uniform vec4 below_horizon : source_color = vec4(0.36, 0.44, 0.32, 1.0);
uniform float horizon_falloff : hint_range(0.1, 4.0) = 0.55;

group_uniforms Sun;
uniform vec4 sun_colour : source_color = vec4(1.0, 0.96, 0.86, 1.0);
uniform float sun_size_degrees : hint_range(0.5, 20.0) = 4.0;
uniform float sun_energy : hint_range(0.0, 20.0) = 9.0;
uniform vec4 sun_haze : source_color = vec4(1.0, 0.93, 0.75, 1.0);
uniform float haze_spread : hint_range(1.0, 64.0) = 7.0;
uniform float haze_strength : hint_range(0.0, 2.0) = 0.55;
uniform vec3 sun_from = vec3(0.35, 0.55, 0.75);

group_uniforms Clouds;
uniform sampler3D cloud_noise : filter_linear, repeat_enable;
uniform vec4 cloud_lit : source_color = vec4(1.0, 0.99, 0.96, 1.0);
uniform vec4 cloud_shaded : source_color = vec4(0.72, 0.78, 0.88, 1.0);
uniform float cloud_scale : hint_range(0.05, 2.0) = 0.5;
uniform float coverage : hint_range(0.0, 1.0) = 0.6;
uniform float cloud_softness : hint_range(0.01, 0.6) = 0.16;
uniform float drift_speed : hint_range(0.0, 0.2) = 0.012;


void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = dir.y;

	// LIGHT0_DIRECTION already points TOWARDS the light in a sky shader.
	vec3 sun = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(sun_from);
	float towards_sun = dot(dir, sun);

	vec3 colour = mix(horizon.rgb, zenith.rgb, pow(clamp(up, 0.0, 1.0), horizon_falloff));
	colour = mix(colour, below_horizon.rgb, smoothstep(0.0, -0.22, up));

	colour += sun_haze.rgb * pow(max(towards_sun, 0.0), haze_spread) * haze_strength;

	if (up > 0.0) {
		vec3 plane = dir / max(up, 0.09) * cloud_scale;
		plane += vec3(TIME * drift_speed, 0.0, TIME * drift_speed * 0.6);

		float shape = texture(cloud_noise, plane).r * 0.68
				+ texture(cloud_noise, plane * 2.7 + 4.1).r * 0.32;
		float cloud = smoothstep(coverage, coverage + cloud_softness, shape);
		cloud *= smoothstep(0.0, 0.30, up);

		float towards = texture(cloud_noise, plane + sun * 0.12).r;
		float lit = smoothstep(0.0, 0.3, shape - towards);
		vec3 body = mix(cloud_shaded.rgb, cloud_lit.rgb, clamp(lit + 0.35, 0.0, 1.0));

		colour = mix(colour, body, cloud);
	}

	// The disc before the valley, so a ridge on the skyline eclipses it.
	float edge = radians(sun_size_degrees);
	float angle = acos(clamp(towards_sun, -1.0, 1.0));
	colour += sun_colour.rgb * (1.0 - smoothstep(edge * 0.75, edge, angle)) * sun_energy;

	// The valley last and over everything: it is solid, so nothing shows through.
	float yaw = radians(valley_yaw_degrees);
	float cy = cos(yaw);
	float sy = sin(yaw);
	vec3 look = vec3(dir.x * cy - dir.z * sy, dir.y, dir.x * sy + dir.z * cy);

	vec4 land = texture(valley, look);
	colour = mix(colour, land.rgb * valley_brightness, land.a * valley_opacity);

	COLOR = colour;
}
