//-------------------------------------------------------------------------------
//
// $Id: vdp18_col_pack-p.vhd,v 1.3 2006/02/28 22:30:41 arnim Exp $
//
// Copyright (c) 2006, Arnim Laeuger (arnim.laeuger@gmx.net)
//
// All rights reserved
//
//-------------------------------------------------------------------------------
package vdp18_col_pack;

  // Define constants for RGB indices
  parameter int r_c = 0;
  parameter int g_c = 1;
  parameter int b_c = 2;

  // Define types for RGB values and tables
  typedef int unsigned rgb_val_t;
  typedef rgb_val_t rgb_triple_t[3];
  typedef rgb_triple_t rgb_table_t[16];

  // Simple RGB Value Array
  // Refer to http://junior.apk.net/~drushel/pub/coleco/twwmca/wk970202.html
  // This is the MF & MdK variant. Note: only the upper three bits are used.
  const rgb_table_t compat_rgb_table_c = '{
    '{  0,   0,   0},                    // Transparent
    '{  0,   0,   0},                    // Black
    '{ 32, 192,  32},                    // Medium Green
    '{ 96, 224,  96},                    // Light Green
    '{ 32,  32, 224},                    // Dark Blue
    '{ 64,  96, 224},                    // Light Blue
    '{160,  32,  32},                    // Dark Red
    '{ 64, 192, 224},                    // Cyan
    '{224,  32,  32},                    // Medium Red
    '{224,  96,  96},                    // Light Red
    '{192, 192,  32},                    // Dark Yellow
    '{192, 192, 128},                    // Light Yellow
    '{ 32, 128,  32},                    // Dark Green
    '{192,  64, 160},                    // Magenta
    '{160, 160, 160},                    // Gray
    '{224, 224, 224}                     // White
  };

  // Full RGB Value Array
  // Refer to tms9928a.c of the MAME source distribution.
  const rgb_table_t full_rgb_table_c = '{
    '{  0,   0,   0},                    // Transparent
    '{  0,   0,   0},                    // Black
    '{ 33, 200,  66},                    // Medium Green
    '{ 94, 220, 120},                    // Light Green
    '{ 84,  85, 237},                    // Dark Blue
    '{125, 118, 252},                    // Light Blue
    '{212,  82,  77},                    // Dark Red
    '{ 66, 235, 245},                    // Cyan
    '{252,  85,  84},                    // Medium Red
    '{255, 121, 120},                    // Light Red
    '{212, 193,  84},                    // Dark Yellow
    '{230, 206, 128},                    // Light Yellow
    '{ 33, 176,  59},                    // Dark Green
    '{201,  91, 186},                    // Magenta
    '{204, 204, 204},                    // Gray
    '{255, 255, 255}                     // White
  };

endpackage : vdp18_col_pack