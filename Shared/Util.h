//
//  Util.h
//
//  Created by Moses DeJong on 10/2/13.
//  MIT Licensed

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

//#import "misc.h"

float min2f(float f1, float f2);
float min3f(float f1, float f2, float f3);

double min2d(double f1, double f2);
double min3d(double f1, double f2, double f3);

float max2f(float f1, float f2);
float max3f(float f1, float f2, float f3);

double max2d(double f1, double f2);
double max3d(double f1, double f2, double f3);

// Inlined integer min() and max() methods, should be as efficient as macros

static inline
uint32_t min2ui(uint32_t v1, uint32_t v2) {
  if (v1 <= v2) {
    return v1;
  } else {
    return v2;
  }
}

static inline
uint32_t min3ui(uint32_t v1, uint32_t v2, uint32_t v3) {
  uint32_t min = min2ui(v1, v2);
  return min2ui(min, v3);
}

static inline
uint32_t max2ui(uint32_t v1, uint32_t v2) {
  if (v1 >= v2) {
    return v1;
  } else {
    return v2;
  }
}

static inline
uint32_t max3ui(uint32_t v1, uint32_t v2, uint32_t v3) {
  uint32_t max = max2ui(v1, v2);
  return max2ui(max, v3);
}

// Clamp an integer value to a min and max range.
// This method operates only on unsigned integer
// values.

static inline
uint32_t clampui(uint32_t val, uint32_t min, uint32_t max) {
  if (val < min) {
    return min;
  } else if (val > max) {
    return max;
  } else {
    return val;
  }
}

// Clamp an integer value to a min and max range.
// This method operates only on signed integer
// values.

static inline
int32_t clampi(int32_t val, int32_t min, int32_t max) {
  if (val < min) {
    return min;
  } else if (val > max) {
    return max;
  } else {
    return val;
  }
}

// 0 = 0, -1 = 1, 1 = 2, -2 = 3, 2 = 4, -3 = 5, 3 = 6

static inline
uint32_t
pixelpack_num_neg_to_offset(int32_t value) {
    if (value == 0) {
        return value;
    } else if (value < 0) {
        return (value * -2) - 1;
    } else {
        return value * 2;
    }
}

static inline
int32_t
pixelpack_offset_to_num_neg(uint32_t value) {
    if (value == 0) {
        return value;
    } else if ((value & 0x1) != 0) {
        // odd numbers are negative values
        return ((int)value + 1) / -2;
    } else {
        return value / 2;
    }
}

static inline
int8_t
pixelpack_offset_uint8_to_int8(uint8_t value)
{
    int offset = (int) value;
    int iVal = pixelpack_offset_to_num_neg(offset);
    assert(iVal >= -128);
    assert(iVal <= 127);
    int8_t sVal = (int8_t) iVal;
    return sVal;
}

static inline
uint8_t
pixelpack_int8_to_offset_uint8(int8_t value)
{
    int iVal = (int) value;
    int offset = pixelpack_num_neg_to_offset(iVal);
    assert(offset >= 0);
    assert(offset <= 255);
    uint8_t offset8 = offset;
#if defined(DEBUG)
    {
        // Validate reverse operation, it must regenerate value
        int8_t decoded = pixelpack_offset_uint8_to_int8(offset8);
        assert(decoded == value);
    }
#endif // DEBUG
    return offset8;
}

// This pair of values is sorted together such that the
// floating point value and the data pointed to remain
// associated. This is critically important when sorting
// an element by a linear floating point value. When
// the original data is needed again, the values from
// the original pointer or data can be read again.

typedef
union {
  uint32_t value;
  void *ptr;
} QuicksortPointerOrIntegerValue;

typedef
struct
{
  double d;
  QuicksortPointerOrIntegerValue ptrOrValue;
} QuicksortDoublePair;

typedef
struct
{
  float f;
  QuicksortPointerOrIntegerValue ptrOrValue;
} QuicksortFloatPair;

// Binary search result constant

#define BINARY_SEARCH_VALUE_NOT_FOUND 0xFFFFFFFF

// class Util

@interface Util : NSObject

// Given a flat array of elements, split the values up into blocks of length elements.

#if !defined(CLIENT_ONLY_IMPL) || defined(DEBUG)

+ (NSArray*) splitIntoSubArraysOfLength:(NSArray*)arr
                                 length:(int)length;

// Given an array of arrays, flatten so that each object in each
// array is appended to a single array.

+ (NSMutableArray*) flattenArrays:(NSArray*)arrayOfValues;

#endif // CLIENT_ONLY_IMPL

