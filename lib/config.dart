/// ─── RupiyaIQ configuration ────────────────────────────────────────────────
/// Paste your free Gemini API key from https://aistudio.google.com/app/apikey
/// (use "Create API key" — NOT a Live-API ephemeral token).
///
/// Symptom of an ephemeral token: it works at first, then within the hour every
/// AI call fails with 401 "ACCESS_TOKEN_TYPE_UNSUPPORTED" and the app silently
/// drops to offline mode. If that happens mid-demo, generate a fresh key.
///
/// Prefer not to commit the key? Leave the placeholder and pass it at run time:
///   flutter run --dart-define=GEMINI_API_KEY=AIza...
const String geminiApiKey =
    String.fromEnvironment('GEMINI_API_KEY', defaultValue: 'YOUR_API_KEY_HERE');

/// Gemini model used for receipt parsing, insights and chat.
/// Verified against the live API on 22 Sep 2026: gemini-2.5-flash now returns
/// 404 "no longer available to new users" and Google points to gemini-3.6-flash.
// If you get "model not found", try 'gemini-3.6-flash-lite'
const String geminiModel = 'gemini-3.6-flash';

/// Every Gemini call is cut off after this long, then we fall back to offline mode.
const Duration kGeminiTimeout = Duration(seconds: 10);

/// Quick reachability probe before each Gemini call; if it fails we skip
/// the call entirely and go straight to the offline fallback.
const Duration kConnectivityTimeout = Duration(seconds: 5);

/// When true, 25 realistic demo expenses (last 45 days) + budgets are inserted
/// on the very first launch only (guarded by a 'seeded' SharedPreferences flag
/// AND by running inside the DB's onCreate). Set to false to start empty.
/// To re-seed: uninstall the app or clear its data.
const bool kSeedDemoData = true;

/// Bundled sample bill used by "Demo mode" (long-press the capture button).
const String kDemoReceiptAsset = 'assets/test_receipt.jpg';

bool get hasGeminiKey =>
    geminiApiKey.trim().isNotEmpty && geminiApiKey != 'YOUR_API_KEY_HERE';
