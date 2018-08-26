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

#import "MetalRenderFrame.h"

// The max number of command buffers in flight
#define MetalRenderContextMaxBuffersInFlight (3)

@interface MetalRenderContext : NSObject

@property (nonatomic, retain) id<MTLDevice> device;
@property (nonatomic, retain) id<MTLLibrary> defaultLibrary;
@property (nonatomic, retain) id<MTLCommandQueue> commandQueue;

@property (nonatomic, retain) dispatch_semaphore_t inFlightSemaphore;

@property (nonatomic, retain) id<MTLBuffer> identityVerticesBuffer;
@property (nonatomic, assign) int identityNumVertices;

@property (nonatomic, retain) id<MTLRenderPipelineState> renderToTexturePipelineState;
@property (nonatomic, retain) id<MTLRenderPipelineState> renderFromTexturePipelineState;

#if defined(DEBUG)

@property (nonatomic, retain) id<MTLRenderPipelineState> debugRenderXYoffsetTexturePipelineState;
@property (nonatomic, retain) id<MTLRenderPipelineState> debugRenderIndexesTexturePipelineState;
@property (nonatomic, retain) id<MTLRenderPipelineState> debugRenderLutiTexturePipelineState;

#endif // DEBUG

@property (nonatomic, retain) id<MTLRenderPipelineState> render12PipelineState;
@property (nonatomic, retain) id<MTLRenderPipelineState> render16PipelineState;

@property (nonatomic, retain) id<MTLRenderPipelineState> renderCroppedIndexesPipelineState;

@property (nonatomic, retain) id<MTLRenderPipelineState> renderCroppedLUTIndexesPipelineState;

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

// Setup render pixpelines

- (void) setupRenderPipelines;

// Huffman render textures initialization

- (void) setupHuffRenderTextures:(CGSize)renderSize
                     renderFrame:(MetalRenderFrame*)renderFrame;

// Specific render operations

#if defined(DEBUG)

// Implements debug render operation where (X,Y) values are written to a buffer

- (void) debugRenderXYToTexture:(id<MTLCommandBuffer>)commandBuffer
                    renderFrame:(MetalRenderFrame*)renderFrame;

// Debug render INDEX values out as grayscale written into the pixel

- (void) debugRenderIndexesToTexture:(id<MTLCommandBuffer>)commandBuffer
                         renderFrame:(MetalRenderFrame*)renderFrame;

// Debug render XY values out as 2 12 bit values

- (void) debugRenderLutiToTexture:(id<MTLCommandBuffer>)commandBuffer
                      renderFrame:(MetalRenderFrame*)renderFrame;

#endif // DEBUG

// Render pass 0 with huffman decoder

- (void) renderHuff0:(id<MTLCommandBuffer>)commandBuffer
         renderFrame:(MetalRenderFrame*)renderFrame;

- (void) renderHuff1:(id<MTLCommandBuffer>)commandBuffer
         renderFrame:(MetalRenderFrame*)renderFrame;

- (void) renderHuff2:(id<MTLCommandBuffer>)commandBuffer
         renderFrame:(MetalRenderFrame*)renderFrame;

- (void) renderHuff3:(id<MTLCommandBuffer>)commandBuffer
         renderFrame:(MetalRenderFrame*)renderFrame;

// Render pass 4 with huffman decoder, this render writes 4 BGRA values and
// does not write intermediate output values.

- (void) renderHuff4:(id<MTLCommandBuffer>)commandBuffer
         renderFrame:(MetalRenderFrame*)renderFrame;

// Blit from N huffman textures so that each texture output
// is blitted into the same output texture.

- (void) blitRenderedTextures:(id<MTLCommandBuffer>)commandBuffer
                  renderFrame:(MetalRenderFrame*)renderFrame;

// Render cropped INDEXES as bytes to texture

- (void) renderCroppedIndexesToTexture:(id<MTLCommandBuffer>)commandBuffer
                    renderFrame:(MetalRenderFrame*)renderFrame;

// Render into the resizeable BGRA texture

- (void) renderToTexture:(id<MTLCommandBuffer>)commandBuffer
             renderFrame:(MetalRenderFrame*)renderFrame;

// Render BGRA pixels to output texture.

- (void) renderCroppedBGRAToTexture:(id<MTLCommandBuffer>)commandBuffer
                        renderFrame:(MetalRenderFrame*)renderFrame;

// Render from the resizable BGRA output texture into the active view

- (void) renderFromTexture:(id<MTLCommandBuffer>)commandBuffer
      renderPassDescriptor:(MTLRenderPassDescriptor*)renderPassDescriptor
               renderFrame:(MetalRenderFrame*)renderFrame
             viewportWidth:(int)viewportWidth
            viewportHeight:(int)viewportHeight;


@end
