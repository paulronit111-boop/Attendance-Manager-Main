import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

Future<void> downloadAndOpenApk(String url) async {
  final uri = Uri.parse(url);

  if (uri.scheme != 'https') {
    throw Exception('The APK download link must use HTTPS.');
  }

  final directory = await getTemporaryDirectory();

  final file = File(
    '${directory.path}/statistics_attendance_update.apk',
  );

  final client = HttpClient();

  try {
    final request = await client.getUrl(uri);
    final response = await request.close();

    if (response.statusCode != 200) {
      throw Exception(
        'APK download failed. HTTP ${response.statusCode}',
      );
    }

    final sink = file.openWrite();

    await response.pipe(sink);

    if (!await file.exists() || await file.length() == 0) {
      throw Exception('The downloaded APK is empty.');
    }

    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );

    if (result.type != ResultType.done) {
      throw Exception(
        'Could not open the APK installer: ${result.message}',
      );
    }
  } finally {
    client.close(force: true);
  }
}