shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, unshaded;

uniform vec4 water_color : source_color = vec4(0.45, 0.67, 0.92, 0.56);
uniform vec4 ripple_color : source_color = vec4(0.76, 0.88, 1.0, 0.34);
uniform vec4 edge_color : source_color = vec4(0.82, 0.93, 1.0, 0.28);

uniform float alpha : hint_range(0.0, 1.0, 0.01) = 0.56;
uniform vec2 flow_direction = vec2(0.0, -1.0);
uniform float flow_speed : hint_range(0.0, 4.0, 0.01) = 0.35;
uniform float wave_scale : hint_range(0.05, 4.0, 0.01) = 0.45;
uniform float wave_strength : hint_range(0.0, 2.0, 0.01) = 0.75;
uniform float stripe_softness : hint_range(0.01, 0.5, 0.01) = 0.18;
uniform float surface_lift : hint_range(0.0, 0.08, 0.001) = 0.018;

varying vec3 world_pos;
varying vec3 world_normal;

float band(float value, float width) {
	float crest = 1.0 - abs(value * 2.0 - 1.0);
	return smoothstep(1.0 - width, 1.0, crest);
}

void vertex() {
	vec3 original_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 dir = flow_direction;
	if (length(dir) < 0.001) {
		dir = vec2(0.0, -1.0);
	}
	dir = normalize(dir);

	float top_mask = smoothstep(0.65, 0.95, NORMAL.y);
	float surface_wave = sin(dot(original_world_pos.xz, vec2(dir.y, -dir.x)) * wave_scale * 2.4 + TIME * flow_speed * 2.2);
	VERTEX.y += surface_wave * surface_lift * wave_strength * top_mask;

	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 dir = flow_direction;
	if (length(dir) < 0.001) {
		dir = vec2(0.0, -1.0);
	}
	dir = normalize(dir);
	vec2 cross_dir = vec2(-dir.y, dir.x);

	vec2 p = world_pos.xz * wave_scale;
	float along = dot(p, dir);
	float across = dot(p, cross_dir);

	float broad_wave = sin(across * 2.3 + sin(along * 0.65) * 0.5 + TIME * flow_speed * 2.0);
	float fine_wave = sin(across * 6.8 + along * 0.9 + TIME * flow_speed * 4.2);

	float broad_band = band(broad_wave * 0.5 + 0.5, stripe_softness);
	float fine_band = band(fine_wave * 0.5 + 0.5, stripe_softness * 0.55) * 0.35;
	float ripple = clamp((broad_band * 0.62 + fine_band) * wave_strength, 0.0, 1.0);

	float top_mask = smoothstep(0.35, 0.8, world_normal.y);
	float view_edge = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);

	vec3 color = water_color.rgb;
	color = mix(color, ripple_color.rgb, ripple * top_mask * ripple_color.a);
	color = mix(color, edge_color.rgb, view_edge * edge_color.a);

	ALBEDO = color;
	ALPHA = clamp(alpha + ripple * 0.08 * top_mask + view_edge * 0.12, 0.0, 1.0);
}
