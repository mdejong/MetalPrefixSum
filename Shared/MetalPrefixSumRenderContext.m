//
//  MetalPrefixSumRenderContext.m
//
//  Copyright 2016 Mo DeJong.
//
//  See LICENSE for terms.
//
//  This object Metal references that are associated with a
//  rendering context like a view but are not defined on a
//  render frame. There is 1 render contet for N render frames.

#include "MetalPrefixSumRenderContext.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inpute to the shaders
#import "AAPLShaderTypes.h"

#import "MetalRenderContext.h"
#import "MetalPrefixSumRenderFrame.h"

// Private API

@interface MetalPrefixSumRenderContext ()

//@property (readonly) size_t numBytesAllocated;

@end

// Main class performing the rendering
@implementation MetalPrefixSumRenderContext

// Setup render pixpelines

- (void) setupRenderPipelines:(MetalRenderContext*)mrc
{
  NSUInteger gpuFamily = [mrc featureSetGPUFamily];

  NSString *sumReduceShader = @"fragmentShaderPrefixSumReduce";
  NSString *sumReduceShaderA7 = @"fragmentShaderPrefixSumReduceA7";
  
  NSString *sumSweepShader = @"fragmentShaderPrefixSumDownSweep";
  NSString *sumSweepShaderA7 = @"fragmentShaderPrefixSumDownSweepA7";
  
  if (gpuFamily == 1) {
    // A7
    sumReduceShader = sumReduceShaderA7;
    sumSweepShader = sumSweepShaderA7;
  }
  
  self.reducePipelineState = [mrc makePipeline:MTLPixelFormatR8Unorm
                                                   pipelineLabel:@"PrefixSumReduce Pipeline"
                                                  numAttachments:1
                                              vertexFunctionName:@"vertexShader"
                                            fragmentFunctionName:sumReduceShader];
  
  NSAssert(self.reducePipelineState, @"reducePipelineState");

  // FIXME: A7 support
  
  self.sweepPipelineState = [mrc makePipeline:MTLPixelFormatR8Unorm
                                 pipelineLabel:@"PrefixSumSweep Pipeline"
                                numAttachments:1
                            vertexFunctionName:@"vertexShader"
                          fragmentFunctionName:sumSweepShader];
  
  NSAssert(self.sweepPipelineState, @"sweepPipelineState");
  
#if defined(DEBUG)
  
  // Debug render state to emit (X,Y) for each pixel of render texture
  
//  self.debugRenderXYoffsetTexturePipelineState = [self makePipeline:MTLPixelFormatBGRA8Unorm
//                                                          pipelineLabel:@"Render To XY Pipeline"
//                                                         numAttachments:1
//                                                     vertexFunctionName:@"vertexShader"
//                                                   fragmentFunctionName:@"samplingShaderDebugOutXYCoordinates"];
  
#endif // DEBUG
}

// Render textures initialization
// renderSize : indicates the size of the entire texture containing block by block numbers
// renderFrame : holds textures used while rendering

