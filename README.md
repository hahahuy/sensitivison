# PeekShield Monorepo

A Melos-managed Flutter monorepo containing:

| Package | Description |
|---------|-------------|
| `packages/peek_shield_core` | Exportable SDK — camera, detection, enrollment, blur widgets |
| `app` | iOS vault application |

## Quick start

```bash
# Install Melos globally
dart pub global activate melos

# Bootstrap workspace (links packages + fetches deps)
melos bootstrap

# Run all tests
melos test

# Analyze
melos analyze
```

## iOS setup

```bash
cd app/ios
pod install
```

Open `app/ios/Runner.xcworkspace` in Xcode. Minimum deployment target: **iOS 14.0**.

## Architecture

See the implementation plan in `.claude/docs/` for full architecture details.

## TFLite model

Place `facenet.tflite` (MobileNetV2, ~1 MB) at `app/assets/models/facenet.tflite` before building.
Also copy to `packages/peek_shield_core/assets/models/facenet.tflite` for SDK standalone tests.
