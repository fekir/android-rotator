# -----------------------------------------------------------------------------
# Android toolchain

ifeq ($(strip $(ANDROID_SDK_ROOT)),)
  ANDROID_SDK_ROOT := /usr/lib/android-sdk
  # debian adds them to PATH
  APKSIGNER     := /usr/bin/apksigner
  AAPT          := /usr/bin/aapt
  AAPT2         := /usr/bin/aapt2
  ZIPALIGN      := /usr/bin/zipalign
  D8            := /usr/bin/d8
  DX            := /usr/lib/android-sdk/build-tools/debian/dx
else
  # debian build tools are missing some pieces, thus search every tool separately
  find-build-tool = $(shell find "$(ANDROID_SDK_ROOT)/build-tools" -type f -name "$(1)" -print 2>/dev/null | sort -V | tail -n1)
  APKSIGNER := $(call find-build-tool,apksigner)
  AAPT      := $(call find-build-tool,aapt)
  AAPT2     := $(call find-build-tool,aapt2)
  ZIPALIGN  := $(call find-build-tool,zipalign)
  D8        := $(call find-build-tool,d8)
  DX        := $(call find-build-tool,dx)
endif

ANDROID_JAR   := $(shell find "$(ANDROID_SDK_ROOT)/platforms" -name "android.jar" 2>/dev/null | sort -V | tail -n1;)
KEYTOOL       := /usr/bin/keytool
# suppose we did not get anything from the user
KOTLINC       := /usr/bin/kotlinc
KOTLIN_STDLIB := /usr/share/kotlin/kotlinc/lib/kotlin-stdlib.jar
KOTLIN_ANNOT  := $(shell find "/usr/share/kotlin/kotlinc/lib/" -name 'annotations-*.jar' 2>/dev/null | sort -V | tail -n1;)
JAVAC         := /usr/bin/javac
JAVA          := /usr/bin/java
PROGUARD      := /usr/bin/proguard
BUNDLETOOL    := $(CURDIR)/bundletool-all-1.18.3.jar
R8            := $(CURDIR)/r8.jar

SOURCE_DATE_EPOCH ?= 315532800

BUILD_TYPE              := debug
AAPT_DEBUG_FLAGS        := --debug-mode
JAVAC_DEBUG_FLAGS       := -g
D8_DEBUG_FLAGS          := --debug
MANIFEST_DEBUGGABLE     := true
ZIPALIGN_ALIGNMENT_ARGS := -p
ifneq ($(DEBUG),1)
  BUILD_TYPE          := release
  AAPT_DEBUG_FLAGS    :=
  JAVAC_DEBUG_FLAGS   :=
  D8_DEBUG_FLAGS      :=
  MANIFEST_DEBUGGABLE := false
endif
ifneq ($(findstring -P,$(shell "$(ZIPALIGN)" 2>&1)),)
  ZIPALIGN_ALIGNMENT_ARGS := -P 16
endif

test-env:
	@printf 'Build Environment:\n'
	@printf ' %-24s: %s\n' \
		'ANDROID_JAR'             '$(ANDROID_JAR)' \
		'APKSIGNER'               '$(APKSIGNER)' \
		'ZIPALIGN'                '$(ZIPALIGN)' \
		'ZIPALIGN_ALIGNMENT_ARGS' '$(ZIPALIGN_ALIGNMENT_ARGS)' \
		'D8'                      '$(D8)' \
		'D8_FLAGS'                '$(D8_DEBUG_FLAGS)' \
		'DX'                      '$(DX)' \
		'PROGUARD'                '$(PROGUARD)' \
		'AAPT'                    '$(AAPT)' \
		'AAPT2'                   '$(AAPT2)' \
		'AAPT(2)_FLAGS'           '$(AAPT_DEBUG_FLAGS)'
.PHONY: test-env
