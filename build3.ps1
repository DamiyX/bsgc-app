$env:JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"
$env:GRADLE_USER_HOME="C:\Users\HP\.gradle_clean7"
C:\Users\HP\Documents\DEV\flutter\bin\flutter.bat build apk --debug *>&1 | Out-File -FilePath build_log.txt
