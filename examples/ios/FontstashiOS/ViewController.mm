//
//  ViewController.m
//  FontstashiOS
//
//  Created by Karim Naaji on 07/10/2014.
//  Copyright (c) 2014 Mapzen. All rights reserved.
//

#import "ViewController.h"

@interface ViewController () 

@property (strong, nonatomic) EAGLContext *context;

- (void)setupGL;
- (void)tearDownGL;
- (void)createFontContext;
- (void)deleteFontContext;
- (void)renderFont;
- (void)loadFonts;
- (void)initShaders;
- (void)pushVerticesForBuffer:(fsuint)buffer vbo:(GLuint*)vbo nVerts:(int*)nVerts;
- (void)renderForVBO:(GLuint)vbo vboSize:(int)vboSize owner:(int)owner;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }

    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    
    transformTextures = [NSMutableDictionary dictionaryWithCapacity:2];
    
    [self setupGL];
    [self initShaders];
}

- (void)initShaders
{
    shaderProgram = glCreateProgram();
    GLuint frag = glCreateShader(GL_FRAGMENT_SHADER);
    GLuint vert = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(frag, 1, &glfs::defaultFragShaderSrc, NULL);
    glShaderSource(vert, 1, &glfs::vertexShaderSrc, NULL);
    glCompileShader(frag);
    glCompileShader(vert);
    glAttachShader(shaderProgram, frag);
    glAttachShader(shaderProgram, vert);
    glLinkProgram(shaderProgram);

    GLint status;
    glGetProgramiv(shaderProgram, GL_LINK_STATUS, &status);
    if (!status) {
        NSLog(@"Program not linked");
        glDeleteProgram(shaderProgram);
    }

    positionAttribLoc = glGetAttribLocation(shaderProgram, "a_position");
    texCoordAttribLoc = glGetAttribLocation(shaderProgram, "a_texCoord");
    fsidAttribLoc = glGetAttribLocation(shaderProgram, "a_fsid");
}

- (void)dealloc
{
    glDeleteProgram(shaderProgram);
    glDeleteTextures(1, &atlas);

    for(NSNumber* textureName in transformTextures) {
        GLuint val = [textureName intValue];
        glDeleteTextures(1, &val);
    }

    glDeleteBuffers(1, &vbo1);
    glDeleteBuffers(1, &vbo2);

    [self tearDownGL];
    
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;
        
        [self tearDownGL];
        
        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }
}

- (void)setupGL
{
    [EAGLContext setCurrentContext:self.context];

    CGSize screen = [UIScreen mainScreen].bounds.size;
    
    glViewport(0, 0, screen.width, screen.height);
    glClearColor(0.25f, 0.25f, 0.28f, 1.0f);

    [self createFontContext];
}

- (void)tearDownGL
{
    [EAGLContext setCurrentContext:self.context];
    
    [self deleteFontContext];
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update
{
    pixelScale = [[UIScreen mainScreen] scale];
    width = self.view.bounds.size.width * pixelScale;
    height = self.view.bounds.size.height * pixelScale;

    glfonsScreenSize(fs, width, height);
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    [self renderFont];
}

#pragma mark - Fontstash

- (void)renderForVBO:(GLuint)vbo vboSize:(int)vboSize owner:(int)ownerId
{
    float projectionMatrix[16] = {0};

    glfonsProjection(fs, projectionMatrix);

    glActiveTexture(GL_TEXTURE1);
    NSNumber* textureName = [transformTextures valueForKey:[NSString stringWithFormat:@"owner-%d", ownerId]];
    glBindTexture(GL_TEXTURE_2D, [textureName intValue]);

    glUseProgram(shaderProgram);

    glUniform1i(glGetUniformLocation(shaderProgram, "u_tex"), 0); // atlas
    glUniform1i(glGetUniformLocation(shaderProgram, "u_transforms"), 1); // transform texture
    glUniform2f(glGetUniformLocation(shaderProgram, "u_tresolution"), 32, 64); // cf glfontstash for transform texture res
    glUniform3f(glGetUniformLocation(shaderProgram, "u_color"), 1.0, 1.0, 1.0);
    glUniform2f(glGetUniformLocation(shaderProgram, "u_resolution"), width, height);
    glUniformMatrix4fv(glGetUniformLocation(shaderProgram, "u_proj"), 1, GL_FALSE, projectionMatrix);

    glBindBuffer(GL_ARRAY_BUFFER, vbo);

    glVertexAttribPointer(positionAttribLoc, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(float), 0);
    glEnableVertexAttribArray(positionAttribLoc);

    glVertexAttribPointer(texCoordAttribLoc, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (const GLvoid*)(2 * sizeof(float)));
    glEnableVertexAttribArray(texCoordAttribLoc);

    glVertexAttribPointer(fsidAttribLoc, 1, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (const GLvoid*)(4 * sizeof(float)));
    glEnableVertexAttribArray(fsidAttribLoc);

    glDrawArrays(GL_TRIANGLES, 0, vboSize);

    glBindBuffer(GL_ARRAY_BUFFER, 0);

    glUseProgram(0);
}

- (void)renderFont
{
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDisable(GL_DEPTH_TEST);

    float x = 100.0f;
    float y = 450.0f;

    for(NSNumber* textId in bufferByTextId) {
        NSNumber* buffer = [bufferByTextId objectForKey:textId];
        glfonsBindBuffer(fs, [buffer intValue]);

        // transform the text ids
        glfonsTransform(fs, [textId intValue], x, y, 0.0f, 1.0f);

        glfonsBindBuffer(fs, 0);

        y += 150.0;
    }

    // track the owner to have a keyvalue pair owner-texture id, should be a class or struct
    int ownerId;

    // upload the transforms for each buffer (lazy upload)
    glfonsBindBuffer(fs, buffer1);
    ownerId = 0;
    glfonsUpdateTransforms(fs, &ownerId);

    glfonsBindBuffer(fs, buffer2);
    ownerId = 1;
    glfonsUpdateTransforms(fs, &ownerId);
    glfonsBindBuffer(fs, 0);

    // Rendering
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, atlas);

    [self renderForVBO:vbo1 vboSize:vbo1size owner:0];
    [self renderForVBO:vbo2 vboSize:vbo2size owner:1];

    glDisable(GL_BLEND);
    
    GLenum glError = glGetError();
    if (glError) {
        printf("GL Error %d!!!\n", glError);
        exit(0);
    }
}

