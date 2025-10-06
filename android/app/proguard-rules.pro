# Minimal proguard rules to satisfy Android build tooling for HERD-V.
# Keep everything by default; shrinker will still run but this file avoids missing-file errors.

# Keep application classes
-keep class android.app.Application { *; }

# Keep Flutter entry points
-keep class io.flutter.app.** { *; }
-keep class io.flutter.embedding.** { *; }

# You can add more rules here if you enable code shrinking and encounter missing-symbol errors.
