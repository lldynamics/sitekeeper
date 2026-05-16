# Sitekeeper Android

This is the native Android port workspace for Sitekeeper.

## Current Scope

- `:app`: minimal Jetpack Compose shell for the Android client.
- `:core:model`: Kotlin data contract for the first `BackupSnapshot` interop pass.
- `:core:database`: Room database slice for project, daily log, site todo, finance, and material data.
- `:core:model` tests: decode and re-encode a P0 iOS-style backup fixture.
- Project tab: reads seeded project records from Room through the P0 backup JSON decoder.
- Project tab: supports local project creation backed by Room.
- Project detail: opens from the project list, shows linked daily logs plus open site todos, and supports adding logs and todos locally.
- Finance and material slices: project detail shows income/expense totals, financial records, and material procurement status.

## Build

This workspace expects JDK 17. Use the checked-in Gradle wrapper from this directory.

```sh
cd android
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :core:model:test
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleDebug
```

Current local verification:

```sh
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :core:model:test :app:assembleDebug --no-daemon
```

This passed after installing Homebrew `openjdk@17`, `gradle`, `android-commandlinetools`, `platforms;android-36`, `build-tools;36.0.0`, and `platform-tools`.
