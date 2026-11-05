# Shipping a native iOS client for a home server
*Summary: a SwiftUI client built with hosted CI, distributed through beta testing, and hardened after diagnosing push and build-delivery failures.*

## Why native

For the first few months, ORION's phone client was a web app. I later wrapped it in a Capacitor shell. iOS web push had sharp edges: declarative web push never wakes the service worker, so the click handler never runs, and a warm resume often restores the last screen. Tapping a push did not reliably open the thing it was about. The fix that worked was to stop trusting the URL iOS handed the page. The server logged every push it sent, the page asked it for pushes from the last six hours on launch and on becoming visible, and opened the newest one under 15 minutes old that it hadn't seen. The server became the source of truth for what I just pushed. The web wrapper was replaced with a native SwiftUI app.

## What the app was

- **Screens:** Today, Chat, Systems, Network, and Activity.
- **Chat:** Streaming with approval cards inline.
- **Systems:** Refreshed every 15 seconds.
- **Security:** Owner key stored in the Keychain; Face ID gate; TLS pinned to my own LAN certificate authority.
- **Targets:** iPhone app, Apple Watch app, widgets, and a sandboxed Mac app with the hardened runtime.
- **Minimums:** iOS 26, macOS 26, and watchOS 11.

The app talked only to the server. AI coding agents wrote the Swift code under operator review and testing.

## Free signing, then paid

I started on free signing: no cost, but the app expires every seven days and there is no push. I deferred the paid developer account at first. Joining the developer account involved one-time paperwork, which included app IDs, App Store Connect records, an upload API key, and a separate APNs key. Both `.p8` keys download exactly once. Release prep required an export compliance flag and privacy manifests on every target. The privacy manifests stated "Data Not Collected" because everything goes to my own server. I also added a watch app icon because App Store Connect rejects a watch app without one. Build numbers were generated from UTC time using the format `yymmddHHMM`.

## Xcode Cloud

Initial builds depended on an intermittently available development machine. Moving builds to hosted CI removed that availability and keychain dependency. The rule became that feature branches push and run a check workflow whose test attachments provide the screenshots. A push to main triggers the TestFlight archive. Screenshots shown to me had to be native renders, not the old web UI. Xcode Cloud builds only from a pushed branch. When agents were told not to push, they fell back to the offline MacBook. Falling back to the offline MacBook caused two lanes to stall.

## Push that said 200 and showed nothing

APNs appeared to be wired end to end: the app registered, the server sent the push, and Apple returned 200—but nothing appeared on the phone. The app initially failed to request notification permission. iOS still handed out a device token, and Apple accepted the push. The phone silently dropped the push. The fix was twofold. The app asks for permission on first launch. If permission was declined, the app shows "Notifications are off on your iPhone" with a button to the system setting. The server stopped calling a push "delivered" just because Apple accepted it. The server records each device's alert authorization. A push to a device with alerts off is logged as accepted with `delivered: 0, muted: 1`. That one change made the logs honest.

## The builds that never reached the phone

A release was reported as shipped even though the installed beta remained several builds behind. Processing had succeeded, but the internal tester group had stopped receiving new builds automatically. "Valid" only meant Apple had finished processing a build, not that any tester could install it. The group's build list stopped advancing. Xcode Cloud was uploading fine, but nothing was attaching new builds to the group anymore. Every upstream status reported success, but the target device still had an older build. The fix was to attach each build to the group explicitly through the App Store Connect API. Attaching the build flipped it to in-beta-testing. I then pulled to refresh TestFlight. The process change mattered more: after every build, check that the group's build list includes it, and only call it shipped once the version number is on the device. I never found out why auto-attach stopped. On the same day, an audit of 434 native controls removed dead buttons. The audit made the app show a receipt only after the server answered 2xx.

## What I'd do differently

I would go native earlier. I would configure push-capable signing at the start, because free signing hides the hardest integration until late. I would define "shipped" as "the expected version is installed on a test device" from the start. I would automate the check for "shipped." I would make the tester-group attach part of the upload script. I would alert when the group's build list stops growing. I would treat "the upstream service accepted it" as a separate state from "the user saw it" in logs and in the UI. Keep the release steps in the repo, as I did; it made setup and later shutdown much easier.
