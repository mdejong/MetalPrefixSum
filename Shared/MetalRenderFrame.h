//
//  MetalRenderFrame.h
//
//  Copyright 2016 Mo DeJong.
//
//  See LICENSE for terms.
//
//  This object contains references to Metal buffers that implement decoding
//  and rendering of encoded movie data stored in a file.

//@import MetalKit;
#include <MetalKit/MetalKit.h>

@class MetalRenderContext;

@interface MetalRenderFrame : NSObject

// This read locked property is set to TRUE while the frame is being
// read by the GPU. Note that multiple GPU reads will not happen with
// the same render frame.

#if defined(DEBUG)
@property (atomic, assign) BOOL isReadLocked;
#endif // DEBUG

@property (nonatomic, retain) MetalRenderContext * mrc;

@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;

@property (nonatomic, assign) int blockWidth;
@property (nonatomic, assign) int blockHeight;

@property (nonatomic, retain) id<MTLTexture> indexesTexture;
@property (nonatomic, retain) id<MTLTexture> lutiOffsetsTexture;
@property (nonatomic, retain) id<MTLTexture> lutsTexture;

@property (nonatomic, retain) id<MTLTexture> renderTexture;

@property (nonatomic, assign) uint32_t bgraAdler;

#if defined(DEBUG)

@property (nonatomic, retain) id<MTLTexture> debugRenderXYoffsetTexture;
@property (nonatomic, retain) id<MTLTexture> debugRenderIndexesTexture;
@property (nonatomic, retain) id<MTLTexture> debugRenderLutiTexture;

#endif // DEBUG

// This combined slices texture contains BGRA pixels that contain 4 INDEX values.
// The individual rendered textures are blitted into this texture to
// combine them together before flattening out to an 8 bit output texture.

@property (nonatomic, retain) id<MTLTexture> renderCombinedSlicesTexture;

// These Metal textures hold fragment shader output which is then blitted
// into renderCombinedSlicesTexture.

@property (nonatomic, retain) id<MTLTexture> render12Zeros;

@property (nonatomic, retain) id<MTLTexture> render12C0R0;
@property (nonatomic, retain) id<MTLTexture> render12C1R0;
@property (nonatomic, retain) id<MTLTexture> render12C2R0;
@property (nonatomic, retain) id<MTLTexture> render12C3R0;

@property (nonatomic, retain) id<MTLTexture> render12C0R1;
@property (nonatomic, retain) id<MTLTexture> render12C1R1;
@property (nonatomic, retain) id<MTLTexture> render12C2R1;
@property (nonatomic, retain) id<MTLTexture> render12C3R1;

@property (nonatomic, retain) id<MTLTexture> render12C0R2;
@property (nonatomic, retain) id<MTLTexture> render12C1R2;
@property (nonatomic, retain) id<MTLTexture> render12C2R2;
@property (nonatomic, retain) id<MTLTexture> render12C3R2;

@property (nonatomic, retain) id<MTLTexture> render12C0R3;
@property (nonatomic, retain) id<MTLTexture> render12C1R3;
@property (nonatomic, retain) id<MTLTexture> render12C2R3;
@property (nonatomic, retain) id<MTLTexture> render12C3R3;

@property (nonatomic, retain) id<MTLTexture> render16C0;
@property (nonatomic, retain) id<MTLTexture> render16C1;
@property (nonatomic, retain) id<MTLTexture> render16C2;
@property (nonatomic, retain) id<MTLTexture> render16C3;

// Buffers passed into shaders

@property (nonatomic, retain) id<MTLBuffer> renderTargetDimensionsAndBlockDimensionsUniform;

// The large Metal buffer where huffman codes are stored

@property (nonatomic, retain) id<MTLBuffer> huffBuff;

// The Metal buffer where huffman symbol lookup table is stored

@property (nonatomic, retain) id<MTLBuffer> huffSymbolTable1;
@property (nonatomic, retain) id<MTLBuffer> huffSymbolTable2;

@property (nonatomic, retain) id<MTLBuffer> blockStartBitOffsets;

@end
