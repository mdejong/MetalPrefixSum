// Objective C interface to elias gamma parsing functions
//  MIT Licensed

#import "Eliasg.h"

#include <assert.h>

#include <string>
#include <vector>
#include <unordered_map>
#include <cstdint>

#import "elias.hpp"

using namespace std;

void
Eliasg_decodeBlockSymbols(
                          int numSymbolsToDecode,
                          uint8_t *bitBuff,
                          int bitBuffN,
                          uint8_t *outBuffer,
                          uint32_t *blockStartBitOffsetsPtr);

// Invoke huffman util module functions

static inline
vector<uint8_t> encode(const uint8_t * bytes,
            const int numBytes)
{
    EliasGammaEncoder encoder;
    
    encoder.emitPaddingZeros = true;
    encoder.emitMSB = true;
    encoder.encode(bytes, numBytes);
    
    return std::move(encoder.bytes);
}

static inline
bool decode(const uint8_t *encodedBitsPtr,
            const unsigned int numSymbols,
            vector<uint8_t> & symbols)
{
    EliasGammaDecoderOpt16 decoder;
    
    decoder.decode(encodedBitsPtr,
                   numSymbols,
                   symbols);
    
    return true;
}

// Generate a table of bit width offsets for N symbols, this is
// the symbol width added to a running counter of the offset
// into a buffer.

// FIXME: would be more optimal to generate a table of just the block
// offsets instead of all of the symbols in a table.

static inline
vector<uint32_t> generateBitOffsets(const uint8_t * symbols, int numSymbols)
{
    vector<uint32_t> bitOffsets;
    bitOffsets.reserve(numSymbols);
    
    unsigned int offset = 0;
    
    EliasGammaEncoder encoder;
    
    for ( int i = 0; i < numSymbols; i++ ) {
        bitOffsets.push_back(offset);
        uint8_t symbol = symbols[i];
        uint32_t bitWidth = encoder.numBits(symbol);
        offset += bitWidth;
    }
    
    return bitOffsets;
}

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

@implementation Eliasg

// Given an input buffer, huffman encode the input values and generate
// output that corresponds to

+ (void) encodeBits:(uint8_t*)inBytes
         inNumBytes:(int)inNumBytes
           outCodes:(NSMutableData*)outCodes
 outBlockBitOffsets:(NSMutableData*)outBlockBitOffsets
              width:(int)width
             height:(int)height
           blockDim:(int)blockDim
{
  vector<uint8_t> outBytesVec = encode(inBytes, inNumBytes);
    
  {
      // Copy from outBytesVec to outCodes
      NSMutableData *mData = outCodes;
      int numBytes = (int)(outBytesVec.size() * sizeof(uint8_t));
      [mData setLength:numBytes];
      memcpy(mData.mutableBytes, outBytesVec.data(), numBytes);
  }
    
  // Generate bit width lookup table from original input symbols
  vector<uint32_t> offsetsVec = generateBitOffsets(inBytes, inNumBytes);

  // The outBlockBitOffsets output contains bit offsets of the start
  // of each block, so skip over (blockDim * blockDim) offsets on
  // each lookup.

  const int maxOffset = (width * height);
  const int blockN = (blockDim * blockDim);
    
  vector<uint32_t> blockStartOffsetsVec;
  blockStartOffsetsVec.reserve(maxOffset / blockN);

  for (int offset = 0; offset < maxOffset; offset += blockN ) {
      int blockStartBitOffset = offsetsVec[offset];
      blockStartOffsetsVec.push_back(blockStartBitOffset);
  }

  {
      int numBytes = (int) (blockStartOffsetsVec.size() * sizeof(uint32_t));
      if ((int)outBlockBitOffsets.length != numBytes) {
          [outBlockBitOffsets setLength:numBytes];
      }
      memcpy(outBlockBitOffsets.mutableBytes, blockStartOffsetsVec.data(), numBytes);
  }
  
  return;
}

// Unoptimized serial decode logic. Note that this logic
// assumes that huffBuff contains +2 bytes at the end
// of the buffer to account for read ahead.

