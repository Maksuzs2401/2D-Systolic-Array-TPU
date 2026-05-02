create_clock -period 5.000 -name clk [get_ports clk]

create_pblock pblock_1
add_cells_to_pblock [get_pblocks pblock_1] [get_cells -quiet [list top_layer]]
resize_pblock [get_pblocks pblock_1] -add {SLICE_X0Y0:SLICE_X30Y179}
resize_pblock [get_pblocks pblock_1] -add {DSP48E2_X0Y0:DSP48E2_X3Y71}
resize_pblock [get_pblocks pblock_1] -add {RAMB18_X0Y0:RAMB18_X1Y71}
resize_pblock [get_pblocks pblock_1] -add {RAMB36_X0Y0:RAMB36_X1Y35}
