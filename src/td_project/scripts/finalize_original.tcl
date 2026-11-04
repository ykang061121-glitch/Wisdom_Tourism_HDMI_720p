import_device eagle_s20.db -package EG4S20BG256
open_project HDMI1.4b_Transmitter_v1.0.prj -noanalyze
import_db HDMI1.4b_Transmitter_v1.0_pr.db
read_sdc ../../../user_source/constraints_source/postroute_reset.sdc
update_timing -mode final
report_timing_summary -file dp_before_fix_hold.rpt -ep_num 128 -path_num 1
fix_hold
update_timing -mode final
report_timing_summary -file final_timing.rpt -ep_num 128 -path_num 1
report_area -io_info -file HDMI1.4b_Transmitter_v1.0_phy.area
export_db HDMI1.4b_Transmitter_v1.0_pr.db
bitgen -bit HDMI1.4b_Transmitter_v1.0.bit
report_timing_status -file dp_final.ts
flow_status -file dp_final_flow.status
exit
