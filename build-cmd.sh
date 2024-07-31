#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# bleat on references to undefined shell variables
set -u

LIBJPEG_TURBO_SOURCE_DIR="libjpeg-turbo"

top="$(pwd)"
stage="$top"/stage

# load autobuild provided shell functions and variables
case "$AUTOBUILD_PLATFORM" in
    windows*)
        autobuild="$(cygpath -u "$AUTOBUILD")"
    ;;
    *)
        autobuild="$AUTOBUILD"
    ;;
esac
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

top="$(pwd)"
stage="$top/stage"
stage_include="$stage/include/jpeglib"
stage_debug="$stage/lib/debug"
stage_release="$stage/lib/release"
mkdir -p "$stage_include"
mkdir -p "$stage_debug"
mkdir -p "$stage_release"

VERSION_HEADER_FILE="$stage_include/jconfig.h"

pushd "$LIBJPEG_TURBO_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            mkdir -p "build"
            pushd "build"
                # Invoke cmake and use as official build
                cmake -G "Ninja Multi-Config" ../ -DWITH_JPEG8=ON -DWITH_CRT_DLL=ON -DWITH_SIMD=ON -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DREQUIRE_SIMD=ON

                cmake --build . --config Debug
                cmake --build . --config Release

                # conditionally run unit tests
                #if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                #    ctest -C Debug
                #    ctest -C Release
                #fi

                cp -a Debug/jpeg-static.lib "$stage_debug/jpeg.lib"
                cp -a Debug/turbojpeg-static.lib "$stage_debug/turbojpeg.lib"
                cp -a Release/jpeg-static.lib "$stage_release/jpeg.lib"
                cp -a Release/turbojpeg-static.lib "$stage_release/turbojpeg.lib"

                cp -a "jconfig.h" "$stage_include"
            popd

            cp -a jerror.h "$stage_include"
            cp -a jmorecfg.h "$stage_include"
            cp -a jpeglib.h "$stage_include"
            cp -a turbojpeg.h "$stage_include"
        ;;
        darwin*)
            opts="${TARGET_OPTS:--arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD_RELEASE}"

            mkdir -p "build_release_x86"
            pushd "build_release_x86"
                CFLAGS="$opts" \
                CXXFLAGS="$opts" \
                cmake .. -G Ninja -DWITH_JPEG8=ON -DWITH_SIMD=ON -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DREQUIRE_SIMD=ON \
                    -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$opts" \
                    -DCMAKE_CXX_FLAGS="$opts" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/release_x86"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                # if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                #     ctest -C Release
                # fi
            popd

            # mkdir -p "build_release_arm64"
            # pushd "build_release_arm64"
            #     CFLAGS="$C_OPTS_ARM64" \
            #     CXXFLAGS="$CXX_OPTS_ARM64" \
            #     LDFLAGS="$LINK_OPTS_ARM64" \
            #     cmake .. -G Ninja -DWITH_JPEG8=ON -DWITH_SIMD=ON -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DREQUIRE_SIMD=ON \
            #         -DCMAKE_BUILD_TYPE="Release" \
            #         -DCMAKE_C_FLAGS="$C_OPTS_ARM64" \
            #         -DCMAKE_CXX_FLAGS="$CXX_OPTS_ARM64" \
            #         -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
            #         -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
            #         -DCMAKE_MACOSX_RPATH=YES \
            #         -DCMAKE_INSTALL_PREFIX="$stage/release_arm64"

            #     cmake --build . --config Release
            #     cmake --install . --config Release

            #     # conditionally run unit tests
            #     # if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            #     #     ctest -C Release
            #     # fi
            # popd

            # create fat libraries
            # lipo -create ${stage}/release_x86/lib/libjpeg.a ${stage}/release_arm64/lib/libjpeg.a -output ${stage}/lib/release/libjpeg.a
            # lipo -create ${stage}/release_x86/lib/libturbojpeg.a ${stage}/release_arm64/lib/libturbojpeg.a -output ${stage}/lib/release/libturbojpeg.a

            # copy headers
            cp -a ${stage}/release_x86/lib/libjpeg.a ${stage}/lib/release/libjpeg.a
            mv $stage/release_x86/include/* $stage_include
        ;;
        linux*)
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            unset DISTCC_HOSTS CFLAGS CPPFLAGS CXXFLAGS

            # Default target per --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"

            mkdir -p "$stage/lib/release"

            mkdir -p "build_release"
            pushd "build_release"
                # Invoke cmake and use as official build
                cmake -E env CFLAGS="$opts" CXXFLAGS="$opts" \
                cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" -DWITH_JPEG8=ON -DWITH_SIMD=ON -DREQUIRE_SIMD=ON -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
                                  -DCMAKE_C_FLAGS="$opts" \
                                  -DCMAKE_CXX_FLAGS="$opts"

                cmake --build . -j$AUTOBUILD_CPU_COUNT --config Release --clean-first

                # conditionally run unit tests
                # if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                #     ctest -C Release
                # fi

                cp -a libjpeg.a "$stage_release/"
                cp -a libturbojpeg.a "$stage_release/"

                cp -a "jconfig.h" "$stage_include"
            popd

            cp -a jerror.h "$stage_include"
            cp -a jmorecfg.h "$stage_include"
            cp -a jpeglib.h "$stage_include"
            cp -a turbojpeg.h "$stage_include"
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp LICENSE.md "$stage/LICENSES/libjpeg-turbo.txt"

    # version will be (e.g.) "1.4.0"
    version=`sed -n -E 's/#define LIBJPEG_TURBO_VERSION  ([0-9])[.]([0-9])[.]([0-9]).*/\1.\2.\3/p' "${VERSION_HEADER_FILE}"`
    # shortver will be (e.g.) "230": eliminate all '.' chars
    #since the libs do not use micro in their filenames, chop off shortver at minor
    short="$(echo $version | cut -d"." -f1-2)"
    shortver="${short//.}"

    echo "${version}" > "${stage}/VERSION.txt"
popd
