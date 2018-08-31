// Objective C interface to elias gamma parsing functions
//  MIT Licensed

#import <Foundation/Foundation.h>

// Our platform independent render class
@interface DeltaEncoder : NSObject

+ (NSData*) encodeByteDeltas:(NSData*)data;

+ (NSData*) decodeByteDeltas:(NSData*)deltas;

@end
