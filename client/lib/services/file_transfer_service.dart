import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'websocket_service.dart';

/// One file in the PC's drop folder (Downloads\TouchPlay).
class PcFile {
  final String name;
  final int size;
  final int mtime; // unix seconds

  PcFile({required this.name, required this.size, required this.mtime});

  factory PcFile.fromJson(Map<String, dynamic> j) => PcFile(
        name: j['name'] as String,
        size: (j['size'] as num).toInt(),
        mtime: (j['mtime'] as num?)?.toInt() ?? 0,
      );

  String get _ext =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';

  bool get isImage =>
      const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(_ext);

  bool get isVideo =>
      const {'mp4', 'mkv', 'avi', 'webm', 'mov'}.contains(_ext);

  String get sizeLabel {
    if (size >= 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (size >= 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '$size B';
  }
}

/// Talks to the PC server's file endpoint (port 8768). Uploads go to the PC's
/// Downloads\TouchPlay folder; downloads are saved into the phone's Downloads
/// via a small platform-channel hop (MediaStore needs native code).
class FileTransferService {
  FileTransferService._();
  static final instance = FileTransferService._();

  static const _port = 8768;
  static const _channel = MethodChannel('touchplay/files');

  String? get _ip => WebSocketService.instance.currentIp;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri(scheme: 'http', host: _ip, port: _port, path: path,
          queryParameters: query);

  bool get hasServer => _ip != null;

  /// Thumbnail URL for an image/video on the PC (served by the file server),
  /// or null when there's no server or the type has no thumbnail.
  String? thumbUrl(PcFile f, {int size = 128}) {
    if (_ip == null || (!f.isImage && !f.isVideo)) return null;
    return _uri('/thumb', {'name': f.name, 's': '$size'}).toString();
  }

  /// Opens the system file picker (native, no extra permissions) and returns
  /// the chosen file copied into the app cache, or null if cancelled.
  Future<({String path, String name})?> pickLocalFile() async {
    final m = await _channel.invokeMapMethod<String, dynamic>('pick_file');
    if (m == null) return null;
    return (path: m['path'] as String, name: m['name'] as String);
  }

  Future<List<PcFile>> listFiles() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.getUrl(_uri('/files'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final list = json.decode(body) as List<dynamic>;
      return [
        for (final e in list) PcFile.fromJson(e as Map<String, dynamic>)
      ];
    } finally {
      client.close();
    }
  }

  /// Downloads [file] from the PC and lands it in the phone's Downloads folder.
  /// Returns a user-readable location string.
  Future<String> download(PcFile file, {void Function(double)? onProgress}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.getUrl(_uri('/download', {'name': file.name}));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('PC said ${res.statusCode}');
      }

      final tmpDir = await getTemporaryDirectory();
      final tmp = File('${tmpDir.path}/${file.name}');
      final sink = tmp.openWrite();
      var received = 0;
      final total = res.contentLength > 0 ? res.contentLength : file.size;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();

      // Native hop → MediaStore Downloads so it shows up in the Files app.
      final saved = await _channel.invokeMethod<String>('save_to_downloads', {
        'path': tmp.path,
        'name': file.name,
      });
      try {
        await tmp.delete();
      } catch (_) {}
      return saved ?? 'Downloads';
    } finally {
      client.close();
    }
  }

  /// Sends a local file to the PC's Downloads\TouchPlay folder.
  /// Returns the name the PC saved it under.
  Future<String> upload(File local, String name,
      {void Function(double)? onProgress}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final total = await local.length();
      final req = await client.postUrl(_uri('/upload', {'name': name}));
      req.headers.contentType = ContentType.binary;
      req.contentLength = total;
      var sent = 0;
      await for (final chunk in local.openRead()) {
        req.add(chunk);
        sent += chunk.length;
        if (total > 0) onProgress?.call(sent / total);
        // Let the socket drain so progress is honest, not buffer-fill speed.
        await req.flush();
      }
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw Exception('PC said ${res.statusCode}');
      }
      final j = json.decode(body) as Map<String, dynamic>;
      return (j['name'] as String?) ?? name;
    } finally {
      client.close();
    }
  }
}
