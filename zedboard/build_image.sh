#!/bin/bash

#-----------------------
# A script to rebuild all components for the FPGA image
#-----------------------

orig_path=$PWD

#### Check paths and available tools

echo "Checking for environment variables..."

# Check $RISCV is set
if [ "$RISCV" == "" ]; then
    echo "Error: Please set up the RISCV environment variables and run again."
    exit 1
fi

if [ "$TOP" == "" ]; then
    echo "Error: Please set variable $$TOP to the lowrisc-chip directory and run again."
    exit 1
fi

# check for Xilinx vivado
vivado_path=`which vivado`
if [ "$vivado_path" == "" ]; then
    echo "Error: Please set up the Xilinx environment variables and run again."
    exit 1
fi
    
# check for vivado version
vivado_version=`vivado -version`
if [[ "$vivado_version" != *v2014.4* ]]; then
    echo "Warning: You are using a Xilinx Vivado other than 2014.4. There may be problem in generating FPGA bitstreams."
fi

echo "Checking for cross-compiling tools..."

# check for riscv-tools
riscv_elf_gcc=`which riscv64-unknown-elf-gcc`
if [ "$riscv_elf_gcc" == "" ]; then
    echo "Compiling the riscv64-unknwon-elf toolchain..."
    cd $TOP
    git submodule update --init riscv-tools
    cd riscv-tools
    git submodule update --init --recursive
    ./build.sh
    echo "The riscv64-unknwon-elf toolchain compiled."
fi

riscv_linux_gcc=`which riscv-linux-gcc`
if [ "$riscv_elf_gcc" == "" ]; then
    echo "Compiling the riscv-linux toolchain..."
    cd $TOP
    git submodule update --init riacv-tools
    cd riscv-tools
    git clone https://github.com/lowrisc/riscv-gcc.git
    cd riscv-gcc
    mkdir build
    cd build
    ../configure --prefix=$RISCV
    make -j linux
    echo "The riscv-linux toolchain compiled."
fi

#### Build the bitstream 

echo "Build the boot.bin..."

cd $TOP
git submodule update --init rocket uncore chisel hardfloat
cd $TOP/fpga-zynq/zedboard
git submodule update --init --recursive

echo "Step 1: Build the FPGA bitstream..."

make rocket
make bitstream

#### Build the FSBL

echo "Step 2: Build the FSBL..."

make fsbl

#### Build the ARM u-boot

echo "Step 3: Build the ARM u-boot..."

make arm-uboot
cp soft_build/u-boot.elf fpga-images-zedboar/boot_image/

#### Build the boot.bin

echo "Finally: Generate the boot.bin..."

rm fpga-images-zedboar/boot.bin
make fpga-images-zedboar/boot.bin

#### Build the fesvr-zynq

echo "Build fesvr-zynq..."

cd $TOP/riscv-tools/riscv-fesvr
if [ ! -d build_fpga ]; then
    mkdir build_fpga
fi
cd build_fpga
../configure --host=arm-xilinx-linux-gnueabi
make -j

#### Build proxy kernel (pk)

echo "Build proxy kernel (pk)..."

cd $TOP/riscv-tools/riscv-pk
if [ ! -d build ]; then
    mkdir build
fi
cd build
../configure --prefix=$RISCV/riscv64-unknown-elf --host=riscv64-unknown-elf
make -j

#### prepare the ARM ramdisk

echo "Prepare the ARM RAMDisk..."
echo "[Note] Root password is needed."

cd $TOP/fpga-zynq/zedboard
make ramdisk-open
sudo cp $TOP/riscv-tools/riscv-fesvr/build_fpga/fesvr-zedboard ramdisk/home/root/fesvr-zynq
sudo cp $TOP/riscv-tools/riscv-fesvr/build_fpga/libfesvr.so ramdisk/usr/local/lib/libfesvr.so
sudo cp $TOP/riscv-tools/riscv-pk/build/pk ramdisk/home/root/pk
make ramdisk-close
sudo \rm -fr ramdisk

#### Build the ARM Linux kernel

echo "Build the ARM Linux kernel..."
make arm-linux
cp deliver_output/uImage fpga-images-zedboard/uImage

echo "Generate Zynq ARM device map..."
make arm-dtb
cp deliver_output/devicetree.dtb fpga-images-zedboard/devicetree.dtb

#### Build the RISC-V Linux Kernel

echo "Build the RISC-V Linux Kernel..."
cd $TOP/riscv-tools
if [ ! -d linux-3.14.13 ]; then
    curl https://www.kernel.org/pub/linux/kernel/v3.x/linux-3.14.13.tar.xz | tar -xJ
    cd linux-3.14.13
    git init
    git remote add origin https://github.com/riscv/riscv-linux.git
    git fetch
    # currently we use an old version of riscv-linux
    git checkout -f 989153f
fi
make ARCH=riscv defconfig
make ARCH=riscv -j vmlinux
cp vmlinux $TOP/fpga-zynq/zedboard/fpga-images-zedboard/riscv/vmlinux

#### Build the Busybox init

echo "Build the Busybox init tools and the RISC-V RAMDisk..."

cd $TOP/riscv-tools
if [ ! -d busybox-1.21.1 ]; then
    curl -L http://busybox.net/downloads/busybox-1.21.1.tar.bz2 | tar -xj
fi
cd busybox-1.21.1
cp $TOP/riscv-tools/busybox_config .config
make -j

$TOP/riscv-tools/make_root.sh
cp root.bin $TOP/fpga-zynq/zedboard/fpga-images-zedboard/riscv/root.bin

#### Finished
echo ""
echo "--------------------------------------------------------------------------------"
echo "The following files have been build in fpga-images-zedboard:"
echo "  boot.bin boot_image/system.bit boot_image/u-boot.elf boot_image/zynq_fsbl.elf"
echo "  devicetree riscv/vmlinux riscv/root.bin uImage uramdisk.image.gz"

cd $orig_path
