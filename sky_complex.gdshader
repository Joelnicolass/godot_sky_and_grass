shader_type sky;
render_mode use_half_res_pass;

/////////////////////////////////////
// 1) OPCIONES DE RENDIMIENTO ///////
/////////////////////////////////////

// Toggles generales
uniform bool use_hdri = true;
uniform bool use_cloud_low  = true;
uniform bool use_cloud_mid  = true;
uniform bool use_cloud_base = true;
uniform bool use_cloud_high = true;

// Calidad (sample counts) por capa
uniform int low_samples        : hint_range(1, 32, 1) = 8;
uniform int mid_samples        : hint_range(1, 32, 1) = 12;
uniform int base_samples       : hint_range(1, 32, 1) = 16;
uniform int high_samples       : hint_range(1, 32, 1) =  8;

// Calidad de sombras por capa
uniform int low_shadow_samples : hint_range(1, 8, 1) = 2;
uniform int mid_shadow_samples : hint_range(1, 8, 1) = 2;
uniform int base_shadow_samples: hint_range(1, 8, 1) = 4;
uniform int high_shadow_samples: hint_range(1, 8, 1) = 2;

/////////////////////////////////////
// 2) HDRI BACKGROUND (opcional) ///
/////////////////////////////////////

uniform samplerCube env_hdri;
uniform float hdri_intensity : hint_range(0.0, 5.0, 0.1) = 1.0;

/////////////////////////////////////
// 3) CLOUD LAYERS (opcionales) ////
/////////////////////////////////////

// Capa baja
uniform sampler2D cloud_low_sampler : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float cloud_low_density      : hint_range(0.0,1.0,0.05) = 0.3;
uniform float cloud_low_scale        : hint_range(0.1,2.0,0.1)   = 0.5;
uniform vec3  cloud_low_color        : source_color           = vec3(1.0);

// Capa media
uniform sampler2D cloud_mid_sampler : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float cloud_mid_density      : hint_range(0.0,1.0,0.05) = 0.4;
uniform float cloud_mid_scale        : hint_range(0.1,2.0,0.1)   = 0.8;
uniform vec3  cloud_mid_color        : source_color           = vec3(1.0);

// Capa base (original)
group_uniforms clouds;
uniform sampler2D cloud_shape_sampler : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloud_noise_sampler : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloud_curves;
uniform float   clouds_density        : hint_range(0.0,1.0,0.1)    = 0.5;
uniform float   clouds_scale          : hint_range(0.5,1.5,0.1)    = 1.0;
uniform float   clouds_smoothness     : hint_range(0.01,0.1,0.01)   = 0.035;
uniform vec3    clouds_light_color    : source_color              = vec3(1.0);
uniform float   clouds_shadow_intensity : hint_range(0.1,10.0,0.1) = 1.0;

// Capa alta
group_uniforms high_clouds;
uniform sampler2D high_clouds_sampler;
uniform float   high_clouds_density    : hint_range(0.0,1.0,0.05) = 0.0;
uniform vec3    high_clouds_color      : source_color           = vec3(1.0);

/////////////////////////////////////
// 4) FUNCIONES AUXILIARES /////////
/////////////////////////////////////

float rand(float n) {
    return fract(sin(n) * 43758.5453123);
}

// …incluye aquí hash(), voronoi(), direction_to_matrix(), get_shooting_star()…//

float cloud_density_custom(vec3 p, float progress, float density_param, float scale_param, float smoothness) {
    float t_o       = TIME * 0.005;
    float t_o_small = TIME * -0.005;
    float noise     = texture(cloud_noise_sampler, p.xy * 4.0 + t_o_small).x * 0.1 + 0.9;
    float shape     = texture(cloud_shape_sampler, (p.xy + t_o) * scale_param).x;
    float height_c  = texture(cloud_curves, vec2(progress, 0.0)).x;
    float base_d    = 1.0 - density_param;
    return smoothstep(
        base_d - smoothness,
        base_d + smoothness,
        shape * noise * height_c
    );
}

vec2 cloud_ray_march_custom(
    vec3 direction,
    vec3 sun_direction,
    float density_param,
    float scale_param,
    float smoothness,
    int   samples,
    int   shadow_samples
) {
    float accum_d = 0.0;
    float accum_l = 0.0;
    float height  = 0.03;
    for (int i = 0; i < samples; i++) {
        float prog = float(i) / float(samples);
        vec3 sample_p = direction * height * prog;
        float d = cloud_density_custom(sample_p, prog, density_param, scale_param, smoothness);
        accum_d += d;
        float light_sum = 0.0;
        for (int f = 0; f < shadow_samples; f++) {
            float sp = float(f) / float(shadow_samples);
            vec3 offset = sun_direction * height * sp;
            light_sum += cloud_density_custom(sample_p + offset, prog, density_param, scale_param, smoothness);
        }
        accum_l += light_sum;
    }
    return vec2(accum_d, accum_l / float(shadow_samples * samples));
}

/////////////////////////////////////
// 5) PASADA PRINCIPAL /////////////
/////////////////////////////////////

void sky() {
    // HDRI (opcional)
    vec3 col = vec3(0.0);
    if (use_hdri) {
        col = texture(env_hdri, EYEDIR).rgb * hdri_intensity;
    }

    // Coordenadas de ray‐march
    vec3 dir_march     = vec3(EYEDIR.xz / clamp(EYEDIR.y, 0.0, 1.0), 1.0);
    bool above_horizon = EYEDIR.y > 0.0;

    // Función inline para mezclar nubes
    #define MIX_LAYER(cond, uv, color, den, sc, sm, smp, sh) \
        if (cond && above_horizon) { \
            vec2 m = cloud_ray_march_custom(dir_march, LIGHT0_DIRECTION, den, sc, sm, smp, sh); \
            float shadow = exp(-m.y * clouds_shadow_intensity); \
            float alpha  = 1.0 - exp(-m.x * 10.0); \
            col = mix(col, color, alpha * shadow); \
        }

    // Baja
    MIX_LAYER(use_cloud_low, cloud_low_sampler, cloud_low_color, cloud_low_density, cloud_low_scale, clouds_smoothness, low_samples, low_shadow_samples)
    // Media
    MIX_LAYER(use_cloud_mid, cloud_mid_sampler, cloud_mid_color, cloud_mid_density, cloud_mid_scale, clouds_smoothness, mid_samples, mid_shadow_samples)
    // Base
    MIX_LAYER(use_cloud_base, cloud_shape_sampler, clouds_light_color, clouds_density, clouds_scale, clouds_smoothness, base_samples, base_shadow_samples)
    // Alta
    if (use_cloud_high && high_clouds_density > 0.0 && above_horizon) {
        vec2 uv = (EYEDIR.xz / clamp(EYEDIR.y + 0.1, 0.0, 1.0)) * 0.25 + TIME * 0.001;
        float ht = texture(high_clouds_sampler, uv).x * high_clouds_density;
        col = mix(col, high_clouds_color, ht);
    }

    // Salida final
    if (AT_HALF_RES_PASS) {
        COLOR = col;
        ALPHA = 1.0;
    } else {
        vec3 final_mix = mix(col, HALF_RES_COLOR.rgb, HALF_RES_COLOR.a);
        COLOR = final_mix;
        ALPHA = 1.0;
    }
}
