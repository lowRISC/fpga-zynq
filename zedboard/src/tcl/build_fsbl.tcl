#!/usr/bin/tclsh
set_workspace zedboard_rocketchip/zedboard_rocketchip.sdk
create_project -type hw -name rocketchip_wrapper_hw_platform_0 -hwspec zedboard_rocketchip/zedboard_rocketchip.sdk/rocketchip_wrapper.hdf
create_project -type app -name FSBL -hwproject rocketchip_wrapper_hw_platform_0 -proc ps7_cortexa9_0 -os standalone -lang C -app {Zynq FSBL}
build -type all
exit

