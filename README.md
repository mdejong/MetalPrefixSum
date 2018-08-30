# MetalPrefixSum

A GPU based parallel prefix sum implementation that operates on byte values. Supports both inclusive scan and exclusive scan.

## Overview

This project demonstrates how Metal can be used to implement code to apply a delta to image data.

## Status

This encoder/decoder implementation of GPU based delta is a test of parallel block based decoding speed.

## Decoding Speed

Please note that current results indicate decoding on the CPU is significantly faster than decoding on the GPU, since each decoding step in a block has to wait until the previous one has completed. Processing blocks in parallel does not appear to be competitive when compared to executing on the CPU.

## Implementation

See AAPLRenderer.m and AAPLShaders.metal for the core GPU rendering logic.

