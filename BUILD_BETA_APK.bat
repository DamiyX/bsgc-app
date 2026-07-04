@echo off
setlocal

cd /d "%~dp0"

set "FLUTTER_ROOT=C:\Users\HP\Documents\DEV\flutter"
set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "GRADLE_USER_HOME=%CD%\.gradle_codex"
set "PUB_CACHE=%CD%\.pub_cache_codex"
set "GIT_CONFIG_GLOBAL=%CD%\.gitconfig_codex"
set "FLUTTER_SUPPRESS_ANALYTICS=true"

echo.
echo BSGC beta APK builder
echo =====================
echo.
echo This will package the app into an installable Android APK.
echo The build cache will stay inside this project folder.
echo.

git config --global --add safe.directory "%FLUTTER_ROOT%" >nul 2>nul

echo Step 1 of 4: Checking Flutter...
call "%FLUTTER_ROOT%\bin\flutter.bat" --version
if errorlevel 1 goto failed

echo.
echo Step 2 of 4: Getting app dependencies...
call "%FLUTTER_ROOT%\bin\flutter.bat" pub get
if errorlevel 1 goto failed

echo.
echo Step 3 of 4: Cleaning old Android build files...
call "%FLUTTER_ROOT%\bin\flutter.bat" clean
if errorlevel 1 goto failed

echo.
echo Step 4 of 4: Building beta APK...
call "%FLUTTER_ROOT%\bin\flutter.bat" build apk --release
if errorlevel 1 goto failed

echo.
echo Done.
echo APK location:
echo %CD%\build\app\outputs\flutter-apk\app-release.apk
echo.
echo You can copy this APK to your Android phone and install it.
pause
exit /b 0

:failed
echo.
echo The APK build did not finish.
echo Please take a screenshot of the error above and share it here.
pause
exit /b 1
