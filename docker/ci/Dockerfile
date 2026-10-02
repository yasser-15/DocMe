# DocMe build image — produces app artifacts inside a container.
#
# WHY THIS EXISTS: the Flutter apps are artifacts, not services. A mobile APK
# cannot be "run" as a container, so the app-side isolation guarantee is that
# builds are reproducible and disposable — no host toolchain, no host state, no
# one developer's SDK version leaking into a produced artifact.
#
# Build (first time downloads ~1.6 GB Flutter SDK + ~1 GB Android SDK):
#   docker build -f docker/ci/Dockerfile -t docme-build .
#
# Build an artifact:
#   docker run --rm -v "${PWD}:/workspace" -w /workspace docme-build
#
# WARNING: this image is deliberately not based on a published Flutter image.
# The community images (cirrusci/flutter, cirruslabs/flutter) are stale — their
# newest tags ship Dart 3.8–3.12, and DocMe requires Dart 3.13.5. They cannot
# be used without silently downgrading the SDK, which CLAUDE.md forbids because
# liquid_glass_widgets requires Flutter >= 3.41. So we install the SDK ourselves,
# pinned by version AND sha256.

FROM debian:bookworm-slim

ARG FLUTTER_VERSION=3.47.6
# From releases_linux.json in flutter_infra_release. Re-verify if you bump the
# version above; a wrong checksum here fails the build rather than silently
# installing something else.
ARG FLUTTER_SHA256=f1631b9c2c8b3529323db412b0d1beacf4a748f8783b0d7cf599a8fd5f461675
ARG ANDROID_CMDLINE_TOOLS=16111833

ENV DEBIAN_FRONTEND=noninteractive \
    FLUTTER_ROOT=/opt/flutter \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    PUB_CACHE=/opt/pub-cache \
    GRADLE_USER_HOME=/opt/gradle-cache \
    CI=true

# OpenJDK 17. Debian bookworm ships 17; OpenJDK 21 needs bookworm-backports.
# The project's Gradle config pins sourceCompatibility/targetCompatibility and
# Kotlin jvmTarget to 17, and AGP 8.x supports 17, so this matches the build
# rather than diverging from it. The host uses JDK 21 via Android Studio's JBR,
# which also works — both produce the same APK.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip \
      openjdk-17-jdk-headless libglu1-mesa \
 && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="$JAVA_HOME/bin:$PATH"

# --- Flutter SDK ---------------------------------------------------------
RUN curl -fsSL -o /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
 && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
 && tar -xJf /tmp/flutter.tar.xz -C /opt \
 && rm /tmp/flutter.tar.xz \
 && git config --global --add safe.directory /opt/flutter

# --- Android SDK ---------------------------------------------------------
RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
 && curl -fsSL -o /tmp/cmdtools.zip \
      "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS}_latest.zip" \
 && unzip -q /tmp/cmdtools.zip -d /tmp/cmdtools \
 && mv /tmp/cmdtools/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest" \
 && rm -rf /tmp/cmdtools /tmp/cmdtools.zip

# cmdline-tools/bin must be on PATH or sdkmanager is simply not found (exit 127).
# platform-tools comes later, once sdkmanager has actually installed it.
ENV PATH="$FLUTTER_ROOT/bin:$FLUTTER_ROOT/bin/cache/dart-sdk/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

# compileSdk 37 is required by permission_handler_android; see CLAUDE.md.
#
# PACKAGE NAMES ARE EXACT AND EASY TO GET WRONG:
#   platforms;android-37   does NOT exist. Android 17 moved to a minor-version
#                          scheme, so the package is platforms;android-37.0.
#                          An older cmdline-tools also cannot see it at all,
#                          which is why the ARG above is pinned to a recent
#                          build rather than 11076708.
#   build-tools;37.0.0     does NOT exist either; 36.0.0 is current.
# A wrong name fails with "Failed to find package", not with a version warning.
#
# Licences are accepted non-interactively so CI never blocks on a prompt.
RUN flutter --version \
 && yes | sdkmanager --licenses >/dev/null || true \
 && sdkmanager --install "platform-tools" "platforms;android-37.0" "build-tools;36.0.0" \
 && flutter config --no-analytics \
 && flutter precache --android --no-ios --universal

WORKDIR /workspace

ENV PATH="$PATH:$ANDROID_HOME/platform-tools"

# pubspec files first so an app-only change does not invalidate this layer.
# The COPY preserves the packages/<name>/ path layout.
COPY packages/*/pubspec.yaml ./

# COPY the source, never bind-mount the repo.
#
# A bind mount reuses the host's .dart_tool/package_config.json, which contains
# Windows absolute paths (C:/src/flutter/..., C:/Users/<you>/AppData/...).
# Inside a Linux container those do not exist and every import fails with
# "Error when reading". Worse, running `pub get` in the container would
# overwrite the host's file and break the host build. Copying is also what CI
# genuinely does, so local container builds stay honest.
#
# .dockerignore excludes build/ and .dart_tool/, so this always copies clean
# sources and forces a fresh resolution with container-correct paths.
COPY packages/ ./packages/

# Default command builds a release APK for the patient app.
CMD ["sh", "-c", "cd packages/patient_app && flutter pub get && flutter build apk --release"]