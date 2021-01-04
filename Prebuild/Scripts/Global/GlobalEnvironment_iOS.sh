#!/usr/bin/env bash

set -e

if [ ! -z "$CHOST" ]; then
	export CHOST;
else
	case $ARCH in
		arm64 )
			export CHOST=aarch64-apple-darwin*;
			;;
		x86_64 )
			export CHOST=$ARCH-apple-darwin*;
			;;
		* )
			mEchoError "Wrong or old host";
			;;
	esac;
fi

if [ ! -z "$SDK" ]; then
	export SDK;
else
	case $ARCH in
		arm64 )
			export SDK=iphoneos;
			;;
		x86_64 )
			export SDK=iphonesimulator;
			;;
		* )
			mEchoError "Wrong or old arch";
			;;
	esac;
fi;

if [ ! -z "$SDKVERSION" ]; then
	SDKNAME=$(basename $(xcrun --sdk $SDK --show-sdk-platform-path) .platform);
	export SDKVERSION;
	export SDKROOT=$(xcrun --sdk $SDK --show-sdk-platform-path)"/Developer/SDKs/$SDKNAME.$SDKVERSION.sdk";
else
	export SDKVERSION=$(xcrun --sdk $SDK --show-sdk-version);
	export SDKROOT=$(xcrun --sdk $SDK --show-sdk-path);
fi

if [ ! -z "$PREFIX" ]; then
	export PREFIX;
else
	export PREFIX="/opt/$SDK-$SDKVERSION/$ARCH";
fi

export CC=$(xcrun --sdk $SDK --find gcc);
export CPP=$(xcrun --sdk $SDK --find gcc)" -E";
export CXX=$(xcrun --sdk $SDK --find g++);
export LD=$(xcrun --sdk $SDK --find ld);
export RANLIB=$(xcrun --sdk $SDK --find ranlib);
export AR=$(xcrun --sdk $SDK --find ar);
export AS=$(xcrun --sdk $SDK --find as);
export NM=$(xcrun --sdk $SDK --find nm);

export CFLAGS="$CFLAGS -arch $ARCH -isysroot $SDKROOT -I$PREFIX/include -miphoneos-version-min=${A_IPHONE_MIN} -fembed-bitcode";
export CPPFLAGS="$CPPFLAGS -arch $ARCH -isysroot $SDKROOT -I$PREFIX/include -miphoneos-version-min=${A_IPHONE_MIN} -fembed-bitcode";
export CXXFLAGS="$CXXFLAGS -arch $ARCH -isysroot $SDKROOT -I$PREFIX/include ${A_CXXFLAG_STD}";
export LDFLAGS="$LDFLAGS -arch $ARCH -isysroot $SDKROOT";
export PKG_CONFIG_PATH="$PKG_CONFIG_PATH":"$SDKROOT/usr/lib/pkgconfig":"$PREFIX/lib/pkgconfig";

echo "ARCH: ${ARCH}";
echo "CHOST: ${CHOST}";
echo "SDK: ${SDK}";
echo "SDKVERSION: ${SDKVERSION}";
echo "SDKNAME: ${SDKNAME}";
echo "SDKROOT: ${SDKROOT}";
echo "PREFIX: ${PREFIX}";
echo "CC: ${CC}";
echo "CPP: ${CPP}";
echo "CXX: ${CXX}";
echo "LD: ${LD}";
echo "RANLIB: ${RANLIB}";
echo "AR: ${AR}";
echo "AS: ${AS}";
echo "NM: ${NM}";
echo "CFLAGS: ${CFLAGS}";
echo "CPPFLAGS: ${CPPFLAGS}";
echo "CXXFLAGS: ${CXXFLAGS}";
echo "LDFLAGS: ${LDFLAGS}";
echo "PKG_CONFIG_PATH: ${PKG_CONFIG_PATH}";
