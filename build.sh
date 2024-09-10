#!/bin/bash
set -e

PROJECTS="edk2 edk2-platforms mbedtls ms-tpm-20-ref optee_os trusted-firmware-a u-boot"

cd ..
for P in $PROJECTS; do
    git clone https://github.com/mt-at-mt/$P.git
    cd $P
    git submodule init
    git submodule update --recursive
    cd -
done

cd build-efi-firmware
make -f verdin.mk -j`nproc`

mkdir -p out
cp ../u-boot/flash.bin out
cp uuu.auto out
