# TELECOM – Audio Conference Platform (iOS)

SwiftUI iOS replica of the Android app [Telecom Audio](https://play.google.com/store/apps/details?id=com.telecom.audio).

## Architecture

```
App/                  Root navigation + DI
Core/                 Networking, Keychain, Session, Device, Config
Data/                 Models, Services, Repositories
Domain/               Protocols
Presentation/         Splash → Login → Home → Zoom Init → Meeting → Recordings
Infrastructure/Zoom/  Zoom SDK isolation (MobileRTC)
DesignSystem/         Colors, fonts, shared controls
Config/               Debug / Staging / Release xcconfig
```

Navigation is centralized via `AppRouter` / `AppState`.

## Verified APIs

| Endpoint | Notes |
|---|---|
| `POST /auth/login` | Response: `{ "token", "status" }` — verified |
| `GET /api/zooms/get-zoom-token` | Flexible Codable — **MAP_AFTER_REAL_RESPONSE** |
| `GET /api/zooms/sub_host/recordings` | Response: `{ success, message, data[] }` — verified empty payload |

Device headers (dynamic):

- `x-device-platform: iOS`
- `x-device-uuid` — Keychain-persisted install UUID
- `x-device-model` — machine identifier
- `x-device-manufacturer: Apple`
- `User-Agent: iOS` (Zoom token)
- `Authorization: Bearer <Keychain token>`

## Environments

`Config/Debug.xcconfig`, `Staging.xcconfig`, `Release.xcconfig` set `API_BASE_URL` and `APP_ENVIRONMENT` (injected into `Info.plist`).

## Zoom Meeting SDK

The app compiles and runs UI/API flows **without** the proprietary SDK (stub path in `ZoomAudioMeetingService`).

To enable real meetings:

1. Download Zoom Meeting SDK for iOS from Zoom Marketplace.
2. Add `MobileRTC.xcframework` (+ resources) to the Learning target.
3. Add Swift flag: `-DZOOM_MEETING_SDK`
4. Confirm `get-zoom-token` JSON and finish **MAP_AFTER_REAL_RESPONSE** in `ZoomModels.swift`.
5. Never put Zoom secrets in the client — use the backend token.

## Run

1. Open `Learning.xcodeproj` in Xcode.
2. Select an iPhone simulator or device.
3. Build & Run (`Cmd+R`).
4. Log in with organization credentials (same as Android).

## Mapping checklist

- [ ] Capture real `get-zoom-token` JSON → update `ZoomModels.swift`
- [ ] Confirm Reset Password Android endpoint → `TelecomAPI.resetPassword` + `ResetPasswordService.isEndpointConfigured = true`
- [ ] Confirm local **Recordings** vs **Cloud Recordings** Android behavior
- [ ] Link MobileRTC and enable `ZOOM_MEETING_SDK`
- [ ] Wire host controls Listen All / Logout All to MobileRTC participant APIs

## Security

- Auth token stored in Keychain only
- Passwords never persisted
- No hardcoded tokens or Zoom secrets in source
