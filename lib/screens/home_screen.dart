import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/drawing_mode.dart';
import '../services/autosave_service.dart';
import '../services/github_update_service.dart';
import 'canvas_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _bounceController = AnimationController(
    duration: const Duration(milliseconds: 1200),
    vsync: this,
  )..repeat(reverse: true);
  late final Animation<double> _bounceAnim =
      Tween<double>(begin: 0, end: -12).animate(
          CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    _checkAutosave();
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  Future<void> _checkAutosave() async {
    if (!mounted) return;
    final has = await AutosaveService.hasAutosave();
    if (!has || !mounted) return;

    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('🎨 Disegno salvato!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        content: const Text(
          'Ho trovato un disegno che stavi facendo.\nVuoi continuare da dove eri rimasta?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No, nuovo', style: TextStyle(fontSize: 16))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('✨ Sì, continua!',
                  style: TextStyle(fontSize: 16))),
        ],
      ),
    );

    if (restore == true && mounted) {
      final bytes = await AutosaveService.loadAutosave();
      if (bytes != null && mounted) {
        _openCanvas(DrawingMode.freeHand, imageBytes: bytes);
      }
    } else {
      await AutosaveService.clearAutosave();
    }
  }

  void _openCanvas(DrawingMode mode, {Uint8List? imageBytes}) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) =>
            CanvasScreen(drawingMode: mode, imageBytes: imageBytes),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
            child: child,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  Future<void> _pickImage(DrawingMode mode) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file != null && mounted) {
      _openCanvas(mode, imageBytes: await file.readAsBytes());
    }
  }

  void _showModeDialog(DrawingMode mode) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          mode == DrawingMode.freeHand ? '✏️ Mano Libera' : '🪣 Colora a Tocco',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Vuoi usare una tua immagine\no iniziare con una tela bianca?',
          style: TextStyle(fontSize: 17),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.image_outlined),
            label: const Text('Usa una foto', style: TextStyle(fontSize: 16)),
            onPressed: () { Navigator.pop(context); _pickImage(mode); },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.brush),
            label: const Text('Tela bianca', style: TextStyle(fontSize: 16)),
            onPressed: () { Navigator.pop(context); _openCanvas(mode); },
          ),
        ],
      ),
    );
  }

  Future<void> _showOptionsDialog() async {
    final ctrl = TextEditingController();
    final correct = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('🔐 Opzioni Genitori',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Risolvi per continuare:', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 12),
          const Text('5 + 3 = ?',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold,
                  color: Colors.deepPurple)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              hintText: '?',
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla')),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(ctrl.text.trim()) == 8),
            child: const Text('✓ Conferma'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (correct != true) {
      if (correct == false) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ Risposta sbagliata! Riprova.',
              style: TextStyle(fontSize: 16)),
          backgroundColor: Colors.redAccent,
        ));
      }
      return;
    }
    _showOptionsPanel();
  }

  void _showOptionsPanel() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _OptionsPanel(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF0F5), Color(0xFFF0E6FF), Color(0xFFE6F4FF)],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            const SizedBox(height: 24),
            AnimatedBuilder(
              animation: _bounceAnim,
              builder: (_, child) => Transform.translate(
                  offset: Offset(0, _bounceAnim.value), child: child),
              child: Column(children: [
                const Text('🎨', style: TextStyle(fontSize: 72)),
                const SizedBox(height: 8),
                const Text('Album da Colorare',
                    style: TextStyle(fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFB048C8))),
                const Text('Scegli come vuoi giocare!',
                    style: TextStyle(fontSize: 18, color: Colors.grey)),
              ]),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(children: [
                _BigModeButton(
                  emoji: '🖌️', label: 'Disegna a Mano Libera',
                  subtitle: 'Pennelli e glitter!',
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B9D), Color(0xFFFF8E53)]),
                  onTap: () => _showModeDialog(DrawingMode.freeHand),
                ),
                const SizedBox(height: 20),
                _BigModeButton(
                  emoji: '🪣', label: 'Colora a Tocco',
                  subtitle: 'Tocca e colora!',
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6B8CFF), Color(0xFF9B59B6)]),
                  onTap: () => _showModeDialog(DrawingMode.floodFill),
                ),
                const SizedBox(height: 20),
                _BigModeButton(
                  emoji: '🖼️', label: 'Carica Immagine',
                  subtitle: 'Apri una foto dalla galleria',
                  gradient: const LinearGradient(
                      colors: [Color(0xFF2ECC71), Color(0xFF1ABC9C)]),
                  onTap: () async {
                    final mode = await showDialog<DrawingMode>(
                      context: context,
                      builder: (_) => SimpleDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        title: const Text('Come vuoi colorare?',
                            style: TextStyle(fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        children: [
                          SimpleDialogOption(
                              onPressed: () =>
                                  Navigator.pop(context, DrawingMode.freeHand),
                              child: const Text('✏️ Mano libera',
                                  style: TextStyle(fontSize: 18))),
                          SimpleDialogOption(
                              onPressed: () =>
                                  Navigator.pop(context, DrawingMode.floodFill),
                              child: const Text('🪣 Colora a tocco',
                                  style: TextStyle(fontSize: 18))),
                        ],
                      ),
                    );
                    if (mode != null) _pickImage(mode);
                  },
                ),
              ]),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: TextButton.icon(
                icon: const Icon(Icons.settings, color: Colors.grey),
                label: const Text('Opzioni',
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
                onPressed: _showOptionsDialog,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _BigModeButton extends StatelessWidget {
  final String emoji, label, subtitle;
  final LinearGradient gradient;
  final VoidCallback onTap;
  const _BigModeButton({required this.emoji, required this.label,
      required this.subtitle, required this.gradient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(24),
      elevation: 6,
      shadowColor: gradient.colors.first.withOpacity(0.4),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 24),
          decoration: BoxDecoration(
              gradient: gradient, borderRadius: BorderRadius.circular(24)),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 20,
                  fontWeight: FontWeight.bold, color: Colors.white)),
              Text(subtitle, style: const TextStyle(
                  fontSize: 14, color: Colors.white70)),
            ]),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 20),
          ]),
        ),
      ),
    );
  }
}

