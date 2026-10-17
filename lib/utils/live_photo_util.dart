import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import 'dart:convert';

import '../constants/constants.dart';
import '../logic/network/api.dart';
import '../logic/network/network_repo.dart';

/// 酷安实况图（Live Photo）工具。
///
/// 后端把实况图拆成「静态封面 + 独立视频」两部分：封面的路径中含 `livepic`
/// 且以 `@<宽>x<高>.<扩展名>` 结尾；视频需用封面地址调用
/// `/v6/livePhoto/showVideo` 解析，接口返回 302，`Location` 即带时效签名的
/// mp4 地址。
class LivePhotoUtil {
  LivePhotoUtil._();

  /// 实况图封面判定规则，与酷安官方保持一致。
  static final RegExp _regExp = RegExp(
    r'https?://\S+livepic\S*@\d+x\d+\.(?:jpg|jpeg|png|gif|webp)(?:[?#].*)?$',
    caseSensitive: false,
  );

  static bool isLivePhoto(String? url) {
    if (url == null) return false;
    final String trimmed = url.trim();
    return trimmed.isNotEmpty && _regExp.hasMatch(trimmed);
  }

  /// 缩略图地址：实况图封面本身即原图，追加 `.s.jpg` 会得到无效地址。
  static String thumbnailUrl(String url) {
    return isLivePhoto(url) ? url : '$url${Constants.SUFFIX_THUMBNAIL}';
  }

  /// 解析实况视频地址，失败返回 null。
  ///
  /// 返回地址带时效签名，故不做长期缓存，只合并同一封面的并发请求。
  static final Map<String, Future<String?>> _pending = {};

  static Future<String?> resolveVideoUrl(String sourceUrl) {
    if (!isLivePhoto(sourceUrl)) return Future<String?>.value();
    final Future<String?>? running = _pending[sourceUrl];
    if (running != null) return running;
    final Future<String?> task = _resolve(sourceUrl).whenComplete(() {
      _pending.remove(sourceUrl);
    });
    _pending[sourceUrl] = task;
    return task;
  }

  static Future<String?> _resolve(String sourceUrl) async {
    try {
      final Response<dynamic> res =
          await NetworkRepo.getLivePhotoVideoUrl(sourceUrl);
      final String? location = res.headers.value('location');
      if (location != null && location.trim().isNotEmpty) {
        return _toHttps(_absoluteUrl(location.trim()));
      }
      final String? fromBody = _extractUrl(res.data);
      if (fromBody != null) {
        return _toHttps(_absoluteUrl(fromBody));
      }
    } catch (e) {
      debugPrint('[livePhoto] 解析实况视频失败: $e');
    }
    return null;
  }

  /// 兼容 302 之外的 JSON 形态：`url` / `data.url` / `data.urlList` 等。
  static String? _extractUrl(dynamic data) {
    if (data is String) {
      final String raw = data.trim();
      if (raw.startsWith('{') || raw.startsWith('[')) {
        try {
          return _extractUrl(jsonDecode(raw));
        } catch (_) {}
      }
      return _looksLikeUrl(raw) ? raw : null;
    }
    if (data is List) {
      for (final dynamic item in data) {
        final String? hit = _extractUrl(item);
        if (hit != null) return hit;
      }
      return null;
    }
    if (data is Map) {
      for (final String key in const [
        'url',
        'videoUrl',
        'video_url',
        'finalUrl',
        'final_url',
      ]) {
        final dynamic value = data[key];
        if (value is String && _looksLikeUrl(value.trim())) return value.trim();
      }
      for (final String key in const ['data', 'urlList', 'url_list']) {
        final String? hit = _extractUrl(data[key]);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  static bool _looksLikeUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  /// 把可能为相对路径的 `Location` 还原为绝对地址。
  static String _absoluteUrl(String url) {
    if (_looksLikeUrl(url)) return url;
    return Uri.parse(Api.livePhotoShowVideo).resolve(url).toString();
  }

  /// 酷安视频 CDN 支持 https，改写后同时规避混合内容与 iOS ATS 限制。
  static String _toHttps(String url) {
    if (!url.startsWith('http://')) return url;
    return 'https://${url.substring('http://'.length)}';
  }
}
