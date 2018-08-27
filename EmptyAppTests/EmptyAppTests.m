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

- (void)testMetalExample {
  // This is an example of a functional test case.
  // Use XCTAssert and related functions to verify your tests produce the correct results.
  
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  
  MetalRenderContext *mrc = [[MetalRenderContext alloc] init];
  
  MetalPrefixSumRenderContext *mpsrc = [[MetalPrefixSumRenderContext alloc] init];

  [mrc setupMetal:device];
  
  [mpsrc setupRenderPipelines:mrc];
  
  XCTAssert(true);
}

//- (void)testPerformanceExample {
//    // This is an example of a performance test case.
//    [self measureBlock:^{
//        // Put the code you want to measure the time of here.
//    }];
//}

@end
