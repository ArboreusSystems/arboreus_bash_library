ios {

	INCLUDEPATH += $$PWD/ios/include
	LIBS += -L$$PWD/ios/lib -lbitcoin-system
}

macos {

	INCLUDEPATH += $$PWD/macos/include
	LIBS += -L$$PWD/macos/lib -lbitcoin-system
}

android {

	contains(ANDROID_TARGET_ARCH,arm64-v8a) {

		INCLUDEPATH += $$PWD/android/arm64/include
		LIBS += -L$$PWD/android/arm64/lib -lbitcoin-system
	}

	contains(ANDROID_TARGET_ARCH,armeabi-v7a) {

		INCLUDEPATH += $$PWD/android/armv7/include
		LIBS += -L$$PWD/android/armv7/lib -lbitcoin-system
	}

	contains(ANDROID_TARGET_ARCH,x86) {

		INCLUDEPATH += $$PWD/android/x86/include
		LIBS += -L$$PWD/android/x86/lib -lbitcoin-system
	}

	contains(ANDROID_TARGET_ARCH,x86_64) {

		INCLUDEPATH += $$PWD/android/x86_64/include
		LIBS += -L$$PWD/android/x86_64/lib -lbitcoin-system
	}
}
