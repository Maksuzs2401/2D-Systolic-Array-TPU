create_clock -period 5.000 -name clk [get_ports clk]

create_pblock pblock_2
add_cells_to_pblock [get_pblocks pblock_2] [get_cells -quiet [list top_layer]]
resize_pblock [get_pblocks pblock_2] -add {SLICE_X0Y60:SLICE_X53Y179}
resize_pblock [get_pblocks pblock_2] -add {DSP48E2_X0Y24:DSP48E2_X7Y71}
resize_pblock [get_pblocks pblock_2] -add {RAMB18_X0Y24:RAMB18_X3Y71}
resize_pblock [get_pblocks pblock_2] -add {RAMB36_X0Y12:RAMB36_X3Y35}
