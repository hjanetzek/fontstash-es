//
//  shaders.h
//  FontstashiOS
//
//  Created by Karim Naaji on 12/16/14.
//  Copyright (c) 2014 Mapzen. All rights reserved.
//

#ifndef FontstashiOS_shaders_h
#define FontstashiOS_shaders_h

namespace glfs {

static const GLchar* vertexShaderSrc = R"END(

#ifdef GL_ES
precision mediump float;
#endif

attribute lowp float a_fsid;
attribute vec2 a_position;
attribute vec2 a_texCoord;

uniform sampler2D u_transforms;
uniform lowp vec2 u_tresolution;
uniform lowp vec2 u_resolution;
uniform mat4 u_proj;

varying vec2 v_uv;
varying float v_alpha;

#define PI 3.14159

#define alpha   tdata.a
#define tx      tdata.x
#define ty      tdata.y
#define theta   tdata.z
#define txp     tdataPrecision.x
#define typ     tdataPrecision.y

/*
 * Converts (i, j) pixel coordinates to the corresponding (u, v) in
 * texture space. The (u,v) targets the center of pixel
 */
vec2 ij2uv(float _i, float _j, float _w, float _h) {
    return vec2(
        (2.0*_i+1.0) / (2.0*_w),
        (2.0*_j+1.0) / (2.0*_h)
    );
}

/*
 * Decodes the id and find its place for its transform inside the texture
 * Returns the (i,j) position inside texture
 */
vec2 id2ij(int _fsid, float _w) {
    float i = mod(float(_fsid * 2), _w);
    float j = floor(float(_fsid * 2) / _w);
    return vec2(i, j);
}

void main() {
    // decode the uv from a text id
    vec2 ij = id2ij(int(a_fsid), u_tresolution.x);
    vec2 uv1 = ij2uv(ij.x, ij.y, u_tresolution.x, u_tresolution.y);
    vec2 uv2 = ij2uv(ij.x+1.0, ij.y, u_tresolution.x, u_tresolution.y);

    // reads the transform data and its precision
    vec4 tdata = texture2D(u_transforms, uv1);
    vec4 tdataPrecision = texture2D(u_transforms, uv2);

    float txe = u_resolution.x / 255.0; // max error on x
    float txy = u_resolution.y / 255.0; // max error on y

    // transforms from [0..1] to [0..resolution] and add lost precision
    tx = u_resolution.x * tx + (txp * txe);
    ty = u_resolution.y * ty + (typ * txy);

    // scale from [0..1] to [0..2pi]
    theta = theta * 2.0 * PI;

    float st = sin(theta);
    float ct = cos(theta);

    // rotates first around +z-axis (0,0,1) and then translates by (tx,ty,0)
    vec4 p = vec4(
        a_position.x * ct - a_position.y * st + tx,
        a_position.x * st + a_position.y * ct + ty,
        0.0,
        1.0
    );
    
    gl_Position = u_proj * p;
    
    v_uv = a_texCoord;
    v_alpha = alpha;
}

)END";

static const GLchar* sdfFragShaderSrc = R"END(

#ifdef GL_ES
precision mediump float;
#endif

uniform lowp sampler2D u_tex;
uniform lowp vec4 u_color;
uniform lowp vec4 u_outlineColor;
uniform lowp vec4 u_sdfParams;
uniform lowp float u_mixFactor;

#define minOutlineD u_sdfParams.x
#define maxOutlineD u_sdfParams.y
#define minInsideD  u_sdfParams.z
#define maxInsideD  u_sdfParams.w

varying vec2 v_uv;

void main(void) {
    float distance = texture2D(u_tex, v_uv).a;
    vec4 inside = smoothstep(minInsideD, maxInsideD, distance) * u_color;
    vec4 outline = smoothstep(minOutlineD, maxOutlineD, distance) * u_outlineColor;

    gl_FragColor = mix(outline, inside, u_mixFactor);
}

)END";

static const GLchar* defaultFragShaderSrc = R"END(

#ifdef GL_ES
precision mediump float;
#endif

uniform lowp sampler2D u_tex;
uniform lowp vec3 u_color;

varying vec2 v_uv;
varying float v_alpha;

void main(void) {
    vec4 texColor = texture2D(u_tex, v_uv);
    gl_FragColor = vec4(u_color.rgb, texColor.a * v_alpha);
}

)END";

}

#endif
