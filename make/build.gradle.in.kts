plugins {
  java
  idea
  // the current kotlin packaged in Debian (1.3-SNAPSHOT)
  // is too old for the current gradle version that is
  // shipped in some IDE.
  // Thus the IDE might propose changes that do not build
  // kotlin("jvm") version "1.3.0"
}

description = "IDE model for the make-based Android project"

sourceSets {
  named("main") {
    java.srcDirs("app/src/main/kotlin", "@GEN_SRC_DIR@")
    resources.srcDir("app/src/main/res")
  }
}

dependencies {
  compileOnly(files("@ANDROID_JAR@", "@KOTLIN_STDLIB@"))
}

idea {
  module {
    generatedSourceDirs.add(file("@GEN_SRC_DIR@"))
  }
}
