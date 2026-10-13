// Netz aus Mattis' Meshy-Modell: beult aus, wenn der Ball hineinfliegt, und schwingt nach.
// Netzebene x = 0, Netz entlang z. Pfosten (|z| > 5,4 m) und Boden bleiben fest.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mr_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
// je Treffer: x = z, y = Hoehe, z = Startzeit, w = Staerke in Metern (Vorzeichen = Richtung)
uniform vec4 hits[4];
uniform float now = 0.0;

float hold(vec3 p) {
	// fest an den Pfosten, oben (Spannseil) straffer als unten
	float wz = 1.0 - smoothstep(3.6, 5.35, abs(p.z));
	float y = clamp(p.y, 1.40, 2.46);
	float wy = sin(3.14159 * (y - 1.40) / 1.16) * 0.85 + 0.15;
	return wz * wy * smoothstep(1.30, 1.42, p.y);
}

float bulge(vec3 p) {
	float d = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 h = hits[i];
		float t = now - h.z;
		if (t < 0.0 || t > 3.0) continue;
		// Delle breitet sich entlang des Netzes aus, schwingt gedaempft nach
		float sz = 0.7 + 2.2 * t;
		float dz = p.z - h.x;
		float dy = p.y - h.y;
		float g = exp(-(dz * dz) / (sz * sz) - (dy * dy) / 0.35);
		float env = exp(-3.2 * t) * sin(15.0 * t) * 1.9;
		d += h.w * g * env / (1.0 + 1.5 * t);
	}
	return d;
}

void vertex() {
	VERTEX.x += bulge(VERTEX) * hold(VERTEX);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb;
	vec3 mr = texture(mr_tex, UV).rgb;
	ROUGHNESS = mr.g;
	METALLIC = mr.b * 0.5;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
