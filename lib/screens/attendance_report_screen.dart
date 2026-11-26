import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';

import '../config/supabase_config.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  final supabase = SupabaseConfig.client;

  final List<String> semesters = [
    '2nd Semester',
    '4th Semester',
    '6th Semester',
  ];

  final List<String> groups = ['DSC', 'DSM'];

  String? selectedSemester;
  String? selectedGroup;
  String? selectedSubjectId;

  DateTime startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime endDate = DateTime.now();

  List<Map<String, dynamic>> subjects = [];
  List<Map<String, dynamic>> reportData = [];
  List<Map<String, dynamic>> monthlyData = [];

  bool loading = false;
  bool subjectsLoading = false;
  bool reportLoaded = false;

  String get ownerId => supabase.auth.currentUser!.id;

  // Checkbox-style option with single selection.
  Widget optionTile({
    required String title,
    required bool selected,
    required ValueChanged<bool?> onChanged,
  }) {
    return CheckboxListTile(
      title: Text(title),
      value: selected,
      onChanged: onChanged,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  // Load subjects according to semester and group.
  Future<void> loadSubjects() async {
    if (selectedSemester == null || selectedGroup == null) {
      return;
    }

    setState(() {
      subjectsLoading = true;
      selectedSubjectId = null;
      subjects = [];
      reportData = [];
      monthlyData = [];
      reportLoaded = false;
    });

    try {
      final result = await supabase
          .from('subjects')
          .select()
          .eq('owner_id', ownerId)
          .eq('semester', selectedSemester!)
          .eq('student_group', selectedGroup!)
          .order('code');

      if (!mounted) return;

      setState(() {
        subjects = List<Map<String, dynamic>>.from(result);
        subjectsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        subjectsLoading = false;
      });

      showMessage('Unable to load subjects: $e');
    }
  }

  // Select date range.
  Future<void> chooseDate(bool isStart) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: isStart ? startDate : endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (selected == null || !mounted) return;

    setState(() {
      if (isStart) {
        startDate = selected;

        if (endDate.isBefore(startDate)) {
          endDate = startDate;
        }
      } else {
        endDate = selected;

        if (startDate.isAfter(endDate)) {
          startDate = endDate;
        }
      }

      reportLoaded = false;
    });
  }

  // Generate report for the selected subject only.
  Future<void> generateReport() async {
    if (selectedSemester == null ||
        selectedGroup == null ||
        selectedSubjectId == null) {
      showMessage('Please select semester, group and subject.');
      return;
    }

    if (startDate.isAfter(endDate)) {
      showMessage('Start date cannot be after end date.');
      return;
    }

    setState(() {
      loading = true;
      reportLoaded = false;
      reportData = [];
      monthlyData = [];
    });

    try {
      // STEP 1: Get students for selected semester and group.
      final studentResult = await supabase
          .from('students')
          .select()
          .eq('owner_id', ownerId)
          .eq('semester', selectedSemester!)
          .eq('student_group', selectedGroup!)
          .order('roll_no');

      final students = List<Map<String, dynamic>>.from(studentResult);

      final Map<String, Map<String, dynamic>> studentStats = {};

      for (final student in students) {
        final id = student['id'].toString();

        studentStats[id] = {
          'student_id': id,
          'roll_no': student['roll_no'] ?? '',
          'name': student['name'] ?? '',
          'present': 0,
          'absent': 0,
          'late': 0,
          'total': 0,
          'percentage': 0.0,
        };
      }

      // STEP 2: Get class sessions for this exact subject.
      final sessionResult = await supabase
          .from('class_sessions')
          .select('id')
          .eq('owner_id', ownerId)
          .eq('semester', selectedSemester!)
          .eq('subject_id', selectedSubjectId!)
          .gte('class_date', DateFormat('yyyy-MM-dd').format(startDate))
          .lte('class_date', DateFormat('yyyy-MM-dd').format(endDate));

      final sessions = List<Map<String, dynamic>>.from(sessionResult);

      final sessionIds = sessions
          .map((session) => session['id'].toString())
          .toList();

      // STEP 3: Get attendance only for those session IDs.
      List<Map<String, dynamic>> attendanceRecords = [];

      if (sessionIds.isNotEmpty) {
        final attendanceResult = await supabase
            .from('attendance')
            .select(
              'student_id, status, attendance_date, subject_id, session_id',
            )
            .eq('owner_id', ownerId)
            .eq('subject_id', selectedSubjectId!)
            .inFilter('session_id', sessionIds)
            .gte('attendance_date', DateFormat('yyyy-MM-dd').format(startDate))
            .lte('attendance_date', DateFormat('yyyy-MM-dd').format(endDate));

        attendanceRecords = List<Map<String, dynamic>>.from(attendanceResult);
      }

      // STEP 4: Calculate student-wise and monthly attendance.
      final Set<String> studentIds = studentStats.keys.toSet();

      final Map<String, Map<String, dynamic>> monthly = {};

      for (final record in attendanceRecords) {
        final studentId = record['student_id'].toString();

        if (!studentIds.contains(studentId)) continue;

        final status = record['status'].toString();

        final stats = studentStats[studentId]!;

        stats['total'] = (stats['total'] as int) + 1;

        if (status == 'Present') {
          stats['present'] = (stats['present'] as int) + 1;
        } else if (status == 'Absent') {
          stats['absent'] = (stats['absent'] as int) + 1;
        } else if (status == 'Late') {
          stats['late'] = (stats['late'] as int) + 1;
        }

        final total = stats['total'] as int;
        final attended = (stats['present'] as int) + (stats['late'] as int);

        stats['percentage'] = total == 0 ? 0.0 : attended * 100 / total;

        final date = DateTime.parse(record['attendance_date'].toString());

        final monthKey = DateFormat('yyyy-MM').format(date);
        final monthLabel = DateFormat('MMMM yyyy').format(date);

        monthly.putIfAbsent(
          monthKey,
          () => {
            'month': monthLabel,
            'present': 0,
            'absent': 0,
            'late': 0,
            'total': 0,
          },
        );

        monthly[monthKey]!['total'] = (monthly[monthKey]!['total'] as int) + 1;

        if (status == 'Present') {
          monthly[monthKey]!['present'] =
              (monthly[monthKey]!['present'] as int) + 1;
        } else if (status == 'Absent') {
          monthly[monthKey]!['absent'] =
              (monthly[monthKey]!['absent'] as int) + 1;
        } else if (status == 'Late') {
          monthly[monthKey]!['late'] = (monthly[monthKey]!['late'] as int) + 1;
        }
      }

      final result = studentStats.values.toList();

      final monthlyResult = monthly.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));

      if (!mounted) return;

      setState(() {
        reportData = result;
        monthlyData = monthlyResult.map((entry) => entry.value).toList();
        loading = false;
        reportLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      showMessage('Error generating report: $e');
    }
  }

  // Export report to Excel.
  Future<void> exportExcel() async {
    if (!reportLoaded || reportData.isEmpty) {
      showMessage('No student data available to export.');
      return;
    }

    try {
      final excel = Excel.createExcel();

      final sheet = excel['Attendance Report'];

      sheet.appendRow([
        TextCellValue('Roll No'),
        TextCellValue('Student Name'),
        TextCellValue('Present'),
        TextCellValue('Absent'),
        TextCellValue('Late'),
        TextCellValue('Total Classes'),
        TextCellValue('Attendance %'),
      ]);

      for (final student in reportData) {
        sheet.appendRow([
          TextCellValue(student['roll_no'].toString()),
          TextCellValue(student['name'].toString()),
          IntCellValue(student['present'] as int),
          IntCellValue(student['absent'] as int),
          IntCellValue(student['late'] as int),
          IntCellValue(student['total'] as int),
          DoubleCellValue((student['percentage'] as num).toDouble()),
        ]);
      }

      final monthlySheet = excel['Monthly Summary'];

      monthlySheet.appendRow([
        TextCellValue('Month'),
        TextCellValue('Present'),
        TextCellValue('Absent'),
        TextCellValue('Late'),
        TextCellValue('Total Entries'),
      ]);

      for (final month in monthlyData) {
        monthlySheet.appendRow([
          TextCellValue(month['month'].toString()),
          IntCellValue(month['present'] as int),
          IntCellValue(month['absent'] as int),
          IntCellValue(month['late'] as int),
          IntCellValue(month['total'] as int),
        ]);
      }

      excel.delete('Sheet1');

      final fileName =
          'Attendance_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';

      excel.save(fileName: fileName);

      showMessage('Excel report exported.');
    } catch (e) {
      showMessage('Excel export failed: $e');
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  int get totalPresent =>
      reportData.fold(0, (sum, item) => sum + (item['present'] as int));

  int get totalAbsent =>
      reportData.fold(0, (sum, item) => sum + (item['absent'] as int));

  int get totalLate =>
      reportData.fold(0, (sum, item) => sum + (item['late'] as int));

  int get totalEntries =>
      reportData.fold(0, (sum, item) => sum + (item['total'] as int));

  Widget summaryCard(String title, int value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 8),
            Text(
              value.toString(),
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
            ),
            Text(title),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Reports'),
        actions: [
          IconButton(
            tooltip: 'Export Excel',
            icon: const Icon(Icons.download),
            onPressed: reportLoaded ? exportExcel : null,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Report Filters',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            // SEMESTER: single selection.
            const Text(
              'Semester',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),

            ...semesters.map((semester) {
              return optionTile(
                title: semester,
                selected: selectedSemester == semester,
                onChanged: (checked) {
                  if (checked == true) {
                    setState(() {
                      selectedSemester = semester;
                      selectedSubjectId = null;
                      subjects = [];
                      reportLoaded = false;
                      reportData = [];
                      monthlyData = [];
                    });

                    loadSubjects();
                  }
                },
              );
            }),

            const Divider(),

            // STUDENT GROUP: single selection.
            const Text(
              'Student Group',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),

            ...groups.map((group) {
              return optionTile(
                title: group,
                selected: selectedGroup == group,
                onChanged: (checked) {
                  if (checked == true) {
                    setState(() {
                      selectedGroup = group;
                      selectedSubjectId = null;
                      subjects = [];
                      reportLoaded = false;
                      reportData = [];
                      monthlyData = [];
                    });

                    loadSubjects();
                  }
                },
              );
            }),

            const Divider(),

            // SUBJECT: single selection.
            const Text(
              'Subject',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),

            if (subjectsLoading) const LinearProgressIndicator(),

            if (!subjectsLoading &&
                selectedSemester != null &&
                selectedGroup != null)
              ...subjects.map((subject) {
                final subjectId = subject['id'].toString();

                return optionTile(
                  title: subject['code'].toString(),
                  selected: selectedSubjectId == subjectId,
                  onChanged: (checked) {
                    if (checked == true) {
                      setState(() {
                        selectedSubjectId = subjectId;
                        reportLoaded = false;
                        reportData = [];
                        monthlyData = [];
                      });
                    }
                  },
                );
              }),

            if (selectedSemester == null || selectedGroup == null)
              const Text('Select semester and student group first.'),

            const SizedBox(height: 18),

            const Text(
              'Date Range',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => chooseDate(true),
                    child: Text(
                      'From: ${DateFormat('dd-MM-yyyy').format(startDate)}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => chooseDate(false),
                    child: Text(
                      'To: ${DateFormat('dd-MM-yyyy').format(endDate)}',
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: loading ? null : generateReport,
                icon: const Icon(Icons.analytics),
                label: Text(loading ? 'Generating...' : 'Generate Report'),
              ),
            ),

            if (loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),

            if (reportLoaded) ...[
              const SizedBox(height: 24),

              const Text(
                'Attendance Summary',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.8,
                children: [
                  summaryCard(
                    'Present',
                    totalPresent,
                    Icons.check_circle_outline,
                  ),
                  summaryCard('Absent', totalAbsent, Icons.cancel_outlined),
                  summaryCard('Late', totalLate, Icons.schedule),
                  summaryCard(
                    'Total Entries',
                    totalEntries,
                    Icons.people_outline,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Student-wise Report',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  Text('${reportData.length} students'),
                ],
              ),

              const SizedBox(height: 10),

              if (reportData.isEmpty)
                const Text('No students found for this selection.')
              else
                ...reportData.map((student) {
                  final percentage = (student['percentage'] as num).toDouble();

                  final lowAttendance = percentage < 75;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${student['roll_no']} - ${student['name']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Wrap(
                            spacing: 14,
                            runSpacing: 6,
                            children: [
                              Text('Present: ${student['present']}'),
                              Text('Absent: ${student['absent']}'),
                              Text('Late: ${student['late']}'),
                              Text('Total: ${student['total']}'),
                            ],
                          ),

                          const SizedBox(height: 8),

                          LinearProgressIndicator(
                            value: (percentage / 100).clamp(0.0, 1.0),
                          ),

                          const SizedBox(height: 5),

                          Row(
                            children: [
                              Text(
                                '${percentage.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: lowAttendance
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (lowAttendance)
                                const Text(
                                  'Below 75% attendance',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 24),

              const Text(
                'Monthly Summary',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              if (monthlyData.isEmpty)
                const Text('No monthly attendance records.')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Month')),
                      DataColumn(label: Text('Present')),
                      DataColumn(label: Text('Absent')),
                      DataColumn(label: Text('Late')),
                      DataColumn(label: Text('Total')),
                    ],
                    rows: monthlyData.map((month) {
                      return DataRow(
                        cells: [
                          DataCell(Text(month['month'].toString())),
                          DataCell(Text(month['present'].toString())),
                          DataCell(Text(month['absent'].toString())),
                          DataCell(Text(month['late'].toString())),
                          DataCell(Text(month['total'].toString())),
                        ],
                      );
                    }).toList(),
                  ),
                ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: exportExcel,
                  icon: const Icon(Icons.file_download),
                  label: const Text('Export to Excel'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
