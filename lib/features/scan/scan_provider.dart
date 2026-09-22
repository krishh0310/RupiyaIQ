import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../config.dart';
import '../../data/models.dart';
import '../../data/services/gemini_service.dart';
import 'receipt_parser.dart';

enum ScanStage { capture, processing, review, success }

const kProcessingSteps = ['Reading text…', 'Understanding bill…', 'Categorizing…', 'Saving…'];

class ScanState {
  const ScanState({
    this.stage = ScanStage.capture,
    this.step = 0,
    this.sourcePath,
    this.draft,
    this.notice,
    this.saved,
  });

  final ScanStage stage;

  /// Index into [kProcessingSteps] while processing.
  final int step;
  final String? sourcePath;

  /// Pre-filled expense shown on the review screen.
  final Expense? draft;

  /// One-off message for a snackbar (e.g. "AI timed out, fill manually").
  final String? notice;
  final Expense? saved;
}

final scanProvider = NotifierProvider<ScanNotifier, ScanState>(ScanNotifier.new);

class ScanNotifier extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanState();

  /// photo → on-device OCR → Gemini JSON → Expense draft → review screen.
  /// Any failure along the way degrades to a manual-entry draft pre-filled
  /// from the OCR text; it never throws.
  Future<void> process(String photoPath) async {
    if (state.stage == ScanStage.processing) return;
    state = ScanState(stage: ScanStage.processing, sourcePath: photoPath);

    // 1. OCR — ML Kit, fully offline.
    var ocr = '';
    String? notice;
    try {
      ocr = await _recognizeText(photoPath);
    } catch (_) {
      notice = "Couldn't read text from this photo — please enter the details.";
    }

    // 2. Gemini structured extraction.
    _setStep(1);
    Expense? draft;
    if (ocr.trim().isEmpty) {
      notice ??= 'No text found on this image — please enter the details.';
    } else {
      // extractReceipt never throws: (json, null) or (null, reason).
      final (json, error) = await ref.read(geminiServiceProvider).extractReceipt(ocr);
      if (json != null) {
        try {
          draft = ReceiptParser.fromGemini(json, rawOcr: ocr);
        } catch (_) {
          notice = 'AI answer was incomplete — fields pre-filled from scanned text.';
        }
      } else {
        notice = '$error Fields pre-filled from scanned text.';
      }
    }

    // 3. Category is part of the AI answer; the short pause lets the stage be read.
    _setStep(2);
    await Future<void>.delayed(const Duration(milliseconds: 350));

    // 4. Copy the photo into app documents so it survives cache clears.
    _setStep(3);
    String imagePath;
    try {
      imagePath = await _persistImage(photoPath);
    } catch (_) {
      imagePath = photoPath;
    }
    draft = (draft ?? ReceiptParser.fromOcrFallback(ocr)).copyWith(imagePath: imagePath);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    state = ScanState(stage: ScanStage.review, sourcePath: photoPath, draft: draft, notice: notice);
  }

  /// "Demo mode" stage safety net: runs the bundled sample bill through the
  /// exact same OCR → Gemini → review pipeline as a real photo.
  Future<void> processDemoReceipt() async {
    if (state.stage == ScanStage.processing) return;
    try {
      final bytes = await rootBundle.load(kDemoReceiptAsset);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'demo_receipt_${DateTime.now().millisecondsSinceEpoch}.jpg'));
      await file.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), flush: true);
      await process(file.path);
    } catch (_) {
      state = const ScanState(notice: "Couldn't load the demo receipt.");
    }
  }

  void markSaved(Expense e) => state = ScanState(stage: ScanStage.success, saved: e);

  void reset() => state = const ScanState();

  void _setStep(int step) {
    if (state.stage != ScanStage.processing) return;
    state = ScanState(stage: ScanStage.processing, step: step, sourcePath: state.sourcePath);
  }

  static Future<String> _recognizeText(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(path));
      return result.text;
    } finally {
      await recognizer.close();
    }
  }

  static Future<String> _persistImage(String source) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'receipts'));
    await dir.create(recursive: true);
    final ext = p.extension(source).isEmpty ? '.jpg' : p.extension(source);
    final dest = p.join(dir.path, 'receipt_${DateTime.now().millisecondsSinceEpoch}$ext');
    return (await File(source).copy(dest)).path;
  }
}
