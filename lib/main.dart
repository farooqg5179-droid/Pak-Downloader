import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const DownloaderHome(),
    );
  }
}

class DownloaderHome extends StatefulWidget {
  const DownloaderHome({super.key});

  @override
  State<DownloaderHome> createState() => _DownloaderHomeState();
}

class _DownloaderHomeState extends State<DownloaderHome> {
  final controller = TextEditingController();
  final dio = Dio();
  double progress = 0;
  bool downloading = false;
  String status = '';

  static const String extractorBaseUrl =
      'https://emkehfwntauhgmdsrcmw.supabase.co/functions/v1/extract';
  static const String supabaseAnonKey =
      'sb_publishable_hrN7MEBF52uf5-nJ6OKDnw_tpclR6Om';

  Future<void> downloadVideo() async {
    final url = controller.text.trim();

    if (url.isEmpty || !Uri.tryParse(url)!.hasScheme) {
      setState(() => status = 'Please enter a valid video URL.');
      return;
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => status = 'URL must start with http:// or https://');
      return;
    }

    final permission = await Permission.storage.request();
    if (!permission.isGranted && Platform.isAndroid) {
      // On newer Android versions app-specific storage is normally enough.
    }

    try {
      setState(() {
        downloading = true;
        progress = 0;
        status = 'Resolving video link...';
      });

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
          downloading = false;
          status = 'Could not resolve a video from this link.';
        });
        return;
      }

      setState(() => status = 'Downloading...');

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

      setState(() => status = 'Saving to gallery...');

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          setState(() {
            downloading = false;
            status =
                'Downloaded, but gallery permission was denied. Enable Photos/Media permission in app settings and try again.';
          });
          return;
        }
      }

      await Gal.putVideo(tempPath, album: 'Pak Downloader');

      setState(() {
        downloading = false;
        progress = 1;
        status = 'Download complete. Saved to your Gallery (Pak Downloader album).';
      });
    } catch (e) {
      setState(() {
        downloading = false;
        status = 'Download failed: ${e.toString()}';
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pak Downloader'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 30),
            const Icon(Icons.download_rounded, size: 72),
            const SizedBox(height: 16),
            const Text(
              'Pak Downloader',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Paste a YouTube, Facebook, Instagram, or TikTok link to download.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'Paste video URL here',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: downloading ? null : downloadVideo,
              icon: const Icon(Icons.download),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Download Video'),
              ),
            ),
            const SizedBox(height: 22),
            if (downloading || progress > 0)
              LinearProgressIndicator(value: progress),
            const SizedBox(height: 12),
            Text(
              status,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
