import_device eagle_s20.db -package EG4S20BG256
open_project HDMI1.4b_Transmitter_v1.0.prj -noanalyze
import_db HDMI1.4b_Transmitter_v1.0_pr.db
write_verilog diagnostic_route_before_hold.v -implement
exit
