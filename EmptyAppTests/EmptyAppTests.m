//
//  EmptyAppTests.m
//  EmptyAppTests
//
//  Created by Mo DeJong on 8/26/18.
//  Copyright © 2018 Apple. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "MetalRenderContext.h"
#import "MetalPrefixSumRenderContext.h"
#import "MetalPrefixSumRenderFrame.h"

#import "prefix_sum.h"

#import "Util.h"

@interface EmptyAppTests : XCTestCase

@end

@implementation EmptyAppTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

// Query a texture that contains byte values and return in
// a buffer of uint8_t typed values.

+ (NSData*) getTextureBytes:(id<MTLTexture>)texture
{
  int width = (int) texture.width;
  int height = (int) texture.height;
  
  NSMutableData *mFramebuffer = [NSMutableData dataWithLength:width*height*sizeof(uint8_t)];
  
  [texture getBytes:(void*)mFramebuffer.mutableBytes
        bytesPerRow:width*sizeof(uint8_t)
      bytesPerImage:width*height*sizeof(uint8_t)
         fromRegion:MTLRegionMake2D(0, 0, width, height)
        mipmapLevel:0
              slice:0];
  
  return [NSData dataWithData:mFramebuffer];
}

// Dump texture that contains simple grayscale pixel values

- (void) dump8BitTexture:(id<MTLTexture>)outTexture
                   label:(NSString*)label
{
  // Copy texture data into debug framebuffer, note that this include 2x scale
  
  int width = (int) outTexture.width;
  int height = (int) outTexture.height;
  
  NSData *bytesData = [self.class getTextureBytes:outTexture];
  uint8_t *bytesPtr = (uint8_t*) bytesData.bytes;
  
  // Dump output words as bytes
  
  if ((1)) {
    fprintf(stdout, "%s as bytes\n", [label UTF8String]);
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t v = bytesPtr[offset];
        fprintf(stdout, "%3d ", v);
      }
      fprintf(stdout, "\n");
    }
    
    fprintf(stdout, "done\n");
  }
}

// Return contents of 8 bit texture as NSArray number values

- (NSArray*) arrayFrom8BitTexture:(id<MTLTexture>)outTexture
{
  // Copy texture data into debug framebuffer, note that this include 2x scale
  
  int width = (int) outTexture.width;
  int height = (int) outTexture.height;
  
  NSData *bytesData = [self.class getTextureBytes:outTexture];
  uint8_t *bytesPtr = (uint8_t*) bytesData.bytes;
  
  // Dump output words as bytes
  
  NSMutableArray *mArr = [NSMutableArray array];
  
  {
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t v = bytesPtr[offset];
        
        [mArr addObject:@(v)];
      }
    }
  }
  
  return mArr;
}

// Adaptor that fills a texture from byte values in an NSArray

- (void) fill8BitTexture:(id<MTLTexture>)texture
              bytesArray:(NSArray*)bytesArray
                     mrc:(MetalRenderContext*)mrc
{
  int width = (int) texture.width;
  int height = (int) texture.height;
  
  NSMutableData *mData = [NSMutableData data];
  [mData setLength:width*height*sizeof(uint8_t)];
  uint8_t *bytePtr = mData.mutableBytes;
  
  for ( int row = 0; row < height; row++ ) {
    for ( int col = 0; col < width; col++ ) {
      int offset = (row * width) + col;
      NSNumber *byteNum = bytesArray[offset];
      uint8_t bVal = (uint8_t) [byteNum unsignedCharValue];
      bytePtr[offset] = bVal;
    }
  }
  
  [mrc fill8bitTexture:texture bytes:bytePtr];
}

