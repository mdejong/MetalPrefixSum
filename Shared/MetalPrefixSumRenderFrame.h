//
//  MetalPrefixSumRenderFrame.h
//
//  Copyright 2016 Mo DeJong.
//
//  See LICENSE for terms.
//
//  This object contains references to Metal buffers that implement a
//  parallel prefix sum calculation implemented with a Metal fragment shader.

//@import MetalKit;
#include <MetalKit/MetalKit.h>

@class MetalPrefixSumRenderContext;

@interface MetalPrefixSumRenderFrame : NSObject

//@property (nonatomic, weak) MetalPrefixSumRenderContext * mrc;

// A prefix sum only works with POT, so the width and height
// must be properly set so that width x height is always
// in terms of a multiple of blockDim.

@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;

@property (nonatomic, assign) NSUInteger blockDim;

// The original input image order in image order

//@property (nonatomic, retain) id<MTLTexture> inputImageOrderTexture;

// The original input image order in block order

@property (nonatomic, retain) id<MTLTexture> inputBlockOrderTexture;
@property (nonatomic, retain) id<MTLTexture> outputBlockOrderTexture;

// As inputBlockOrderTexture is reduced, a series of output
// textures is needed to buffer data. Note that the final
// reduce texture is not actually rendered, it will contain
// only zeros.

@property (nonatomic, retain) NSMutableArray *reduceTextures;
@property (nonatomic, retain) NSMutableArray *sweepTextures;
@property (nonatomic, retain) id<MTLTexture> zeroTexture;

#if defined(DEBUG)

//@property (nonatomic, retain) id<MTLTexture> debugRenderXYoffsetTexture;

#endif // DEBUG

// Buffers passed into shaders

@property (nonatomic, retain) id<MTLBuffer> renderTargetDimensionsAndBlockDimensionsUniform;

@end
