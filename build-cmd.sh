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

# remove_cxxstd
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

top="$(pwd)"
stage="$top/stage"
stage_include="$stage/include/jpeglib"
stage_release="$stage/lib/release"
mkdir -p "$stage_include"
mkdir -p "$stage_release"

pushd "$LIBJPEG_TURBO_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            opts="$(replace_switch /Zi /Z7 $LL_BUILD_RELEASE)"
            plainopts="$(remove_switch /GR $(remove_cxxstd $opts))"

            mkdir -p "$stage/lib/release"

            mkdir -p "build"
            pushd "build"
                # Invoke cmake and use as official build
                cmake -G "Ninja Multi-Config" ../ \
                    -DCMAKE_C_FLAGS:STRING="$plainopts" \
                    -DCMAKE_CXX_FLAGS:STRING="$opts" \
                    -DWITH_JPEG8=ON -DWITH_CRT_DLL=ON -DWITH_SIMD=ON \
                    -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DREQUIRE_SIMD=ON

                cmake --build . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                   ctest -C Release
                fi

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
            export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

            for arch in x86_64 arm64 ; do
                ARCH_ARGS="-arch $arch"
                opts="${TARGET_OPTS:-$ARCH_ARGS $LL_BUILD_RELEASE}"
                cc_opts="$(remove_cxxstd $opts)"
                ld_opts="$ARCH_ARGS"

                mkdir -p "build_$arch"
                pushd "build_$arch"
                    CFLAGS="$cc_opts" \
                    CXXFLAGS="$opts" \
                    LDFLAGS="$ld_opts" \
                    cmake .. -G Ninja -DWITH_JPEG8=ON -DWITH_SIMD=ON -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DREQUIRE_SIMD=ON \
                        -DCMAKE_BUILD_TYPE="Release" \
                        -DCMAKE_C_FLAGS="$cc_opts" \
                        -DCMAKE_CXX_FLAGS="$opts" \
                        -DCMAKE_OSX_ARCHITECTURES:STRING="$arch" \
                        -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                        -DCMAKE_MACOSX_RPATH=YES \
                        -DCMAKE_INSTALL_PREFIX="$stage" \
                        -DCMAKE_INSTALL_LIBDIR="$stage/lib/release/$arch" \
                        -DCMAKE_INSTALL_INCLUDEDIR="$stage_include"

                    cmake --build . --config Release --parallel $AUTOBUILD_CPU_COUNT
                    cmake --install . --config Release

                    # conditionally run unit tests
                    if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                        ctest -C Release --parallel $AUTOBUILD_CPU_COUNT
                    fi
                popd
            done

            # create fat libraries
            lipo -create -output ${stage}/lib/release/libjpeg.a ${stage}/lib/release/x86_64/libjpeg.a ${stage}/lib/release/arm64/libjpeg.a
            lipo -create -output ${stage}/lib/release/libturbojpeg.a ${stage}/lib/release/x86_64/libturbojpeg.a ${stage}/lib/release/arm64/libturbojpeg.a
        ;;
        linux*)
            # Default target per --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"
            plainopts="$(remove_cxxstd $opts)"

            mkdir -p "$stage/lib/release"

            mkdir -p "build_release"
            pushd "build_release"
                # Invoke cmake and use as official build
                cmake .. -G Ninja -DCMAKE_BUILD_TYPE="Release" \
                                -DWITH_JPEG8=ON -DWITH_SIMD=ON -DREQUIRE_SIMD=ON \
                                -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
                                -DCMAKE_C_FLAGS="$plainopts" \
                                -DCMAKE_CXX_FLAGS="$opts"

                cmake --build . -j$AUTOBUILD_CPU_COUNT --config Release --clean-first

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi

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
popd