+ (void) decodeBits:(int)numSymbolsToDecode
           bitBuff:(uint8_t*)bitBuff
          bitBuffN:(int)bitBuffN
          outBuffer:(uint8_t*)outBuffer
     bitOffsetTable:(uint32_t*)bitOffsetTable
{
    vector<uint8_t> outVec;
    outVec.reserve(numSymbolsToDecode);
    
    decode(bitBuff, numSymbolsToDecode, outVec);
    // FIXME: how should decode method return the result data?
    // Since size of buffer is know, this module can assume
    // that allocated buffer is large enough to handle known
    // number of symbols.
    memcpy(outBuffer, outVec.data(), numSymbolsToDecode);
}

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

// Decode symbols by reversing zerod mapping and then applying
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

+ (void) decodeBlockSymbols:(int)numSymbolsToDecode
                    bitBuff:(uint8_t*)bitBuff
                   bitBuffN:(int)bitBuffN
                  outBuffer:(uint8_t*)outBuffer
    blockStartBitOffsetsPtr:(uint32_t*)blockStartBitOffsetsPtr
{
    Eliasg_decodeBlockSymbols(numSymbolsToDecode, bitBuff, bitBuffN, outBuffer, blockStartBitOffsetsPtr);
}

@end


// Single byte clz table implementation with
// special case for clz(0) -> 8 to support
// 9 bit maximum value with 8 bit input.

static
uint8_t clz_byte[256] = {
    8, 7, 6, 6, 5, 5, 5, 5,
    4, 4, 4, 4, 4, 4, 4, 4,
    3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3, 3,
    2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0
};

ushort
clz4Byte(uint8_t byteVal)
{
    return clz_byte[byteVal];
}

// branchless version

ushort
offset_to_num_neg(ushort value) {
    ushort oneIfOddZeroIfEven = (value & 0x1);
    // case 0    : val
    // case even : (value / 2);
    // case odd  : ((value+1) / 2)
    ushort valDiv2 = (value + oneIfOddZeroIfEven) >> 1;
    // even = 1 - 0 - 0 = 1
    // odd  = 1 - 1 - 1 = -1
    short negOneIfOddOneIfEven = 1 - oneIfOddZeroIfEven - oneIfOddZeroIfEven;
    // Represent as unsigned byte
    return ushort(valDiv2 * negOneIfOddOneIfEven);
}

// Shader decode loop simulation that is able to decode
// multiple symbols from a block by looking block start
// offset up in a table. Note that this impl assumes
// that there are at least 2 padding bytes at the end
// of huffBuff so that read ahead does not go past the
// end of a buffer.

