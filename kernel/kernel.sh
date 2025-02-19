#!/bin/bash
#set -e
#Replace links accordingly

TG_CHAT="chat_token" 
TG_BOT="bot_token"

# Function to send message to Telegram
tg_post_msg() {
    curl -s -X POST "https://api.telegram.org/bot$TG_BOT/sendMessage" \
    -d chat_id="$TG_CHAT" \
    -d "disable_web_page_preview=true" \
    -d "parse_mode=html" \
    -d text="$1"
}

# Function to send document to Telegram
tg_post_doc() {
    curl --progress-bar -F document=@"$1" "https://api.telegram.org/bot$TG_BOT/sendDocument" \
    -F chat_id="$TG_CHAT"  \
    -F "disable_web_page_preview=true" \
    -F "parse_mode=html" \
    -F caption="$2"
}

# Initialize Toolchains
echo -e "$green Checking for GCC directories... $white"
if [ -d "$HOME/gcc64" ] && [ -d "$HOME/gcc32" ]; then
    echo -e "$green GCC directories already exist. Skipping clone. $white"
else
    echo -e "$green Cloning GCC toolchains... $white"
    git clone --depth=1 https://github.com/mvaisakh/gcc-arm64 "$HOME"/gcc64
    git clone --depth=1 https://github.com/mvaisakh/gcc-arm "$HOME"/gcc32
    echo -e "$green GCC toolchains cloned successfully. $white"
fi

# Initialize Clang
echo -e "$green Checking for Clang directory... $white"
if [ -d "$HOME/clang" ]; then
    echo -e "$green Clang directory already exists. Skipping clone. $white"
else
    echo -e "$green Cloning Clang... $white"
    git clone -b 14 --depth=1 https://bitbucket.org/shuttercat/clang "$HOME"/clang
    echo -e "$green Clang cloned successfully. $white"
fi

# Initialize Kernel
echo -e "$green Checking for Kernel directory... $white"
if [ -d "kernel" ]; then
    echo -e "$green Kernel directory 'kernel' already exists. Skipping clone. $white"
else
    echo -e "$green Cloning Kernel repository... $white"
    git clone https://github.com/narikootam-dev/kernel_xiaomi_msm4.14 -b 15 kernel
    echo -e "$green Kernel repository cloned successfully. $white"
fi

# Begin kernel compilation
cd kernel
KERNEL_DEFCONFIG=vendor/sweet_user_defconfig
date=$(date +"%Y-%m-%d-%H%M")
export ARCH=arm64
export SUBARCH=arm64
export zipname="MerakiKernel-sweet-${date}.zip"
export PATH="$HOME/gcc64/bin:$HOME/gcc32/bin:$PATH"
export STRIP="$HOME/gcc64/aarch64-elf/bin/strip"
export KBUILD_COMPILER_STRING=$("$HOME"/gcc64/bin/aarch64-elf-gcc --version | head -n 1)
export PATH="$HOME/clang/bin:$PATH"
export KBUILD_COMPILER_STRING=$("$HOME"/clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')

# Notify Telegram about the start of compilation
tg_post_msg "Kernel compilation started for device 'Sweet'."
COMMIT=$(git log --pretty=format:"%s" -5)
tg_post_msg "<b>Recent Changelogs:</b>%0A$COMMIT"

# Speed up build process
MAKE="./makeparallel"
BUILD_START=$(date +"%s")
blue='\033[0;34m'
cyan='\033[0;36m'
yellow='\033[0;33m'
red='\033[0;31m'
nocol='\033[0m'

echo "**** Kernel defconfig set to $KERNEL_DEFCONFIG ****"
echo -e "$blue***********************************************"
echo "          STARTING KERNEL BUILD          "
echo -e "***********************************************$nocol"
make $KERNEL_DEFCONFIG O=out CC=clang
make -j$(nproc --all) O=out \
                              ARCH=arm64 \
                              LLVM=1 \
                              LLVM_IAS=1 \
                              AR=llvm-ar \
                              NM=llvm-nm \
                              LD=ld.lld \
                              OBJCOPY=llvm-objcopy \
                              OBJDUMP=llvm-objdump \
                              STRIP=llvm-strip \
                              CC=clang \
                              CROSS_COMPILE=aarch64-linux-gnu- \
                              CROSS_COMPILE_ARM32=arm-linux-gnueabi-  2>&1 |& tee error.log

# Check if build was successful
export IMG="$MY_DIR"/out/arch/arm64/boot/Image.gz
export dtbo="$MY_DIR"/out/arch/arm64/boot/dtbo.img
export dtb="$MY_DIR"/out/arch/arm64/boot/dtb.img

find out/arch/arm64/boot/dts/ -name '*.dtb' -exec cat {} + >out/arch/arm64/boot/dtb
if [ -f "out/arch/arm64/boot/Image.gz" ] && [ -f "out/arch/arm64/boot/dtbo.img" ] && [ -f "out/arch/arm64/boot/dtb" ]; then
    git clone -q https://github.com/narikootam-dev/AnyKernel3
    cp out/arch/arm64/boot/Image.gz AnyKernel3
    cp out/arch/arm64/boot/dtb AnyKernel3
    cp out/arch/arm64/boot/dtbo.img AnyKernel3
    rm -f *zip
    cd AnyKernel3
    sed -i "s/is_slot_device=0/is_slot_device=auto/g" anykernel.sh
    zip -r9 "../${zipname}" * -x '*.git*' README.md *placeholder >> /dev/null
    cd ..
    rm -rf AnyKernel3
    echo -e "Build completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!"
    tg_post_msg "Build completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!"
    echo ""
    echo -e "Kernel package '${zipname}' is ready!"
    echo ""
    tg_post_msg "Kernel package '${zipname}' is ready!"
    rm -rf out
    rm -rf error.log
    tg_post_doc "${zipname}"
    rm -rf ${zipname}
else
    tg_post_msg "Kernel build failed."
    tg_post_doc "error.log" 
fi
