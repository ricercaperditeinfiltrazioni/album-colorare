import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_drawing_board/flutter_drawing_board.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/drawing_mode.dart';
import '../services/autosave_service.dart';

class _GlitterParticle {
  final Offset pos;
  final Color color;
  final double size;
  final double opacity;
  const _GlitterParticle(this.pos, this.color, this.size, this.opacity);
  _GlitterParticle fade() =>
      _GlitterParticle(pos, color, size, opacity - 0.04);
}

class _GlitterPainter extends CustomPainter {
  final List<_GlitterParticle> particles;
  const _GlitterPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      if (p.opacity <= 0) continue;
      final paint = Paint()
        ..color = p.color.withOpacity(p.opacity.clamp(0.0, 1.0));
      final path = Path();
      for (int i = 0; i < 4; i++) {
        final angle = i * pi / 2;
        final outer = Offset(p.pos.dx + cos(angle) * p.size,
            p.pos.dy + sin(angle) * p.size);
        final inner = Offset(p.pos.dx + cos(angle + pi / 4) * p.size * 0.4,
            p.pos.dy + sin(angle + pi / 4) * p.size * 0.4);
        i == 0 ? path.moveTo(outer.dx, outer.dy) : path.lineTo(outer.dx, outer.dy);
        path.lineTo(inner.dx, inner.dy);
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_GlitterPainter old) => true;
}

img.Image _floodFill(img.Image image, int x, int y,
    img.ColorRgba8 fillColor, int tolerance) {
  final target = image.getPixel(x, y);
  if (_match(target, fillColor, 0)) return image;
  final queue = <Point<int>>[Point(x, y)];
  final visited = <int>{};
  final w = image.width;
  final h = image.height;
  while (queue.isNotEmpty) {
    final p = queue.removeLast();
    if (p.x < 0 || p.x >= w || p.y < 0 || p.y >= h) continue;
    final key = p.y * w + p.x;
    if (visited.contains(key)) continue;
    if (!_match(image.getPixel(p.x, p.y), target, tolerance)) continue;
    visited.add(key);
    image.setPixel(p.x, p.y, fillColor);
    queue.addAll([Point(p.x + 1, p.y), Point(p.x - 1, p.y),
      Point(p.x, p.y + 1), Point(p.x, p.y - 1)]);
  }
  return image;
}

bool _match(img.Pixel a, img.Pixel b, int t) =>
    (a.r - b.r).abs() <= t &&
    (a.g - b.g).abs() <= t &&
    (a.b - b.b).abs() <= t;