- (void)testMetalReduce4x4To2x4 {
  NSArray *expectedInputArr = @[
                               @0, @1, @2, @3,
                               @4, @5, @6, @7,
                               @8, @9, @10, @11,
                               @12, @13, @14, @15
                               ];
  
  NSArray *expectedRenderedArr = @[
                                  @1, @5,
                                  @9, @13,
                                  @17, @21,
                                  @25, @29
                                  ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];

  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(4, 4);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> sameDimTargetTexture = (id<MTLTexture>) mpsrf.sweepTextures[0];
  
  XCTAssert(outputTexture.width == 2);
  XCTAssert(outputTexture.height == 4);
  
  // fill inputTexture

  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture:inputTexture outputTexture:outputTexture sameDimTargetTexture:sameDimTargetTexture level:1];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];

  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
  [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  if (dump) {
  [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }

  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

- (void)testMetalReduce2x4To2x2 {
  NSArray *expectedInputArr = @[
                               @(0 + 1), @(2 + 3),
                               @(4 + 5), @(6 + 7),
                               @(8 + 9), @(10 + 11),
                               @(12 + 13), @(14 + 15)
                               ];
  
  NSArray *expectedRenderedArr = @[
                                  @(1+5),   @(9+13),
                                  @(17+21), @(25+29)
                                  ];

  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(2, 4);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> sameDimTargetTexture = (id<MTLTexture>) mpsrf.sweepTextures[0];
  
  XCTAssert(outputTexture.width == 2);
  XCTAssert(outputTexture.height == 2);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture:inputTexture outputTexture:outputTexture sameDimTargetTexture:sameDimTargetTexture level:1];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

- (void)testMetalReduce2x4To2x2Ident1 {
  // Starting with ident input at 4x4 [1, 2, 3, 4 ..., 16]
  
  NSArray *expectedInputArr = @[
                                @(3), @(7),
                                @(11), @(15),
                                @(19), @(23),
                                @(27), @(31)
                                ];
  
  NSArray *expectedRenderedArr = @[
                                   @(10), @(26),
                                   @(42), @(58)
                                   ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(2, 4);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> sameDimTargetTexture = (id<MTLTexture>) mpsrf.sweepTextures[0];
  
  XCTAssert(outputTexture.width == 2);
  XCTAssert(outputTexture.height == 2);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture:inputTexture outputTexture:outputTexture sameDimTargetTexture:sameDimTargetTexture level:1];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

// 4x4 -> 2x4 -> 2x2 but only do the second render to 2x2

- (void)testMetalReduce2x4To2x2Ident2 {
  // Starting with ident input at 4x4 [1, 2, 3, 4 ..., 16]
  
  NSArray *expectedInputArr = @[
                                @(3), @(7),
                                @(11), @(15),
                                @(19), @(23),
                                @(27), @(31)
                                ];
  
  NSArray *expectedRenderedArr = @[
                                   @(10), @(26),
                                   @(42), @(58)
                                   ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(4, 4);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[1];
  id<MTLTexture> sameDimTargetTexture = (id<MTLTexture>) mpsrf.sweepTextures[1];
  
  XCTAssert(inputTexture.width == 2);
  XCTAssert(inputTexture.height == 4);
  
  XCTAssert(outputTexture.width == 2);
  XCTAssert(outputTexture.height == 2);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Reduce second step
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture:inputTexture outputTexture:outputTexture sameDimTargetTexture:sameDimTargetTexture level:2];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

- (void)testMetalReduce2x2To1x2 {
  NSArray *expectedInputArr = @[
                               @(1+5),   @(9+13),
                               @(17+21), @(25+29)
                               ];
  
  NSArray *expectedRenderedArr = @[
                                  @(1+5+9+13),
                                  @(17+21+25+29)
                                  ];

  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(2, 2);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> sameDimTargetTexture = (id<MTLTexture>) mpsrf.sweepTextures[0];
  
  XCTAssert(outputTexture.width == 1);
  XCTAssert(outputTexture.height == 2);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture:inputTexture outputTexture:outputTexture sameDimTargetTexture:sameDimTargetTexture level:1];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTextureD1"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTextureD1"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

//- (void)testPerformanceExample {
//    // This is an example of a performance test case.
//    [self measureBlock:^{
//        // Put the code you want to measure the time of here.
//    }];
//}

// Test 32 x 32 input case that gets reduced down to 16x32

- (void)testMetalReduce32x32To16x32 {
  NSMutableArray *expectedInputArr = [NSMutableArray array];
  
  {
    int width = 32;
    int height = 32;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = offset & 0xFF;
        [expectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  // Reduce 32x32 down to 16x32
  
  NSMutableData *expectedInputData = [Util bytesArrayToData:expectedInputArr];
  NSMutableData *expectedRenderedData = [NSMutableData dataWithLength:expectedInputData.length/2];
  
  PrefixSum_reduce((uint8_t*)expectedInputData.bytes, (int)expectedInputData.length,
                   (uint8_t*)expectedRenderedData.bytes, (int)expectedRenderedData.length);
  
  // Convert prefix sum reduction back to NSArray
  
  NSArray *expectedRenderedArr = [Util byteDataToArray:expectedRenderedData];
  
  {
    int width = 16;
    int height = 32;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        if (offset == 58) {
          offset = 58;
        }
        
        uint8_t *ptr = (uint8_t *) expectedRenderedData.bytes;
        int sumByte = ptr[offset];
        
        if (offset == 58) {
          offset = 58;
        }
        
      }
    }
  }
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(32, 32);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> sameDimTargetTexture = (id<MTLTexture>) mpsrf.sweepTextures[0];
  
  XCTAssert(outputTexture.width == 16);
  XCTAssert(outputTexture.height == 32);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture:inputTexture outputTexture:outputTexture sameDimTargetTexture:sameDimTargetTexture level:1];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTextureD1"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTextureD1"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
  
  {
    int width = 16;
    int height = 32;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        NSNumber *expectedNum = expectedRenderedArr[offset];
        NSNumber *renderedNum = renderedArr[offset];
        
        BOOL same = [renderedNum isEqualToNumber:expectedNum];
        
        if (!same) {
          XCTAssert(FALSE, @"!same %d != %d at offset %d", [renderedNum unsignedIntValue], [expectedNum unsignedIntValue], offset);
        }
      }
    }
  }

}


// Test 16 x 32 input case that gets reduced down to 16x16

- (void)testMetalReduce16x32To16x16 {
  NSMutableArray *expectedInputArr = [NSMutableArray array];
  
  {
    int width = 16;
    int height = 32;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = offset & 0xFF;
        [expectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  NSMutableData *expectedInputData = [Util bytesArrayToData:expectedInputArr];
  NSMutableData *expectedRenderedData = [NSMutableData dataWithLength:expectedInputData.length/2];
  
  PrefixSum_reduce((uint8_t*)expectedInputData.bytes, (int)expectedInputData.length,
                   (uint8_t*)expectedRenderedData.bytes, (int)expectedRenderedData.length);
  
  // Convert prefix sum reduction back to NSArray
  
  NSArray *expectedRenderedArr = [Util byteDataToArray:expectedRenderedData];
  
  {
    int width = 16;
    int height = 16;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        if (offset == 58) {
          offset = 58;
        }
        
        uint8_t *ptr = (uint8_t *) expectedRenderedData.bytes;
        int sumByte = ptr[offset];
        
        if (offset == 58) {
          offset = 58;
        }
        
      }
    }
  }
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(16, 32);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> sameDimTargetTexture = (id<MTLTexture>) mpsrf.sweepTextures[0];
  
  XCTAssert(outputTexture.width == 16);
  XCTAssert(outputTexture.height == 16);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture:inputTexture outputTexture:outputTexture sameDimTargetTexture:sameDimTargetTexture level:1];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTextureD1"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTextureD1"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
  
  {
    int width = 16;
    int height = 16;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        NSNumber *expectedNum = expectedRenderedArr[offset];
        NSNumber *renderedNum = renderedArr[offset];
        
        BOOL same = [renderedNum isEqualToNumber:expectedNum];
        
        if (!same) {
          XCTAssert(FALSE, @"!same %d != %d at offset %d", [renderedNum unsignedIntValue], [expectedNum unsignedIntValue], offset);
        }
      }
    }
  }
  
}


// Test 16 x 16 input case that gets reduced down to 8x16

- (void)testMetalReduce16x16To8x16 {
  NSMutableArray *expectedInputArr = [NSMutableArray array];
  
  {
    int width = 16;
    int height = 16;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = offset & 0xFF;
        [expectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  NSMutableData *expectedInputData = [Util bytesArrayToData:expectedInputArr];
  NSMutableData *expectedRenderedData = [NSMutableData dataWithLength:expectedInputData.length/2];
  
  PrefixSum_reduce((uint8_t*)expectedInputData.bytes, (int)expectedInputData.length,
                   (uint8_t*)expectedRenderedData.bytes, (int)expectedRenderedData.length);
  
  // Convert prefix sum reduction back to NSArray
  
  NSArray *expectedRenderedArr = [Util byteDataToArray:expectedRenderedData];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(16, 16);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> sameDimTargetTexture = (id<MTLTexture>) mpsrf.sweepTextures[0];
  
  XCTAssert(outputTexture.width == 8);
  XCTAssert(outputTexture.height == 16);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture:inputTexture outputTexture:outputTexture sameDimTargetTexture:sameDimTargetTexture level:1];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTextureD1"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTextureD1"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
  
  {
    int width = 8;
    int height = 16;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        NSNumber *expectedNum = expectedRenderedArr[offset];
        NSNumber *renderedNum = renderedArr[offset];
        
        BOOL same = [renderedNum isEqualToNumber:expectedNum];
        
        if (!same) {
          XCTAssert(FALSE, @"!same %d != %d at offset %d", [renderedNum unsignedIntValue], [expectedNum unsignedIntValue], offset);
        }
      }
    }
  }
  
}

