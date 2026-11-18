# InvestMetric: project handoff

This document carries the project from one chat to the next. A new chat, or a new person, should
read it first. It records:
- what the app is
- what has been decided, and why
- what has been built and what is left
- how to run and test it on a real phone

> **For a new Claude chat:** read this whole file before doing anything. Then follow
> "First tasks for the next chat" at the end.

---

## 1. What the app is

InvestMetric is an Android-first mobile app, built with Flutter and Firebase. It tracks a family's
investments in one place and replaces an Excel sheet. It covers:

- **What you own:** mutual funds, stocks, FDs, RDs, post office schemes, bonds, PPF, EPF, NPS,
  gold/SGB, property and insurance.
- **Interest and ROI:** interest earned per deposit, per bank and per tax year, plus maturity
  amounts and payouts.
- **Tax:**
  - TDS that banks deduct, and the TDS limits
  - Form 15G/15H tracking
  - AIS import, comparing the interest reported to the tax department with what the app expects
- **Key dates:** maturities, RD instalments, SIP dates and tax deadlines.

It is built for general use. Any family can use it, not just one person.

---

## 2. Decisions already made (don't re-ask these)

| Topic | Decision |
|---|---|
| Platforms | **Android first**, iPhone later from the same Flutter code |
| Framework | **Flutter** |
| Backend | **Firebase**: Firestore for data, Firebase Auth with **Google login** |
| Family | **One Google login manages everyone.** Family members (e.g. mother, sister) are *profiles*, not users. They don't install the app or log in. Their email is stored only as a reference: it's the address their CAS and bank statements go to. |
| Cost | **Keep the app free.** No paid APIs and no paid Firebase features. |
| Mutual fund prices | Fetched **on demand** (refresh button) from AMFI's free public NAV file, directly from the phone. No server or Cloud Functions. |
| Stock prices | **Entered by hand** (no free official API) |
| Theme | **Dark, deep navy, classy**, with a champagne-gold accent. Dark is the default; light and auto are also available. |
| AIS | The AIS **JSON** download is **encrypted** (an undocumented format for the portal's own offline tool), so it isn't used. The app imports the **AIS PDF** instead. Its password is the PAN in lower case + date of birth as DDMMYYYY, and the app fills it in from the member's profile. |
| Privacy | The AIS PDF and its password never leave the phone. Only the extracted amounts are saved. Firestore rules allow each user to read and write only `users/{their uid}/…`. |
| App id | `com.investmetric.app`, display name "Invest Tracker" (can be renamed later) |
| Repository | GitHub **`rahulsyn27/InvestMetric`** (keep it **private**) |

---

## 3. Where the code is right now

- **3 commits** on branch `main`:
  1. `Investment tracker app: Phase 1`
  2. `Use com.investmetric.app and a shared debug key`
  3. `Connect Firebase and import AIS PDFs`
  4. (this file, `HANDOFF.md`, is added in a 4th commit)
- **The code has NOT been pushed to GitHub yet.** The cloud session reached GitHub through the
  account `lurvik215`, which doesn't have write access to `rahulsyn27/InvestMetric`.
- **The full code is in the file `InvestMetric.bundle`** (a git bundle with the complete history),
  which was downloaded from the previous chat.

### Get the code into GitHub (do this first)

On your computer, in the folder that has `InvestMetric.bundle`, run these one after another:

```bash
git clone InvestMetric.bundle InvestMetric
```

```bash
cd InvestMetric
```

```bash
git remote set-url origin https://github.com/rahulsyn27/InvestMetric.git
```

```bash
git push -u origin main
```

If the GitHub repo was created with a README, the push is rejected because the repo isn't empty.
In that case, run this instead:

```bash
git pull --rebase origin main
```

```bash
git push -u origin main
```

Or, to let a cloud Claude session push for you: in the repo's Settings → Collaborators, invite the
GitHub account that Claude is connected to, and accept the invite with **Write** access.

---

## 4. Tech stack and versions

- **Flutter 3.50.0** (stable, Nov 2026) with **Dart 3.14**.
- **Material is now a separate package.** In Flutter 3.50, `package:flutter/material.dart` is
  **deprecated**. The project imports **`package:material_ui/material_ui.dart`** instead (the
  `material_ui` package). Keep it that way.
- Main packages:
  - `firebase_core ^5.2.0`, `firebase_auth ^7.1.0`, `cloud_firestore ^7.2.0`
  - `google_sign_in ^7.2.0`: the v7 API, i.e. `GoogleSignIn.instance.initialize()` and
    `authenticate()`, not the old `signIn()`
  - `flutter_riverpod ^3.5.0`: Riverpod 3, using `Notifier` / `NotifierProvider`. Don't use the
    legacy `StateProvider`.
  - `intl`, `http`, `shared_preferences`
  - `syncfusion_flutter_pdf ^35.2.12`: opens the password-protected AIS PDF and extracts the text
    with positions. Pure Dart, so it works in `flutter test`.
  - `file_picker ^13.4.0`: v13 API, `FilePicker.pickFile(...)` then `readAsBytes()`
- **Font:** Manrope, bundled in `assets/fonts` under the OFL licence. Roboto is the fallback for
  the ₹ sign.

### Code layout

```
lib/
  main.dart               Firebase init, offline persistence, app start
  app.dart                MaterialApp, AuthGate, creates the "Self" profile on first login
  firebase_options.dart   Android config for project "investmetric" (iOS not set up)
  core/
    money.dart            ₹12,34,567 formatting, ₹12.4 L / ₹1.25 Cr, parsing
    dates.dart            TaxYear (Apr–Mar), addMonths, date helpers
    tax_rules.dart        ALL tax numbers in one place (update after each Budget)
  models/
    member.dart           family profile (name, relation, email, PAN, DOB, senior check)
    investment.dart       one flexible record for every asset type
    ais.dart              AIS statement, records, entries, tax payments, refunds
  logic/                  pure Dart, unit tested
    deposit_math.dart     FD/RD interest: value, maturity, interest between dates, payouts
    valuation.dart        invested/current/gain, CAGR, totals by asset type
    interest_report.dart  interest per member per bank per tax year + expected TDS
    upcoming_events.dart  maturities, RD instalments, SIPs, payouts, tax deadlines
    amfi.dart             AMFI NAVAll.txt download, parsing and search
    ais_parser.dart       reads AIS tables from positioned words
    ais_pdf.dart          opens the encrypted PDF, password helper, errors
    ais_match.dart        "SBI" = "STATE BANK OF INDIA" matching; app-vs-AIS interest check
  data/
    repository.dart       Repository interface + Firestore impl + in-memory impl (tests)
    auth_service.dart     Google sign-in → Firebase; web client id constant
    providers.dart        Riverpod providers (auth, data, selected member, theme, NAVs, AIS)
  theme/app_theme.dart    dark navy + gold theme, light theme, AppColors extension
  ui/                     screens (Home, Holdings, Detail, Form, Calendar, Tax, Family,
                          AIS import, AIS section, fund search, sign-in)
test/
  logic_test.dart         money, dates, interest maths, valuation, TDS report, AMFI, events
  ais_test.dart           builds an encrypted AIS-like PDF and reads it end to end; bank matching
  app_test.dart           widget tests: every tab, filters, add-investment, AIS import flow
  support/ais_fixture.dart  generator for the fake AIS PDF (made-up data)
firestore.rules           per-user security rules
docs/screenshots/         app screenshots (dark theme)
```

### Firestore data

```
users/{uid}/members/{memberId}          name, relation, email, pan, dateOfBirth, isSelf
users/{uid}/investments/{investmentId}  memberId, type, name, institution, rates, dates,
                                        units/prices or balances, TDS / 15G-15H flags
users/{uid}/ais/{memberId}_{startYear}  imported AIS: records, entries, payments, refunds
```

Dates are stored as `yyyy-MM-dd` strings. Writes don't wait for the server (offline-first) and
errors are logged.

---

## 5. Firebase setup (project `investmetric`)

| Item | Value |
|---|---|
| Project id | `investmetric` (project number 168978417222) |
| Android package | `com.investmetric.app` |
| Debug SHA-1 | `79:A7:0E:86:16:A4:74:F9:85:4C:26:8C:E1:27:C2:51:C7:F9:6E:15` |
| Debug SHA-256 | `DD:BC:37:E2:32:36:82:F4:E6:4C:B6:D9:67:29:25:7B:0B:48:FA:95:85:CE:BB:23:00:55:5B:9D:33:C9:36:29` |
| Web client id (used for Google sign-in) | `168978417222-sgnpg9i92q2qe25ppbm309fjgunm4mc5.apps.googleusercontent.com` |

- The SHA values come from **`android/app/debug.keystore`**, which is committed to the repo on
  purpose. That way debug builds from any computer are signed the same way and Google login keeps
  working. Before releasing on the Play Store, make a separate release key, keep it out of git, and
  add its SHA-1 in Firebase too.
- `android/app/google-services.json` is in the repo. The app reads its settings from
  `lib/firebase_options.dart`, so the Google Services Gradle plugin isn't used.

### ⚠️ Check before testing

The downloaded `google-services.json` has **no Android OAuth client** (`client_type: 1`). That
usually means the SHA fingerprints weren't saved when it was downloaded. In the Firebase console:

1. Go to **Project settings → Your apps → Android app**. Make sure **both** fingerprints above are
   listed, and add them if not.
2. Go to **Authentication → Sign-in method** and make sure **Google** is enabled, with a support
   email set.
3. Go to **Firestore Database**. Make sure it exists (region `asia-south1`, production mode) and
   that the **Rules** tab has the contents of `firestore.rules` published.

If login fails with `DEVELOPER_ERROR`, code 10, or "No credentials available", the cause is almost
always step 1.

---

## 6. What is built (done)

- **Sign-in:** Google login. A "Self" profile is created automatically on first login.
- **Family profiles:**
  - add, edit and delete members, with name, relation, reference email, PAN and date of birth
  - date of birth is used for the senior citizen check
  - PAN and date of birth fill in the AIS password automatically
  - "All family / each member" filter chips on every tab
- **Investments:** add, edit, close and delete every asset type. The form changes with the type:
  - **Deposits** (FD, RD, post office, bonds): amount or monthly instalment, rate, start and
    maturity dates (with 1/2/3/5/10-year shortcuts), compounding, cumulative or payout, "bank
    deducts TDS" switch, Form 15G/15H switch, and a live "₹X at maturity" preview.
  - **Market** (MF, stock, gold): units, amount invested, current price, purchase date, SIP amount
    and day. Mutual funds are picked by name from the AMFI list, which links the scheme code.
  - **Balance** (PPF, EPF, NPS, property, insurance, other): total put in, current balance, rate.
- **Home:** current value, invested, total gain, number of holdings, allocation bar by asset type,
  the next 4 events, and an interest summary for the tax year.
- **Holdings:** grouped by asset type with totals and gain %, owner name shown when viewing "All
  family", show/hide closed holdings, and a **refresh mutual fund prices** button (AMFI).
- **Investment detail:**
  - **Deposits:** interest earned so far, interest this tax year, maturity amount, time left, next
    payout, Form 15G/15H toggle.
  - **Market holdings:** units, average cost, price and its date, CAGR, SIP, AMFI code, and a
    manual "Update price" button.
- **Calendar:** the next 12 months of maturities (with overdue ones highlighted), RD instalments,
  SIPs, interest payouts and tax deadlines (advance tax, ITR due date, revised/belated return,
  31 March, 15G/15H reminder).
- **Tax tab:**
  - taxable and tax-free interest per tax year, with previous/next year buttons
  - interest grouped by member and bank, with a progress bar towards the TDS limit (₹50,000, or
    ₹1,00,000 for seniors)
  - expected TDS, a "near the limit" warning, and Form 15G/15H status
- **AIS import:**
  - choose the member, pick the AIS PDF, unlock it, preview what was read, save
  - **reads:** Part B1 TDS/TCS (source, TAN, quarterly credits), B2 SFT, B3 tax payments (advance
    and self-assessment), and B4 refunds; handles wrapped text and the watermark
  - **compares:** each bank's interest in AIS against the app's estimate up to the same date, and
    flags: matches / AIS higher / AIS lower / not in AIS yet / in AIS but not in the app
  - shows TDS split by salary, interest and other
  - if nothing could be read, a "Copy text read from PDF" button helps fix the reader
- **Theme:** dark navy with gold, plus light and auto modes (saved on the phone), and a navy launch
  screen.
- **Quality:** `flutter analyze` reports no issues and **34 tests pass**.

---

## 7. Known gaps and risks (be honest about these)

1. **The app has never run on a real phone.** The cloud machine had no Android SDK. Only the Dart
   code was compiled and tested. The first `flutter run` may surface Gradle or Android setup
   issues, which should be fixed then.
2. **The AIS reader was tested on a fake PDF** built to match a screenshot of a real AIS, not on a
   real AIS file. The real PDF may extract text in a different order. Fix this with the
   "Copy text read from PDF" output, with PAN and names hidden.
3. **Interest figures are estimates** (days ÷ 365, standard compounding). They're usually within a
   few rupees of the bank, but banks round and post interest on their own schedules.
4. **iOS is not set up in Firebase.** `firebase_options.dart` throws on iOS.
5. **Syncfusion PDF licence:** free under its Community License, but the user should register at
   https://www.syncfusion.com/products/communitylicense
6. **The shared debug key** is fine for a private repo. Release builds need their own secret key.
7. Tax rules follow the **Income-tax Act, 2025** (in force since 1 April 2026), which uses "tax
   year" and new section numbers (salary TDS shows as "Section 392" in AIS). All limits and rates
   are in `lib/core/tax_rules.dart`. This is not tax advice.

---

## 8. How to run and test locally

### One-time setup

1. Install **Flutter 3.50+**: https://docs.flutter.dev/get-started/install
2. Install **Android Studio** (it provides the Android SDK). Then run:
   ```bash
   flutter doctor
   ```
   Fix anything it reports and accept the Android licences.
3. On the phone, turn on **Developer options → USB debugging** and connect it by USB.

### Run

```bash
cd InvestMetric
```

```bash
flutter pub get
```

```bash
flutter test
```

```bash
flutter run
```

### Manual test checklist (on the phone)

- [ ] Google login works and the "Self" profile appears in the Family tab
- [ ] Add family members (with PAN + date of birth for one senior member)
- [ ] Add an FD (cumulative), an FD (quarterly payout) and an RD; check the maturity preview
      against the bank's figure
- [ ] Add a mutual fund by searching the AMFI list; tap refresh on Holdings and check the NAV
      updates
- [ ] Add a stock and update its price by hand
- [ ] Add PPF / EPF balances
- [ ] Home totals, allocation bar and "Coming up" look right; the member filter works on every tab
- [ ] Calendar shows maturities, SIPs, RD instalments and tax dates
- [ ] Tax tab: interest per bank, the TDS limit bar, the senior limit for the senior member, and
      the 15G/15H toggle
- [ ] **Import a real AIS PDF:** the password auto-fills, the data is read correctly, and the app vs
      AIS interest comparison makes sense
- [ ] Turn on airplane mode: the app still opens and shows data; changes sync when back online
- [ ] Switch between dark, light and auto themes
- [ ] Sign out and sign in again: the data is still there

---

## 9. Next features (in this order)

### 9.1 Returns by period (agreed as next)

This adds a **Returns** card on Home and on each holding, with period buttons **1M · 3M · 6M ·
1Y · This tax year · All time**. Each shows the gain in ₹ and %, split into **interest earned** and
**market change**.

- **Deposits:** exact, using the existing `DepositMath.interestBetween(inv, from, to)`.
- **Mutual funds:** fetch historical NAVs from AMFI's free NAV history. Value on date X =
  units × NAV(X), adjusted for units bought after X.
- **Stocks and manual balances:** save a **value snapshot** to Firestore
  (`users/{uid}/snapshots/{yyyy-MM-dd}`) whenever prices are refreshed or the app opens (at most
  once a day). Period returns for these build up from the day the feature is added.
- **Monthly interest view:** a bar chart of interest earned per month and payouts received per
  month, per member and bank.
- Proper **XIRR** needs dated transactions, which come with the CAS import (9.2).

### 9.2 Later

1. **Mutual fund CAS import** (CAMS/KFintech consolidated statement PDF, also password protected):
   all folios, transactions and lots → XIRR, SIP history.
2. **Excel/CSV import** of the existing spreadsheet: map columns once, then import.
3. **Capital gains:**
   - short-term vs long-term per lot
   - equity: LTCG 12.5% above ₹1.25 lakh a year; STCG 20%
   - debt funds bought after April 2023 taxed at the slab rate
   - a "book gains tax-free" suggestion
   - a capital gains report for the ITR
4. **Advance tax planner**, using AIS B3 payments.
5. **Phone notifications** for maturities, SIPs and tax dates (`flutter_local_notifications`).
6. **iPhone build**: add an iOS app in Firebase and run `flutterfire configure`.

---

## 10. Design reference

The original clickable mockups (light theme, 6 screens) are here:
https://claude.ai/artifact/5EM1zuU6SfXEKxDtfYSK8r

The built app follows the same structure in the dark navy theme. See `docs/screenshots/`.

---

## First tasks for the next chat

1. Make sure the code is in GitHub `rahulsyn27/InvestMetric` (section 3).
2. Go through the Firebase checks in section 5.
3. Run `flutter test`, then `flutter run` on the phone. Fix any Android build issues.
4. Work through the manual checklist in section 8, especially **importing a real AIS PDF**. Fix the
   AIS reader if needed.
5. Build **Returns by period** (section 9.1).
