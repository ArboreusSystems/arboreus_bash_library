ios {

	INCLUDEPATH += $$PWD/ios/include
	LIBS += -L$$PWD/ios/lib \
		-lboost_atomic \
		-lboost_chrono \
		-lboost_date_time \
		-lboost_filesystem \
		-lboost_iostreams \
		-lboost_log \
		-lboost_program_options \
		-lboost_regex \
		-lboost_system \
		-lboost_thread
}

macos {

	INCLUDEPATH += $$PWD/macos/include
	LIBS += -L$$PWD/macos/lib \
		-lboost_atomic \
		-lboost_chrono \
		-lboost_date_time \
		-lboost_filesystem \
		-lboost_iostreams \
		-lboost_log \
		-lboost_program_options \
		-lboost_regex \
		-lboost_system \
		-lboost_thread
}

android {

	contains(ANDROID_TARGET_ARCH,arm64-v8a) {

		INCLUDEPATH += $$PWD/android/arm64/include
		LIBS += -L$$PWD/android/arm64/lib \
			-lboost_atomic \
			-lboost_chrono \
			-lboost_date_time \
			-lboost_filesystem \
			-lboost_iostreams \
			-lboost_log \
			-lboost_program_options \
			-lboost_regex \
			-lboost_system \
			-lboost_thread
	}

	contains(ANDROID_TARGET_ARCH,armeabi-v7a) {

		INCLUDEPATH += $$PWD/android/armv7/include
		LIBS += -L$$PWD/android/armv7/lib \
			-lboost_atomic \
			-lboost_chrono \
			-lboost_date_time \
			-lboost_filesystem \
			-lboost_iostreams \
			-lboost_log \
			-lboost_program_options \
			-lboost_regex \
			-lboost_system \
			-lboost_thread
	}

	contains(ANDROID_TARGET_ARCH,x86) {

		INCLUDEPATH += $$PWD/android/x86/include
		LIBS += -L$$PWD/android/x86/lib \
			-lboost_atomic \
			-lboost_chrono \
			-lboost_date_time \
			-lboost_filesystem \
			-lboost_iostreams \
			-lboost_log \
			-lboost_program_options \
			-lboost_regex \
			-lboost_system \
			-lboost_thread
	}

	contains(ANDROID_TARGET_ARCH,x86_64) {

		INCLUDEPATH += $$PWD/android/x86_64/include
		LIBS += -L$$PWD/android/x86_64/lib \
			-lboost_atomic \
			-lboost_chrono \
			-lboost_date_time \
			-lboost_filesystem \
			-lboost_iostreams \
			-lboost_log \
			-lboost_program_options \
			-lboost_regex \
			-lboost_system \
			-lboost_thread
	}
}