// Test 16 x 16 input case that gets reduced down to 8x16

- (void)testMetalReduce8x16To8x8 {
  NSMutableArray *expectedInputArr = [NSMutableArray array];
  
  {
    int width = 8;
    int height = 16;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = offset & 0xFF;
        [expectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  NSMutableData *expectedInputData = [Util bytesArrayToData:expectedInputArr];
  NSMutableData *expectedRenderedData = [NSMutableData dataWithLength:expectedInputData.length/2];
  
  PrefixSum_reduce((uint8_t*)expectedInputData.bytes, (int)expectedInputData.length,
                   (uint8_t*)expectedRenderedData.bytes, (int)expectedRenderedData.length);
  
  // Convert prefix sum reduction back to NSArray
  
  NSArray *expectedRenderedArr = [Util byteDataToArray:expectedRenderedData];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(8, 16);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> sameDimTargetTexture = (id<MTLTexture>) mpsrf.sweepTextures[0];
  
  XCTAssert(outputTexture.width == 8);
  XCTAssert(outputTexture.height == 8);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture:inputTexture outputTexture:outputTexture sameDimTargetTexture:sameDimTargetTexture level:1];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTextureD1"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTextureD1"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
  
  {
    int width = 8;
    int height = 8;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        NSNumber *expectedNum = expectedRenderedArr[offset];
        NSNumber *renderedNum = renderedArr[offset];
        
        BOOL same = [renderedNum isEqualToNumber:expectedNum];
        
        if (!same) {
          XCTAssert(FALSE, @"!same %d != %d at offset %d", [renderedNum unsignedIntValue], [expectedNum unsignedIntValue], offset);
        }
      }
    }
  }
  
}

// Test 8x8 input case that gets reduced down to 4x8

- (void)testMetalReduce8x8To4x8 {
  NSMutableArray *expectedInputArr = [NSMutableArray array];
  
  {
    int width = 8;
    int height = 8;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = offset & 0xFF;
        [expectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  NSMutableData *expectedInputData = [Util bytesArrayToData:expectedInputArr];
  NSMutableData *expectedRenderedData = [NSMutableData dataWithLength:expectedInputData.length/2];
  
  PrefixSum_reduce((uint8_t*)expectedInputData.bytes, (int)expectedInputData.length,
                   (uint8_t*)expectedRenderedData.bytes, (int)expectedRenderedData.length);
  
  // Convert prefix sum reduction back to NSArray
  
  NSArray *expectedRenderedArr = [Util byteDataToArray:expectedRenderedData];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(8, 8);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> sameDimTargetTexture = (id<MTLTexture>) mpsrf.sweepTextures[0];
  
  XCTAssert(outputTexture.width == 4);
  XCTAssert(outputTexture.height == 8);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture:inputTexture outputTexture:outputTexture sameDimTargetTexture:sameDimTargetTexture level:1];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTextureD1"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTextureD1"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
  
  {
    int width = 4;
    int height = 8;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        NSNumber *expectedNum = expectedRenderedArr[offset];
        NSNumber *renderedNum = renderedArr[offset];
        
        BOOL same = [renderedNum isEqualToNumber:expectedNum];
        
        if (!same) {
          XCTAssert(FALSE, @"!same %d != %d at offset %d", [renderedNum unsignedIntValue], [expectedNum unsignedIntValue], offset);
        }
      }
    }
  }
  
}

// Test 4x8 input case that gets reduced down to 4x4

- (void)testMetalReduce4x8To4x4 {
  NSMutableArray *expectedInputArr = [NSMutableArray array];
  
  {
    int width = 4;
    int height = 8;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = offset & 0xFF;
        [expectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  NSMutableData *expectedInputData = [Util bytesArrayToData:expectedInputArr];
  NSMutableData *expectedRenderedData = [NSMutableData dataWithLength:expectedInputData.length/2];
  
  PrefixSum_reduce((uint8_t*)expectedInputData.bytes, (int)expectedInputData.length,
                   (uint8_t*)expectedRenderedData.bytes, (int)expectedRenderedData.length);
  
  // Convert prefix sum reduction back to NSArray
  
  NSArray *expectedRenderedArr = [Util byteDataToArray:expectedRenderedData];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(4, 8);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> sameDimTargetTexture = (id<MTLTexture>) mpsrf.sweepTextures[0];
  
  XCTAssert(outputTexture.width == 4);
  XCTAssert(outputTexture.height == 4);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture:inputTexture outputTexture:outputTexture sameDimTargetTexture:sameDimTargetTexture level:1];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTextureD1"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTextureD1"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
  
  {
    int width = 4;
    int height = 4;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        NSNumber *expectedNum = expectedRenderedArr[offset];
        NSNumber *renderedNum = renderedArr[offset];
        
        BOOL same = [renderedNum isEqualToNumber:expectedNum];
        
        if (!same) {
          XCTAssert(FALSE, @"!same %d != %d at offset %d", [renderedNum unsignedIntValue], [expectedNum unsignedIntValue], offset);
        }
      }
    }
  }
  
}

// Sweep up to 1x2