class _OptionsPanel extends StatefulWidget {
  const _OptionsPanel();
  @override
  State<_OptionsPanel> createState() => _OptionsPanelState();
}

class _OptionsPanelState extends State<_OptionsPanel> {
  bool _checking = false;
  String _status = '';

  Future<void> _checkUpdates() async {
    setState(() { _checking = true; _status = 'Controllo in corso...'; });
    final info = await GithubUpdateService.checkForUpdates();
    if (!mounted) return;
    if (info == null) {
      setState(() { _checking = false; _status = '⚠️ Nessuna connessione.'; });
      return;
    }
    if (GithubUpdateService.isNewerVersion(info.tagName)) {
      setState(() { _checking = false; _status = '🎉 v${info.tagName} disponibile!'; });
      if (info.apkUrl != null && mounted) {
        showDialog(context: context, builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('🎉 Aggiornamento v${info.tagName}!',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          content: Text(info.body.length > 300
              ? '${info.body.substring(0, 300)}...' : info.body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Dopo')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                GithubUpdateService.downloadApk(info.apkUrl!);
              },
              child: const Text('⬇️ Scarica APK'),
            ),
          ],
        ));
      }
    } else {
      setState(() { _checking = false; _status = '✅ Sei aggiornata! (v${info.tagName})'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        const Text('⚙️ Opzioni',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: _checking
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        color: Colors.white))
                : const Icon(Icons.system_update_alt),
            label: Text(_checking ? 'Controllo...' : '🔍 Cerca Aggiornamenti',
                style: const TextStyle(fontSize: 18)),
            onPressed: _checking ? null : _checkUpdates,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6B8CFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_status, style: const TextStyle(fontSize: 15, color: Colors.grey),
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: 16),
        const Text('Album da Colorare v1.0.0\nCreato con ❤️ per le tue bambine',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 8),
      ]),
    );
  }
}
