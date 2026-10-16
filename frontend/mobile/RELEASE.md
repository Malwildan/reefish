# Android release APK

Release builds use a local upload key. Keep both `android/app/reefish-upload-key.jks` and `android/key.properties` backed up in a private, access-controlled location. They are ignored by Git. Losing the keystore prevents signing future updates with the same certificate; never commit or share either file.

From `D:\reefish\frontend\mobile`, with the local `config\supabase.local.json` configured:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
& 'C:\Users\akmal\develop\flutter\bin\flutter.bat' build apk --release --target lib/main.dart --dart-define-from-file=config/supabase.local.json --build-name=1.0.0 --build-number=2 --android-project-arg=kotlin.incremental=false
```

This builds one universal APK at `build\app\outputs\flutter-apk\app-release.apk`, suitable for the supported Android ABIs. The release signing config fails the Gradle build if the local properties or keystore are missing. The application ID remains `com.reefish.reefish_mobile`.
