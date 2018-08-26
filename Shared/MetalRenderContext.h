//
//  MetalRenderContext.h
//
//  Copyright 2016 Mo DeJong.
//
//  See LICENSE for terms.
//
//  This module references Metal objects that are associated with
//  a rendering context, like a view but are not defined on a
//  render frame. There is 1 render context for N render frames.

//@import MetalKit;
#include <MetalKit/MetalKit.h>

@interface MetalRenderContext : NSObject

@property (nonatomic, retain) id<MTLDevice> device;
@property (nonatomic, retain) id<MTLLibrary> defaultLibrary;
@property (nonatomic, retain) id<MTLCommandQueue> commandQueue;

@property (nonatomic, retain) id<MTLBuffer> identityVerticesBuffer;
@property (nonatomic, assign) int identityNumVertices;

// Invoke this method once a MetalRenderFrame object has been created
// to allocate and create metal resources with the given device instance.

- (void) setupMetal:(nonnull id <MTLDevice>)device;

// Create a MTLRenderPipelineDescriptor given a vertex and fragment shader

- (id<MTLRenderPipelineState>) makePipeline:(MTLPixelFormat)pixelFormat
                              pipelineLabel:(NSString*)pipelineLabel
                             numAttachments:(int)numAttachments
                         vertexFunctionName:(NSString*)vertexFunctionName
                       fragmentFunctionName:(NSString*)fragmentFunctionName;

// Util to allocate a BGRA 32 bits per pixel texture
// with the given dimensions.

- (id<MTLTexture>) makeBGRATexture:(CGSize)size pixels:(uint32_t*)pixels usage:(MTLTextureUsage)usage;

// Allocate texture that contains an 8 bit int value in the range (0, 255)
// represented by a half float value.

- (id<MTLTexture>) make8bitTexture:(CGSize)size bytes:(uint8_t*)bytes usage:(MTLTextureUsage)usage;

// Allocate 16 bit unsigned int texture

- (id<MTLTexture>) make16bitTexture:(CGSize)size halfwords:(uint16_t*)halfwords usage:(MTLTextureUsage)usage;

@end