// Implement the complex task of block zero padding and
// segmentation into squares of size blockSize.
// The return value is an array of rows where
// each row is an array of values.

#if !defined(CLIENT_ONLY_IMPL)

+ (NSArray*) splitIntoBlocksOfSize:(uint32_t)blockSize
                            values:(NSArray*)values
                             width:(uint32_t)width
                            height:(uint32_t)height
                  numBlocksInWidth:(uint32_t)numBlocksInWidth
                 numBlocksInHeight:(uint32_t)numBlocksInHeight
                         zeroValue:(NSObject*)zeroValue;

#endif // CLIENT_ONLY_IMPL

// This optimized version of splitIntoBlocksOfSize operates
// only on byte values. The input buffer is not padded with
// zeros while the output buffer is.

+ (void) splitIntoBlocksOfSize:(uint32_t)blockSize
                       inBytes:(uint8_t*)inBytes
                      outBytes:(uint8_t*)outBytes
                         width:(uint32_t)width
                        height:(uint32_t)height
              numBlocksInWidth:(uint32_t)numBlocksInWidth
             numBlocksInHeight:(uint32_t)numBlocksInHeight
                     zeroValue:(uint8_t)zeroValue;

// This optimized version of splitIntoBlocksOfSize operates
// only on word values. The input buffer is not padded with
// zeros while the output buffer is.

+ (void) splitIntoBlocksOfSize:(uint32_t)blockSize
                      inPixels:(uint32_t*)inPixels
                     outPixels:(uint32_t*)outPixels
                         width:(uint32_t)width
                        height:(uint32_t)height
              numBlocksInWidth:(uint32_t)numBlocksInWidth
             numBlocksInHeight:(uint32_t)numBlocksInHeight
                     zeroValue:(uint32_t)zeroValue;

#if !defined(CLIENT_ONLY_IMPL) || defined(DEBUG)

// Phony wrapper function that calls optimized splitIntoBlocksOfSize
// for word arguments but with NSObject inputs and outputs. This
// is useful only for test cases already written for the non-optimzied
// version of this code.

+ (NSArray*) splitIntoBlocksOfSizeWP:(uint32_t)blockSize
                              values:(NSArray*)values
                               width:(uint32_t)width
                              height:(uint32_t)height
                    numBlocksInWidth:(uint32_t)numBlocksInWidth
                   numBlocksInHeight:(uint32_t)numBlocksInHeight
                           zeroValue:(NSObject*)zeroValue;

// Implement the tricky task of reading blocks of values
// and flattening them out into an array of values.
// This involves processing each row of blocks
// and then appending each row of flat values.

+ (NSArray*) flattenBlocksOfSize:(uint32_t)blockSize
                          values:(NSArray*)values
                numBlocksInWidth:(uint32_t)numBlocksInWidth;

#endif // CLIENT_ONLY_IMPL

// This optimized version of flattenBlocksOfSize reads 32bit pixels
// from inPixels and writes the flattened blocks to the passed in
// outPixels buffer. This implementation is significantly more
// optimal when compared to flattenBlocksOfSize and it does not allocate
// intermediate objects in the tight loop. The buffers pointed to
// by inPixels and outPixels must be the same length as defined by
// the passed in width and height.

+ (void) flattenBlocksOfSize:(uint32_t)blockSize
                    inPixels:(uint32_t*)inPixels
                   outPixels:(uint32_t*)outPixels
            numBlocksInWidth:(uint32_t)numBlocksInWidth
           numBlocksInHeight:(uint32_t)numBlocksInHeight;

// Return the size of an image in terms of blocks given the block
// side dimension and the pixel width and height of the image.

+ (CGSize) blockSizeForSize:(CGSize)pixelSize
             blockDimension:(int)blockDimension;

// Given an array of pixel values, convert to an array of pixels values
// that contain a NSNumber of unsigned 32 bit type.

+ (NSArray*) pixelDataToArray:(NSData*)pixelData;

// Given an array of pixels inside NSNumber objects,
// append each pixel word to a mutable data and return.

+ (NSMutableData*) pixelsArrayToData:(NSArray*)pixels;

// Given a buffer of bytes, convert to an array of NSNumbers
// that contain and unsigned byte.

+ (NSArray*) byteDataToArray:(NSData*)byteData;

// Given an array of byte inside NSNumber objects,
// append each byte to a mutable data and return.

+ (NSMutableData*) bytesArrayToData:(NSArray*)bytes;

// Return the size of the file in bytes

+ (uint32_t) filesize:(NSString*)filepath;

// Format numbers into as comma separated string

+ (NSString*) formatNumbersAsString:(NSArray*)numbers;

@end
