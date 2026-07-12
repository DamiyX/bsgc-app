# Mistakes & Gotchas to Avoid

## 1. Animating Massive Offsets in ListView
**Mistake**: Triggering `_scrollController.animateTo(0.0)` from offsets that are thousands of pixels away.
**Consequence**: `ListView.builder` cannot rapidly layout massive numbers of frames during a high-speed animation, causing it to thrash and display a blank/white screen glitch during the scroll.
**Solution**: When a massive distance must be animated, jump the controller to a visually reasonable boundary (e.g., `_scrollController.jumpTo(2000.0)`) and immediately run a slower, smoother `animateTo(0.0, duration: 800ms, curve: fastOutSlowIn)`. This maintains the illusion of a long, smooth scroll without breaking the renderer.

## 2. Un-awaited Firebase Storage Uploads
**Mistake**: Immediately calling `getDownloadURL()` without awaiting the completion of `putFile()`.
**Consequence**: The SDK throws a Firebase `[core/object-not-found]` exception because the URL is requested before the image stream finishes pushing to the bucket.
**Solution**: Always `await` the `UploadTask` directly or capture its `TaskSnapshot` and verify `snapshot.state == TaskState.success` before fetching the download URL.

## 3. Native SDK Crashes in Release Builds
**Mistake**: Blindly initializing native-dependent plugins like `FirebaseCrashlytics` on startup without wrapping in an error boundary.
**Consequence**: If the Android Gradle Plugin (AGP) or `google-services.json` fails to inject the exact required app ID during compilation, the native SDK will throw an `IllegalStateException` on launch. In a release build, this instantly crashes the app before the splash screen even vanishes.
**Solution**: Wrap calls like `FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError` in a Dart `try-catch` block. This ensures that a failure in the Crashlytics native bindings prints an error rather than completely crashing the application startup.

## 4. Unstable IntlPhoneField State
**Mistake**: Relying exclusively on the `initialValue` property of an `IntlPhoneField` while inside an asynchronous form.
**Consequence**: `initialValue` only populates when the widget mounts. If the parent state triggers a rebuild (e.g. `setState` for a loading spinner disappearing), the field may wipe out the pre-filled number, leaving the user confused when they return to the screen.
**Solution**: Always pass a `TextEditingController` to `IntlPhoneField(controller: ...)` and set `_phoneController.text = _getLocalPhoneNumber(savedNumber)` to guarantee reliable text persistence regardless of widget rebuilds.

## 5. Cloudinary Upload "Configuration Missing"
**Mistake**: Failing to provide a valid `upload_preset` string when replacing Firebase Storage with Cloudinary's raw REST API.
**Consequence**: The upload instantly rejects with an exception. Cloudinary requires the preset parameter to tell the bucket which folder and transformation rules to apply.
**Solution**: Ensure you create an *Unsigned* upload preset in the Cloudinary dashboard, and pass it directly in the `FormData` as `upload_preset: 'your-preset'`.

## 6. Infinite Stream-Recreation Loop on Scroll
**Mistake**: Triggering a setState that recreates a Firestore Stream when the user scrolls to the top (scroll.offset >= maxScrollExtent) without verifying if more data actually exists.
**Consequence**: If no more data exists, the scroll position remains at the boundary. The stream recreates, causes a loading spinner, finishes, and the boundary condition instantly triggers the setState again, causing an infinite, glitchy loading loop.
**Solution**: Always implement a _hasMoreMessages boolean flag. Compare the returned document count to the _messageLimit. If they are fewer, set _hasMoreMessages = false and completely block the scroll listener from triggering any further stream fetches.
