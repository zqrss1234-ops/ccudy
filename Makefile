export TARGET = iphone:clang:latest:7.0
export ARCHS = arm64 arm64e

include Libraries/LicenseManager.xcconfig

INSTALL_TARGET_PROCESSES = YallaLite YallaLite11 YallaLite22 YallaLite33 YallaLite44 YallaLite55 YallaLite66 YallaLite77 YallaLite88

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = abdulilah
abdulilah_FILES = Tweak/Tweak.xm Tweak/Speed.xm Tweak/Glitch.xm Libraries/LicenseManager.m
abdulilah_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/Libraries -DLICENSE_SERVER_URL=\"$(LICENSE_SERVER_URL)\"
abdulilah_FRAMEWORKS = UIKit QuartzCore AudioToolbox AVFoundation Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
