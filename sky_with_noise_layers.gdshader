shader_type sky;
render_mode use_half_res_pass;

group_uniforms sky;
uniform vec3 top_color    : source_color = vec3(0.2, 0.5, 0.9);
uniform vec3 bottom_color : source_color = vec3(0.8, 0.9, 1.0);

////////////////////////////////////
// 1) HDRI OPCIONAL ///////////////
////////////////////////////////////
uniform bool      use_hdri   = false;
uniform samplerCube env_hdri;
uniform float     hdri_intensity   : hint_range(0.0,5.0,0.1) = 1.0;

////////////////////////////////////
// 2) CAPAS DE NUBE “PLANAS” ///////
////////////////////////////////////
// Capa A
uniform bool      use_layer_a     = false;
uniform sampler2D layer_a_sampler  : filter_linear, repeat_enable;
uniform float     layer_a_scale    : hint_range(0.1,10.0,0.1) = 1.0;
uniform float     layer_a_speed    : hint_range(0.0,1.0,0.01)= 0.1;
uniform float     layer_a_density  : hint_range(0.0,1.0,0.05)= 0.5;
uniform vec3      layer_a_color    : source_color = vec3(1.0);

// Capa B
uniform bool      use_layer_b      = false;
uniform sampler2D layer_b_sampler  : filter_linear, repeat_enable;
uniform float     layer_b_scale    : hint_range(0.1,10.0,0.1) = 2.0;
uniform float     layer_b_speed    : hint_range(0.0,1.0,0.01)= 0.2;
uniform float     layer_b_density  : hint_range(0.0,1.0,0.05)= 0.3;
uniform vec3      layer_b_color    : source_color = vec3(1.0);

// --- Nuevos uniforms de dirección para cada capa plana
uniform vec2 layer_a_direction = vec2(1.0, 0.0); // (1,0)=derecha, (0,1)=arriba, etc.
uniform vec2 layer_b_direction = vec2(-1.0, 0.0);
////////////////////////////////////
// 3) TUS NUBES RAYMARCH ORIGINALES/
////////////////////////////////////
group_uniforms clouds;
uniform sampler2D cloud_shape_sampler  : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloud_noise_sampler  : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloud_curves;
uniform int     clouds_samples         : hint_range(8,32,8) = 16;
uniform int     shadow_sample          : hint_range(1,4,1)  = 4;
uniform float   clouds_density         : hint_range(0.0,1.0,0.1)=0.5;
uniform float   clouds_scale           : hint_range(0.5,1.5,0.1)=1.0;
uniform float   clouds_smoothness      : hint_range(0.01,0.1,0.01)=0.035;
uniform vec3    clouds_light_color     : source_color=vec3(1.0);
uniform float   clouds_shadow_intensity: hint_range(0.1,10.0,0.1)=1.0;

group_uniforms high_clouds;
uniform sampler2D high_clouds_sampler;
uniform float   high_clouds_density    : hint_range(0.0,1.0,0.05)=0.0;

////////////////////////////////////
// 4) FUNCIONES AUXILIARES /////////
////////////////////////////////////
float rand(float n){ return fract(sin(n)*43758.5453123); }
float cloud_density(vec3 p, float prog){
    float t = TIME * 0.005;
    float n = texture(cloud_noise_sampler, p.xy*4.0 - t).x*0.1 + 0.9;
    float s = texture(cloud_shape_sampler, (p.xy + t)*clouds_scale).x;
    float h = texture(cloud_curves, vec2(prog,0.0)).x;
    float bd = 1.0 - clouds_density;
    return smoothstep(bd-clouds_smoothness, bd+clouds_smoothness, s*n*h);
}
vec2 cloud_ray_march(vec3 dir, vec3 sun){
    float d=0.0, l=0.0, h=0.03;
    for(int i=0;i<clouds_samples;i++){
        float p=float(i)/float(clouds_samples);
        vec3 pt=dir*h*p;
        float cd=cloud_density(pt,p);
        d+=cd;
        for(int j=0;j<shadow_sample;j++){
            float sp=float(j)/float(shadow_sample);
            l+=cloud_density(pt+sun*h*sp,p);
        }
    }
    return vec2(d, l/float(shadow_sample*clouds_samples));
}

////////////////////////////////////
// 5) PASADA PRINCIPAL /////////////
////////////////////////////////////
void sky(){
    // 5.1) Sky gradient base
    vec3 col = mix(bottom_color, top_color, clamp(EYEDIR.y,0.0,1.0));

    // 5.2) HDRI detrás
    if(use_hdri){
        col = mix(col, texture(env_hdri, EYEDIR).rgb*hdri_intensity, 1.0);
    }

    // 5.3) Capas planas A/B
     vec2 uv = EYEDIR.xy * 0.5 + 0.5;

    // Capa A
    if(use_layer_a){
        // desplazamiento en la dirección indicada
        vec2 offset_a = layer_a_direction * (layer_a_speed * TIME);
        float m = texture(layer_a_sampler, uv * layer_a_scale + offset_a).r;
        col = mix(col, layer_a_color, m * layer_a_density);
    }

    // Capa B
    if(use_layer_b){
        vec2 offset_b = layer_b_direction * (layer_b_speed * TIME);
        float m = texture(layer_b_sampler, uv * layer_b_scale + offset_b).r;
        col = mix(col, layer_b_color, m * layer_b_density);
    }

    // 5.4) Nubes raymarch (half res)
    if(AT_HALF_RES_PASS){
        vec3 dirm = vec3(EYEDIR.xz/ clamp(EYEDIR.y,0.0,1.0),1.0);
        vec2 cr = EYEDIR.y>0.0 ? cloud_ray_march(dirm, LIGHT0_DIRECTION) : vec2(0.0);
        COLOR = mix(bottom_color, clouds_light_color, exp(-cr.y*clouds_shadow_intensity));
        ALPHA = 1.0 - exp(-cr.x * clamp(abs(EYEDIR.y),0.0,1.0) *10.0);
    } else {
        // 5.5) Combinación final
        vec3 skyc = col;
        // altas
        if(high_clouds_density>0.0){
            vec2 hu = EYEDIR.xz/ clamp(EYEDIR.y+0.1,0.0,1.0)*0.25 + TIME*0.001;
            float hm = texture(high_clouds_sampler,hu).x*high_clouds_density;
            skyc = mix(skyc, clouds_light_color, hm);
        }
        COLOR = mix(skyc, HALF_RES_COLOR.rgb, HALF_RES_COLOR.a);
    }
}
