//
//  MetalPrefixSumRenderContext.h
//
//  Copyright 2016 Mo DeJong.
//
//  See LICENSE for terms.
//
//  This module references Metal objects that are used to render
//  a prefix sum result with a fragment shader using Metal.

//@import MetalKit;
#include <MetalKit/MetalKit.h>

@class MetalRenderContext;
@class MetalPrefixSumRenderFrame;

@interface MetalPrefixSumRenderContext : NSObject

// Prefix Sum Reduce step

@property (nonatomic, retain) id<MTLRenderPipelineState> reducePipelineState;
@property (nonatomic, retain) id<MTLRenderPipelineState> sweepPipelineState;

#if defined(DEBUG)

//@property (nonatomic, retain) id<MTLRenderPipelineState> debugRenderXYoffsetTexturePipelineState;

#endif // DEBUG

// Setup render pixpelines

- (void) setupRenderPipelines:(MetalRenderContext*)mrc;

// Huffman render textures initialization

- (void) setupRenderTextures:(MetalRenderContext*)mrc
                  renderSize:(CGSize)renderSize
                 renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
              blockDimension:(int)blockDimension;

// Specific render operations

// Prefix sum render operation, this executes a single reduce step

- (void) renderPrefixSumReduce:(MetalRenderContext*)mrc
                 commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                   renderFrame:(MetalPrefixSumRenderFrame*)renderFrame;

- (void) renderPrefixSumSweep:(MetalRenderContext*)mrc
                commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
                inputTexture1:(id<MTLTexture>)inputTexture1
                inputTexture2:(id<MTLTexture>)inputTexture2
                outputTexture:(id<MTLTexture>)outputTexture;

#if defined(DEBUG)

// Implements debug render operation where (X,Y) values are written to a buffer

//- (void) debugRenderXYToTexture:(id<MTLCommandBuffer>)commandBuffer
//                    renderFrame:(MetalPrefixSumRenderFrame*)renderFrame;

#endif // DEBUG

/*

// Render cropped INDEXES as bytes to texture

- (void) renderCroppedIndexesToTexture:(id<MTLCommandBuffer>)commandBuffer
                    renderFrame:(MetalPrefixSumRenderFrame*)renderFrame;

// Render into the resizeable BGRA texture

- (void) renderToTexture:(id<MTLCommandBuffer>)commandBuffer
             renderFrame:(MetalPrefixSumRenderFrame*)renderFrame;

// Render BGRA pixels to output texture.

- (void) renderCroppedBGRAToTexture:(id<MTLCommandBuffer>)commandBuffer
                        renderFrame:(MetalPrefixSumRenderFrame*)renderFrame;

// Render from the resizable BGRA output texture into the active view

- (void) renderFromTexture:(id<MTLCommandBuffer>)commandBuffer
      renderPassDescriptor:(MTLRenderPassDescriptor*)renderPassDescriptor
               renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
             viewportWidth:(int)viewportWidth
            viewportHeight:(int)viewportHeight;

*/


@end
