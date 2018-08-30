// Objective C interface to elias gamma parsing functions
//  MIT Licensed

#import "DeltaEncoder.h"

#include <assert.h>

#include <string>
#include <vector>
#include <unordered_map>
#include <cstdint>

using namespace std;

static inline
string get_code_bits_as_string(uint32_t code, const int width)
{
    string bitsStr;
    int c4 = 1;
    for ( int i = 0; i < width; i++ ) {
        bool isOn = ((code & (0x1 << i)) != 0);
        if (isOn) {
            bitsStr = "1" + bitsStr;
        } else {
            bitsStr = "0" + bitsStr;
        }
        
        if ((c4 == 4) && (i != (width - 1))) {
            bitsStr = "-" + bitsStr;
            c4 = 1;
        } else {
            c4++;
        }
    }
    return bitsStr;
}

// Generate signed delta, note that this method supports repeated value that delta to zero

template <typename T>
vector<T>
encodeDelta(const vector<T> & orderVec)
{
    T prev;
    vector<T> deltas;
    deltas.reserve(orderVec.size());
    
    // The first value is always a delta from zero, so handle it before
    // the loop logic.
    
    {
        T val = orderVec[0];
        deltas.push_back(val);
        prev = val;
    }
    
    int maxi = (int) orderVec.size();
    for (int i = 1; i < maxi; i++) {
        T val = orderVec[i];
        T delta = val - prev;
        deltas.push_back(delta);
        prev = val;
    }
    
    return std::move(deltas);
}

template <typename T>
vector<T>
decodePlusDelta(const vector<T> &deltas, const bool minusOne = false)
{
    T prev;
    vector<T> values;
    values.reserve(deltas.size());
    
    // The first value is always a delta from zero, so handle it before
    // the loop logic.
    
    {
        T val = deltas[0];
        values.push_back(val);
        prev = val;
    }
    
    int maxi = (int) deltas.size();
    for (int i = 1; i < maxi; i++) {
        T delta = deltas[i];
        if (minusOne) {
            delta += 1;
        }
        T val = prev + delta;
        values.push_back(val);
        prev = val;
    }
    
    return std::move(values);
}

template <typename T>
vector<T>
decodeDelta(const vector<T> &deltas)
{
    return decodePlusDelta(deltas, false);
}

// zerod representation

// 0 = 0, -1 = 1, 1 = 2, -2 = 3, 2 = 4, -3 = 5, 3 = 6

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

// Main class performing the rendering

@implementation DeltaEncoder

// Encode symbols by calculating signed byte deltas
// and then converting to zerod deltas which can
// be represented as positive integer values.

+ (NSData*) encodeSignedByteDeltas:(NSData*)data
{
  vector<int8_t> inBytes;
  inBytes.resize(data.length);
  memcpy(inBytes.data(), data.bytes, data.length);
  
  vector<int8_t> outSignedDeltaBytes = encodeDelta(inBytes);
    
  NSMutableData *outZerodDeltaBytes = [NSMutableData data];
  [outZerodDeltaBytes setLength:outSignedDeltaBytes.size()];
  uint8_t *outZerodDeltaPtr = (uint8_t *) outZerodDeltaBytes.mutableBytes;
    
  // Convert signed delta to zerod (unsigned) deltas
  const int maxNumBytes = (int) outSignedDeltaBytes.size();

  for (int i = 0; i < maxNumBytes; i++) {
      int8_t sVal = outSignedDeltaBytes[i];
      uint8_t zerodVal = pixelpack_int8_to_offset_uint8(sVal);
      *outZerodDeltaPtr++ = zerodVal;
  }

  return [NSData dataWithData:outZerodDeltaBytes];
}

// Decode symbols by reversing zigzag mapping and then applying
// signed 8 bit deltas to recover the original symbols as uint8_t.

+ (NSData*) decodeSignedByteDeltas:(NSData*)deltas
{
  const int maxNumBytes = (int) deltas.length;

  vector<uint8_t> signedDeltaBytes;
  signedDeltaBytes.resize(maxNumBytes);
  const uint8_t *zerodDeltasPtr = (uint8_t *) deltas.bytes;
  
  for (int i = 0; i < maxNumBytes; i++) {
    uint8_t zerodVal = zerodDeltasPtr[i];
    int8_t sVal = pixelpack_offset_uint8_to_int8(zerodVal);
    signedDeltaBytes[i] = (uint8_t) sVal;
  }

  // Apply signed deltas
  vector<uint8_t> outSymbols = decodeDelta(signedDeltaBytes);
    
  NSMutableData *mData = [NSMutableData data];
  [mData setLength:maxNumBytes];
  memcpy((void*)mData.mutableBytes, (void*)outSymbols.data(), maxNumBytes);
    
  return [NSData dataWithData:mData];
}

// Reverse zigzag encoding on deltas but do not undelta the data.

+ (NSData*) decodeZigZagBytes:(NSData*)deltas
{
  const int maxNumBytes = (int) deltas.length;
  
  vector<uint8_t> signedDeltaBytes;
  signedDeltaBytes.resize(maxNumBytes);
  const uint8_t *zerodDeltasPtr = (uint8_t *) deltas.bytes;
  
  for (int i = 0; i < maxNumBytes; i++) {
    uint8_t zerodVal = zerodDeltasPtr[i];
    int8_t sVal = pixelpack_offset_uint8_to_int8(zerodVal);
    signedDeltaBytes[i] = (uint8_t) sVal;
  }
  
  NSMutableData *mData = [NSMutableData data];
  [mData setLength:maxNumBytes];
  memcpy((void*)mData.mutableBytes, (void*)signedDeltaBytes.data(), maxNumBytes);
  
  return [NSData dataWithData:mData];
}

@end

