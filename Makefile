export TARGET = iphone:clang:latest:14.0
export ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = YallaLite YallaLite11 YallaLite22 YallaLite33 YallaLite44 YallaLite55 YallaLite66 YallaLite77 YallaLite88

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = abdulilah
abdulilah_FILES = Tweak/Tweak.m Tweak/Speed.m Tweak/Glitch.m
abdulilah_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/Libraries
abdulilah_FRAMEWORKS = UIKit QuartzCore AudioToolbox AVFoundation Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
