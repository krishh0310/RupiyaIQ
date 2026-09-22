import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/widgets.dart';
import 'scan_provider.dart';

enum _CamStatus { initializing, ready, denied, noCamera, error }

/// Step 1: full-screen live preview with guide frame, tap-to-focus, torch,
/// gallery fallback and graceful permission / no-camera states.
class CameraView extends ConsumerStatefulWidget {
  const CameraView({super.key});

  @override
  ConsumerState<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends ConsumerState<CameraView> with WidgetsBindingObserver {
  CameraController? _controller;
  _CamStatus _status = _CamStatus.initializing;
  bool _torch = false;
  bool _capturing = false;
  bool _initInFlight = false; // the permission dialog itself triggers inactive→resumed
  Offset? _focusTap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  /// Release the camera when backgrounded; re-acquire (and re-check
  /// permission — the user may have just granted it in Settings) on resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      final c = _controller;
      if (c == null) return;
      _controller = null;
      c.dispose();
      if (mounted) setState(() => _status = _CamStatus.initializing);
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _init();
    }
  }

  Future<void> _init() async {
    if (_initInFlight) return;
    _initInFlight = true;
    try {
      await _initCamera();
    } finally {
      _initInFlight = false;
    }
  }

  Future<void> _initCamera() async {
    final permission = await Permission.camera.request();
    if (!mounted) return;
    if (!permission.isGranted) {
      setState(() => _status = _CamStatus.denied);
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _status = _CamStatus.noCamera);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(back, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await controller.initialize();
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _torch = false;
        _status = _CamStatus.ready;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _status = e.code.contains('AccessDenied') || e.code.contains('Restricted')
          ? _CamStatus.denied
          : _CamStatus.error);
    } catch (_) {
      if (mounted) setState(() => _status = _CamStatus.error);
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await c.takePicture();
      if (_torch) await c.setFlashMode(FlashMode.off);
      ref.read(scanProvider.notifier).process(file.path);
    } catch (_) {
      if (mounted) showSnack(context, "Couldn't take the photo — try again.", isError: true);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (picked != null) ref.read(scanProvider.notifier).process(picked.path);
    } catch (_) {
      if (mounted) showSnack(context, "Couldn't open the gallery.", isError: true);
    }
  }

  /// Stage safety net: long-press the shutter to scan the bundled sample bill.
  void _demoMode() {
    HapticFeedback.mediumImpact();
    showSnack(context, 'Demo mode — scanning the sample receipt');
    ref.read(scanProvider.notifier).processDemoReceipt();
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } catch (_) {
      if (mounted) showSnack(context, 'Flashlight not available on this camera.');
    }
  }

  Future<void> _focusAt(TapUpDetails d, BoxConstraints box) async {
    final c = _controller;
    if (c == null) return;
    setState(() => _focusTap = d.localPosition);
    // Normalised 0..1 point; approximate under the cover-scaling, good enough for focus.
    final point = Offset(d.localPosition.dx / box.maxWidth, d.localPosition.dy / box.maxHeight);
    try {
      await c.setFocusPoint(point);
      await c.setExposurePoint(point);
    } catch (_) {/* not all devices support focus points */}
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _focusTap = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (_status) {
        _CamStatus.ready => _preview(),
        _CamStatus.initializing => const Center(child: CircularProgressIndicator(color: Colors.white)),
        _CamStatus.denied => _message(
            icon: Icons.no_photography_rounded,
            title: 'Camera access needed',
            body: 'RupiyaIQ uses the camera only to photograph your bills. '
                'Photos stay on your phone. You can also pick a bill from your gallery.',
            primary: FilledButton.icon(
              onPressed: openAppSettings,
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Open settings'),
            ),
            showRetry: true,
          ),
        _CamStatus.noCamera => _message(
            icon: Icons.videocam_off_rounded,
            title: 'No camera found',
            body: 'This device has no usable camera. Pick a bill photo from your gallery instead.',
          ),
        _CamStatus.error => _message(
            icon: Icons.error_outline_rounded,
            title: 'Camera unavailable',
            body: 'Another app may be using the camera. Try again, or pick from your gallery.',
            showRetry: true,
          ),
      },
    );
  }

  Widget _preview() {
    final c = _controller!;
    return Stack(fit: StackFit.expand, children: [
      LayoutBuilder(builder: (context, box) {
        // Scale the preview to cover the whole screen without distortion.
        final screenRatio = box.maxWidth / box.maxHeight;
        var scale = screenRatio * c.value.aspectRatio;
        if (scale < 1) scale = 1 / scale;
        return GestureDetector(
          onTapUp: (d) => _focusAt(d, box),
          child: Stack(fit: StackFit.expand, children: [
            ClipRect(child: Transform.scale(scale: scale, child: Center(child: CameraPreview(c)))),
            const IgnorePointer(child: CustomPaint(painter: _GuidePainter())),
            if (_focusTap != null)
              Positioned(
                left: _focusTap!.dx - 32,
                top: _focusTap!.dy - 32,
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1.4, end: 1),
                    duration: const Duration(milliseconds: 250),
                    builder: (_, v, child) => Transform.scale(scale: v, child: child),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.amberAccent, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        );
      }),
      // Top bar
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            _RoundIcon(icon: Icons.close_rounded, onTap: () => Navigator.of(context).maybePop(), tooltip: 'Close'),
            const Spacer(),
            _RoundIcon(
              icon: _torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
              onTap: _toggleTorch,
              tooltip: 'Flashlight',
              active: _torch,
            ),
          ]),
        ),
      ),
      // Hint
      const Align(
        alignment: Alignment(0, -0.72),
        child: IgnorePointer(
          child: Text('Align bill inside frame\n(long-press shutter for demo bill)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 8)])),
        ),
      ),
      // Bottom controls
      Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _RoundIcon(icon: Icons.photo_library_rounded, onTap: _pickFromGallery, tooltip: 'Pick from gallery', size: 52),
              PressableScale(
                onTap: _capture,
                onLongPress: _demoMode,
                child: Container(
                  width: 82,
                  height: 82,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _capturing ? Colors.white54 : Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 52),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
    Widget? primary,
    bool showRetry = false,
  }) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _RoundIcon(icon: Icons.close_rounded, onTap: () => Navigator.of(context).maybePop(), tooltip: 'Close'),
          ),
          const Spacer(),
          Icon(icon, size: 72, color: Colors.white70),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 28),
          ?primary,
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _pickFromGallery,
            icon: const Icon(Icons.photo_library_rounded),
            label: const Text('Pick from gallery'),
          ),
          TextButton.icon(
            onPressed: _demoMode,
            icon: const Icon(Icons.receipt_long_rounded, color: Colors.white70),
            label: const Text('Use demo receipt', style: TextStyle(color: Colors.white70)),
          ),
          if (showRetry)
            TextButton(
              onPressed: () {
                setState(() => _status = _CamStatus.initializing);
                _init();
              },
              child: const Text('Try again', style: TextStyle(color: Colors.white)),
            ),
          const Spacer(),
        ]),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, required this.tooltip, this.size = 44, this.active = false});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: PressableScale(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.amber : Colors.black.withValues(alpha: 0.45),
            ),
            child: Icon(icon, color: active ? Colors.black : Colors.white, size: size * 0.5),
          ),
        ),
      );
}

/// Dims everything outside a receipt-shaped window and draws corner brackets.
class _GuidePainter extends CustomPainter {
  const _GuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.82, h = size.height * 0.56;
    final rect = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.47), width: w, height: h);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(20));

    final overlay = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);
    canvas.drawPath(overlay, Paint()..color = Colors.black.withValues(alpha: 0.45));

    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    final l = rect.left, t = rect.top, r = rect.right, b = rect.bottom;
    canvas
      ..drawPath(Path()..moveTo(l, t + len)..lineTo(l, t + 8)..quadraticBezierTo(l, t, l + 8, t)..lineTo(l + len, t), p)
      ..drawPath(Path()..moveTo(r - len, t)..lineTo(r - 8, t)..quadraticBezierTo(r, t, r, t + 8)..lineTo(r, t + len), p)
      ..drawPath(Path()..moveTo(l, b - len)..lineTo(l, b - 8)..quadraticBezierTo(l, b, l + 8, b)..lineTo(l + len, b), p)
      ..drawPath(Path()..moveTo(r - len, b)..lineTo(r - 8, b)..quadraticBezierTo(r, b, r, b - 8)..lineTo(r, b - len), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
