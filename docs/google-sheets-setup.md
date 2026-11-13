# Google Sheets access

The consultant-sheet feature signs in with Google through AppAuth (system browser, PKCE) and asks for one scope, `drive.file`, which only covers the workbook the user picks in Google's own picker.

- OAuth client: type iOS, bundle ID `app.arcaeaoffline`. The client ID and its reversed URL scheme are public identifiers and live in `GoogleProbeAuth.swift` and `ArcaeaOffline/Resources/Info.plist`. There is no client secret.
- Google Cloud project APIs: Google Sheets API, Google Drive API, Google Picker API.
- The consent screen is in **Testing**: only listed test users can sign in, and Google expires refresh tokens after seven days, so the app asks to reconnect about weekly. Publishing the consent screen removes both limits.
- SideStore may re-sign the app with a bundle ID suffix. The sign-in callback uses the URL scheme, not the bundle ID, so it keeps working.
