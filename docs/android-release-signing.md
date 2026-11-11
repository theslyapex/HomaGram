# Android release signing

HomaGram Android release APK and AAB files are built by GitHub Actions.

- The upload keystore is generated once and must remain stable for all future updates.
- Keep the keystore and its passwords in GitHub Actions repository secrets only.
- Required secrets: ANDROID_KEYSTORE_BASE64, ANDROID_KEY_ALIAS, ANDROID_STORE_PASSWORD, ANDROID_KEY_PASSWORD.
- Required repository variables: SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.
- Release builds target Android API 36.
- The Flutter CI workflow assigns a monotonically increasing GitHub Actions run number as the Android version code. Do not replace the signing keystore after distributing a release.
- Download release APK/AAB files from the workflow run artifacts. Do not commit generated signing files or build outputs.
