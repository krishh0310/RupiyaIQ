# RupiyaIQ 🧾✨

**Snap a photo of any paper bill.** On-device OCR reads it, Gemini turns it into structured data, and RupiyaIQ categorises it, flags unusual spending and answers questions about your money.

Built with Flutter, Riverpod, ML Kit, Gemini, SQLite and fl_chart. Android, API 24+.

---

## 1. Setup

1. **Install Flutter** (stable 3.47+ / Dart 3.13+, as pinned in pubspec.yaml; tested on 3.47.5): https://docs.flutter.dev/get-started/install
   Run `flutter doctor` and fix anything it flags under *Android toolchain* (Android Studio + SDK + accepted licenses).
2. **Get dependencies**
   ```bash
   cd rupiya_iq
   flutter pub get
   ```
3. **Paste your Gemini API key** (free):
   - Go to https://aistudio.google.com/app/apikey and click **Create API key**.
   - Open `lib/config.dart` and replace the placeholder:
     ```dart
     const String geminiApiKey = 'YOUR_API_KEY_HERE';
     ```
   - Without a key the app still works: OCR, manual entry, charts, anomalies and template insights all run offline.
   - Use the **Create API key** button. Do not use a Live-API ephemeral token: it works at first, then within the hour every AI call fails with `401 ACCESS_TOKEN_TYPE_UNSUPPORTED` and the app quietly falls back to offline mode.
   - Alternatively, keep the key out of the repo and pass it at run time: `flutter run --dart-define=GEMINI_API_KEY=AIza...`
   - The default model is `gemini-3.6-flash`. Verified live on 22 Sep 2026: `gemini-2.5-flash` and `gemini-2.0-flash` now return 404 *"no longer available to new users"*. If you get *model not found*, try `'gemini-3.6-flash-lite'`.
   - `google_generative_ai` is deprecated upstream but kept on purpose. The post-hackathon migration path is `firebase_ai` (Firebase AI Logic).

## 2. Run on a physical Android phone

1. On the phone: **Settings → About phone → tap "Build number" 7 times** to unlock Developer options.
2. **Settings → Developer options → enable USB debugging.** (On iQOO/Vivo, also enable *"USB debugging (Security settings)"* and *"Install via USB"* if you see them.)
3. Connect over USB and accept the "Allow USB debugging?" prompt on the phone.
4. Check it's visible, then run:
   ```bash
   flutter devices
   flutter run --release        # smoothest animations for the demo
   ```
   Or build and install an APK:
   ```bash
   flutter build apk --release
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```

Wireless alternative (Android 11+): Developer options → *Wireless debugging* → pair, then `adb pair <ip:port>` and `adb connect <ip:port>`.

## 3. Demo-day safety nets

- **Demo mode:** long-press the shutter button, or tap *Use demo receipt* when the camera is unavailable. This runs `assets/test_receipt.jpg` (a FreshMart grocery bill, ₹1,272.60, paid by UPI) through the full OCR → Gemini → review pipeline.
- **Offline:** a 5 s HTTP HEAD probe runs before every Gemini call. If it fails, the app skips Gemini and goes straight to the local fallbacks (pre-filled manual entry, template insight cards, a locally computed chat answer).
- The app is locked to portrait. The Insights tab shows *Last updated* and whether the cards came from Gemini or the offline templates.

## 4. Demo data

`kSeedDemoData = true` in `lib/config.dart` inserts 25 realistic bills (Zomato, Big Bazaar, Indian Oil, Apollo Pharmacy, Amazon, Electricity Board, Uber…) spread over the last 45 days, plus budgets. This happens **on first launch only** (it runs only when the database is first created, and a `seeded` SharedPreferences flag guards it too), so every chart, insight and anomaly has data.

- Set it to `false` to start empty.
- To re-seed or reset: uninstall the app (or *App info → Storage → Clear data*) and run again.

The demo data is tuned so that the ₹5,200 Amazon order is the anomaly, the Shopping budget goes red and Food spending is up this week.

## 5. How it works (for the judges)

```
📷 Camera / Gallery
   └─► ML Kit Text Recognition (on-device, offline)
        └─► Gemini (JSON mode, 10 s timeout, 1 retry on malformed JSON)
             ├─ ok   ─► Review screen (every field editable, AI confidence shown)
             └─ fail ─► Review screen pre-filled by local OCR heuristics (merchant, total, date, payment)
                          └─► Duplicate check (merchant + total ≥95% similar, date ±1 day)
                               └─► SQLite ─► Anomaly engine ─► Home / Insights / History update live
```

| Piece | File | Notes |
|---|---|---|
| Receipt prompt + Gemini calls | `lib/data/services/gemini_service.dart` | Exact system prompt; `application/json` output; retry; error → friendly message |
| AI JSON → Expense | `lib/features/scan/receipt_parser.dart` | Tolerates strings-for-numbers, missing totals, future dates, unknown categories |
| Anomaly engine | `lib/features/insights/anomaly_engine.dart` | Per category, 30-day trailing average excluding the bill itself. Flag if > 2.5× or > ₹2,000 above. Needs ≥ 2 prior bills |
| Insight cards | `lib/features/insights/insight_generator.dart` | Compact summary → Gemini → cards; local template cards if offline |
| Ask your money | `lib/features/insights/chat_service.dart` | Injects a ~1–2 KB data summary as the system prompt and streams the answer |
| Prompt data summary | `lib/features/insights/spending_summary.dart` | Category totals vs previous period, top merchants, largest bills |
| DB | `lib/data/db_helper.dart`, `lib/data/repositories/expense_repository.dart` | `expenses`, `items` (cascade), `budgets`; indexes on date/category |

**Privacy:** receipt photos and the database stay on the phone. Gemini only receives OCR text (for parsing) or aggregated totals (for insights/chat).

## 6. Project layout

```
lib/
  main.dart                 app + theme mode
  config.dart               API key, model, seed flag
  core/                     theme, constants (categories/colours), utils (₹ formatting), widgets, router (bottom nav shell)
  data/                     models, db_helper, seed_data, repositories/, services/gemini_service
  features/
    dashboard/              home screen, budget sheet, expenses/budgets providers
    scan/                   camera, processing, review/edit, success, scan provider, receipt parser
    insights/               charts, AI cards, anomaly engine, chat (service + widget), providers
    history/                grouped list with sticky headers, detail screen
test/logic_test.dart        anomaly engine, duplicate score, parser, JSON recovery
```

## 7. Checks

```bash
flutter analyze   # 0 issues
flutter test      # anomaly / duplicate / parser / JSON tests
```

## Troubleshooting

- **Camera permission denied:** the scan screen explains why it's needed and offers *Open settings* and *Pick from gallery*.
- **No internet:** OCR still runs, the review form is pre-filled from local heuristics, and insights fall back to template cards.
- **Fonts look plain on first launch offline:** Google Fonts are downloaded once, on first run with internet, then cached.
