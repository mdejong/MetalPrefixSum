// Objective C interface to elias gamma parsing functions
//  MIT Licensed

#import <Foundation/Foundation.h>

// Our platform independent render class
@interface DeltaEncoder : NSObject

// Encode symbols by calculating signed byte deltas
// and then converting to zerod deltas which can
// be represented as positive integer values.

+ (NSData*) encodeSignedByteDeltas:(NSData*)data;

// Decode symbols by reversing zerod mapping and then applying
// signed 8 bit deltas to recover the original symbols as uint8_t.

+ (NSData*) decodeSignedByteDeltas:(NSData*)deltas;

// Reverse zigzag encoding on deltas but do not undelta the data.

+ (NSData*) decodeZigZagBytes:(NSData*)deltas;

@end
