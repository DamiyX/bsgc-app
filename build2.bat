@echo off
set JAVA_HOME=C:\Program Files\Android\Android Studio\jbr
set GRADLE_USER_HOME=C:\Users\HP\.gradle_clean7
set FLUTTER_SUPPRESS_ANALYTICS=true
cd "C:\Users\HP\Documents\DEV\Bible study group chat\bsgc_app"
call C:\Users\HP\Documents\DEV\flutter\bin\flutter.bat clean
call C:\Users\HP\Documents\DEV\flutter\bin\flutter.bat build apk --debug
