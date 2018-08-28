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
  NSArray *epectedInputArr = @[
                               @0, @1, @2, @3,
                               @4, @5, @6, @7,
                               @8, @9, @10, @11,
                               @12, @13, @14, @15
                               ];
  
  NSArray *epectedRenderedArr = @[
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
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  
  XCTAssert(outputTexture.width == 2);
  XCTAssert(outputTexture.height == 4);
  
  // fill inputTexture

  [self fill8BitTexture:inputTexture bytesArray:epectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf];
  
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
  
  XCTAssert([inputArr isEqualToArray:epectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:epectedRenderedArr]);
}

- (void)testMetalReduce2x4To2x2 {
  NSArray *epectedInputArr = @[
                               @(0 + 1), @(2 + 3),
                               @(4 + 5), @(6 + 7),
                               @(8 + 9), @(10 + 11),
                               @(12 + 13), @(14 + 15)
                               ];
  
  NSArray *epectedRenderedArr = @[
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
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  
  XCTAssert(outputTexture.width == 2);
  XCTAssert(outputTexture.height == 2);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:epectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf];
  
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
  
  XCTAssert([inputArr isEqualToArray:epectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:epectedRenderedArr]);
}

- (void)testMetalReduce2x2To1x2 {
  NSArray *epectedInputArr = @[
                               @(1+5),   @(9+13),
                               @(17+21), @(25+29)
                               ];
  
  NSArray *epectedRenderedArr = @[
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
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  
  XCTAssert(outputTexture.width == 1);
  XCTAssert(outputTexture.height == 2);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:epectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf];
  
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
  
  XCTAssert([inputArr isEqualToArray:epectedInputArr]);
  XCTAssert([renderedArr isEqualToArray:epectedRenderedArr]);
}

//- (void)testPerformanceExample {
//    // This is an example of a performance test case.
//    [self measureBlock:^{
//        // Put the code you want to measure the time of here.
//    }];
//}

// Test 32 x 32 input case that gets reduced down to 16x32

