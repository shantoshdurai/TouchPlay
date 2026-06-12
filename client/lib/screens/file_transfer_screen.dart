import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/file_transfer_service.dart';
import '../services/haptics.dart';
import '../services/websocket_service.dart' as ws;
import '../widgets/ambience.dart';

const _accent = Color(0xFF6FB6FF);

/// Phone ⇄ PC file drop. The PC side serves Downloads\TouchPlay; anything the
/// phone sends lands there, and anything in there can be pulled to the phone.
class FileTransferScreen extends StatefulWidget {
  const FileTransferScreen({super.key});

  @override
  State<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends State<FileTransferScreen> {
  List<PcFile>? _files;
  String? _error;
  bool _loading = true;
  late final StreamSubscription<ws.ConnectionState> _connSub;
  ws.ConnectionState _conn = ws.WebSocketService.instance.state;

  // name → progress 0..1 for active transfers
  final _downloading = <String, double>{};
  // Files already saved to this phone (this session) / sent from this phone —
  // so the list reads like a story instead of a bare download icon.
  final _saved = <String>{};
  final _sentFromPhone = <String>{};
  double? _uploadProgress;
  String? _uploadName;

  @override
  void initState() {
    super.initState();
    // File browsing is nicer one-handed: let this screen rotate to portrait
    // (the rest of the app stays landscape-locked).
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    // Auto-load the list the moment the PC link comes up — no dead "blocks"
    // while disconnected, no manual retry needed.
    _connSub = ws.WebSocketService.instance.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _conn = s);
      if (s == ws.ConnectionState.connected) _refresh();
    });
    _refresh();
  }

  @override
  void dispose() {
    _connSub.cancel();
    // Orientation is owned by main.dart's push(): the home menu rotates
    // freely, landscape-only screens lock it on entry.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!FileTransferService.instance.hasServer ||
          ws.WebSocketService.instance.state != ws.ConnectionState.connected) {
        throw Exception('Not connected to the PC server');
      }
      final files = await FileTransferService.instance.listFiles();
      if (!mounted) return;
      setState(() {
        _files = files;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = FileTransferService.instance.hasServer
            ? 'Couldn\'t reach the PC. Is the TouchPlay server running?'
            : 'Connect to your PC first — open the server on your PC.';
        _loading = false;
      });
    }
  }

  Future<void> _download(PcFile f) async {
    if (_downloading.containsKey(f.name)) return;
    Haptics.instance.tick();
    setState(() => _downloading[f.name] = 0);
    try {
      final where = await FileTransferService.instance.download(
        f,
        onProgress: (p) {
          if (mounted) setState(() => _downloading[f.name] = p);
        },
      );
      if (!mounted) return;
      _saved.add(f.name);
      _toast('Saved to $where');
    } catch (e) {
      if (mounted) _toast('Download failed — $e');
    } finally {
      if (mounted) setState(() => _downloading.remove(f.name));
    }
  }

  Future<void> _pickAndUpload() async {
    Haptics.instance.tick();
    final picked = await FileTransferService.instance.pickLocalFile();
    if (picked == null) return;
    final name = picked.name;
    setState(() {
      _uploadProgress = 0;
      _uploadName = name;
    });
    try {
      final savedAs = await FileTransferService.instance.upload(
        File(picked.path),
        name,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (!mounted) return;
      _sentFromPhone.add(savedAs);
      _toast('Sent — on the PC in Downloads\\TouchPlay as "$savedAs"');
      _refresh();
    } catch (e) {
      if (mounted) _toast('Send failed — $e');
    } finally {
      if (mounted) {
        setState(() {
          _uploadProgress = null;
          _uploadName = null;
        });
      }
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 12.5)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF14161F),
      duration: const Duration(seconds: 3),
    ));
  }

  IconData _iconFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image_outlined;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'webm':
        return Icons.movie_outlined;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'ogg':
        return Icons.music_note_outlined;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_outlined;
      case 'pdf':
      case 'doc':
      case 'docx':
      case 'txt':
        return Icons.description_outlined;
      case 'apk':
      case 'exe':
        return Icons.widgets_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  /// "2 min ago" style label from a unix-seconds mtime.
  static String _ago(int mtime) {
    if (mtime <= 0) return '';
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(mtime * 1000));
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    final d = DateTime.fromMillisecondsSinceEpoch(mtime * 1000);
    return '${d.day}/${d.month}/${d.year}';
  }

  /// Real preview for photos/videos (served by the PC), icon for the rest.
  Widget _thumbFor(PcFile f) {
    final url = FileTransferService.instance.thumbUrl(f);
    if (url == null) {
      return SizedBox(
        width: 42,
        height: 42,
        child: Icon(_iconFor(f.name), color: Colors.white54, size: 22),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 42,
        height: 42,
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(color: Colors.white.withValues(alpha: 0.05)),
          Image.network(
            url,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                Icon(_iconFor(f.name), color: Colors.white54, size: 22),
          ),
          if (f.isVideo)
            const Center(
                child:
                    Icon(Icons.play_circle, color: Colors.white70, size: 18)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AmbientBackground(
        child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _topBar(),
            if (_uploadProgress != null) _uploadBanner(),
            Expanded(child: _body()),
          ],
        ),
        ),
      ),
      floatingActionButton: PillButton(
        label: 'Send file to PC',
        icon: Icons.upload_file,
        busy: _uploadProgress != null,
        onTap: () {
          if (_uploadProgress == null) _pickAndUpload();
        },
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white70, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            const Text('File Transfer',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('PC: Downloads\\TouchPlay',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 10.5)),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
              onPressed: _refresh,
            ),
          ],
        ),
      );

  Widget _uploadBanner() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x1A6FB6FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x556FB6FF)),
          ),
          child: Row(
            children: [
              const Icon(Icons.upload, color: _accent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sending $_uploadName…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: _uploadProgress,
                      minHeight: 3,
                      backgroundColor: Colors.white12,
                      color: _accent,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _accent, strokeWidth: 2));
    }
    if (_error != null) {
      final connected = _conn == ws.ConnectionState.connected;
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 380),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(connected ? Icons.cloud_off : Icons.wifi_off,
                  color: const Color(0xFFFF6B6B), size: 36),
              const SizedBox(height: 12),
              Text(connected ? 'PC didn\'t answer' : 'Not connected to a PC',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                connected
                    ? 'The control link is up but the file service didn\'t '
                        'respond. Restart the TouchPlay server on your PC.'
                    : 'Open the TouchPlay server on your PC. The phone '
                        'connects by itself and this list will load '
                        'automatically.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 14),
              PillButton(label: 'Retry now', width: 160, onTap: _refresh),
            ],
          ),
        ),
      );
    }
    final files = _files ?? const <PcFile>[];
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open,
                color: Colors.white.withValues(alpha: 0.12), size: 44),
            const SizedBox(height: 12),
            const Text(
              'No files on the PC yet.\nDrop files into Downloads\\TouchPlay '
              'on your PC,\nor send one from this phone.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white38, fontSize: 12.5, height: 1.5),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: _accent,
      backgroundColor: const Color(0xFF14161F),
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
        itemCount: files.length,
        separatorBuilder: (_, __) =>
            const Divider(color: Color(0xFF1C1C28), height: 1),
        itemBuilder: (_, i) {
          final f = files[i];
          final progress = _downloading[f.name];
          final sentByMe = _sentFromPhone.contains(f.name);
          final saved = _saved.contains(f.name);

          final Widget action;
          if (progress != null) {
            action = SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  value: progress > 0 ? progress : null,
                  strokeWidth: 2,
                  color: _accent),
            );
          } else if (saved) {
            action = const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, color: Color(0xFF3DDC84), size: 16),
              SizedBox(width: 5),
              Text('On phone',
                  style: TextStyle(color: Color(0xFF3DDC84), fontSize: 10.5)),
            ]);
          } else {
            // Explicit verb instead of a bare icon: this COPIES the PC file
            // onto the phone (into Downloads/TouchPlay).
            action = GestureDetector(
              onTap: () => _download(f),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _accent.withValues(alpha: 0.7)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.download_rounded, color: _accent, size: 15),
                  SizedBox(width: 5),
                  Text('Save to phone',
                      style: TextStyle(color: _accent, fontSize: 10.5)),
                ]),
              ),
            );
          }

          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: _thumbFor(f),
            title: Text(f.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text(
                '${f.sizeLabel} · ${_ago(f.mtime)}'
                '${sentByMe ? ' · sent from this phone' : ''}',
                style: TextStyle(
                    color: sentByMe
                        ? _accent.withValues(alpha: 0.65)
                        : Colors.white38,
                    fontSize: 11)),
            trailing: action,
          );
        },
      ),
    );
  }
}
