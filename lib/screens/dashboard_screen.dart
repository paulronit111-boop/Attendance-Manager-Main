
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../services/apk_downloader.dart';

import 'students_screen.dart';
import 'attendance_screen.dart';
import 'attendance_report_screen.dart';
import 'class_records_screen.dart';

const String updateInfoUrl =
    'https://statistics-attendence.web.app/update/version.json';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _checkingForUpdates = false;

  @override
  void initState() {
    super.initState();

    // Automatically check for updates when dashboard opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  // Logout.
  Future<void> logout(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();

    if (!context.mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/',
      (route) => false,
    );
  }

  // Check for app updates.
  Future<void> _checkForUpdates({bool showStatus = false}) async {
    // APK updates are only supported on Android.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (showStatus && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'APK updates are available only on Android.',
            ),
          ),
        );
      }
      return;
    }

    if (_checkingForUpdates) return;

    setState(() {
      _checkingForUpdates = true;
    });

    try {
      final packageInfo = await PackageInfo.fromPlatform();

      final currentBuild =
          int.tryParse(packageInfo.buildNumber) ?? 0;

      final response = await http
          .get(
            Uri.parse(
              '$updateInfoUrl?t=${DateTime.now().millisecondsSinceEpoch}',
            ),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Could not contact the update server.');
      }

      final Map<String, dynamic> updateInfo =
          jsonDecode(response.body);

      final latestBuild =
          int.tryParse('${updateInfo['build_number']}') ?? 0;

      // No new update available.
      if (latestBuild <= currentBuild) {
        if (showStatus && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your app is already up to date.',
              ),
            ),
          );
        }
        return;
      }

      final latestVersion =
          updateInfo['version']?.toString() ?? 'New version';

      final apkUrl =
          updateInfo['apk_url']?.toString() ?? '';

      final releaseNotes =
          updateInfo['release_notes']?.toString() ??
              'Performance improvements and bug fixes.';

      final forceUpdate =
          updateInfo['force_update'] == true;

      if (apkUrl.isEmpty) {
        throw Exception('The APK download link is missing.');
      }

      if (!mounted) return;

      _showUpdateDialog(
        version: latestVersion,
        apkUrl: apkUrl,
        releaseNotes: releaseNotes,
        forceUpdate: forceUpdate,
      );
    } catch (error) {
      debugPrint('Update check failed: $error');

      if (showStatus && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not check for updates: $error',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _checkingForUpdates = false;
        });
      }
    }
  }

  // Display update dialog.
  void _showUpdateDialog({
    required String version,
    required String apkUrl,
    required String releaseNotes,
    required bool forceUpdate,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (dialogContext) {
        bool downloading = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(
                    Icons.system_update,
                    color: Colors.indigo,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('New update available'),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Version $version is available.',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(releaseNotes),
                  if (downloading) ...[
                    const SizedBox(height: 20),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('Downloading update...'),
                  ],
                ],
              ),
              actions: [
                if (!forceUpdate)
                  TextButton(
                    onPressed: downloading
                        ? null
                        : () {
                            Navigator.pop(dialogContext);
                          },
                    child: const Text('Later'),
                  ),
                FilledButton(
                  onPressed: downloading
                      ? null
                      : () async {
                          setDialogState(() {
                            downloading = true;
                          });

                          try {
                            await downloadAndOpenApk(apkUrl);

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (error) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                downloading = false;
                              });

                              ScaffoldMessenger.of(dialogContext)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Update failed: $error',
                                  ),
                                  duration: const Duration(seconds: 6),
                                ),
                              );
                            }
                          }
                        },
                  child: downloading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Update now'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics Department'),
        actions: [
          // Manual Check for Updates button.
          IconButton(
            tooltip: 'Check for Updates',
            onPressed: _checkingForUpdates
                ? null
                : () => _checkForUpdates(showStatus: true),
            icon: _checkingForUpdates
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.system_update),
          ),

          // Logout button.
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () => logout(context),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              children: [
                const Icon(
                  Icons.school,
                  size: 75,
                  color: Colors.indigo,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Gurucharan University, Silchar',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Statistics Department',
                  style: TextStyle(fontSize: 17),
                ),
                const SizedBox(height: 35),

                // Manage Students.
                dashboardCard(
                  context,
                  title: 'Manage Students',
                  subtitle: 'Add, edit, view and delete students',
                  icon: Icons.people,
                  color: Colors.blue,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StudentsScreen(),
                      ),
                    );
                  },
                ),

                // Mark Attendance.
                dashboardCard(
                  context,
                  title: 'Mark Attendance',
                  subtitle: 'Record daily class attendance',
                  icon: Icons.fact_check,
                  color: Colors.green,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AttendanceScreen(),
                      ),
                    );
                  },
                ),

                // Attendance Reports.
                dashboardCard(
                  context,
                  title: 'Attendance Reports',
                  subtitle: 'View attendance and generate reports',
                  icon: Icons.bar_chart,
                  color: Colors.orange,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const AttendanceReportScreen(),
                      ),
                    );
                  },
                ),

                // Class Records.
                dashboardCard(
                  context,
                  title: 'Class Records',
                  subtitle:
                      'View and delete records semester-wise and paper-wise',
                  icon: Icons.history,
                  color: Colors.purple,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ClassRecordsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Reusable dashboard card.
  Widget dashboardCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: CircleAvatar(
          radius: 27,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            icon,
            color: color,
            size: 28,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 17,
        ),
        onTap: onTap,
      ),
    );
  }
}