- (void)testMetalReduce32x32To16x32 {
  NSMutableArray *epectedInputArr = [NSMutableArray array];
  
  {
    int width = 32;
    int height = 32;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = offset & 0xFF;
        [epectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  // Reduce 32x32 down to 16x32
  
  NSMutableData *epectedInputData = [Util bytesArrayToData:epectedInputArr];
  NSMutableData *epectedRenderedData = [NSMutableData dataWithLength:epectedInputData.length/2];
  
  PrefisSum_reduce((uint8_t*)epectedInputData.bytes, (int)epectedInputData.length,
                   (uint8_t*)epectedRenderedData.bytes, (int)epectedRenderedData.length);
  
  // Convert prefix sum reduction back to NSArray
  
  NSArray *epectedRenderedArr = [Util byteDataToArray:epectedRenderedData];
  
  {
    int width = 16;
    int height = 32;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        if (offset == 58) {
          offset = 58;
        }
        
        uint8_t *ptr = (uint8_t *) epectedRenderedData.bytes;
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
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  
  XCTAssert(outputTexture.width == 16);
  XCTAssert(outputTexture.height == 32);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:epectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf];
  
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
  
  XCTAssert([inputArr isEqualToArray:epectedInputArr]);
  
  XCTAssert([renderedArr isEqualToArray:epectedRenderedArr]);
  
  {
    int width = 16;
    int height = 32;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        NSNumber *expectedNum = epectedRenderedArr[offset];
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
  NSMutableArray *epectedInputArr = [NSMutableArray array];
  
  {
    int width = 16;
    int height = 32;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = offset & 0xFF;
        [epectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  NSMutableData *epectedInputData = [Util bytesArrayToData:epectedInputArr];
  NSMutableData *epectedRenderedData = [NSMutableData dataWithLength:epectedInputData.length/2];
  
  PrefisSum_reduce((uint8_t*)epectedInputData.bytes, (int)epectedInputData.length,
                   (uint8_t*)epectedRenderedData.bytes, (int)epectedRenderedData.length);
  
  // Convert prefix sum reduction back to NSArray
  
  NSArray *epectedRenderedArr = [Util byteDataToArray:epectedRenderedData];
  
  {
    int width = 16;
    int height = 16;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        if (offset == 58) {
          offset = 58;
        }
        
        uint8_t *ptr = (uint8_t *) epectedRenderedData.bytes;
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
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  
  XCTAssert(outputTexture.width == 16);
  XCTAssert(outputTexture.height == 16);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:epectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf];
  
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
  
  XCTAssert([inputArr isEqualToArray:epectedInputArr]);
  
  XCTAssert([renderedArr isEqualToArray:epectedRenderedArr]);
  
  {
    int width = 16;
    int height = 16;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        NSNumber *expectedNum = epectedRenderedArr[offset];
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
  NSMutableArray *epectedInputArr = [NSMutableArray array];
  
  {
    int width = 16;
    int height = 16;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = offset & 0xFF;
        [epectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  NSMutableData *epectedInputData = [Util bytesArrayToData:epectedInputArr];
  NSMutableData *epectedRenderedData = [NSMutableData dataWithLength:epectedInputData.length/2];
  
  PrefisSum_reduce((uint8_t*)epectedInputData.bytes, (int)epectedInputData.length,
                   (uint8_t*)epectedRenderedData.bytes, (int)epectedRenderedData.length);
  
  // Convert prefix sum reduction back to NSArray
  
  NSArray *epectedRenderedArr = [Util byteDataToArray:epectedRenderedData];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(16, 16);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  
  XCTAssert(outputTexture.width == 8);
  XCTAssert(outputTexture.height == 16);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:epectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf];
  
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
  
  XCTAssert([inputArr isEqualToArray:epectedInputArr]);
  
  XCTAssert([renderedArr isEqualToArray:epectedRenderedArr]);
  
  {
    int width = 8;
    int height = 16;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        NSNumber *expectedNum = epectedRenderedArr[offset];
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
  NSMutableArray *epectedInputArr = [NSMutableArray array];
  
  {
    int width = 8;
    int height = 16;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        uint8_t offsetAsByte = offset & 0xFF;
        [epectedInputArr addObject:@(offsetAsByte)];
      }
    }
  }
  
  NSMutableData *epectedInputData = [Util bytesArrayToData:epectedInputArr];
  NSMutableData *epectedRenderedData = [NSMutableData dataWithLength:epectedInputData.length/2];
  
  PrefisSum_reduce((uint8_t*)epectedInputData.bytes, (int)epectedInputData.length,
                   (uint8_t*)epectedRenderedData.bytes, (int)epectedRenderedData.length);
  
  // Convert prefix sum reduction back to NSArray
  
  NSArray *epectedRenderedArr = [Util byteDataToArray:epectedRenderedData];
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];
  
  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  MetalPrefixSumRenderFrame *mpsrf = [[MetalPrefixSumRenderFrame alloc] init];
  
  CGSize renderSize = CGSizeMake(8, 16);
  
  [mpsrc setupRenderTextures:mrc renderSize:renderSize renderFrame:mpsrf];
  
  id<MTLTexture> inputTexture = (id<MTLTexture>) mpsrf.inputBlockOrderTexture;
  id<MTLTexture> outputTexture = (id<MTLTexture>) mpsrf.reduceTextures[0];
  
  XCTAssert(outputTexture.width == 8);
  XCTAssert(outputTexture.height == 8);
  
  // fill inputTexture
  
  [self fill8BitTexture:inputTexture bytesArray:epectedInputArr mrc:mrc];
  
  // Get a metal command buffer
  
  id <MTLCommandBuffer> commandBuffer = [mrc.commandQueue commandBuffer];
  
#if defined(DEBUG)
  assert(commandBuffer);
#endif // DEBUG
  
  commandBuffer.label = @"XCTestRenderCommandBuffer";
  
  // Prefix sum setup and render steps
  
  [mpsrc renderPrefixSumReduce:mrc commandBuffer:commandBuffer renderFrame:mpsrf];
  
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
  
  XCTAssert([inputArr isEqualToArray:epectedInputArr]);
  
  XCTAssert([renderedArr isEqualToArray:epectedRenderedArr]);
  
  {
    int width = 8;
    int height = 8;
    
    for ( int row = 0; row < height; row++ ) {
      for ( int col = 0; col < width; col++ ) {
        int offset = (row * width) + col;
        
        NSNumber *expectedNum = epectedRenderedArr[offset];
        NSNumber *renderedNum = renderedArr[offset];
        
        BOOL same = [renderedNum isEqualToNumber:expectedNum];
        
        if (!same) {
          XCTAssert(FALSE, @"!same %d != %d at offset %d", [renderedNum unsignedIntValue], [expectedNum unsignedIntValue], offset);
        }
      }
    }
  }
  
}

@end