- (void)testMetalSweep1x1to1x2 {
  NSArray *expectedInputArr1 = @[
                               @(0)
                               ];
  
  NSArray *expectedInputArr2 = @[
                               @(1),
                               @(2)
                               ];
  
  NSArray *expectedRenderedArr = @[
                                  @(0),
                                  @(1)
                                  ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(2, 2);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture1 = (id<MTLTexture>) mpsrf.zeroTexture;
  id<MTLTexture> inputTexture2 = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.sweepTextures[0];
  
  XCTAssert(outputTexture.width == 1);
  XCTAssert(outputTexture.height == 2);
  
  // fill inputTexture

  [self fill8BitTexture:inputTexture1 bytesArray:expectedInputArr1 mrc:mrc];
  [self fill8BitTexture:inputTexture2 bytesArray:expectedInputArr2 mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
    
  [mpsrc renderPrefixSumSweep:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture1:inputTexture1 inputTexture2:inputTexture2 outputTexture:outputTexture level:1 isExclusive:TRUE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture1 label:@"inputTexture1"];
  }

  if (dump) {
    [self dump8BitTexture:inputTexture2 label:@"inputTexture2"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  {
    NSMutableData *expectedInput1Data = [Util bytesArrayToData:expectedInputArr1];
    NSMutableData *expectedInput2Data = [Util bytesArrayToData:expectedInputArr2];
    
    NSMutableData *expectedRenderedData = [NSMutableData dataWithLength:expectedInput2Data.length];
    
    PrefixSum_downsweep((uint8_t*)expectedInput1Data.bytes, (int)expectedInput1Data.length,
                        (uint8_t*)expectedInput2Data.bytes, (int)expectedInput2Data.length,
                        (uint8_t*)expectedRenderedData.bytes, (int)expectedRenderedData.length);
    
    NSArray *cRenderedArr = [Util byteDataToArray:expectedRenderedData];
    
    XCTAssert([cRenderedArr isEqualToArray:expectedRenderedArr]);
  }

  NSArray *input1Arr = [self arrayFrom8BitTexture:inputTexture1];
  XCTAssert([input1Arr isEqualToArray:expectedInputArr1]);
  
  NSArray *input2Arr = [self arrayFrom8BitTexture:inputTexture2];
  XCTAssert([input2Arr isEqualToArray:expectedInputArr2]);
  
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

// Sweep up to 2x2

- (void)testMetalSweep1x2to2x2 {
  NSArray *expectedInputArr1 = @[
                                        @(0),         @(1)
                                ];
  
  NSArray *expectedInputArr2 = @[
                                @(10), @(20), @(30), @(40)
                                ];
  
  NSArray *expectedRenderedArr = @[
                                  @(0), @(0+10), @(1), @(1+30)
                                  ];

  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(2, 2);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture1 = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> inputTexture2 = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(outputTexture.width == 2);
  XCTAssert(outputTexture.height == 2);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture1 bytesArray:expectedInputArr1 mrc:mrc];
  [self fill8BitTexture:inputTexture2 bytesArray:expectedInputArr2 mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  [mpsrc renderPrefixSumSweep:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture1:inputTexture1 inputTexture2:inputTexture2 outputTexture:outputTexture level:1 isExclusive:TRUE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture1 label:@"inputTexture1"];
  }
  
  if (dump) {
    [self dump8BitTexture:inputTexture2 label:@"inputTexture2"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  {
    NSMutableData *expectedInput1Data = [Util bytesArrayToData:expectedInputArr1];
    NSMutableData *expectedInput2Data = [Util bytesArrayToData:expectedInputArr2];
    
    NSMutableData *expectedRenderedData = [NSMutableData dataWithLength:expectedInput2Data.length];
    
    PrefixSum_downsweep((uint8_t*)expectedInput1Data.bytes, (int)expectedInput1Data.length,
                        (uint8_t*)expectedInput2Data.bytes, (int)expectedInput2Data.length,
                        (uint8_t*)expectedRenderedData.bytes, (int)expectedRenderedData.length);
    
    NSArray *cRenderedArr = [Util byteDataToArray:expectedRenderedData];
    
    XCTAssert([cRenderedArr isEqualToArray:expectedRenderedArr]);
  }
  
  NSArray *input1Arr = [self arrayFrom8BitTexture:inputTexture1];
  XCTAssert([input1Arr isEqualToArray:expectedInputArr1]);
  
  NSArray *input2Arr = [self arrayFrom8BitTexture:inputTexture2];
  XCTAssert([input2Arr isEqualToArray:expectedInputArr2]);
  
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

// Sweep up to 2x4

- (void)testMetalSweep2x2to2x4 {
  NSArray *expectedInputArr1 = @[
                                        @(0),      @(0+10),         @(1),       @(1+30)
                                ];
  
  NSArray *expectedInputArr2 = @[
                                @(10), @(20), @(30), @(40), @(50), @(60), @(70), @(80)
                                ];
  
  NSArray *expectedRenderedArr = @[
                                  @(0), @(10), @(10), @(40), @(1), @(51), @(31), @(31+70)
                                  ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(2, 4);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture1 = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> inputTexture2 = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;

  XCTAssert(inputTexture1.width == 2);
  XCTAssert(inputTexture1.height == 2);
  
  XCTAssert(inputTexture2.width == 2);
  XCTAssert(inputTexture2.height == 4);
  
  XCTAssert(outputTexture.width == 2);
  XCTAssert(outputTexture.height == 4);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture1 bytesArray:expectedInputArr1 mrc:mrc];
  [self fill8BitTexture:inputTexture2 bytesArray:expectedInputArr2 mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  [mpsrc renderPrefixSumSweep:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture1:inputTexture1 inputTexture2:inputTexture2 outputTexture:outputTexture level:1 isExclusive:TRUE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture1 label:@"inputTexture1"];
  }
  
  if (dump) {
    [self dump8BitTexture:inputTexture2 label:@"inputTexture2"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  {
    NSMutableData *expectedInput1Data = [Util bytesArrayToData:expectedInputArr1];
    NSMutableData *expectedInput2Data = [Util bytesArrayToData:expectedInputArr2];
    
    NSMutableData *expectedRenderedData = [NSMutableData dataWithLength:expectedInput2Data.length];
    
    PrefixSum_downsweep((uint8_t*)expectedInput1Data.bytes, (int)expectedInput1Data.length,
                        (uint8_t*)expectedInput2Data.bytes, (int)expectedInput2Data.length,
                        (uint8_t*)expectedRenderedData.bytes, (int)expectedRenderedData.length);
    
    NSArray *cRenderedArr = [Util byteDataToArray:expectedRenderedData];
    
    XCTAssert([cRenderedArr isEqualToArray:expectedRenderedArr]);
  }
  
  NSArray *input1Arr = [self arrayFrom8BitTexture:inputTexture1];
  XCTAssert([input1Arr isEqualToArray:expectedInputArr1]);
  
  NSArray *input2Arr = [self arrayFrom8BitTexture:inputTexture2];
  XCTAssert([input2Arr isEqualToArray:expectedInputArr2]);
  
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

// Sweep up to 4x4

- (void)testMetalSweep2x4to4x4 {
  NSArray *expectedInputArr1 = @[
                                @(0), @(1), @(2), @(3), @(4), @(5), @(6), @(7),
                                ];
  
  NSArray *expectedInputArr2 = @[
                                @(10), @(20), @(30), @(40), @(50), @(60), @(70), @(80),
                                @(90), @(100), @(110), @(120), @(130), @(140), @(150), @(160)
                                ];
  
  NSArray *expectedRenderedArr = @[
                                  // 0 -> (10,20)
                                  @(0), @(10),
                                  // 1 -> (30, 40)
                                  @(1), @(31),
                                  // 2 -> (50, 60)
                                  @(2), @(52),
                                  // 3 -> (70, 80)
                                  @(3), @(73),
                                  // 4 -> (90, 100)
                                  @(4), @(94),
                                  // 5 -> (110, 120)
                                  @(5), @(115),
                                  // 6 -> (130, 140)
                                  @(6), @(136),
                                  // 7 -> (150, 160)
                                  @(7), @(157)
                                  ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(4, 4);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture1 = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> inputTexture2 = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture1.width == 2);
  XCTAssert(inputTexture1.height == 4);
  
  XCTAssert(inputTexture2.width == 4);
  XCTAssert(inputTexture2.height == 4);
  
  XCTAssert(outputTexture.width == 4);
  XCTAssert(outputTexture.height == 4);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture1 bytesArray:expectedInputArr1 mrc:mrc];
  [self fill8BitTexture:inputTexture2 bytesArray:expectedInputArr2 mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  [mpsrc renderPrefixSumSweep:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture1:inputTexture1 inputTexture2:inputTexture2 outputTexture:outputTexture level:1 isExclusive:TRUE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture1 label:@"inputTexture1"];
  }
  
  if (dump) {
    [self dump8BitTexture:inputTexture2 label:@"inputTexture2"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  {
    NSMutableData *expectedInput1Data = [Util bytesArrayToData:expectedInputArr1];
    NSMutableData *expectedInput2Data = [Util bytesArrayToData:expectedInputArr2];
    
    NSMutableData *expectedRenderedData = [NSMutableData dataWithLength:expectedInput2Data.length];
    
    PrefixSum_downsweep((uint8_t*)expectedInput1Data.bytes, (int)expectedInput1Data.length,
                        (uint8_t*)expectedInput2Data.bytes, (int)expectedInput2Data.length,
                        (uint8_t*)expectedRenderedData.bytes, (int)expectedRenderedData.length);
    
    NSArray *cRenderedArr = [Util byteDataToArray:expectedRenderedData];
    
    XCTAssert([cRenderedArr isEqualToArray:expectedRenderedArr]);
  }
  
  NSArray *input1Arr = [self arrayFrom8BitTexture:inputTexture1];
  XCTAssert([input1Arr isEqualToArray:expectedInputArr1]);
  
  NSArray *input2Arr = [self arrayFrom8BitTexture:inputTexture2];
  XCTAssert([input2Arr isEqualToArray:expectedInputArr2]);
  
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

// Sweep 16x32 up to 32x32

- (void)testMetalSweep16x32to32x32 {
  NSMutableArray *expectedInput1Arr = [NSMutableArray array];
  
  {
    int width = 16;
    int height = 32;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = offset & 0xFF;
        [expectedInput1Arr addObject:@(offsetAsByte)];
      }
    }
  }

  NSMutableArray *expectedInput2Arr = [NSMutableArray array];
  
  // Offset * 10 clamped to byte range
  
  {
    int width = 32;
    int height = 32;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        int mult = offset * 10;
        uint8_t offsetAsByte = mult & 0xFF;
        [expectedInput2Arr addObject:@(offsetAsByte)];
      }
    }
  }
  
  NSMutableData *expectedInput1Data = [Util bytesArrayToData:expectedInput1Arr];
  NSMutableData *expectedInput2Data = [Util bytesArrayToData:expectedInput2Arr];
  
  NSMutableData *expectedRenderedData = [NSMutableData dataWithLength:expectedInput2Data.length];
  
  PrefixSum_downsweep((uint8_t*)expectedInput1Data.bytes, (int)expectedInput1Data.length,
                      (uint8_t*)expectedInput2Data.bytes, (int)expectedInput2Data.length,
                      (uint8_t*)expectedRenderedData.bytes, (int)expectedRenderedData.length);
  
  NSArray *expectedRenderedArr = [Util byteDataToArray:expectedRenderedData];
    
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(32, 32);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture1 = (id<MTLTexture>) mpsrf.reduceTextures[0];
  id<MTLTexture> inputTexture2 = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture1.width == 16);
  XCTAssert(inputTexture1.height == 32);
  
  XCTAssert(inputTexture2.width == 32);
  XCTAssert(inputTexture2.height == 32);
  
  XCTAssert(outputTexture.width == 32);
  XCTAssert(outputTexture.height == 32);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture1 bytesArray:expectedInput1Arr mrc:mrc];
  [self fill8BitTexture:inputTexture2 bytesArray:expectedInput2Arr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  [mpsrc renderPrefixSumSweep:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture1:inputTexture1 inputTexture2:inputTexture2 outputTexture:outputTexture level:1 isExclusive:TRUE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture1 label:@"inputTexture1"];
  }
  
  if (dump) {
    [self dump8BitTexture:inputTexture2 label:@"inputTexture2"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *input1Arr = [self arrayFrom8BitTexture:inputTexture1];
  XCTAssert([input1Arr isEqualToArray:expectedInput1Arr]);
  
  NSArray *input2Arr = [self arrayFrom8BitTexture:inputTexture2];
  XCTAssert([input2Arr isEqualToArray:expectedInput2Arr]);
  
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
  
  {
    int width = 32;
    int height = 32;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        NSNumber *expectedNum = expectedRenderedArr[offset];
        NSNumber *renderedNum = renderedArr[offset];
        
        BOOL same = [renderedNum isEqualToNumber:expectedNum];
        
        if (!same) {
          XCTAssert(FALSE, @"!same %d != %d at offset %d", [renderedNum unsignedIntValue], [expectedNum unsignedIntValue], offset);
        }
      }
    }
  }

}


// ------ reduce and then sweep together

- (void)testMetalFullPrefixSum2x2 {
  NSArray *expectedInputArr = @[
                                @(0), @(1),
                                @(2), @(3)
                                ];
  
  NSArray *expectedRenderedArr = @[
                                   @(0), @(0),
                                   @(1), @(3)
                                   ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(2, 2);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;

  XCTAssert(inputTexture.width == 2);
  XCTAssert(inputTexture.height == 2);
  
  XCTAssert(outputTexture.width == 2);
  XCTAssert(outputTexture.height == 2);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSum:mrc commandBuffer:commandBuffer renderFrame:mpsrf isExclusive:TRUE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTextureD1"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTextureD1"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

- (void)testMetalFullPrefixSum2x2FirstNonZero {
  NSArray *expectedInputArr = @[
                                @(1), @(2),
                                @(3), @(4)
                                ];
  
  NSArray *expectedRenderedArr = @[
                                   @(0), @(1),
                                   @(3), @(6)
                                   ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(2, 2);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture.width == 2);
  XCTAssert(inputTexture.height == 2);
  
  XCTAssert(outputTexture.width == 2);
  XCTAssert(outputTexture.height == 2);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSum:mrc commandBuffer:commandBuffer renderFrame:mpsrf isExclusive:TRUE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTextureD1"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTextureD1"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}


// Is there a reduce problem when doing 2 steps of a render operation
// from 4x4 to 2x4 to 2x2 ?

- (void)testMetalReduce4x4To2x2TwoRenderPasses {
  NSArray *expectedInputArr = @[
                                @1, @2, @3, @4,
                                @5, @6, @7, @8,
                                @9, @10, @11, @12,
                                @13, @14, @15, @16
                                ];
  
  NSArray *expectedRenderedStep1Arr = @[
                                        @3, @7,
                                        @11, @15,
                                        @19, @23,
                                        @27, @31
                                        ];
  
  NSArray *expectedRenderedStep2Arr = @[
                                        @10, @26,
                                        @42, @58
                                        ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(4, 4);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  
  id<MTLTexture> outputTexture1 = (id<MTLTexture>) mpsrf.reduceTextures[0];
  XCTAssert(outputTexture1.width == 2);
  XCTAssert(outputTexture1.height == 4);
  
  id<MTLTexture> outputTexture2 = (id<MTLTexture>) mpsrf.reduceTextures[1];
  XCTAssert(outputTexture2.width == 2);
  XCTAssert(outputTexture2.height == 2);

  XCTAssert(outputTexture1 != outputTexture2);
  
  id<MTLTexture> sameDimTargetTexture1 = (id<MTLTexture>) mpsrf.sweepTextures[0];
  id<MTLTexture> sameDimTargetTexture2 = (id<MTLTexture>) mpsrf.sweepTextures[1];
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];

  // fill outputTexture1 and outputTexture2 for debug purposes
  
  {
    NSArray *arr = @[
                                          @(0xFF), @(0xFF),
                                          @(0xFF), @(0xFF),
                                          @(0xFF), @(0xFF),
                                          @(0xFF), @(0xFF)
                                          ];

    [self fill8BitTexture:outputTexture1 bytesArray:arr mrc:mrc];
  }
  
  {
    NSArray *arr = @[
                     @(0xFF), @(0xFF),
                     @(0xFF), @(0xFF)
                     ];
    
    [self fill8BitTexture:outputTexture2 bytesArray:arr mrc:mrc];
  }
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture:inputTexture outputTexture:outputTexture1 sameDimTargetTexture:sameDimTargetTexture1 level:1];
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf inputTexture:outputTexture1 outputTexture:outputTexture2 sameDimTargetTexture:sameDimTargetTexture2 level:2];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture1 label:@"outputTextureL1"];
  }

  if (dump) {
    [self dump8BitTexture:outputTexture2 label:@"outputTextureL2"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *rendered1Arr = [self arrayFrom8BitTexture:outputTexture1];
  NSArray *rendered2Arr = [self arrayFrom8BitTexture:outputTexture2];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([rendered1Arr isEqualToArray:expectedRenderedStep1Arr]);
  XCTAssert([rendered2Arr isEqualToArray:expectedRenderedStep2Arr]);
}

- (void)testMetalFullPrefixSum4x4 {
  NSMutableArray *expectedInputArr = [NSMutableArray array];
  NSArray *expectedRenderedArr;
  
  {
    int width = 4;
    int height = 4;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = (offset + 1) & 0xFF;
        [expectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  // Calculate simple prefix sum on CPU
  
  {
    NSMutableData *expectedInputData = [Util bytesArrayToData:expectedInputArr];
    
    NSMutableData *expectedPrefixSumData = [NSMutableData dataWithLength:expectedInputData.length];
    
    PrefixSum_exclusive((uint8_t*)expectedInputData.bytes, (int)expectedInputData.length,
                     (uint8_t*)expectedPrefixSumData.bytes, (int)expectedPrefixSumData.length);
    
    expectedRenderedArr = [Util byteDataToArray:expectedPrefixSumData];
  }

// INPUT

//  1   2   3   4
//  5   6   7   8
//  9  10  11  12
//  13  14  15  16

// EXPECTED OUTPUT:
  
//  0   1   3   6
//  10  15  21  28
//  36  45  55  66
//  78  91 105 120
  
//  0 0+1 0+1+2 0+1+2+3       =  0  1  3  6
//  10 10+5 10+5+6 10+5+6+7   = 10 15 21 28
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(4, 4);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture.width == 4);
  XCTAssert(inputTexture.height == 4);
  
  XCTAssert(outputTexture.width == 4);
  XCTAssert(outputTexture.height == 4);
  
  XCTAssert(mpsrf.reduceTextures.count == 3);
  XCTAssert(mpsrf.sweepTextures.count == 3);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSum:mrc commandBuffer:commandBuffer renderFrame:mpsrf isExclusive:TRUE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  // Print each reduce output texture
  
  {
    for ( int offset = 0 ; offset < (int)mpsrf.reduceTextures.count; offset += 1 ) {
      id<MTLTexture> outputTexture = mpsrf.reduceTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"reduceTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  {
    for ( int offset = (int)mpsrf.sweepTextures.count - 1 ; offset >= 0; offset -= 1 ) {
      id<MTLTexture> outputTexture = mpsrf.sweepTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"sweepTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

// Test 8x8 ident starting with the value 1

- (void)testMetalFullPrefixSum8x8 {
  NSMutableArray *expectedInputArr = [NSMutableArray array];
  NSArray *expectedRenderedArr;
  
  {
    int width = 8;
    int height = 8;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = (offset + 1) & 0xFF;
        [expectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  // Calculate simple prefix sum on CPU
  
  {
    NSMutableData *expectedInputData = [Util bytesArrayToData:expectedInputArr];
    
    NSMutableData *expectedPrefixSumData = [NSMutableData dataWithLength:expectedInputData.length];
    
    PrefixSum_exclusive((uint8_t*)expectedInputData.bytes, (int)expectedInputData.length,
                     (uint8_t*)expectedPrefixSumData.bytes, (int)expectedPrefixSumData.length);
    
    expectedRenderedArr = [Util byteDataToArray:expectedPrefixSumData];
  }
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(8, 8);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture.width == 8);
  XCTAssert(inputTexture.height == 8);
  
  XCTAssert(outputTexture.width == 8);
  XCTAssert(outputTexture.height == 8);
  
  XCTAssert(mpsrf.reduceTextures.count == 5);
  XCTAssert(mpsrf.sweepTextures.count == 5);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSum:mrc commandBuffer:commandBuffer renderFrame:mpsrf  isExclusive:TRUE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  // Print each reduce output texture
  
  {
    for ( int offset = 0 ; offset < (int)mpsrf.reduceTextures.count; offset += 1 ) {
      id<MTLTexture> outputTexture = mpsrf.reduceTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"reduceTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  {
    for ( int offset = (int)mpsrf.sweepTextures.count - 1 ; offset >= 0; offset -= 1 ) {
      id<MTLTexture> outputTexture = mpsrf.sweepTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"sweepTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

// Test 16x16 ident starting with the value 1

- (void)testMetalFullPrefixSum16x16 {
  NSMutableArray *expectedInputArr = [NSMutableArray array];
  NSArray *expectedRenderedArr;
  
  {
    int width = 16;
    int height = 16;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = (offset + 1) & 0xFF;
        [expectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  // Calculate simple prefix sum on CPU
  
  {
    NSMutableData *expectedInputData = [Util bytesArrayToData:expectedInputArr];
    
    NSMutableData *expectedPrefixSumData = [NSMutableData dataWithLength:expectedInputData.length];
    
    PrefixSum_exclusive((uint8_t*)expectedInputData.bytes, (int)expectedInputData.length,
                     (uint8_t*)expectedPrefixSumData.bytes, (int)expectedPrefixSumData.length);
    
    expectedRenderedArr = [Util byteDataToArray:expectedPrefixSumData];
  }
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(16, 16);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture.width == 16);
  XCTAssert(inputTexture.height == 16);
  
  XCTAssert(outputTexture.width == 16);
  XCTAssert(outputTexture.height == 16);
  
  XCTAssert(mpsrf.reduceTextures.count == 7);
  XCTAssert(mpsrf.sweepTextures.count == 7);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSum:mrc commandBuffer:commandBuffer renderFrame:mpsrf  isExclusive:TRUE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  // Print each reduce output texture
  
  {
    for ( int offset = 0 ; offset < (int)mpsrf.reduceTextures.count; offset += 1 ) {
      id<MTLTexture> outputTexture = mpsrf.reduceTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"reduceTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  {
    for ( int offset = (int)mpsrf.sweepTextures.count - 1 ; offset >= 0; offset -= 1 ) {
      id<MTLTexture> outputTexture = mpsrf.sweepTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"sweepTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

// Test 32x32 ident starting with the value 1

- (void)testMetalFullPrefixSum32x32 {
  NSMutableArray *expectedInputArr = [NSMutableArray array];
  NSArray *expectedRenderedArr;
  
  {
    int width = 32;
    int height = 32;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = (offset + 1) & 0xFF;
        [expectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  // Calculate simple prefix sum on CPU
  
  {
    NSMutableData *expectedInputData = [Util bytesArrayToData:expectedInputArr];
    
    NSMutableData *expectedPrefixSumData = [NSMutableData dataWithLength:expectedInputData.length];
    
    PrefixSum_exclusive((uint8_t*)expectedInputData.bytes, (int)expectedInputData.length,
                     (uint8_t*)expectedPrefixSumData.bytes, (int)expectedPrefixSumData.length);
    
    expectedRenderedArr = [Util byteDataToArray:expectedPrefixSumData];
  }
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(32, 32);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture.width == 32);
  XCTAssert(inputTexture.height == 32);
  
  XCTAssert(outputTexture.width == 32);
  XCTAssert(outputTexture.height == 32);
  
  XCTAssert(mpsrf.reduceTextures.count == 9);
  XCTAssert(mpsrf.sweepTextures.count == 9);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSum:mrc commandBuffer:commandBuffer renderFrame:mpsrf isExclusive:TRUE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  // Print each reduce output texture
  
  {
    for ( int offset = 0 ; offset < (int)mpsrf.reduceTextures.count; offset += 1 ) {
      id<MTLTexture> outputTexture = mpsrf.reduceTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"reduceTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  {
    for ( int offset = (int)mpsrf.sweepTextures.count - 1 ; offset >= 0; offset -= 1 ) {
      id<MTLTexture> outputTexture = mpsrf.sweepTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"sweepTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

// Prefix sum of 2 blocks of size 2x2, input 2x4

- (void)testMetalFullPrefixSum2x2WithTwoBlocks2x4 {
  // Two 2x2 blocks in block by block order
  NSArray *expectedInputArr = @[
                                @(0), @(1), @(2), @(3),
                                @(10), @(11), @(12), @(13)
                                ];
  
  NSArray *expectedRenderedArr = @[
                                   @(0), @(0), @(0+1), @(0+1+2),
                                   @(0), @(10), @(10+11), @(10+11+12)
                                   ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(2, 4);
  CGSize blockSize = CGSizeMake(2, 2);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:blockSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture.width == 2);
  XCTAssert(inputTexture.height == 4);
  
  XCTAssert(outputTexture.width == 2);
  XCTAssert(outputTexture.height == 4);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSum:mrc commandBuffer:commandBuffer renderFrame:mpsrf isExclusive:TRUE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  // Print each reduce output texture
  
  {
    for ( int offset = 0 ; offset < (int)mpsrf.reduceTextures.count; offset += 1 ) {
      id<MTLTexture> outputTexture = mpsrf.reduceTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"reduceTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  {
    for ( int offset = (int)mpsrf.sweepTextures.count - 1 ; offset >= 0; offset -= 1 ) {
      id<MTLTexture> outputTexture = mpsrf.sweepTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"sweepTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

// Prefix sum of 2 blocks of size 2x2, input 4x2

- (void)testMetalFullPrefixSum2x2WithTwoBlocks4x2 {
  // Two 2x2 blocks in block by block order
  NSArray *expectedInputArr = @[
                                @(0), @(1), @(2), @(3),
                                @(10), @(11), @(12), @(13)
                                ];
  
  NSArray *expectedRenderedArr = @[
                                   @(0), @(0), @(0+1), @(0+1+2),
                                   @(0), @(10), @(10+11), @(10+11+12)
                                   ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(4, 2);
  CGSize blockSize = CGSizeMake(2, 2);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:blockSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture.width == 4);
  XCTAssert(inputTexture.height == 2);
  
  XCTAssert(outputTexture.width == 4);
  XCTAssert(outputTexture.height == 2);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSum:mrc commandBuffer:commandBuffer renderFrame:mpsrf isExclusive:TRUE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  // Print each reduce output texture
  
  {
    for ( int offset = 0 ; offset < (int)mpsrf.reduceTextures.count; offset += 1 ) {
      id<MTLTexture> outputTexture = mpsrf.reduceTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"reduceTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  {
    for ( int offset = (int)mpsrf.sweepTextures.count - 1 ; offset >= 0; offset -= 1 ) {
      id<MTLTexture> outputTexture = mpsrf.sweepTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"sweepTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

// An inclusive implementation of scan is implemented by copying all
// the results from an exclusive scan to the left by 1 position and
// then executing a single add operation to regenerate the final
// value in the inclusive scan.

- (void)testMetalFullInclusivePrefixSum2x2 {
  NSArray *expectedInputArr = @[
                                @(1), @(2),
                                @(3), @(4)
                                ];
  
  NSArray *expectedRenderedArr = @[
                                   @(1), @(3),
                                   @(6), @(10)
                                   ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(2, 2);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture.width == 2);
  XCTAssert(inputTexture.height == 2);
  
  XCTAssert(outputTexture.width == 2);
  XCTAssert(outputTexture.height == 2);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSum:mrc commandBuffer:commandBuffer renderFrame:mpsrf isExclusive:FALSE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

- (void)testMetalFullInclusivePrefixSum4x4 {
  NSMutableArray *expectedInputArr = [NSMutableArray array];
  NSArray *expectedRenderedArr;
  
  {
    int width = 4;
    int height = 4;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = (offset + 1) & 0xFF;
        [expectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  // Calculate simple prefix sum on CPU
  
  {
    NSMutableData *expectedInputData = [Util bytesArrayToData:expectedInputArr];
    
    NSMutableData *expectedPrefixSumData = [NSMutableData dataWithLength:expectedInputData.length];
    
    PrefixSum_inclusive((uint8_t*)expectedInputData.bytes, (int)expectedInputData.length,
                     (uint8_t*)expectedPrefixSumData.bytes, (int)expectedPrefixSumData.length);
    
    expectedRenderedArr = [Util byteDataToArray:expectedPrefixSumData];
  }
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(4, 4);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture.width == 4);
  XCTAssert(inputTexture.height == 4);
  
  XCTAssert(outputTexture.width == 4);
  XCTAssert(outputTexture.height == 4);
  
  XCTAssert(mpsrf.reduceTextures.count == 3);
  XCTAssert(mpsrf.sweepTextures.count == 3);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSum:mrc commandBuffer:commandBuffer renderFrame:mpsrf isExclusive:FALSE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  // Print each reduce output texture
  
  {
    for ( int offset = 0 ; offset < (int)mpsrf.reduceTextures.count; offset += 1 ) {
      id<MTLTexture> outputTexture = mpsrf.reduceTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"reduceTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  {
    for ( int offset = (int)mpsrf.sweepTextures.count - 1 ; offset >= 0; offset -= 1 ) {
      id<MTLTexture> outputTexture = mpsrf.sweepTextures[offset];
      
      if (dump) {
        int level = offset + 1;
        NSString *levelStr = [NSString stringWithFormat:@"sweepTextureL%d", level];
        [self dump8BitTexture:outputTexture label:levelStr];
      }
    }
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

- (void)testMetalFullInclusivePrefixSum2x2WithTwoBlocks {
  // Two 2x2 blocks in block by block order
  NSArray *expectedInputArr = @[
                                @(0), @(1), @(2), @(3),
                                @(10), @(11), @(12), @(13)
                                ];
  
  NSArray *expectedRenderedArr = @[
                                   @(0), @(0+1), @(0+1+2), @(0+1+2+3),
                                   @(10), @(10+11), @(10+11+12), @(10+11+12+13)
                                   ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(2, 4);
  CGSize blockSize = CGSizeMake(2, 2);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:blockSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture.width == 2);
  XCTAssert(inputTexture.height == 4);
  
  XCTAssert(outputTexture.width == 2);
  XCTAssert(outputTexture.height == 4);
  
  // The first reduction step reduces from 2x4 to 2x2 and not to 1x4
  // since a width of 1 complicates shader math.
  
  id<MTLTexture> reduction1Texture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  XCTAssert(reduction1Texture.width == 1);
  XCTAssert(reduction1Texture.height == 4);
  
  id<MTLTexture> zerosTexture = (id<MTLTexture>) mpsrf.zeroTexture;
  
  XCTAssert(zerosTexture.width == 1);
  XCTAssert(zerosTexture.height == 2);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSum:mrc commandBuffer:commandBuffer renderFrame:mpsrf isExclusive:FALSE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

// Four blocks at block dim 2x2, fits exactly into a square texture

- (void)testMetalFullInclusivePrefixSum2x2WithFourBlocks {
  // Four 2x2 blocks in block by block order
  NSArray *expectedInputArr = @[
                                @(0),  @(1), @(2), @(3),
                                @(10), @(1), @(2), @(3),
                                @(20), @(1), @(2), @(3),
                                @(30), @(1), @(2), @(3)
                                ];
  
  NSArray *expectedRenderedArr = @[
                                   @(0),  @(0+1),  @(0+1+2),  @(0+1+2+3),
                                   @(10), @(10+1), @(10+1+2), @(10+1+2+3),
                                   @(20), @(20+1), @(20+1+2), @(20+1+2+3),
                                   @(30), @(30+1), @(30+1+2), @(30+1+2+3)
                                   ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(4, 4);
  CGSize blockSize = CGSizeMake(2, 2);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:blockSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture.width == 4);
  XCTAssert(inputTexture.height == 4);
  
  XCTAssert(outputTexture.width == 4);
  XCTAssert(outputTexture.height == 4);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSum:mrc commandBuffer:commandBuffer renderFrame:mpsrf isExclusive:FALSE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

// Four blocks at block dim 2x2, fits exactly into a square texture

- (void)testMetalFullInclusivePrefixSum2x2WithThreeBlocks {
  // Three 2x2 blocks in block by block order, note that
  // zero padding is needed to reach a square size
  // for the entire texture.
  
  NSArray *expectedInputArr = @[
                                @(0),  @(1), @(2), @(3),
                                @(10), @(1), @(2), @(3),
                                @(20), @(1), @(2), @(3),
                                @(0), @(0), @(0), @(0)
                                ];
  
  NSArray *expectedRenderedArr = @[
                                   @(0),  @(0+1),  @(0+1+2),  @(0+1+2+3),
                                   @(10), @(10+1), @(10+1+2), @(10+1+2+3),
                                   @(20), @(20+1), @(20+1+2), @(20+1+2+3),
                                   @(0), @(0), @(0), @(0)
                                   ];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(4, 4);
  CGSize blockSize = CGSizeMake(2, 2);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize blockSize:blockSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.outputBlockOrderTexture;
  
  XCTAssert(inputTexture.width == 4);
  XCTAssert(inputTexture.height == 4);
  
  XCTAssert(outputTexture.width == 4);
  XCTAssert(outputTexture.height == 4);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:expectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSum:mrc commandBuffer:commandBuffer renderFrame:mpsrf isExclusive:FALSE];
  
  // Wait for commands to be rendered
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  
  // Dump output of render process
  
  BOOL dump = TRUE;
  
  if (dump) {
    [self dump8BitTexture:inputTexture label:@"inputTexture"];
  }
  
  if (dump) {
    [self dump8BitTexture:outputTexture label:@"outputTexture"];
  }
  
  NSArray *inputArr = [self arrayFrom8BitTexture:inputTexture];
  NSArray *renderedArr = [self arrayFrom8BitTexture:outputTexture];
  
  XCTAssert([inputArr isEqualToArray:expectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:expectedRenderedArr]);
}

@end

