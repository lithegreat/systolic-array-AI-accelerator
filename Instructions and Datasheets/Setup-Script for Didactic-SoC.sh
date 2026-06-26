#!/bin/bash

if [ -d "${HOME}/Edu4Chip" ]; then
	echo "${HOME}/Edu4Chip already exists"
else
#### create Edu4Chip directory in HOME
cd ${HOME}
mkdir Edu4Chip
cd Edu4Chip

#### Download and extract bender
wget https://github.com/pulp-platform/bender/releases/download/v0.31.0/bender-0.31.0-x86_64-linux-gnu-ubuntu24.04.tar.gz
tar -xzf bender-0.31.0-x86_64-linux-gnu-ubuntu24.04.tar.gz --one-top-level=benderDir
rm bender-0.31.0-x86_64-linux-gnu-ubuntu24.04.tar.gz

#### clone Didactic-SoC repository
git clone https://github.com/Edu4Chip/Didactic-SoC.git
cd ${HOME}/Edu4Chip/Didactic-SoC
git checkout 618da1b0040121c79fed179a344a8e0438abad70

#### adjust Makefiles for 64-bit riscv compiler and fix some errors

cd ${HOME}/Edu4Chip/Didactic-SoC/sw
#### 64-bit compiler
sed -i "13s/32/64/"  Makefile
#### fix error
sed -i "38s/TEST/TESTCASE/"  Makefile

cd ${HOME}/Edu4Chip/Didactic-SoC/fpga
#### fix error
sed -i "11s/blink/blinky/"  Makefile
#### 64-bit compiler
sed -i "28s/riscv32-unknown-elf-gdb/riscv64-unknown-elf-gdb/"  Makefile

cd ${HOME}/Edu4Chip/Didactic-SoC/fpga/sw
#### 64-bit compiler
sed -i "12s/riscv32-unknown-elf-gcc/riscv64-unknown-elf-gcc/"  Makefile

cd ${HOME}/Edu4Chip/Didactic-SoC/fpga/sw/hello
#### change UART frequency to 25MHz as PLL of FPGA is configured for 25 MHz
sed -i "15s/8000000/25000000/"  hello.c
		
cd ${HOME}/Edu4Chip/Didactic-SoC/fpga/constraints
#### contstrain 2 GPIO-Pins to built-in LEDs of PYNQ-Z1 board
sed -i "64s/Y18/N15/"  z1.xdc
sed -i "81s/W13/M15/"  z1.xdc

cd ${HOME}/Edu4Chip/Didactic-SoC/fpga/utils
#### set serial number of FT4232H in openocd config file
#### the module has to be attached to the PC's USB-port during this step
serial=$(lsusb -v -d 0403:6011 | grep iSerial | sed -n 's/.* //p')
sed -i "2s/DEADBEEF/$serial/" openocd-didactic.cfg
#### set vid_pid of FT4232H in openocd config file
sed -i "6s/0x6010/0x6011/"  openocd-didactic.cfg

#### change simulation Makefile from CLI mode to GUI mode
cd ${HOME}/Edu4Chip/Didactic-SoC/sim
sed -i "92s/-c/-gui/" Makefile

#### initialize repository
export PATH=${HOME}/Edu4Chip/benderDir:$PATH
cd ${HOME}/Edu4Chip/Didactic-SoC
make repository_init
#### build questasim library
cd ${HOME}/Edu4Chip/Didactic-SoC/sim
module load mentor/questasim/2023.4
make compile
make elaborate
module unload mentor/questasim/2023.4

#### load riscv compiler environment module
module load eda_freeware/riscv/64-elf-ubuntu-24.04-gcc/2026.04.05
#### compile blink example code for simulation
cd ${HOME}/Edu4Chip/Didactic-SoC
make build_test
#### compile blink example code for FPGA
cd ${HOME}/Edu4Chip/Didactic-SoC/fpga/sw
make env
make build_test
#### compile UART hello example code for FPGA
sed -i "8s/blinky/hello/"  Makefile
make build_test
module unload eda_freeware/riscv/64-elf-ubuntu-24.04-gcc/2026.04.05

##### build FPGA project
cd ${HOME}/Edu4Chip/Didactic-SoC/fpga
module load xilinx/vivado/2024.1
make all_xilinx
module unload xilinx/vivado/2024.1
fi
