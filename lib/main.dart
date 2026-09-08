import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const PakDownloaderApp());
}

class PakDownloaderApp extends StatelessWidget {
  const PakDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pak Downloader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B1210),
      ),
      home: const DownloaderHome(),
    );
  }
}

enum Platform_ { tiktok, instagram, facebook, youtube, unknown }

enum FlowState { idle, ready, working, success, error }

class DownloaderHome extends StatefulWidget {
  const DownloaderHome({super.key});

  @override
  State<DownloaderHome> createState() => _DownloaderHomeState();
}

class _DownloaderHomeState extends State<DownloaderHome>
    with SingleTickerProviderStateMixin {
  final dio = Dio();

  static const String extractorBaseUrl =
      'https://emkehfwntauhgmdsrcmw.supabase.co/functions/v1/extract';
  static const String supabaseAnonKey =
      'sb_publishable_hrN7MEBF52uf5-nJ6OKDnw_tpclR6Om';

  FlowState flowState = FlowState.idle;
  Platform_ detectedPlatform = Platform_.unknown;
  String? clipboardUrl;
  double progress = 0;
  String message = '';
  bool showManualInput = false;
  final manualController = TextEditingController();

  late final AnimationController pulseController;

  @override
  void initState() {
    super.initState();
    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    checkClipboard();
  }

  @override
  void dispose() {
    pulseController.dispose();
    manualController.dispose();
    super.dispose();
  }

  Platform_ detectPlatform(String url) {
    final u = url.toLowerCase();
    if (u.contains('tiktok.com')) return Platform_.tiktok;
    if (u.contains('instagram.com')) return Platform_.instagram;
    if (u.contains('facebook.com') || u.contains('fb.watch')) {
      return Platform_.facebook;
    }
    if (u.contains('youtube.com') || u.contains('youtu.be')) {
      return Platform_.youtube;
    }
    return Platform_.unknown;
  }

  bool looksLikeVideoLink(String text) {
    final t = text.trim().toLowerCase();
    if (!t.startsWith('http://') && !t.startsWith('https://')) return false;
    return t.contains('tiktok.com') ||
        t.contains('instagram.com') ||
        t.contains('facebook.com') ||
        t.contains('fb.watch') ||
        t.contains('youtube.com') ||
        t.contains('youtu.be');
  }

  Future<void> checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (looksLikeVideoLink(text)) {
        setState(() {
          clipboardUrl = text;
          detectedPlatform = detectPlatform(text);
          flowState = FlowState.ready;
        });
      } else {
        setState(() {
          clipboardUrl = null;
          flowState = FlowState.idle;
        });
      }
    } catch (_) {
      // Clipboard access can fail silently; user can still paste manually.
    }
  }

  String platformName(Platform_ p) {
    switch (p) {
      case Platform_.tiktok:
        return 'TikTok';
      case Platform_.instagram:
        return 'Instagram';
      case Platform_.facebook:
        return 'Facebook';
      case Platform_.youtube:
        return 'YouTube';
      case Platform_.unknown:
        return 'Video';
    }
  }

  IconData platformIcon(Platform_ p) {
    switch (p) {
      case Platform_.tiktok:
        return Icons.music_note_rounded;
      case Platform_.instagram:
        return Icons.camera_alt_rounded;
      case Platform_.facebook:
        return Icons.facebook_rounded;
      case Platform_.youtube:
        return Icons.smart_display_rounded;
      case Platform_.unknown:
        return Icons.link_rounded;
    }
  }

  Color platformColor(Platform_ p) {
    switch (p) {
      case Platform_.tiktok:
        return const Color(0xFF25F4EE);
      case Platform_.instagram:
        return const Color(0xFFE1306C);
      case Platform_.facebook:
        return const Color(0xFF1877F2);
      case Platform_.youtube:
        return const Color(0xFFFF0000);
      case Platform_.unknown:
        return const Color(0xFF10B981);
    }
  }

  Future<void> startDownload() async {
    final url = clipboardUrl ?? manualController.text.trim();
    if (url.isEmpty || !looksLikeVideoLink(url)) {
      setState(() {
        flowState = FlowState.error;
        message = 'No valid video link found. Copy a link and try again.';
      });
      return;
    }

    setState(() {
      flowState = FlowState.working;
      progress = 0;
      message = 'Resolving video...';
    });

    try {
      final extractResponse = await dio.get(
        extractorBaseUrl,
        queryParameters: {'url': url},
        options: Options(headers: {
          'Authorization': 'Bearer $supabaseAnonKey',
          'apikey': supabaseAnonKey,
        }),
      );

      final directUrl = extractResponse.data['video_url'] as String?;
      if (directUrl == null || directUrl.isEmpty) {
        setState(() {
          flowState = FlowState.error;
          message = 'Could not resolve a video from this link.';
        });
        return;
      }

      setState(() => message = 'Downloading...');

      final dir = await getTemporaryDirectory();
      final fileName =
          'pak_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final tempPath = '${dir.path}/$fileName';

      await dio.download(
        directUrl,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            setState(() => progress = received / total);
          }
        },
      );

      setState(() => message = 'Saving to gallery...');

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          setState(() {
            flowState = FlowState.error;
            message = 'Gallery permission denied. Enable it in app settings.';
          });
          return;
        }
      }

      await Gal.putVideo(tempPath, album: 'Pak Downloader');

      setState(() {
        flowState = FlowState.success;
        progress = 1;
        message = 'Saved to Gallery';
      });

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          flowState = FlowState.idle;
          clipboardUrl = null;
          progress = 0;
          message = '';
        });
        checkClipboard();
      }
    } catch (e) {
      setState(() {
        flowState = FlowState.error;
        message = 'Download failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = flowState == FlowState.ready || flowState == FlowState.working
        ? platformColor(detectedPlatform)
        : const Color(0xFF10B981);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.4),
            radius: 1.2,
            colors: [
              accent.withOpacity(0.18),
              const Color(0xFF0B1210),
            ],
          ),
        ),
        child: SafeArea(
          child: GestureDetector(
            onTap: () async {
              if (flowState == FlowState.idle || flowState == FlowState.error) {
                await checkClipboard();
              }
            },
            behavior: HitTestBehavior.translucent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pak Downloader',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() => showManualInput = !showManualInput);
                        },
                        icon: Icon(
                          Icons.edit_note_rounded,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(flex: 2),
                  _buildCenterContent(accent),
                  const Spacer(flex: 3),
                  if (showManualInput) _buildManualInput(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterContent(Color accent) {
    switch (flowState) {
      case FlowState.idle:
        return Column(
          key: const ValueKey('idle'),
          children: [
            Icon(Icons.content_paste_search_rounded,
                size: 56, color: Colors.white.withOpacity(0.25)),
            const SizedBox(height: 18),
            Text(
              'Copy a video link',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'TikTok · Instagram · Facebook · YouTube',
              style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 32),
            TextButton.icon(
              onPressed: checkClipboard,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Check clipboard'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        );

      case FlowState.ready:
        return Column(
          key: const ValueKey('ready'),
          children: [
            _pulsingButton(accent, onTap: startDownload),
            const SizedBox(height: 28),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(platformIcon(detectedPlatform), size: 16, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    '${platformName(detectedPlatform)} video ready',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Tap to download',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 13,
              ),
            ),
          ],
        );

      case FlowState.working:
        return Column(
          key: const ValueKey('working'),
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      strokeWidth: 4,
                      color: accent,
                      backgroundColor: Colors.white.withOpacity(0.08),
                    ),
                  ),
                  Icon(Icons.download_rounded, size: 44, color: accent),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );

      case FlowState.success:
        return Column(
          key: const ValueKey('success'),
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981).withOpacity(0.15),
              ),
              child: const Icon(Icons.check_rounded,
                  size: 52, color: Color(0xFF10B981)),
            ),
            const SizedBox(height: 20),
            const Text(
              'Saved to Gallery',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

      case FlowState.error:
        return Column(
          key: const ValueKey('error'),
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.redAccent.withOpacity(0.12),
              ),
              child: const Icon(Icons.close_rounded,
                  size: 48, color: Colors.redAccent),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: checkClipboard,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        );
    }
  }

  Widget _pulsingButton(Color accent, {required VoidCallback onTap}) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, child) {
        final scale = 1.0 + (pulseController.value * 0.06);
        return Transform.scale(scale: scale, child: child);
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [accent.withOpacity(0.9), accent.withOpacity(0.6)],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.4),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(Icons.download_rounded,
              size: 52, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildManualInput() {
    return Column(
      children: [
        TextField(
          controller: manualController,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'Or paste a link manually',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white70),
              onPressed: () {
                final text = manualController.text.trim();
                if (looksLikeVideoLink(text)) {
                  setState(() {
                    clipboardUrl = text;
                    detectedPlatform = detectPlatform(text);
                    flowState = FlowState.ready;
                    showManualInput = false;
                  });
                } else {
                  setState(() {
                    flowState = FlowState.error;
                    message = 'That doesn\'t look like a valid video link.';
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
