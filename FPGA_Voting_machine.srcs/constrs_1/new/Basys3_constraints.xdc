## Basys 3 Constraints File for FPGA Voting Machine
## Board: Digilent Basys 3 (XC7A35T-1CPG236C)

## Clock signal (100 MHz)
set_property PACKAGE_PIN W5 [get_ports clock]
set_property IOSTANDARD LVCMOS33 [get_ports clock]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clock]

## Reset - Center push button (BTNC)
set_property PACKAGE_PIN U18 [get_ports reset]
set_property IOSTANDARD LVCMOS33 [get_ports reset]

## Mode switch - SW0
set_property PACKAGE_PIN V17 [get_ports mode]
set_property IOSTANDARD LVCMOS33 [get_ports mode]

## Voting Buttons
# Button 1 (Candidate 1) - BTNU (Up)
set_property PACKAGE_PIN T18 [get_ports button1]
set_property IOSTANDARD LVCMOS33 [get_ports button1]

# Button 2 (Candidate 2) - BTNL (Left)
set_property PACKAGE_PIN W19 [get_ports button2]
set_property IOSTANDARD LVCMOS33 [get_ports button2]

# Button 3 (Candidate 3) - BTNR (Right)
set_property PACKAGE_PIN T17 [get_ports button3]
set_property IOSTANDARD LVCMOS33 [get_ports button3]

# Button 4 (Candidate 4) - BTND (Down)
set_property PACKAGE_PIN U17 [get_ports button4]
set_property IOSTANDARD LVCMOS33 [get_ports button4]

## LEDs
set_property PACKAGE_PIN U16 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

set_property PACKAGE_PIN E19 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

set_property PACKAGE_PIN U19 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]

set_property PACKAGE_PIN V19 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

set_property PACKAGE_PIN W18 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[4]}]

set_property PACKAGE_PIN U15 [get_ports {led[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[5]}]

set_property PACKAGE_PIN U14 [get_ports {led[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[6]}]

set_property PACKAGE_PIN V14 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[7]}]

## Configuration options
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
