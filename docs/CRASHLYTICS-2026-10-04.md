# Crashlytics — integration done; physical receipt pending

H2 is not complete: no physical test crash, symbol upload or readable Firebase
dashboard receipt has been observed. The only currently registered iPhone is
unavailable. Integration/privacy and a fresh Simulator build are verified locally.

FirebaseCrashlytics is a dependency of the existing pinned Firebase SDK, without
adding Google Analytics. Info.plist disables collection before Firebase startup.
Simulator/unit-test hosts disable collection and delete unsent reports. Debug
physical QA must explicitly enable it; release physical builds allow diagnostics
unless opted out. Profile's crash-report control is separate from first-party
product analytics. No UID, email, story prose, GPS or screen breadcrumbs are set.

The final Xcode build phase uses Firebase's Crashlytics/run script with the
required dSYM, binary and built GoogleService-Info.plist inputs. Build settings
produce DWARF with dSYM and disable the extra Debug dylib. External symbol upload
is guarded by `PLATFORM_NAME=iphoneos` and explicit
`VERDURE_UPLOAD_CRASH_SYMBOLS=YES`; it defaults to NO for this local sprint.
The fresh Simulator binary and dSYM UUIDs match in
`docs/evidence/crashlytics-local-symbols-2026-10-04.json`. That is local symbol
evidence only, not proof of readable device reports.

## Physical QA procedure still required

1. Connect/unlock a physical iPhone, select the free Personal Team and record
   its model, iOS version and build SHA. Verify Firebase's configured app/bundle
   identity; the legacy GoogleService file mismatch is not silently corrected.
2. Build with `VERDURE_UPLOAD_CRASH_SYMBOLS=YES` to exercise the configured
   upload phase. Record success/failure and the binary/dSYM UUID match. This is
   an explicit diagnostic upload, not a Functions/rules/index deployment.
3. In the Debug launch arguments set `-QAEnableCrashReporting YES` and
   `-QAExposeTestCrash YES`. Local Auth/Firestore/Functions/Storage can still
   use DEBUG emulator opt-in; diagnostics intentionally go to Crashlytics.
4. Launch once, then stop Xcode and launch from the phone without the debugger.
   Profile exposes the physical QA test-crash action only under both flags and
   with crash reporting enabled. Trigger it, relaunch and allow upload.
5. Save a dashboard receipt showing the physical device/build and readable
   `CrashReporting.runPhysicalQACrash`/source frames. Record pending or failed
   delivery honestly. Remove QA flags after the test.

App/website privacy and App Privacy notes now disclose Crashlytics diagnostic
collection, independent opt-out and no Google Analytics/ad SDK. The privacy
manifest declares crash/other diagnostic data and corrects first-party product
interaction linkage. Exact native/web policy parity passed 18 local page tests.

The integration follows Firebase's official
[iOS setup](https://firebase.google.com/docs/crashlytics/ios/get-started) and
[symbol configuration](https://firebase.google.com/docs/crashlytics/ios/get-deobfuscated-reports).
