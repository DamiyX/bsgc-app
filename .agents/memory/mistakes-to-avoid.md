# Mistakes & Gotchas to Avoid

## 1. Animating Massive Offsets in ListView
**Mistake**: Triggering `_scrollController.animateTo(0.0)` from offsets that are thousands of pixels away.
**Consequence**: `ListView.builder` cannot rapidly layout massive numbers of frames during a high-speed animation, causing it to thrash and display a blank/white screen glitch during the scroll.
**Solution**: When a massive distance must be animated, jump the controller to a visually reasonable boundary (e.g., `_scrollController.jumpTo(2000.0)`) and immediately run a slower, smoother `animateTo(0.0, duration: 800ms, curve: fastOutSlowIn)`. This maintains the illusion of a long, smooth scroll without breaking the renderer.

## 2. Un-awaited Firebase Storage Uploads
**Mistake**: Immediately calling `getDownloadURL()` without awaiting the completion of `putFile()`.
**Consequence**: The SDK throws a Firebase `[core/object-not-found]` exception because the URL is requested before the image stream finishes pushing to the bucket.
**Solution**: Always `await` the `UploadTask` directly or capture its `TaskSnapshot` and verify `snapshot.state == TaskState.success` before fetching the download URL.
