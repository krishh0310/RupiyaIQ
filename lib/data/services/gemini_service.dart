import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../../config.dart';

final geminiServiceProvider = Provider<GeminiService>((ref) => GeminiService());

/// User-presentable failure. Every Gemini error is mapped to one of these so
/// callers only ever need `on GeminiException`.
class GeminiException implements Exception {
  const GeminiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GeminiService {
  /// The exact receipt-parsing system prompt from the product spec.
  static const receiptSystemPrompt = '''
You are a receipt parsing engine. Extract data from receipt OCR text and return ONLY valid JSON matching this schema, no markdown, no explanation:
{
  "merchant": "string — shop/vendor name, cleaned",
  "date": "YYYY-MM-DD — if not found, use today's date",
  "items": [{"name": "string", "price": number, "quantity": number}],
  "subtotal": number,
  "tax": number,
  "total": number,
  "category": "exactly one of: Food, Fuel, Grocery, Health, Shopping, Bills, Travel, Entertainment, Other",
  "payment_method": "Cash | UPI | Card | Unknown",
  "confidence": number 0-1
}
Rules: prices as numbers without currency symbols; if items list is incomplete, include what you can; category must be your best inference from merchant + items; if total is missing, sum the items.''';

  static const _offlineMessage = "You're offline — switched to offline mode.";

  // ── Connectivity pre-check ────────────────────────────────────────────────
  // One HTTP HEAD to the Gemini host (5 s cap) before each call. If it fails
  // we skip Gemini entirely instead of waiting out the 10 s timeout on stage.
  // Results are cached briefly so a burst of calls costs one probe.
  static DateTime? _checkedAt;
  static bool _online = false;

  static Future<bool> isOnline() async {
    final checkedAt = _checkedAt;
    if (checkedAt != null) {
      final age = DateTime.now().difference(checkedAt);
      if (age < (_online ? const Duration(seconds: 30) : const Duration(seconds: 5))) return _online;
    }
    final client = HttpClient()..connectionTimeout = kConnectivityTimeout;
    try {
      final request = await client
          .headUrl(Uri.parse('https://generativelanguage.googleapis.com/'))
          .timeout(kConnectivityTimeout);
      final response = await request.close().timeout(kConnectivityTimeout);
      await response.drain<void>().timeout(kConnectivityTimeout);
      _online = true; // any HTTP status (even 404) proves the host is reachable
    } catch (_) {
      _online = false;
    } finally {
      client.close(force: true);
    }
    _checkedAt = DateTime.now();
    return _online;
  }

  /// Throws [GeminiException] if there is no key or no connectivity.
  Future<GenerativeModel> _model({String? system, bool json = false, double temperature = 0.2}) async {
    if (!hasGeminiKey) {
      throw const GeminiException('Gemini API key not set (lib/config.dart) — using offline mode.');
    }
    if (!await isOnline()) throw const GeminiException(_offlineMessage);
    return GenerativeModel(
      model: geminiModel,
      apiKey: geminiApiKey,
      systemInstruction: system == null ? null : Content.system(system),
      generationConfig: GenerationConfig(
        temperature: temperature,
        // Structured output: Gemini is asked to emit raw JSON, no prose.
        responseMimeType: json ? 'application/json' : null,
      ),
    );
  }

  /// OCR text → receipt JSON. NEVER throws.
  /// Returns (json, null) on success, or (null, user-facing reason) on any
  /// failure — no key, offline, timeout, API error, or unparseable JSON.
  Future<(Map<String, dynamic>?, String?)> extractReceipt(String ocrText) async {
    try {
      return (await parseReceipt(ocrText), null);
    } on GeminiException catch (e) {
      return (null, e.message);
    } catch (_) {
      return (null, 'AI extraction failed — switched to manual entry.');
    }
  }

  /// OCR text → receipt JSON map (throws [GeminiException]; prefer [extractReceipt]).
  ///
  /// Attempt 1 sends the OCR text as-is. If the reply is not parseable JSON,
  /// attempt 2 repeats it with an explicit "ONLY valid JSON" reminder. If that
  /// also fails we throw, and the scan flow falls back to manual entry
  /// pre-filled from the OCR text. Timeouts/network errors are not retried.
  Future<Map<String, dynamic>> parseReceipt(String ocrText) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final model = await _model(system: receiptSystemPrompt, json: true, temperature: 0.1);
    for (var attempt = 0; attempt < 2; attempt++) {
      final prompt = StringBuffer('Today is $today.\nReceipt OCR text:\n"""\n$ocrText\n"""');
      if (attempt == 1) {
        prompt.write('\n\nIMPORTANT: Your previous answer was not valid JSON. '
            'Return ONLY valid JSON matching the schema — no markdown, no code fences, no commentary.');
      }
      final decoded = decodeJsonLoose(await _generate(model, prompt.toString()));
      if (decoded is Map<String, dynamic>) return decoded;
    }
    throw const GeminiException('AI returned an unreadable answer — please check the fields.');
  }

  /// One-shot text generation (used for insight cards). Throws [GeminiException].
  Future<String> generate(String prompt, {String? system, bool json = false}) async =>
      _generate(await _model(system: system, json: json, temperature: 0.6), prompt);

  /// Streams a chat answer chunk-by-chunk. [history] is (isUser, text) pairs.
  /// Errors surface as [GeminiException] on the stream.
  Stream<String> chatStream({
    required String system,
    required List<(bool, String)> history,
    required String message,
  }) async* {
    try {
      final model = await _model(system: system, temperature: 0.3);
      final chat = model.startChat(history: [
        for (final (isUser, text) in history)
          isUser ? Content.text(text) : Content.model([TextPart(text)]),
      ]);
      // .timeout on a stream = max 10 s gap between chunks.
      await for (final chunk in chat.sendMessageStream(Content.text(message)).timeout(kGeminiTimeout)) {
        final text = chunk.text;
        if (text != null && text.isNotEmpty) yield text;
      }
    } catch (e) {
      throw _mapError(e);
    }
  }

  Future<String> _generate(GenerativeModel model, String prompt) async {
    try {
      final response = await model.generateContent([Content.text(prompt)]).timeout(kGeminiTimeout);
      return response.text ?? '';
    } catch (e) {
      throw _mapError(e);
    }
  }

  static GeminiException _mapError(Object e) {
    if (e is GeminiException) return e;
    if (e is TimeoutException) {
      return const GeminiException('AI took longer than 10s — switched to offline mode.');
    }
    if (e is SocketException || e is HttpException) {
      _online = false;
      _checkedAt = DateTime.now();
      return const GeminiException(_offlineMessage);
    }
    if (e is GenerativeAIException) {
      return GeminiException('Gemini error: ${e.message}');
    }
    return const GeminiException("Couldn't reach Gemini — switched to offline mode.");
  }

  /// Tolerant JSON decode: strips ```json fences and, failing that, pulls out
  /// the outermost {...} or [...] block. Returns null if nothing parses.
  static Object? decodeJsonLoose(String raw) {
    var text = raw.trim();
    text = text.replaceAll(RegExp(r'^```(?:json)?\s*'), '');
    text = text.replaceAll(RegExp(r'\s*```$'), '');
    try {
      return jsonDecode(text);
    } catch (_) {}
    for (final (open, close) in [('{', '}'), ('[', ']')]) {
      final start = text.indexOf(open), end = text.lastIndexOf(close);
      if (start >= 0 && end > start) {
        try {
          return jsonDecode(text.substring(start, end + 1));
        } catch (_) {}
      }
    }
    return null;
  }
}