class CanvasScreen extends StatefulWidget {
  final DrawingMode drawingMode;
  final Uint8List? imageBytes;
  const CanvasScreen({super.key, required this.drawingMode, this.imageBytes});

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen>
    with WidgetsBindingObserver {
  final _drawingController = DrawingController();
  final _transformController = TransformationController();
  final _canvasKey = GlobalKey();

  Color _color = Colors.red;
  double _brushSize = 8.0;
  bool _isGlitter = false;
  bool _isSaving = false;

  img.Image? _currentImage;
  ui.Image? _displayImage;
  final _history = <img.Image>[];
  final _particles = <_GlitterParticle>[];
  final _rng = Random();
  Timer? _glitterTimer;

  final _palette = const [
    Colors.red, Color(0xFFFF6B9D), Colors.orange, Colors.yellow,
    Colors.green, Color(0xFF00BCD4), Colors.blue, Color(0xFF9B59B6),
    Colors.brown, Colors.black, Colors.white, Colors.grey,
    Color(0xFFFFD700), Color(0xFF00E676), Color(0xFFFF4081), Color(0xFF40C4FF),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.imageBytes != null) _loadImage(widget.imageBytes!);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _drawingController.dispose();
    _transformController.dispose();
    _glitterTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _autoSave();
    }
  }

  Future<void> _autoSave() async {
    final bytes = await _captureCanvas();
    if (bytes != null) await AutosaveService.saveDrawing(bytes);
  }

  Future<void> _loadImage(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return;
    _history.clear();
    setState(() => _currentImage = decoded.clone());
    await _updateDisplay(decoded);
  }

  Future<void> _updateDisplay(img.Image image) async {
    final png = Uint8List.fromList(img.encodePng(image));
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _displayImage = frame.image);
  }

  Future<Uint8List?> _captureCanvas() async {
    try {
      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      final image = await boundary?.toImage(pixelRatio: 2.0);
      final data = await image?.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) { return null; }
  }

  Future<void> _saveToGallery() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final bytes = await _captureCanvas();
      if (bytes != null) {
        await Gal.putImageBytes(bytes,
            name: 'colorare_${DateTime.now().millisecondsSinceEpoch}.png');
        if (mounted) _snack('🎉 Salvato in galleria!', Colors.green);
      }
    } catch (_) {
      if (mounted) _snack('❌ Errore salvataggio', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _share() async {
    try {
      final bytes = await _captureCanvas();
      if (bytes == null) return;
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/mio_disegno.png')..writeAsBytesSync(bytes);
      await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')],
          text: '🎨 Guarda il mio disegno!');
    } catch (_) {
      if (mounted) _snack('❌ Errore condivisione', Colors.red);
    }
  }

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ));

  void _undo() {
    if (widget.drawingMode == DrawingMode.freeHand) {
      _drawingController.undo();
    } else if (_history.isNotEmpty) {
      final prev = _history.removeLast();
      setState(() => _currentImage = prev.clone());
      _updateDisplay(prev);
    }
  }

  void _reset() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('🗑️ Vuoi ricominciare?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: const Text('Tutto verrà cancellato!',
            style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('No', style: TextStyle(fontSize: 16))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _drawingController.clear();
              if (widget.imageBytes != null) _loadImage(widget.imageBytes!);
              setState(() => _particles.clear());
              AutosaveService.clearAutosave();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sì, ricomincia',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Future<void> _onTap(TapDownDetails details) async {
    if (widget.drawingMode != DrawingMode.floodFill) return;
    if (_currentImage == null) return;
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    final sx = _currentImage!.width / box.size.width;
    final sy = _currentImage!.height / box.size.height;
    final ix = (local.dx * sx).round().clamp(0, _currentImage!.width - 1);
    final iy = (local.dy * sy).round().clamp(0, _currentImage!.height - 1);
    _history.add(_currentImage!.clone());
    if (_history.length > 20) _history.removeAt(0);
    final fillColor = img.ColorRgba8(_color.red, _color.green, _color.blue, 255);
    final filled = _floodFill(_currentImage!.clone(), ix, iy, fillColor, 30);
    if (mounted) {
      setState(() => _currentImage = filled);
      _updateDisplay(filled);
    }
  }

  void _startGlitter(Offset pos) {
    if (!_isGlitter) return;
    _glitterTimer?.cancel();
    _glitterTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!mounted) return;
      final colors = [Colors.pink, Colors.yellow, Colors.cyan, Colors.purple,
        Colors.orange, Colors.lightGreen, Colors.white];
      setState(() {
        for (int i = 0; i < 3; i++) {
          _particles.add(_GlitterParticle(
            pos + Offset(_rng.nextDouble() * 30 - 15, _rng.nextDouble() * 30 - 15),
            colors[_rng.nextInt(colors.length)],
            _rng.nextDouble() * 6 + 2, 0.9,
          ));
        }
        for (int i = _particles.length - 1; i >= 0; i--) {
          final faded = _particles[i].fade();
          if (faded.opacity <= 0) { _particles.removeAt(i); }
          else { _particles[i] = faded; }
        }
      });
    });
  }

  void _stopGlitter() => _glitterTimer?.cancel();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F0FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFB048C8),
        foregroundColor: Colors.white,
        title: Text(
          widget.drawingMode == DrawingMode.freeHand
              ? '🖌️ Mano Libera' : '🪣 Colora a Tocco',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (widget.drawingMode == DrawingMode.freeHand)
            IconButton(
              tooltip: 'Effetto Glitter',
              icon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _isGlitter ? Colors.yellowAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('✨', style: TextStyle(fontSize: 22)),
              ),
              onPressed: () => setState(() => _isGlitter = !_isGlitter),
            ),
          if (_isSaving)
            const Padding(padding: EdgeInsets.all(12),
                child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.deepPurple,
        tooltip: 'Reimposta zoom',
        onPressed: () => _transformController.value = Matrix4.identity(),
        child: const Icon(Icons.fit_screen),
      ),
      body: Column(children: [
        Expanded(
          child: GestureDetector(
            onTapDown: _onTap,
            onPanStart: (d) => _startGlitter(d.localPosition),
            onPanUpdate: (d) => _startGlitter(d.localPosition),
            onPanEnd: (_) => _stopGlitter(),
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.5, maxScale: 5.0,
              child: RepaintBoundary(
                key: _canvasKey,
                child: Stack(children: [
                  Positioned.fill(child: CustomPaint(painter: _CheckerPainter())),
                  if (_displayImage != null && widget.drawingMode == DrawingMode.floodFill)
                    Positioned.fill(child: RawImage(
                        image: _displayImage, fit: BoxFit.contain)),
                  if (widget.drawingMode == DrawingMode.freeHand)
                    Positioned.fill(child: DrawingBoard(
                      controller: _drawingController,
                      background: _displayImage != null
                          ? RawImage(image: _displayImage, fit: BoxFit.contain)
                          : Container(color: Colors.white),
                      showDefaultActions: false,
                      showDefaultTools: false,
                    )),
                  if (_particles.isNotEmpty)
                    Positioned.fill(child: IgnorePointer(
                      child: CustomPaint(
                          painter: _GlitterPainter(List.from(_particles))),
                    )),
                ]),
              ),
            ),
          ),
        ),
        _buildToolbar(),
      ]),
    );
  }

  Widget _buildToolbar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _palette.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final c = _palette[i];
              final sel = c.value == _color.value;
              return GestureDetector(
                onTap: () {
                  setState(() => _color = c);
                  if (widget.drawingMode == DrawingMode.freeHand) {
                    _drawingController.setStyle(color: c);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: sel ? 44 : 36, height: sel ? 44 : 36,
                  decoration: BoxDecoration(
                    color: c, shape: BoxShape.circle,
                    border: Border.all(
                        color: sel ? Colors.deepPurple : Colors.grey.shade300,
                        width: sel ? 3 : 1),
                    boxShadow: sel
                        ? [BoxShadow(color: c.withOpacity(0.5), blurRadius: 8)]
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        if (widget.drawingMode == DrawingMode.freeHand)
          Row(children: [
            const Text('🖌️', style: TextStyle(fontSize: 20)),
            Expanded(
              child: Slider(
                value: _brushSize, min: 2, max: 40, divisions: 19,
                activeColor: _color,
                onChanged: (v) {
                  setState(() => _brushSize = v);
                  _drawingController.setStyle(color: _color, strokeWidth: v);
                },
              ),
            ),
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _color),
              child: Center(child: Container(
                width: _brushSize.clamp(4.0, 28.0),
                height: _brushSize.clamp(4.0, 28.0),
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white),
              )),
            ),
          ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _Btn(icon: '↩️', label: 'Undo', color: Colors.orange, onTap: _undo),
          _Btn(icon: '🗑️', label: 'Reset', color: Colors.red, onTap: _reset),
          _Btn(icon: '💾', label: 'Salva', color: Colors.green,
              onTap: _isSaving ? null : _saveToGallery),
          _Btn(icon: '📤', label: 'Condividi', color: Colors.blue, onTap: _share),
        ]),
      ]),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const s = 20.0;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white);
    final p = Paint()..color = const Color(0xFFEEEEEE);
    for (double y = 0; y < size.height; y += s) {
      for (double x = 0; x < size.width; x += s) {
        if (((x / s).toInt() + (y / s).toInt()) % 2 == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, s, s), p);
        }
      }
    }
  }
  @override
  bool shouldRepaint(_) => false;
}

class _Btn extends StatelessWidget {
  final String icon, label;
  final Color color;
  final VoidCallback? onTap;
  const _Btn({required this.icon, required this.label,
      required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.bold, color: color)),
          ]),
        ),
      ),
    );
  }
}
