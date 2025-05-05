shader_type spatial;
render_mode unshaded;

uniform float terrain_min_y;
uniform float terrain_max_y;
varying float v_h;

void vertex() {
    // Normaliza de forma lineal entre min_y y max_y
    v_h = clamp((VERTEX.y - terrain_min_y) / (terrain_max_y - terrain_min_y), 0.0, 1.0);
}

void fragment() {
    // Salida en escala de grises
    ALBEDO   = vec3(v_h);
    EMISSION = ALBEDO;
}
