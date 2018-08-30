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

// Prefix Sum reduce and sweep states

@property (nonatomic, retain) id<MTLRenderPipelineState> reducePipelineState;
@property (nonatomic, retain) id<MTLRenderPipelineState> sweepPipelineState;
@property (nonatomic, retain) id<MTLRenderPipelineState> inclusiveSweepPipelineState;

#if defined(DEBUG)

//@property (nonatomic, retain) id<MTLRenderPipelineState> debugRenderXYoffsetTexturePipelineState;

#endif // DEBUG

// Setup render pixpelines

- (void) setupRenderPipelines:(MetalRenderContext*)mrc;

// Render textures initialization
// renderSize : indicates the size of the entire texture containing block by block values
// blockSize  : indicates the size of the block to be summed
// renderFrame : holds textures used while rendering

- (void) setupRenderTextures:(MetalRenderContext*)mrc
                  renderSize:(CGSize)renderSize
                   blockSize:(CGSize)blockSize
                 renderFrame:(MetalPrefixSumRenderFrame*)renderFrame;

// Specific render operations

// Prefix sum render operation, this executes a single reduce step

- (void) renderPrefixSumReduce:(MetalRenderContext*)mrc
                 commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                   renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
                  inputTexture:(id<MTLTexture>)inputTexture
                 outputTexture:(id<MTLTexture>)outputTexture
                         level:(int)level;

// Prefix sum sweep, this executes a single sweep step

- (void) renderPrefixSumSweep:(MetalRenderContext*)mrc
                commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
                inputTexture1:(id<MTLTexture>)inputTexture1
                inputTexture2:(id<MTLTexture>)inputTexture2
                outputTexture:(id<MTLTexture>)outputTexture
                        level:(int)level
                  isExclusive:(BOOL)isExclusive;

// Process block by block order data from inputBlockOrderTexture
// using Blelloch's work efficient method. This parallel prefix sum
// generates an exclusive prefix sum and the result is written to
// outputBlockOrderTexture.

- (void) renderPrefixSum:(MetalRenderContext*)mrc
           commandBuffer:(id<MTLCommandBuffer>)commandBuffer
             renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
             isExclusive:(BOOL)isExclusive;

@end
