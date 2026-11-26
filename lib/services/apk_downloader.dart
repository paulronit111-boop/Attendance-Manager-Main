import 'apk_downloader_stub.dart'
    if (dart.library.io) 'apk_downloader_io.dart' as platform;

Future<void> downloadAndOpenApk(String url) {
  return platform.downloadAndOpenApk(url);
}