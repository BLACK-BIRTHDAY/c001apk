import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../utils/live_photo_util.dart';

/// 实况图视频播放覆盖层。
///
/// 先用封面地址解析出视频地址（带时效签名），再用内嵌 WebView 播放 mp4，
/// 从而复用现有 `flutter_inappwebview` 依赖，无需引入视频播放器。
class LivePhotoPlayer extends StatefulWidget {
  const LivePhotoPlayer({
    super.key,
    required this.sourceUrl,
    required this.coverUrl,
    required this.onClose,
  });

  /// 实况图封面地址，用于解析视频。
  final String sourceUrl;

  /// 视频加载期间的静态封面。
  final String coverUrl;

  final VoidCallback onClose;

  @override
  State<LivePhotoPlayer> createState() => _LivePhotoPlayerState();
}

class _LivePhotoPlayerState extends State<LivePhotoPlayer> {
  late final Future<String?> _videoUrl;

  @override
  void initState() {
    super.initState();
    _videoUrl = LivePhotoUtil.resolveVideoUrl(widget.sourceUrl);
  }

  @override
  Widget build(BuildContext context) {
    // opaque 让整层吞掉点击，避免穿透到下方的 PhotoView 触发退出。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: FutureBuilder<String?>(
                future: _videoUrl,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return _loading();
                  }
                  final String? url = snapshot.data;
                  if (url == null || url.isEmpty) {
                    // 解析失败时兜底显示静态封面，不阻断浏览。
                    return CachedNetworkImage(
                      imageUrl: widget.coverUrl,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      errorWidget: (_, __, ___) => Center(
                        child: Text(
                          '实况视频解析失败',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  }
                  return _WebVideoPlayer(
                    videoUrl: url,
                    posterUrl: widget.coverUrl,
                  );
                },
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loading() {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _WebVideoPlayer extends StatelessWidget {
  const _WebVideoPlayer({required this.videoUrl, required this.posterUrl});

  final String videoUrl;
  final String posterUrl;

  @override
  Widget build(BuildContext context) {
    // 签名后的视频地址 query 中含 `&`，需转义为 `&amp;` 才能安全写入 HTML 属性。
    final String src = _escapeAttr(videoUrl);
    final String poster = _escapeAttr(posterUrl);
    final String html = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
  html, body { margin: 0; padding: 0; height: 100%; background: #000; overflow: hidden; }
  video { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);
          width: 100%; height: 100%; object-fit: contain; background: #000; }
</style>
</head>
<body>
<video src="$src" poster="$poster" controls autoplay loop
       playsinline webkit-playsinline preload="auto"></video>
</body>
</html>''';

    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: html,
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptEnabled: true,
        disableContextMenu: true,
      ),
    );
  }

  static String _escapeAttr(String value) {
    return value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
  }
}
