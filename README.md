# Invest Tracker

A family investment tracker for India, built with Flutter and Firebase. It replaces the Excel sheet:
mutual funds, FDs, RDs, PPF, EPF, NPS, stocks, gold, post office schemes and more, for everyone in
the family, in one app.

<p>
  <img src="docs/screenshots/home.png" width="200" alt="Home">
  <img src="docs/screenshots/holdings.png" width="200" alt="Holdings">
  <img src="docs/screenshots/interest.png" width="200" alt="Interest and TDS">
  <img src="docs/screenshots/calendar.png" width="200" alt="Calendar">
</p>

## What it does (Phase 1)

- **Google login.** Data is stored in Firestore under your account and works offline too.
- **Family profiles.** Add parents, siblings and others. They don't need the app. You manage
  everything, and each investment belongs to one person.
- **All asset types.**
  - FDs, RDs, bonds and post office schemes: rate-based interest maths.
  - Mutual funds, stocks and gold: units × price.
  - PPF, EPF, NPS, property and insurance: a balance you update yourself.
- **Interest tracking.** For each deposit: interest earned so far, interest in each tax year, the
  maturity amount and the next payout.
- **TDS estimate.** Interest is grouped by bank and by person. The app shows when a bank will cross
  the TDS limit (₹50,000, or ₹1 lakh for senior citizens) and how much TDS to expect. It also tracks
  whether Form 15G/15H has been submitted.
- **Calendar.** Maturities, RD instalments, SIP dates, interest payouts and tax deadlines
  (advance tax, ITR, 31 March).
- **AIS import.** Pick the AIS PDF from the income tax portal. The password (PAN in small letters
  + date of birth DDMMYYYY) is filled in from the member's profile. The app reads:
  - TDS/TCS by source (salary, interest and others)
  - SFT information
  - advance and self-assessment tax paid
  - refunds

  It then compares each bank's reported interest with what that member's deposits should have
  earned up to the same date, and flags:
  - mismatches
  - deposits that are missing in the app
  - banks that haven't reported yet

  The PDF and password never leave the phone. Only the amounts are saved.
- **Free mutual fund prices.** Tap refresh on Holdings to pull today's NAVs from AMFI's public file.
  There's no server and no cost. Stock prices are updated by hand.
- **Themes.** Dark navy theme by default, plus light and auto modes.

Tax numbers live in [`lib/core/tax_rules.dart`](lib/core/tax_rules.dart), so they're easy to
update after a Budget.

## Roadmap

- **Phase 2:**
  - Import the mutual fund CAS PDF.
  - Import from Excel/CSV.
  - (AIS PDF import is done.)
- **Phase 3:**
  - Capital gains (short-term vs long-term, the ₹1.25 lakh exemption).
  - XIRR from transactions.
  - Advance tax planner.
  - Reports for filing the ITR.
- **Phase 4:** reminders as phone notifications, and an iPhone build.

## Run it

You need [Flutter](https://docs.flutter.dev/get-started/install) (3.50 or newer) and Android
Studio, or a phone with USB debugging turned on.

```bash
flutter pub get
flutter test
```

The app won't start until Firebase is connected, as described below.

## Connect Firebase (one time)

The Firebase project is **investmetric**. The Android app id is **`com.investmetric.app`**.

1. **Authentication → Get started → Sign-in method → Google → Enable.** Pick a support email and
   save.
2. **Firestore Database → Create database.** Pick location `asia-south1` (Mumbai) and **production
   mode**. Then open the **Rules** tab, paste in [`firestore.rules`](firestore.rules), and click
   **Publish**.
3. **Project settings (gear icon) → General → Your apps → Add app → Android:**
   - Android package name: `com.investmetric.app`
   - App nickname: `InvestMetric Android`
   - Debug signing certificate SHA-1: `79:A7:0E:86:16:A4:74:F9:85:4C:26:8C:E1:27:C2:51:C7:F9:6E:15`
4. Click **Register app** and download **`google-services.json`**.
5. In the same app's settings, click **Add fingerprint** and add the SHA-256:
   `DD:BC:37:E2:32:36:82:F4:E6:4C:B6:D9:67:29:25:7B:0B:48:FA:95:85:CE:BB:23:00:55:5B:9D:33:C9:36:29`
6. Download `google-services.json` again, now that both fingerprints are added. Generate
   `lib/firebase_options.dart` from it, either with `flutterfire configure` or by hand: it needs the
   API key, app id, sender id and project id from the JSON. Set `kGoogleServerClientId` in
   `lib/data/auth_service.dart` to the `client_id` of the `client_type: 3` entry.

**About the SHA-1:** it comes from `android/app/debug.keystore`. This debug key is shared through
the repo on purpose, so Google sign-in works from any computer without registering a new
fingerprint. Before publishing to the Play Store, create a separate release key, keep it out of
git, and add its SHA-1 as well.

If Google login fails with `DEVELOPER_ERROR` or code 10, check the SHA-1 above and the server
client id.

## Code layout

```
lib/
  core/       money formatting (₹12,34,567), tax years, tax rules
  models/     Member, Investment
  logic/      deposit interest maths, valuation, interest & TDS report,
              calendar events, AMFI NAV parsing  (pure Dart, unit tested)
  data/       Firestore repository, Google sign-in, Riverpod providers
  theme/      dark navy + gold theme, light theme
  ui/         screens
test/         unit tests for the maths, widget tests for the screens
```

Data is stored in Firestore like this:

```
users/{uid}/members/{memberId}          name, relation, email, PAN, date of birth
users/{uid}/investments/{investmentId}  one document per FD / fund / account
```

## Licences

PDFs are read with [`syncfusion_flutter_pdf`](https://pub.dev/packages/syncfusion_flutter_pdf),
which is free under the Syncfusion **Community License** for individuals and small organisations
(under $1M revenue). Register for it at <https://www.syncfusion.com/products/communitylicense>.
The Manrope font is under the SIL Open Font License (`assets/fonts/OFL.txt`).

## Notes

- Interest figures are estimates from the rate (days ÷ 365). They're usually within a few rupees of
  the bank's figures, but banks round and post interest on their own schedules.
- Nothing here is tax advice. Check the numbers with your bank or a CA before filing.