- (void)loadFonts
{
    NSBundle* bundle = [NSBundle mainBundle];
    char* resourcePath;

    resourcePath = (char*)[[bundle pathForResource:@"amiri-regular"
                                            ofType:@"ttf"] UTF8String];

    amiri = fonsAddFont(fs, "amiri", resourcePath);

    if (amiri == FONS_INVALID) {
        NSLog(@"Could not add font normal");
    }

    resourcePath = (char*)[[bundle pathForResource:@"DejaVuSerif"
                                            ofType:@"ttf"] UTF8String];

    dejavu = fonsAddFont(fs, "droid-serif", resourcePath);

    if(dejavu == FONS_INVALID) {
        NSLog(@"Could not add font droid serif");
    }

    resourcePath = (char*)[[bundle pathForResource:@"fireflysung"
                                            ofType:@"ttf"] UTF8String];

    han = fonsAddFont(fs, "fireflysung", resourcePath);

    if(han == FONS_INVALID) {
        NSLog(@"Could not add font droid sans japanese");
    }

    resourcePath = (char*)[[bundle pathForResource:@"Sanskrit2003"
                                            ofType:@"ttf"] UTF8String];

    hindi = fonsAddFont(fs, "Sanskrit2003", resourcePath);

    if(hindi == FONS_INVALID) {
        NSLog(@"Could not add font Sanskrit2003");
    }
}

