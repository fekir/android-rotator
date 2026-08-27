# FIXME: use jar instead of zip, is output reproducibe?

# -----------------------------------------------------------------------------
# Make helpers

RED    := \033[31m
YELLOW := \033[33m
RESET  := \033[0m
define run_silent
    @\
    output=$$( ( $(1) ) 2>&1 ); \
    code=$$?; \
    if [ -n "$$output" ]; then :; output=$$( printf "%s\nX" "$$output" ); output=$${output%X}; fi; \
    if [ $$code -ne 0 ]; then :; \
        printf    "$(RED)%s\n%s$(RESET)" "$(1)" "$$output"; \
    elif printf '%s' "$$output" | grep -i -q "warning"; then :; \
        printf "$(YELLOW)%s\n%s$(RESET)" "$(1)" "$$output"; \
    elif [ -n "$(strip $(VERBOSE))" ]; then :; \
        printf '%s\n%s' "$(1)" "$$output"; \
    fi; \
    exit $$code;
endef

# -----------------------------------------------------------------------------
# Toolchain

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

test-env:
	@printf '%-11s: %s\n' \
		'ANDROID_JAR' '$(ANDROID_JAR)' \
		'APKSIGNER'   '$(APKSIGNER)' \
		'ZIPALIGN'    '$(ZIPALIGN)' \
		'D8'          '$(D8)' \
		'DX'          '$(DX)' \
		'PROGUARD'    '$(PROGUARD)' \
		'AAPT'        '$(AAPT)'\
		'AAPT2'       '$(AAPT2)'
.PHONY: test-env

# -----------------------------------------------------------------------------
# Source files

MANIFEST     := app/src/main/AndroidManifest.in.xml
RES_DIR      := app/src/main/res
RES_FILES    := $(shell find "$(RES_DIR)" -type f 2>/dev/null)
KOTLIN_FILES := $(shell find "app/src/main/kotlin" -name "*.kt" -type f 2>/dev/null)

# Android - SDK   - Build.VERSION.SDK_INT
# 17      - 37    - Build.VERSION_CODES.CINNAMON_BUN
# 16      - 36    - Build.VERSION_CODES.BAKLAVA
# 15      - 35    - Build.VERSION_CODES.VANILLA_ICE_CREAM
# 14      - 34    - Build.VERSION_CODES.UPSIDE_DOWN_CAKE
# 13      - 33    - Build.VERSION_CODES.TIRAMISU
# 12      - 31,32 - Build.VERSION_CODES.S
# 11      - 30    - Build.VERSION_CODES.R
# 10      - 29    - Build.VERSION_CODES.Q
#  9      - 28    - Build.VERSION_CODES.P
#  8      - 26,27 - Build.VERSION_CODES.O
#  7      - 24,25 - Build.VERSION_CODES.N
#  6      - 23    - Build.VERSION_CODES.M
MIN_SDK      := 23
TARGET_SDK   := 36

ifneq ($(wildcard $(R8)),)
RULES_PROGUARD := rules.pro
else ifneq ($(wildcard $(D8)),)
RULES_PROGUARD := rules.d8.pro
else
RULES_PROGUARD := rules.pro
endif

# -----------------------------------------------------------------------------
# Targets for creating apk

BUILD_DIR ?= build2
clean:
	@rm -rf "$(BUILD_DIR)"
.PHONY: clean

# create a zip file with all resources compiled by aapt2
RES_ZIP := $(BUILD_DIR)/resources.zip
$(RES_ZIP): $(RES_FILES) $(ANDROID_JAR)
	@echo "generate archive $@ from following resources $^"
	@mkdir -p "$(@D)"
	$(call run_silent,"$(AAPT2)" compile --dir "$(RES_DIR)" -o "$(RES_ZIP)" )
resources.zip: $(RES_ZIP)
.PHONY: resources.zip

# create manifest file to be consumed by android toolchain
ANDROIDMANIFEST := $(BUILD_DIR)/AndroidManifest.xml
$(ANDROIDMANIFEST): $(MANIFEST)
	@mkdir -p "$(@D)"
	@echo "generate manifest file"
	@sed -e 's|@MIN_SDK@|$(MIN_SDK)|g' -e 's|@TARGET_SDK@|$(TARGET_SDK)|g' "$<" > "$@"

# create base apk and R.java with manifest and resources.arsc, .class/.dex files are missing from the apk
GEN_DIR := $(BUILD_DIR)/gen/src
AAPT_PROGUARD := $(BUILD_DIR)/aapt.pro
R_CLASSES_STAMP := $(BUILD_DIR)/gen/.r-classes.stamp
ifneq ($(wildcard $(AAPT2)),)
BASE_APK := $(BUILD_DIR)/apk/base.apk
$(BASE_APK): $(RES_ZIP) $(ANDROID_JAR) $(ANDROIDMANIFEST)
	@echo "generate $@ and R.java from $^"
	@mkdir -p "$(@D)" "$(GEN_DIR)"
	$(call run_silent, \
		"$(AAPT2)" link \
			-I "$(ANDROID_JAR)" \
			--manifest "$(ANDROIDMANIFEST)" \
			--min-sdk-version "$(MIN_SDK)" \
			-o "$@" \
			--auto-add-overlay \
			--java "$(GEN_DIR)" \
			--proguard "$(AAPT_PROGUARD)" \
			$(RES_ZIP) \
	)
base.apk: $(BASE_APK)
.PHONY: base.apk

GEN_CLASS_DIR := $(BUILD_DIR)/gen/classes
$(R_CLASSES_STAMP): $(BASE_APK)
	@echo "generate R.class from R.java"
	@mkdir -p "$(@D)"
	$(call run_silent, \
		"$(JAVAC)" \
			-classpath "$(ANDROID_JAR)" \
			-d "$(GEN_CLASS_DIR)" \
			$$(find "$(GEN_DIR)" -name R.java -type f) \
	)
	@touch "$@"

else
R_JAVA_STAMP := $(BUILD_DIR)/gen/.r-java.stamp
$(R_JAVA_STAMP): $(ANDROID_JAR) $(ANDROIDMANIFEST)
	@echo "generate $@ and R.java from $^"
	@mkdir -p "$(@D)" "$(GEN_DIR)"
	$(call run_silent, \
		"$(AAPT)" package \
			-f -m -J "$(GEN_DIR)" \
			-S "$(RES_DIR)" \
			-I "$(ANDROID_JAR)" \
			-M "$(ANDROIDMANIFEST)" \
			-G "$(AAPT_PROGUARD)" \
	)
	@touch $(R_JAVA_STAMP)

$(R_CLASSES_STAMP): $(R_JAVA_STAMP)
	@echo "generate R.class from R.java"
	@mkdir -p "$(@D)"
	$(call run_silent, \
		"$(JAVAC)" \
			-classpath "$(ANDROID_JAR)" \
			-d "$(GEN_CLASS_DIR)" \
			$$(find "$(GEN_DIR)" -name R.java -type f) \
	)
	@touch "$@"
endif
r.class: $(R_CLASSES_STAMP)
.PHONY: r.class

KOTLIN_JAR := $(BUILD_DIR)/kotlin.jar
ifneq ($(wildcard $(PROGUARD)),)
KOTLIN_JAR_UNOPT := $(BUILD_DIR)/kotlin_unopt.jar
$(KOTLIN_JAR_UNOPT): $(KOTLIN_FILES) $(R_CLASSES_STAMP)
	@echo "Compile Kotlin sources to .class files"
	@mkdir -p "$(@D)"
	$(call run_silent, \
		"$(KOTLINC)" \
			-classpath "$(ANDROID_JAR):$(GEN_CLASS_DIR)" \
			-d "$@" \
			$(KOTLIN_FILES) \
	)
# NOTE: as alternative to -dontwarn search for annotation
# my current kotlinc seems to bring /usr/share/kotlin/kotlinc/lib/annotations-13.0.jar
$(KOTLIN_JAR): $(KOTLIN_JAR_UNOPT) $(R_CLASSES_STAMP) $(RULES_PROGUARD)
	@echo "Optimize .class files"
	@mkdir -p "$(@D)"
	$(call run_silent, \
		"$(PROGUARD)" \
			-dontobfuscate -libraryjars "$(ANDROID_JAR):$(KOTLIN_STDLIB):$(KOTLIN_ANNOT)" \
			-injars "${KOTLIN_JAR_UNOPT}" \
			-outjars "$@" \
			-include "$(AAPT_PROGUARD)" \
			-include "$(RULES_PROGUARD)" \
	)
else
$(KOTLIN_JAR): $(KOTLIN_FILES) $(R_CLASSES_STAMP)
	@echo "Compile Kotlin sources to .class files"
	@mkdir -p "$(@D)"
	$(call run_silent, \
		"$(KOTLINC)" \
			-classpath "$(ANDROID_JAR):$(GEN_CLASS_DIR)" \
			-d "$@" \
			$(KOTLIN_FILES) \
	)
endif
kotlin.jar: $(KOTLIN_JAR)
.PHONY: kotlin.jar

DEX_ZIP := $(BUILD_DIR)/dex.zip
ifneq ($(wildcard $(R8)),)
$(DEX_ZIP): $(KOTLIN_JAR) $(KOTLIN_STDLIB) $(ANDROID_JAR)
	@echo "Compile .class files to .dex files"
	@mkdir -p "$(@D)"
	$(call run_silent, \
		"$(JAVA)" -jar "$(R8)" \
			--release \
			--min-api "$(MIN_SDK)" \
			--lib "$(ANDROID_JAR)" \
			--lib "$(KOTLIN_ANNOT)" \
			--pg-conf "$(AAPT_PROGUARD)" \
			--no-data-resources \
			--output "$@" \
			"$(KOTLIN_STDLIB)" \
			"$(KOTLIN_JAR)" \
	)
else ifneq ($(wildcard $(D8)),)
$(DEX_ZIP): $(KOTLIN_JAR) $(KOTLIN_STDLIB) $(ANDROID_JAR)
	@echo "Compile .class files to .dex files"
	@mkdir -p "$(@D)"
	$(call run_silent, \
		"$(D8)" \
			--output "$@" \
			--lib "$(ANDROID_JAR)" \
			--min-api "$(MIN_SDK)" \
			"$(KOTLIN_STDLIB)" \
			"$(KOTLIN_JAR)" \
	)
else
$(DEX_ZIP): $(KOTLIN_JAR) $(KOTLIN_STDLIB) $(ANDROID_JAR)
	@echo "Compile .class files to .dex files"
	@mkdir -p "$(@D)"
	$(call run_silent, \
		"$(DX)" \
			--dex \
			--min-sdk-version "$(MIN_SDK)" \
			--output="$@" \
			"$(KOTLIN_STDLIB)" \
			"$(KOTLIN_JAR)" \
	)
	@# remove kotlin builtin annotation files
	$(call run_silent, zip -d build2/dex.zip 'kotlin/*.kotlin_builtins' 'META-INF/*kotlin_module' 'META-INF/MANIFEST.MF' )

endif
dex.zip: $(DEX_ZIP)
.PHONY: dex.zip

# Add classes.dex to APK
# with aapt, this was not necessary, but with aapt2, we need to add the dex file manually.
# since resources.arsc needs to be uncompressed
# keep $(BASE_APK) and add content of $(DEX_ZIP)

UNSIGNED_APK := $(BUILD_DIR)/apk/unsigned.apk
ifneq ($(wildcard $(AAPT2)),)
$(UNSIGNED_APK): $(BASE_APK) $(DEX_ZIP)
	@echo "merge base.apk and dex files"
	@mkdir -p $(BUILD_DIR)/merged
	@cp "$(BASE_APK)" $(UNSIGNED_APK)
	$(call run_silent,unzip -q "$(DEX_ZIP)" -d $(BUILD_DIR)/merged)
	$(call run_silent,(cd $(BUILD_DIR)/merged; find . -type f -print0 | sort -z | TZ=UTC xargs -0 -r zip -X -q ../apk/unsigned.apk))
	@rm -rf "$(BUILD_DIR)/merged"
else
$(UNSIGNED_APK): $(DEX_ZIP) $(ANDROIDMANIFEST)
	@echo "Package dex with manifest and libraries"
	@mkdir -p "$(@D)" $(BUILD_DIR)/merged
	$(call run_silent,unzip -q "$(DEX_ZIP)" -d $(BUILD_DIR)/merged)
	$(call run_silent, \
		"$(AAPT)" package \
			-f -F "$@" \
			-I "$(ANDROID_JAR)" \
			-M "$(ANDROIDMANIFEST)" \
			-S "$(RES_DIR)" \
			$(BUILD_DIR)/merged \
	)

	@rm -rf "$(BUILD_DIR)/merged"
endif
unsigned.apk: $(UNSIGNED_APK)
.PHONY: unsigned.apk

ALIGNED_APK := $(BUILD_DIR)/apk/aligned.apk
$(ALIGNED_APK): $(UNSIGNED_APK)
	@echo "zip-align $< to $@"
	$(call run_silent,"$(ZIPALIGN)" -f -p 4 "$<" "$@")

aligned.apk: $(ALIGNED_APK)
.PHONY: aligned.apk

DEBUG_KEYSTORE := $(CURDIR)/debug.keystore
$(DEBUG_KEYSTORE):
	@echo "Generating debug $@"
	"$(KEYTOOL)" -genkeypair -v \
		-keystore "$@" \
		-storepass android \
		-keypass android \
		-alias androiddebugkey \
		-keyalg RSA \
		-keysize 2048 \
		-validity 10000 \
		-dname "CN=Android Debug,O=Android,C=US"

OUT_APK := $(BUILD_DIR)/apk/RotationSwitcher.apk
$(OUT_APK): $(ALIGNED_APK) $(DEBUG_KEYSTORE)
	@mkdir -p "$(@D)"
	@echo "sign $< to $@"
	$(call run_silent, \
		"$(APKSIGNER)" sign \
			--ks "$(DEBUG_KEYSTORE)" \
			--ks-pass pass:android \
			--key-pass pass:android \
			--v4-signing-enabled true \
			--out "$@" \
			"$(ALIGNED_APK)" \
	)

apk: $(OUT_APK)


# -----------------------------------------------------------------------------
# Targets for creating aab + apk

ifneq ($(wildcard $(BUNDLETOOL)),)
BUNDLE_DIR := $(BUILD_DIR)/bundle


BUNDLE_PROTO_APK := $(BUNDLE_DIR)/proto.apk
$(BUNDLE_PROTO_APK): $(RES_ZIP) $(ANDROID_JAR) $(ANDROIDMANIFEST)
	@mkdir -p "$(@D)"
	@echo "Generate $@ from $^"
	$(call run_silent, \
		"$(AAPT2)" link \
			-I "$(ANDROID_JAR)" \
			--manifest "$(ANDROIDMANIFEST)" \
			--min-sdk-version "$(MIN_SDK)" \
			--auto-add-overlay \
			--proto-format \
			--proguard "$(AAPT_PROGUARD)" \
			-o "$@" \
			$(RES_ZIP) \
	)
proto.apk: $(BUNDLE_PROTO_APK)
.PHONY: proto.apk


BUNDLE_MODULE_DIR := $(BUNDLE_DIR)/base
BUNDLE_MODULE_ZIP := $(BUNDLE_DIR)/base.zip
$(BUNDLE_MODULE_ZIP): $(BUNDLE_PROTO_APK) $(DEX_ZIP)
	@echo "Preparing Android App Bundle module..."

	@rm -rf "$(BUNDLE_MODULE_DIR)"
	@mkdir -p "$(BUNDLE_MODULE_DIR)"
	@unzip -q "$(BUNDLE_PROTO_APK)" -d "$(BUNDLE_MODULE_DIR)"

	@mkdir -p "$(BUNDLE_MODULE_DIR)/manifest"
	@mv "$(BUNDLE_MODULE_DIR)/AndroidManifest.xml" "$(BUNDLE_MODULE_DIR)/manifest/AndroidManifest.xml"

	@mkdir -p "$(BUNDLE_MODULE_DIR)/dex"
	@unzip -q "$(DEX_ZIP)" -d "$(BUNDLE_MODULE_DIR)/dex/"

	@rm -f "$@"
	$(call run_silent,(cd $(BUNDLE_MODULE_DIR); find . -type f -print0 | sort -z | TZ=UTC xargs -0 -r zip -X -q ../base.zip))

base.zip: $(BUNDLE_MODULE_ZIP)
.PHONY: base.zip




OUT_AAB := $(BUNDLE_DIR)/app-debug.aab
$(OUT_AAB): $(BUNDLE_MODULE_ZIP)
	@mkdir -p "$(@D)"
	@rm -f "$@"
	@echo "Creating Android App Bundle..."
	$(call run_silent, \
		$(JAVA) -jar $(BUNDLETOOL) build-bundle \
			--modules="$(BUNDLE_MODULE_ZIP)" \
			--output="$@" \
	)

	@echo "Validating Android App Bundle..."
	$(call run_silent, $(JAVA) -jar $(BUNDLETOOL) validate --bundle="$@" > /dev/null )

bundle: $(OUT_AAB)

BUNDLE_APKS := $(BUNDLE_DIR)/app.apks
$(BUNDLE_APKS): $(OUT_AAB) $(DEBUG_KEYSTORE)
	@echo "Create $@ from $^"
	@mkdir -p "$(@D)"
	@rm -f "$@"

	$(call run_silent, \
		$(JAVA) -jar $(BUNDLETOOL) build-apks \
			--bundle="$(OUT_AAB)" \
			--output="$@" \
			--mode=universal \
			--ks="$(DEBUG_KEYSTORE)" \
			--ks-pass=pass:android \
			--ks-key-alias=androiddebugkey \
			--key-pass=pass:android \
	)

BUNDLE_APK := $(BUNDLE_DIR)/RotationSwitcher.apk
$(BUNDLE_APK): $(BUNDLE_APKS)
	@echo "Create $@ from $^"
	@mkdir -p "$(@D)"
	@rm -f "$@"
	@unzip -p "$(BUNDLE_APKS)" universal.apk > "$@"
bundle-apk: $(BUNDLE_APK)
else
bundle:
	@echo "No bundletool found"
	@exit 1;
bundle-apk: bundle
endif
.PHONY: bundle-apk bundle

all: test-env apk bundle bundle-apk
.PHONY: all
