ios {

	INCLUDEPATH += $$PWD/ios/include
	LIBS += -L$$PWD/ios/lib -lsecp256k1
}

macos {

	INCLUDEPATH += $$PWD/macos/include
	LIBS += -L$$PWD/macos/lib -lsecp256k1
}

android {

	contains(ANDROID_TARGET_ARCH,arm64-v8a) {

		INCLUDEPATH += $$PWD/android/arm64/include
		LIBS += -L$$PWD/android/arm64/lib -lsecp256k1
	}

	contains(ANDROID_TARGET_ARCH,armeabi-v7a) {

		INCLUDEPATH += $$PWD/android/armv7/include
		LIBS += -L$$PWD/android/armv7/lib -lsecp256k1
	}

	contains(ANDROID_TARGET_ARCH,x86) {

		INCLUDEPATH += $$PWD/android/x86/include
		LIBS += -L$$PWD/android/x86/lib -lsecp256k1
	}

	contains(ANDROID_TARGET_ARCH,x86_64) {

		INCLUDEPATH += $$PWD/android/x86_64/include
		LIBS += -L$$PWD/android/x86_64/lib -lsecp256k1
	}
}
