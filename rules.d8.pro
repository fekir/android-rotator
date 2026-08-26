# keep classes, especially when using d8, otherwise it causes following warnings
# Warning in build2/kotlin.jar:info/fekir/rotator/RotationService.class:
# The companion object Companion could not be found in class info.fekir.rotator.RotationService

-keep,allowoptimization class info.fekir.rotator.BootReceiver { *; }
-keep,allowoptimization class info.fekir.rotator.MainActivity { *; }
-keep,allowoptimization class info.fekir.rotator.RotationService { *; }
