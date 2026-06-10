import 'dart:io';

import 'package:flutter/material.dart';

import '../services/file_transfer_service.dart';
import '../services/haptics.dart';
import '../services/websocket_service.dart' as ws;

const _accent = Color(0xFF00D4FF);

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

  // name → progress 0..1 for active transfers
  final _downloading = <String, double>{};
  double? _uploadProgress;
  String? _uploadName;

  @override
  void initState() {
    super.initState();
    _refresh();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _topBar(),
            if (_uploadProgress != null) _uploadBanner(),
            Expanded(child: _body()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadProgress == null ? _pickAndUpload : null,
        backgroundColor: _accent,
        foregroundColor: const Color(0xFF06121A),
        icon: const Icon(Icons.upload_file),
        label: const Text('Send file to PC',
            style: TextStyle(fontWeight: FontWeight.w700)),
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
            color: const Color(0x1A00D4FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x5500D4FF)),
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: Colors.white24, size: 40),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _refresh,
              style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _accent)),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    final files = _files ?? const <PcFile>[];
    if (files.isEmpty) {
      return const Center(
        child: Text(
          'No files on the PC yet.\nDrop files into Downloads\\TouchPlay on '
          'your PC,\nor send one from this phone.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 12.5, height: 1.5),
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
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(_iconFor(f.name), color: Colors.white54, size: 22),
            title: Text(f.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text(f.sizeLabel,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: progress != null
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        value: progress > 0 ? progress : null,
                        strokeWidth: 2,
                        color: _accent),
                  )
                : IconButton(
                    icon: const Icon(Icons.download_rounded,
                        color: _accent, size: 22),
                    onPressed: () => _download(f),
                  ),
          );
        },
      ),
    );
  }
}
