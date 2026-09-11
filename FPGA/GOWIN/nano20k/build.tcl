# Gowin Tcl Batch Build Script for Sipeed Tang Nano 20K
# Project: TinyQV RISC-V SoC with RV2A03 NES APU
# Target FPGA: Gowin GW2AR-LV18QN88C8/I7 (GW2AR-18C)

# Always execute in the directory where this script and project reside
set script_dir [file dirname [file normalize [info script]]]
cd $script_dir

# Default target process is "all" (synthesis + place & route + bitstream)
set target "all"
if {$argc > 0} {
    set target [lindex $argv 0]
}

puts "============================================================"
puts "  TinyQV RV2A03 Tang Nano 20K - Gowin EDA Build Flow"
puts "  Target: $target"
puts "  Working Dir: $script_dir"
puts "============================================================"

# Open Gowin project
if {[catch {open_project nano20k.gprj} err]} {
    puts stderr "ERROR: Failed to open project nano20k.gprj: $err"
    exit 1
}

# Ensure critical project options are set
set_option -top_module tangnano20k_top
set_option -verilog_std sysv2017
set_option -use_sspi_as_gpio 1

# Execute flow
if {$target == "syn"} {
    puts "==> Running Logic Synthesis..."
    if {[catch {run syn} err]} {
        puts stderr "ERROR: Synthesis failed: $err"
        exit 1
    }
} elseif {$target == "pnr"} {
    puts "==> Running Place & Route..."
    if {[catch {run pnr} err]} {
        puts stderr "ERROR: Place & Route failed: $err"
        exit 1
    }
} else {
    puts "==> Running Full Flow: Synthesis, PnR, Bitstream Generation..."
    if {[catch {run all} err]} {
        puts stderr "ERROR: Build failed: $err"
        exit 1
    }
}

puts "============================================================"
puts "  Gowin Build Finished Successfully!"
puts "============================================================"
exit 0
