import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/supabase.dart';

/// Private storage. Files are never public: we hand out 1-hour signed URLs
/// and cache them in memory so lists don't re-sign on every rebuild.
class MediaRepo {
  MediaRepo._();
  static final instance = MediaRepo._();

  static const _uuid = Uuid();
  final _cache = <String, (String url, DateTime expires)>{};
  final _inflight = <String, Future<String>>{};

  /// Synchronous peek so widgets can render immediately without a loading flash.
  String? cachedUrl(String path, {String bucket = 'circle-media'}) {
    final cached = _cache['$bucket/$path'];
    return cached != null && cached.$2.isAfter(DateTime.now()) ? cached.$1 : null;
  }

  Future<String> signedUrl(String path, {String bucket = 'circle-media'}) {
    final key = '$bucket/$path';
    final cached = _cache[key];
    if (cached != null && cached.$2.isAfter(DateTime.now())) return Future.value(cached.$1);
    return _inflight[key] ??= sb.storage.from(bucket).createSignedUrl(path, 3600).then((url) {
      _cache[key] = (url, DateTime.now().add(const Duration(minutes: 55)));
      return url;
    }).whenComplete(() => _inflight.remove(key));
  }

  /// Pick + compress photos (image_picker re-encodes with max size/quality → small uploads on mobile data).
  Future<List<XFile>> pickPhotos({bool multiple = true, ImageSource source = ImageSource.gallery}) async {
    final picker = ImagePicker();
    if (multiple && source == ImageSource.gallery) {
      return picker.pickMultiImage(maxWidth: 2048, maxHeight: 2048, imageQuality: 82, limit: 10);
    }
    final one = await picker.pickImage(source: source, maxWidth: 2048, maxHeight: 2048, imageQuality: 82);
    return one == null ? const [] : [one];
  }

  String _ext(String name, String fallback) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return fallback;
    final e = name.substring(dot + 1).toLowerCase();
    return e.length <= 5 ? e : fallback;
  }

  String _mimeFor(String ext) => switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'heic' => 'image/heic',
        'm4a' => 'audio/m4a',
        'aac' => 'audio/aac',
        'mp3' => 'audio/mpeg',
        'webm' => 'audio/webm',
        'ogg' => 'audio/ogg',
        'mp4' => 'video/mp4',
        _ => 'image/jpeg',
      };

  /// Uploads into {circleId}/{folder}/{uuid}.{ext} and registers it in `media`.
  Future<String> uploadToCircle({
    required String circleId,
    required String folder,
    required Uint8List bytes,
    required String filename,
    String? mime,
    int? durationMs,
  }) async {
    final ext = _ext(filename, 'jpg');
    final contentType = mime ?? _mimeFor(ext);
    final path = '$circleId/$folder/${_uuid.v4()}.$ext';
    await sb.storage.from('circle-media').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false, cacheControl: '31536000'),
        );
    await sb.from('media').insert({
      'circle_id': circleId,
      'uploader_id': requireUserId(),
      'path': path,
      'mime': contentType,
      'bytes': bytes.length,
      'duration_ms': durationMs,
    });
    return path;
  }

  Future<List<String>> uploadPhotos(String circleId, String folder, List<XFile> files) async {
    final paths = <String>[];
    for (final f in files) {
      paths.add(await uploadToCircle(circleId: circleId, folder: folder, bytes: await f.readAsBytes(), filename: f.name));
    }
    return paths;
  }

  Future<String> uploadAvatar(XFile file) async {
    final uid = requireUserId();
    final ext = _ext(file.name, 'jpg');
    final path = '$uid/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await sb.storage.from('avatars').uploadBinary(
          path,
          await file.readAsBytes(),
          fileOptions: FileOptions(contentType: _mimeFor(ext), upsert: true),
        );
    return path;
  }

  Future<String> uploadCompetitionPhoto(String entryId, XFile file) async {
    final ext = _ext(file.name, 'jpg');
    final path = '$entryId/${_uuid.v4()}.$ext';
    await sb.storage.from('competition').uploadBinary(
          path,
          await file.readAsBytes(),
          fileOptions: FileOptions(contentType: _mimeFor(ext)),
        );
    return path;
  }
}
