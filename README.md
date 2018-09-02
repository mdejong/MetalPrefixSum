# MetalPrefixSum

A GPU based parallel prefix sum implementation that operates on byte values. Supports both inclusive scan and exclusive scan.

## Overview

This project demonstrates how Metal can be used to implement code to apply a delta to image data. Processes 8x8 blocks by default.

## Status

This encoder/decoder implementation of GPU based delta is a test of parallel block based decoding speed.

## Decoding Speed

Currently, the 2D fragment shader based implementation is not fast enough to process full screen video at 30 FPS.

## Implementation

See AAPLRenderer.m and AAPLShaders.metal for the core GPU rendering logic.

