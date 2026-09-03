# Digital Asset Links and Universal Links Configuration

This directory hosts the authoritative domain verification files required by Android App Links and Apple Universal Links for `https://braidapp.com/join/*`.

## 1. Android App Links (`assetlinks.json`)

Android uses `assetlinks.json` to verify that the app package `com.bsgc.bsgc_app` owns the domain `braidapp.com`.

### Steps to configure production fingerprints:

1. **Google Play App Signing (Production Builds)**:
   - Navigate to Google Play Console: **Release** > **Setup** > **App Integrity** > **App Signing**.
   - Copy the SHA-256 fingerprint under **App signing key certificate**.
   - In `assetlinks.json`, replace `"REPLACE_WITH_PLAY_APP_SIGNING_CERTIFICATE_SHA256"` with this 32-pair hex string (e.g., `14:6D:E9:7F:...`).

2. **Upload / Debug Keystore (Optional for Local Sideloads & Testing)**:
   - To verify sideloaded builds directly on test devices before store distribution, extract the SHA-256 from your upload key:
     ```bash
     keytool -list -v -keystore /path/to/upload-keystore.jks -alias upload
     ```
   - For standard local debug builds:
     ```bash
     keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
     ```
   - In `assetlinks.json`, replace `"REPLACE_WITH_UPLOAD_CERTIFICATE_SHA256_OPTIONAL"` with that SHA-256 fingerprint.

3. **Deploy to Firebase Hosting**:
   ```bash
   firebase deploy --only hosting
   ```

4. **Verify Domain Association**:
   Test Google's verification API:
   ```
   https://digitalassetlinks.googleapis.com/v1/statements:check?source.web.site=https://braidapp.com&relation=delegate_permission/common.handle_all_urls&target.android_app.package_name=com.bsgc.bsgc_app&target.android_app.certificate.sha256_fingerprint=<YOUR_SHA256_FINGERPRINT>
   ```

---

## 2. Apple Universal Links (`apple-app-site-association`)

iOS uses `apple-app-site-association` to verify domain ownership.

1. Locate your 10-character Apple Developer Team ID in the Apple Developer portal.
2. In `apple-app-site-association`, replace `REPLACE_WITH_APPLE_TEAM_ID` in `REPLACE_WITH_APPLE_TEAM_ID.com.bsgc.bsgcApp`.
3. Deploy to Firebase Hosting (`firebase deploy --only hosting`).