- (void) setupRenderTextures:(MetalRenderContext*)mrc
                  renderSize:(CGSize)renderSize
                 renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
{
  const BOOL debug = TRUE;
  
  unsigned int width = renderSize.width;
  unsigned int height = renderSize.height;

  const int blockDim = HUFF_BLOCK_DIM;
  
  renderFrame.width = width;
  renderFrame.height = height;
  renderFrame.blockDim = blockDim;
  
  // Texture that holds block order input bytes
  
  {
    id<MTLTexture> txt = [mrc make8bitTexture:CGSizeMake(width, height) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
    
    renderFrame.inputBlockOrderTexture = txt;
    
    if (debug) {
      NSLog(@"input       : texture %3d x %3d", (int)txt.width, (int)txt.height);
    }
  }

  // Texture that holds block order input bytes
  
  {
    id<MTLTexture> txt = [mrc make8bitTexture:CGSizeMake(width, height) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
    
    renderFrame.outputBlockOrderTexture = txt;
    
    if (debug) {
      NSLog(@"output      : texture %3d x %3d", (int)txt.width, (int)txt.height);
    }
  }
  
  // FIXME: pass int recursion depth into reduction and sweep shader (stack on N of these)
  
  renderFrame.reduceTextures = [NSMutableArray array];
  renderFrame.sweepTextures = [NSMutableArray array];
  
  int textureWidth = width;
  int textureHeight = height;
  
  // Create a single output texture at 1/2 the height
  
  int pot = 1;
  
  const int maxNumReductions = log2(4096);
  
  for (int i = 0; i < maxNumReductions; i++) {
    if (textureWidth == textureHeight) {
      // square texture to rect of 1/2 the width
      textureWidth = textureWidth / 2;
    } else {
      // rect texture to square that is 1/2 the height
      textureHeight = textureHeight / 2;
    }
    
    if (textureWidth == 1 && textureHeight == 1) {
      break;
    }
    
    int reduceStep = i + 1;
    
    if (debug) {
    NSLog(@"reduction %d : texture %3d x %3d : POT %d", reduceStep, textureWidth, textureHeight, pot);
    }
    
    id<MTLTexture> txt;
    
    txt = [mrc make8bitTexture:CGSizeMake(textureWidth, textureHeight) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];

    [renderFrame.reduceTextures addObject:txt];
    
    if (debug) {
    NSLog(@"sweep     %d : texture %3d x %3d : POT %d", reduceStep, textureWidth, textureHeight, pot);
    }
    
    txt = [mrc make8bitTexture:CGSizeMake(textureWidth, textureHeight) bytes:NULL usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
    
    [renderFrame.sweepTextures addObject:txt];
    
    // FIXME: allocate target dimension buffer to pass in POT ?
    
    pot *= 2;
  }
  
  // One last texture is uninitialized so it is all zeros
  
  {
    id<MTLTexture> txt;
    
    assert(textureWidth == 1);
    assert(textureHeight == 1);
    
    txt = [mrc make8bitTexture:CGSizeMake(textureWidth, textureHeight) bytes:NULL usage:MTLTextureUsageShaderRead];
    
    renderFrame.zeroTexture = txt;
    
    if (debug) {
    NSLog(@"zeros : texture %d x %d", textureWidth, textureHeight);
    }
  }
  
  // Dimensions passed into shaders
  
  renderFrame.renderTargetDimensionsAndBlockDimensionsUniform = [mrc.device newBufferWithLength:sizeof(RenderTargetDimensionsAndBlockDimensionsUniform) options:MTLResourceStorageModeShared];
  
  {
    RenderTargetDimensionsAndBlockDimensionsUniform *ptr = renderFrame.renderTargetDimensionsAndBlockDimensionsUniform.contents;
    ptr->width = width;
    ptr->height = height;
    ptr->blockWidth = width;
    ptr->blockHeight = height;
  }
  
  return;
}

#if defined(DEBUG)

/*

// Implements debug render operation where (X,Y) values are written to a buffer

- (void) debugRenderXYToTexture:(id<MTLCommandBuffer>)commandBuffer
                    renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
{
  // Debug render XY values out as 2 12 bit values
  
  MTLRenderPassDescriptor *debugRenderXYToTexturePassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if(debugRenderXYToTexturePassDescriptor != nil)
  {
    id<MTLTexture> texture0 = renderFrame.debugRenderXYoffsetTexture;
    
    debugRenderXYToTexturePassDescriptor.colorAttachments[0].texture = texture0;
    debugRenderXYToTexturePassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    debugRenderXYToTexturePassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    // Create a render command encoder so we can render into something
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:debugRenderXYToTexturePassDescriptor];
    renderEncoder.label = @"debugRenderToXYCommandEncoder";
    
    [renderEncoder pushDebugGroup: @"debugRenderToXY"];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, texture0.width, texture0.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.debugRenderXYoffsetTexturePipelineState];
    
    [renderEncoder setVertexBuffer:self.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:renderFrame.indexesTexture
                              atIndex:AAPLTextureIndexes];
    [renderEncoder setFragmentTexture:renderFrame.lutiOffsetsTexture
                              atIndex:AAPLTextureLutOffsets];
    [renderEncoder setFragmentTexture:renderFrame.lutsTexture
                              atIndex:AAPLTextureLuts];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:self.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // debugRenderToIndexes
    
    [renderEncoder endEncoding];
  }
}

*/

#endif // DEBUG

// Prefix sum render operation, this executes a single reduce step

// FIXME: no reason to pass render frame to these methods since they accept textures directly

- (void) renderPrefixSumReduce:(MetalRenderContext*)mrc
                 commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                   renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
                  inputTexture:(id<MTLTexture>)inputTexture
                 outputTexture:(id<MTLTexture>)outputTexture
                         level:(int)level
{
  const BOOL debug = TRUE;
  
  if (debug) {
    NSLog(@"renderPrefixSumReduce inputTexture: %4d x %4d and outputTexture: %4d x %4d at level %d", (int)inputTexture.width, (int)inputTexture.height, (int)outputTexture.width, (int)outputTexture.height, level);
  }
  
#if defined(DEBUG)
  assert(mrc);
  assert(commandBuffer);
  assert(renderFrame);
#endif // DEBUG
  
  MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (renderPassDescriptor != nil)
  {
#if defined(DEBUG)
    // Output of a square reduce is 1/2 the width
    // Output of a rect reduce is 1/2 the height
    
    if (inputTexture.width == inputTexture.height) {
      // reduce square
      assert((inputTexture.width / 2) == outputTexture.width);
      assert(inputTexture.height == outputTexture.height);
    } else {
      // reduce rect
      assert(inputTexture.width == outputTexture.width);
      assert((inputTexture.height / 2) == outputTexture.height);
    }
#endif // DEBUG
    
    renderPassDescriptor.colorAttachments[0].texture = outputTexture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
#if defined(DEBUG)
    assert(renderEncoder);
#endif // DEBUG

    NSString *debugLabel = [NSString stringWithFormat:@"PrefixSumReduce%d", level];
    renderEncoder.label = debugLabel;
    [renderEncoder pushDebugGroup:debugLabel];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, outputTexture.width, outputTexture.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.reducePipelineState];
    
    [renderEncoder setVertexBuffer:mrc.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:inputTexture atIndex:0];
    
    [renderEncoder setFragmentBuffer:renderFrame.renderTargetDimensionsAndBlockDimensionsUniform
                              offset:0
                             atIndex:0];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:mrc.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
  }
}

// Prefix sum sweep, this executes a single sweep step

- (void) renderPrefixSumSweep:(MetalRenderContext*)mrc
                commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
                inputTexture1:(id<MTLTexture>)inputTexture1
                inputTexture2:(id<MTLTexture>)inputTexture2
                outputTexture:(id<MTLTexture>)outputTexture
                        level:(int)level
{
  const BOOL debug = TRUE;
  
  if (debug) {
    NSLog(@"renderPrefixSumSweep inputTexture1: %4d x %4d and inputTexture2: %4d x %4d and outputTexture: %4d x %4d at level %d", (int)inputTexture1.width, (int)inputTexture1.height, (int)inputTexture2.width, (int)inputTexture2.height, (int)outputTexture.width, (int)outputTexture.height, level);
  }
  
#if defined(DEBUG)
  assert(mrc);
  assert(commandBuffer);
  assert(renderFrame);
#endif // DEBUG
  
  MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
  
  if (renderPassDescriptor != nil)
  {
#if defined(DEBUG)
    // Output of a square reduce is 1/2 the width
    // Output of a rect reduce is 1/2 the height
    
    assert(inputTexture2.width == outputTexture.width);
    assert(inputTexture2.height == outputTexture.height);
    
    if (inputTexture1.width == inputTexture1.height) {
      // square
      assert(inputTexture1.width == outputTexture.width);
      assert((inputTexture1.height * 2) == outputTexture.height);
    } else {
      // rect
      assert((inputTexture1.width * 2) == outputTexture.width);
      assert(inputTexture1.height == outputTexture.height);
    }
#endif // DEBUG
    
    renderPassDescriptor.colorAttachments[0].texture = outputTexture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
#if defined(DEBUG)
    assert(renderEncoder);
#endif // DEBUG
    
    NSString *debugLabel = [NSString stringWithFormat:@"PrefixSumSweep%d", level];
    renderEncoder.label = debugLabel;
    [renderEncoder pushDebugGroup:debugLabel];
    
    // Set the region of the drawable to which we'll draw.
    
    MTLViewport mtlvp = {0.0, 0.0, outputTexture.width, outputTexture.height, -1.0, 1.0 };
    [renderEncoder setViewport:mtlvp];
    
    [renderEncoder setRenderPipelineState:self.sweepPipelineState];
    
    [renderEncoder setVertexBuffer:mrc.identityVerticesBuffer
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices];
    
    [renderEncoder setFragmentTexture:inputTexture1 atIndex:0];
    [renderEncoder setFragmentTexture:inputTexture2 atIndex:1];
    
    [renderEncoder setFragmentBuffer:renderFrame.renderTargetDimensionsAndBlockDimensionsUniform
                              offset:0
                             atIndex:0];
    
    // Draw the 3 vertices of our triangle
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:mrc.identityNumVertices];
    
    [renderEncoder popDebugGroup]; // RenderToTexture
    
    [renderEncoder endEncoding];
  }
}

// Process input texture data written in block by block order from
// the frame.inputBlockOrderTexture, generate parallel prefix sum
// and then write the result frame.outputBlockOrderTexture

- (void) renderPrefixSum:(MetalRenderContext*)mrc
           commandBuffer:(id<MTLCommandBuffer>)commandBuffer
             renderFrame:(MetalPrefixSumRenderFrame*)renderFrame
{
  const BOOL debug = TRUE;
  
  // Determine how to recurse based on configuration in renderFrame
  
#if defined(DEBUG)
  assert(renderFrame.reduceTextures.count == renderFrame.sweepTextures.count);
#endif // DEBUG
  
  int maxStep = (int) renderFrame.reduceTextures.count;
  
  if (debug) {
    NSLog(@"num reduce/sweep steps %3d", maxStep);
  }
  
  {
    id<MTLTexture> inputTexture = renderFrame.inputBlockOrderTexture;
    
    for (int i = 0; i < maxStep; i++) {
      id<MTLTexture> outputTexture = renderFrame.reduceTextures[i];
      
      if (debug) {
        NSLog(@"reduce step   : %d uses reduceTextures[%2d] and reduceTextures[%2d]", i+1, i-1, i);        
        NSLog(@"inputTexture  : %4d x %4d", (int)inputTexture.width, (int)inputTexture.height);
        NSLog(@"outputTexture : %4d x %4d", (int)outputTexture.width, (int)outputTexture.height);
      }
      
      [self renderPrefixSumReduce:mrc
                    commandBuffer:commandBuffer
                      renderFrame:renderFrame
                     inputTexture:inputTexture
                    outputTexture:outputTexture
                            level:i+1];
      
      inputTexture = outputTexture;
    }
  }

  // Once all reduce operations have been completed the down sweep can be processed
  
  {
    int i = maxStep - 1;
    
    id<MTLTexture> inputTexture1 = renderFrame.zeroTexture;
    id<MTLTexture> inputTexture2;
    
    for ( ; i >= 0; i--) {
      // inputTexture1 is zeros or output of previous sweep
      
      // inputTexture2 is the reduce output for this level
      inputTexture2 = renderFrame.reduceTextures[i];
      
      id<MTLTexture> outputTexture = renderFrame.sweepTextures[i];
      
      if (debug) {
        NSLog(@"sweep         : step %2d uses reduceTextures[%2d] sweepTextures[%2d]", i+1, i, i);
        NSLog(@"inputTexture1 : %4d x %4d", (int)inputTexture1.width, (int)inputTexture1.height);
        NSLog(@"inputTexture2 : %4d x %4d", (int)inputTexture2.width, (int)inputTexture2.height);
        NSLog(@"outputTexture : %4d x %4d", (int)outputTexture.width, (int)outputTexture.height);
      }
      
      [self renderPrefixSumSweep:mrc
                   commandBuffer:commandBuffer
                     renderFrame:renderFrame
                   inputTexture1:inputTexture1
                   inputTexture2:inputTexture2
                   outputTexture:outputTexture
                           level:i+1];

      inputTexture1 = outputTexture;
    }
    
    // A final down sweep adds values to the original input
    
    id<MTLTexture> outputTexture = renderFrame.outputBlockOrderTexture;
    inputTexture2 = renderFrame.inputBlockOrderTexture;
    
    if (debug) {
      NSLog(@"final sweep");
      NSLog(@"inputTexture1 : %4d x %4d", (int)inputTexture1.width, (int)inputTexture1.height);
      NSLog(@"inputTexture2 : %4d x %4d", (int)inputTexture2.width, (int)inputTexture2.height);
      NSLog(@"outputTexture : %4d x %4d", (int)outputTexture.width, (int)outputTexture.height);
    }
    
    [self renderPrefixSumSweep:mrc
                 commandBuffer:commandBuffer
                   renderFrame:renderFrame
                 inputTexture1:inputTexture1
                 inputTexture2:inputTexture2
                 outputTexture:outputTexture
                         level:0];
  }
  
  return;
}

@end
