# Same audited logical reset boundary, mapped by current Q/MI connectivity.
set reset_entry_0 [get_pins {frame_read_write_m0/read_buf/asy_r_rst1_reg_syn_4.sr}]
if {[llength $reset_entry_0] != 1} {error "Reset entry mismatch; stop"}
set_false_path -from [get_clocks ext_mem_clk] -to $reset_entry_0