void
Eliasg_decodeBlockSymbols(
                               int numSymbolsToDecode,
                               uint8_t *bitBuff,
                               int bitBuffN,
                               uint8_t *outBuffer,
                               uint32_t *blockStartBitOffsetsPtr)
{
    uint16_t inputBitPattern = 0;
    unsigned int numBitsRead = 0;
    
    const int debugOut = 0;
    const int debugOutShowEmittedSymbols = 0;
    
    int symbolsLeftToDecode = numSymbolsToDecode;
    int symboli = 0;
    
    int outOffseti = 0;
    
    const int blockDim = 8;
    int blocki = 0;
    
    // Init first symbol to zero, will be reset to zero each time a block
    // has been fully read.
    ushort prevSymbol = 0;
    
    for ( ; symbolsLeftToDecode > 0; symbolsLeftToDecode--, symboli++ ) {
        // Gather a 16 bit pattern by reading 2 or 3 bytes.
        
        if (debugOut) {
            printf("decode symbol number %5d : numBitsRead %d\n", symboli, numBitsRead);
        }
        
        if (symboli != 0 && ((symboli % (blockDim * blockDim)) == 0)) {
            blocki += 1;
            
            // When starting a new block, check that numBitsRead matches
            // the block start offset.
            
            int blockBitOffset = blockStartBitOffsetsPtr[blocki];
            assert(numBitsRead == blockBitOffset);
            
            prevSymbol = 0;
        }
        
        const unsigned int numBytesRead = (numBitsRead / 8);
        const unsigned int numBitsReadMod8 = (numBitsRead % 8);
        
        // Read 3 bytes where a partial number of bits
        // is used from the first byte, then all the
        // bits in the second pattern are used, followed
        // by a partial number of bits from the 3rd byte.
#if defined(DEBUG)
        assert((numBytesRead+2) < bitBuffN);
#endif // DEBUG
        
        unsigned int b0 = bitBuff[numBytesRead];
        unsigned int b1 = bitBuff[numBytesRead+1];
        unsigned int b2 = bitBuff[numBytesRead+2];
        
        if (debugOut) {
            printf("read byte %5d : pattern %s\n", numBytesRead, get_code_bits_as_string(b0, 16).c_str());
            printf("read byte %5d : pattern %s\n", numBytesRead+1, get_code_bits_as_string(b1, 16).c_str());
            printf("read byte %5d : pattern %s\n", numBytesRead+2, get_code_bits_as_string(b2, 16).c_str());
        }
        
        // Prepare the input bytes using shifts so that the results always
        // fit into 16 bit intermediate registers.
        
        // Left shift the already consumed bits off left side of b0
        b0 <<= numBitsReadMod8;
        b0 &= 0xFF;
        
        if (debugOut) {
            printf("b0 %s\n", get_code_bits_as_string(b0, 16).c_str());
        }
        
        b0 = b0 << 8;
        
        if (debugOut) {
            printf("b0 %s\n", get_code_bits_as_string(b0, 16).c_str());
        }
        
        inputBitPattern = b0;
        
        if (debugOut) {
            printf("inputBitPattern (b0) %s : binary length %d\n", get_code_bits_as_string(inputBitPattern, 16).c_str(), 16);
        }
        
        // Left shift the 8 bits in b1 then OR into inputBitPattern
        
        if (debugOut) {
            printf("b1 %s\n", get_code_bits_as_string(b1, 16).c_str());
        }
        
        b1 <<= numBitsReadMod8;
        
        if (debugOut) {
            printf("b1 %s\n", get_code_bits_as_string(b1, 16).c_str());
        }
        
#if defined(DEBUG)
        assert((inputBitPattern & b1) == 0);
#endif // DEBUG
        
        inputBitPattern |= b1;
        
        if (debugOut) {
            printf("inputBitPattern (b1) %s : binary length %d\n", get_code_bits_as_string(inputBitPattern, 16).c_str(), 16);
        }
        
        if (debugOut) {
            printf("b2 %s\n", get_code_bits_as_string(b2, 16).c_str());
        }
        
        // Right shift b2 to throw out unused bits
        b2 >>= (8 - numBitsReadMod8);
        
        if (debugOut) {
            printf("b2 %s\n", get_code_bits_as_string(b2, 16).c_str());
        }
        
#if defined(DEBUG)
        assert((inputBitPattern & b2) == 0);
#endif // DEBUG
        
        inputBitPattern |= b2;
        
        if (debugOut) {
            printf("inputBitPattern (b2) %s : binary length %d\n", get_code_bits_as_string(inputBitPattern, 16).c_str(), 16);
        }
        
        if (debugOut) {
            printf("input bit pattern %s : binary length %d\n", get_code_bits_as_string(inputBitPattern, 16).c_str(), 16);
        }
        
        ushort countOfZeros = clz4Byte(uint8_t(inputBitPattern >> 8));
        
        // Shift left to place MSB of symbol at the MSB of 16 bit register
        ushort shiftedLeft = inputBitPattern << countOfZeros;
        
        // Shift right to place MSB of value at correct bit offset
        ushort shiftedRight = shiftedLeft >> (16 - (countOfZeros+1));
        
        VariableBitWidthSymbol vws;
        vws.symbol = (shiftedRight - 1);;
        vws.bitWidth = ((countOfZeros << 1) + 1); // ((countOfZeros * 2) + 1);
        
        if (debugOut) {
            printf("decoded elias symbol %d\n", vws.symbol);
        }
        
        numBitsRead += vws.bitWidth;
        
        if (debugOut) {
            printf("consume symbol bits %d\n", vws.bitWidth);
        }
        
        // Convert positive delta back to signed byte value, then
        // apply delta to previous symbol and constrain to byte range
        
        uint8_t unsignedDelta = offset_to_num_neg(vws.symbol);
        ushort symbol = (prevSymbol + unsignedDelta) & 0xFF;
        outBuffer[outOffseti++] = symbol;
        prevSymbol = symbol;
        
        if (debugOut) {
            printf("write symbol %d\n", symbol & 0xFF);
        }
        
        if (debugOutShowEmittedSymbols) {
            printf("out[%5d] = %3d (aka 0x%02X) : bits %2d : total num bits %5d\n", outOffseti-1, symbol&0xFF, symbol, vws.bitWidth, numBitsRead-vws.bitWidth);
        }
    }
    
    return;
}