- (void)createFontContext
{
    // keeping track of the buffer associated with each text id
    bufferByTextId = [NSMutableDictionary dictionaryWithCapacity:TEXT_NUMBER];
    NSNumber* key;
    GLFONSparams params;

    params.errorCallback = errorCallback;
    params.createAtlas = createAtlas;
    params.createTexTransforms = createTexTransforms;
    params.updateAtlas = updateAtlas;
    params.updateTransforms = updateTransforms;

    fs = glfonsCreate(512, 512, FONS_ZERO_TOPLEFT, params, (__bridge void*) self);
    
    if (fs == NULL) {
        NSLog(@"Could not create font context");
    }
    
    [self loadFonts];

    owner = 0; // track ownership

    glfonsBufferCreate(fs, 32, &buffer1);
    glfonsBindBuffer(fs, buffer1);

    glfonsGenText(fs, 5, texts);

    fonsSetFont(fs, han);
    fonsSetSize(fs, 100.0);
    fonsSetShaping(fs, "han", "TTB", "ch");
    glfonsRasterize(fs, texts[0], "緳 踥踕", FONS_EFFECT_NONE);
    key = [NSNumber numberWithInt:texts[0]];
    bufferByTextId[key] = [NSNumber numberWithInt:buffer1];

    fonsClearState(fs);

    fonsSetFont(fs, amiri);

    fonsSetSize(fs, 200.0);
    fonsSetShaping(fs, "arabic", "RTL", "ar");
    glfonsRasterize(fs, texts[1], "سنالى ما شاسعة وق", FONS_EFFECT_NONE);
    key = [NSNumber numberWithInt:texts[1]];
    bufferByTextId[key] = [NSNumber numberWithInt:buffer1];

    fonsClearState(fs);

    glfonsBufferCreate(fs, 32, &buffer2);
    glfonsBindBuffer(fs, buffer2);

    fonsSetSize(fs, 100.0);
    fonsSetShaping(fs, "arabic", "RTL", "ar");
    glfonsRasterize(fs, texts[2], "تسجّل يتكلّم", FONS_EFFECT_NONE);
    key = [NSNumber numberWithInt:texts[2]];
    bufferByTextId[key] = [NSNumber numberWithInt:buffer2];

    fonsClearState(fs);

    fonsSetFont(fs, dejavu);

    fonsSetSize(fs, 50.0);
    fonsSetShaping(fs, "french", "left-to-right", "fr");
    glfonsRasterize(fs, texts[3], "ffffi", FONS_EFFECT_NONE);
    key = [NSNumber numberWithInt:texts[3]];
    bufferByTextId[key] = [NSNumber numberWithInt:buffer2];

    fonsClearState(fs);

    fonsSetFont(fs, hindi);
    fonsSetSize(fs, 200.0);
    fonsSetShaping(fs, "devanagari", "LTR", "hi");
    glfonsRasterize(fs, texts[4], "हालाँकि प्रचलित रूप पूजा", FONS_EFFECT_NONE);
    key = [NSNumber numberWithInt:texts[4]];
    bufferByTextId[key] = [NSNumber numberWithInt:buffer2];

    glfonsBindBuffer(fs, buffer2);
    float x0, y0, x1, y1;
    glfonsGetBBox(fs, texts[3], &x0, &y0, &x1, &y1);
    NSLog(@"BBox %f %f %f %f", x0, y0, x1, y1);
    NSLog(@"Glyph count %d", glfonsGetGlyphCount(fs, texts[3]));
    NSLog(@"Glyph offset %f", glfonsGetGlyphOffset(fs, texts[3], 1));

    [self pushVerticesForBuffer:buffer1 vbo:&vbo1 nVerts:&vbo1size];
    [self pushVerticesForBuffer:buffer2 vbo:&vbo2 nVerts:&vbo2size];

    glfonsBindBuffer(fs, 0);
}

- (void)pushVerticesForBuffer:(fsuint)buffer vbo:(GLuint*)vbo nVerts:(int*)nVerts {
    glfonsBindBuffer(fs, buffer);
    glGenBuffers(1, vbo);
    glBindBuffer(GL_ARRAY_BUFFER, *vbo);

    std::vector<float> vertices;

    if(glfonsVertices(fs, &vertices, nVerts)) {
        glBufferData(GL_ARRAY_BUFFER, sizeof(float) * vertices.size(), vertices.data(), GL_STATIC_DRAW);
    }

    glfonsBindBuffer(fs, 0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

- (void)deleteFontContext
{
    glfonsDelete(fs);
}

#pragma mark GPU access

- (void) updateAtlas:(const unsigned int*)pixels xoff:(unsigned int)xoff
                yoff:(unsigned int)yoff width:(unsigned int)w height:(unsigned int)h
{
    NSLog(@"Update atlas %d %d %d %d", xoff, yoff, w, h);

    glBindTexture(GL_TEXTURE_2D, atlas);
    glTexSubImage2D(GL_TEXTURE_2D, 0, xoff, yoff, w, h, GL_ALPHA, GL_UNSIGNED_BYTE, pixels);
    glBindTexture(GL_TEXTURE_2D, 0);
}

- (void) updateTransforms:(const unsigned int*)pixels xoff:(unsigned int)xoff
                     yoff:(unsigned int)yoff width:(unsigned int)w height:(unsigned int)h owner:(int)ownerId
{
    NSLog(@"Update transform %d %d %d %d", xoff, yoff, w, h);

    NSNumber* textureName = [transformTextures valueForKey:[NSString stringWithFormat:@"owner-%d", ownerId]];

    glBindTexture(GL_TEXTURE_2D, [textureName intValue]);
    glTexSubImage2D(GL_TEXTURE_2D, 0, xoff, yoff, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    glBindTexture(GL_TEXTURE_2D, 0);
}

- (void) createAtlasWithWidth:(unsigned int)w height:(unsigned int)h
{
    NSLog(@"Create texture atlas");

    glGenTextures(1, &atlas);
    glBindTexture(GL_TEXTURE_2D, atlas);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_ALPHA, w, h, 0, GL_ALPHA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glBindTexture(GL_TEXTURE_2D, 0);
}

- (void) createTextureTransformsWithWidth:(unsigned int)w height:(unsigned int)h
{
    NSLog(@"Create texture transforms");

    GLuint textureName;
    glGenTextures(1, &textureName);
    glBindTexture(GL_TEXTURE_2D, textureName);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glBindTexture(GL_TEXTURE_2D, 0);

    transformTextures[[NSString stringWithFormat:@"owner-%d", owner++]] = [NSNumber numberWithInt:textureName];
}

@end