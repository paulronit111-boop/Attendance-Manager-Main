
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../config/supabase_config.dart';

class ClassRecordsScreen extends StatefulWidget {
  const ClassRecordsScreen({super.key});

  @override
  State<ClassRecordsScreen> createState() =>
      _ClassRecordsScreenState();
}

class _ClassRecordsScreenState extends State<ClassRecordsScreen> {
  final supabase = SupabaseConfig.client;

  final teachers = ['SC', 'SG', 'MHB', 'BB', 'RP'];

  final semesters = [
    '2nd Semester',
    '4th Semester',
    '6th Semester',
  ];

  String? selectedTeacher;
  String? selectedSemester;
  String? selectedSubject;

  String? departmentId;
  String? userRole;

  List<Map<String, dynamic>> subjects = [];
  List<Map<String, dynamic>> classRecords = [];

  bool loadingAccess = true;
  bool loadingSubjects = false;
  bool loadingRecords = false;

  String? deletingSessionId;

  bool get isAdmin => userRole == 'admin';

  bool get isTeacher => userRole == 'teacher';

  @override
  void initState() {
    super.initState();
    initializeAccess();
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // --------------------------------------------------
  // LOAD DEPARTMENT ACCESS
  // --------------------------------------------------

  Future<void> initializeAccess() async {
    setState(() => loadingAccess = true);

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('Please log in again.');
      }

      final membership = await supabase
          .from('department_members')
          .select('department_id, role')
          .eq('user_id', user.id)
          .maybeSingle();

      if (membership == null) {
        throw Exception('Department membership not found.');
      }

      final role = membership['role'].toString();
      final metadata = user.userMetadata ?? {};

      String? teacherCode;

      if (role == 'teacher') {
        teacherCode = metadata['teacher_code']?.toString();

        if (teacherCode == null ||
            !teachers.contains(teacherCode)) {
          throw Exception(
            'Teacher profile is not properly configured.',
          );
        }

        if (membership['department_id'].toString() !=
            metadata['department_id']?.toString()) {
          throw Exception(
            'Teacher department information does not match.',
          );
        }
      }

      if (role != 'admin' && role != 'teacher') {
        throw Exception('Invalid department role.');
      }

      if (!mounted) return;

      setState(() {
        departmentId = membership['department_id'].toString();
        userRole = role;

        if (role == 'teacher') {
          selectedTeacher = teacherCode;
        }
      });
    } catch (e) {
      showMessage('Error loading department access: $e');
    } finally {
      if (mounted) {
        setState(() => loadingAccess = false);
      }
    }
  }

  // --------------------------------------------------
  // SELECTION CHECKBOX
  // --------------------------------------------------

  Widget selectionCheckbox({
    required String title,
    required bool selected,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: selected,
              onChanged: enabled ? (_) => onTap() : null,
              visualDensity: VisualDensity.compact,
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // LOAD SUBJECTS
  // --------------------------------------------------

  Future<void> loadSubjects() async {
    if (selectedSemester == null || departmentId == null) {
      return;
    }

    setState(() {
      loadingSubjects = true;
      subjects = [];
      selectedSubject = null;
      classRecords = [];
    });

    try {
      final data = await supabase
          .from('subjects')
          .select()
          .eq('department_id', departmentId!)
          .eq('semester', selectedSemester!)
          .order('code');

      if (!mounted) return;

      setState(() {
        subjects = List<Map<String, dynamic>>.from(data);
      });

      if (subjects.isEmpty) {
        showMessage('No subjects found for this semester.');
      }
    } catch (e) {
      showMessage('Error loading subjects: $e');
    } finally {
      if (mounted) {
        setState(() => loadingSubjects = false);
      }
    }
  }

  // --------------------------------------------------
  // LOAD CLASS RECORDS
  // --------------------------------------------------

  Future<void> loadClassRecords() async {
    if (selectedTeacher == null ||
        selectedSemester == null ||
        selectedSubject == null) {
      showMessage(
        'Select teacher, semester and subject first.',
      );
      return;
    }

    if (departmentId == null) {
      showMessage('Department information is missing.');
      return;
    }

    setState(() {
      loadingRecords = true;
      classRecords = [];
    });

    try {
      final data = await supabase
          .from('class_sessions')
          .select()
          .eq('department_id', departmentId!)
          .eq('teacher', selectedTeacher!)
          .eq('semester', selectedSemester!)
          .eq('subject_id', selectedSubject!)
          .order('class_date', ascending: false)
          .order('class_number', ascending: true);

      if (!mounted) return;

      setState(() {
        classRecords =
            List<Map<String, dynamic>>.from(data);
      });

      if (classRecords.isEmpty) {
        showMessage(
          'No class records found for this selection.',
        );
      }
    } catch (e) {
      showMessage('Error loading class records: $e');
    } finally {
      if (mounted) {
        setState(() => loadingRecords = false);
      }
    }
  }

  // --------------------------------------------------
  // OPEN ATTENDANCE DETAILS
  // --------------------------------------------------

  Future<void> showAttendanceDetails(
    Map<String, dynamic> record,
  ) async {
    final sessionId = record['id'].toString();

    if (departmentId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(
              child: Text('Loading attendance...'),
            ),
          ],
        ),
      ),
    );

    try {
      final attendanceData = await supabase
          .from('attendance')
          .select('id, student_id, status')
          .eq('department_id', departmentId!)
          .eq('session_id', sessionId);

      final List<Map<String, dynamic>> rows =
          List<Map<String, dynamic>>.from(attendanceData);

      if (rows.isEmpty) {
        if (mounted) Navigator.pop(context);

        showMessage(
          'No attendance records found for this class.',
        );
        return;
      }

      final studentIds = rows
          .map((row) => row['student_id'].toString())
          .toSet()
          .toList();

      final studentData = await supabase
          .from('students')
          .select('id, roll_no, name')
          .eq('department_id', departmentId!)
          .inFilter('id', studentIds);

      final Map<String, Map<String, dynamic>> studentsById = {
        for (final student in studentData)
          student['id'].toString():
              Map<String, dynamic>.from(student),
      };

      // Explicit dynamic map type fixes the Dart nullability errors.

      final List<Map<String, dynamic>> attendanceRows =
          rows.map<Map<String, dynamic>>((row) {
        final student =
            studentsById[row['student_id'].toString()];

        return <String, dynamic>{
          'id': row['id'].toString(),
          'student_id': row['student_id'].toString(),
          'roll_no':
              student?['roll_no']?.toString() ?? '-',
          'name':
              student?['name']?.toString() ?? 'Student not found',
          'status': row['status'].toString(),
          'original_status': row['status'].toString(),
        };
      }).toList();

      attendanceRows.sort((a, b) {
        return (a['roll_no'] as String)
            .compareTo(b['roll_no'] as String);
      });

      if (!mounted) return;

      Navigator.pop(context);

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          bool saving = false;

          return StatefulBuilder(
            builder: (context, setDialogState) {
              final presentCount = attendanceRows
                  .where((row) => row['status'] == 'Present')
                  .length;

              final absentCount = attendanceRows
                  .where((row) => row['status'] == 'Absent')
                  .length;

              final lateCount = attendanceRows
                  .where((row) => row['status'] == 'Late')
                  .length;

              final total = attendanceRows.length;

              final changedCount = attendanceRows
                  .where((row) =>
                      row['status'] != row['original_status'])
                  .length;

              return AlertDialog(
                title: Text(
                  'Class ${record['class_number']} Attendance',
                ),
                content: SizedBox(
                  width: 550,
                  height: MediaQuery.of(context).size.height * 0.65,
                  child: Column(
                    children: [
                      Text(
                        'Date: ${DateFormat('dd-MM-yyyy').format(DateTime.parse(record['class_date'].toString()))}',
                      ),
                      Text('Teacher: ${record['teacher']}'),

                      const SizedBox(height: 14),

                      // ATTENDANCE SUMMARY

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _summaryChip(
                            'Total: $total',
                            Colors.blue,
                          ),
                          _summaryChip(
                            'Present: $presentCount',
                            Colors.green,
                          ),
                          _summaryChip(
                            'Absent: $absentCount',
                            Colors.red,
                          ),
                          if (lateCount > 0)
                            _summaryChip(
                              'Late: $lateCount',
                              Colors.orange,
                            ),
                        ],
                      ),

                      const Divider(height: 24),

                      const Text(
                        'Tick to mark Present. Untick to mark Absent.',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Expanded(
                        child: ListView.builder(
                          itemCount: attendanceRows.length,
                          itemBuilder: (context, index) {
                            final student = attendanceRows[index];

                            final isPresent =
                                student['status'] == 'Present';

                            final status =
                                student['status'].toString();

                            return Card(
                              margin: const EdgeInsets.only(
                                bottom: 6,
                              ),
                              child: CheckboxListTile(
                                value: isPresent,
                                activeColor: Colors.green,
                                onChanged: saving
                                    ? null
                                    : (value) {
                                        setDialogState(() {
                                          student['status'] =
                                              value == true
                                                  ? 'Present'
                                                  : 'Absent';
                                        });
                                      },
                                title: Text(
                                  '${student['roll_no']} - ${student['name']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  status,
                                  style: TextStyle(
                                    color: status == 'Present'
                                        ? Colors.green
                                        : status == 'Absent'
                                            ? Colors.red
                                            : Colors.orange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                            );
                          },
                        ),
                      ),

                      if (changedCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '$changedCount correction(s) not saved yet.',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.pop(dialogContext),
                    child: const Text('Close'),
                  ),

                  FilledButton.icon(
                    onPressed: saving || changedCount == 0
                        ? null
                        : () async {
                            setDialogState(() {
                              saving = true;
                            });

                            try {
                              for (final student in attendanceRows) {
                                if (student['status'] !=
                                    student['original_status']) {
                                  await supabase
                                      .from('attendance')
                                      .update({
                                    'status': student['status'],
                                  })
                                      .eq(
                                        'id',
                                        student['id'] as Object,
                                      )
                                      .eq('session_id', sessionId)
                                      .eq(
                                        'department_id',
                                        departmentId!,
                                      );
                                }
                              }

                              for (final student in attendanceRows) {
                                student['original_status'] =
                                    student['status'];
                              }

                              if (!dialogContext.mounted) return;

                              Navigator.pop(dialogContext);

                              showMessage(
                                'Attendance updated successfully.',
                              );
                            } catch (e) {
                              setDialogState(() {
                                saving = false;
                              });

                              showMessage(
                                'Error updating attendance: $e',
                              );
                            }
                          },
                    icon: saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      saving ? 'Saving...' : 'Save Changes',
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showMessage('Error loading attendance: $e');
      }
    }
  }

  // --------------------------------------------------
  // ATTENDANCE SUMMARY CHIP
  // --------------------------------------------------

  Widget _summaryChip(String label, Color color) {
    return Chip(
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
    );
  }

  // --------------------------------------------------
  // DELETE CLASS SESSION
  // --------------------------------------------------

  Future<void> confirmDeleteClass(
    Map<String, dynamic> record,
  ) async {
    final sessionId = record['id'].toString();
    final classNumber = record['class_number'].toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Class?'),
        content: Text(
          'Are you sure you want to delete Class $classNumber '
          'and its attendance records? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      deletingSessionId = sessionId;
    });

    try {
      await supabase.rpc(
        'delete_class_session',
        params: {
          'p_session_id': sessionId,
        },
      );

      if (!mounted) return;

      showMessage(
        'Class $classNumber deleted successfully.',
      );

      await loadClassRecords();
    } catch (e) {
      showMessage('Error deleting class: $e');
    } finally {
      if (mounted) {
        setState(() {
          deletingSessionId = null;
        });
      }
    }
  }

  // --------------------------------------------------
  // DISPLAY CLASS RECORDS
  // --------------------------------------------------

  Widget buildRecordsList() {
    if (loadingRecords) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (classRecords.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('No class records available.'),
        ),
      );
    }

    return Column(
      children: classRecords.map((record) {
        final sessionId = record['id'].toString();

        final classNumber =
            record['class_number'].toString();

        final teacher = record['teacher'].toString();

        final date = DateFormat('dd-MM-yyyy').format(
          DateTime.parse(record['class_date'].toString()),
        );

        final isDeleting =
            deletingSessionId == sessionId;

        final paper = subjects.firstWhere(
          (s) => s['id'].toString() == selectedSubject,
          orElse: () => {'code': 'Selected paper'},
        )['code'];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            onTap: () => showAttendanceDetails(record),
            leading: CircleAvatar(
              child: Text(classNumber),
            ),
            title: Text(
              'Class $classNumber',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              'Date: $date\n'
              'Teacher: $teacher\n'
              'Paper: $paper\n'
              'Tap to view and edit attendance',
            ),
            isThreeLine: true,
            trailing: isDeleting
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : IconButton(
                    tooltip: 'Delete class',
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    onPressed: deletingSessionId == null
                        ? () => confirmDeleteClass(record)
                        : null,
                  ),
          ),
        );
      }).toList(),
    );
  }

  // --------------------------------------------------
  // BUILD SCREEN
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (loadingAccess) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (departmentId == null || userRole == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Class Records'),
        ),
        body: const Center(
          child: Text(
            'Unable to load department information. '
            'Please log in again.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Class Records'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: loadingRecords || loadingSubjects
                ? null
                : () {
                    if (selectedSemester != null) {
                      loadSubjects();
                    }
                  },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 850,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TEACHER SELECTION

                const Text(
                  'Select Teacher',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                if (isAdmin)
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: teachers.map((teacher) {
                      return selectionCheckbox(
                        title: teacher,
                        selected:
                            selectedTeacher == teacher,
                        onTap: () {
                          setState(() {
                            selectedTeacher = teacher;
                            classRecords = [];
                          });
                        },
                      );
                    }).toList(),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                    ),
                    child: Chip(
                      avatar: const Icon(Icons.person),
                      label: Text(
                        'Logged-in Teacher: $selectedTeacher',
                      ),
                    ),
                  ),

                const Divider(height: 28),

                // SEMESTER SELECTION

                const Text(
                  'Select Semester',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: semesters.map((semester) {
                    return selectionCheckbox(
                      title: semester,
                      selected:
                          selectedSemester == semester,
                      onTap: () {
                        setState(() {
                          selectedSemester = semester;
                          selectedSubject = null;
                          subjects = [];
                          classRecords = [];
                        });

                        loadSubjects();
                      },
                    );
                  }).toList(),
                ),

                const Divider(height: 28),

                // SUBJECT SELECTION

                const Text(
                  'Select Paper',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                if (loadingSubjects)
                  const LinearProgressIndicator(),

                if (!loadingSubjects && subjects.isEmpty)
                  const Text(
                    'Select a semester to load papers.',
                  ),

                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: subjects.map((subject) {
                    final code =
                        subject['code'].toString();

                    final id =
                        subject['id'].toString();

                    return selectionCheckbox(
                      title: code,
                      selected: selectedSubject == id,
                      onTap: () {
                        setState(() {
                          selectedSubject = id;
                          classRecords = [];
                        });
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),

                // VIEW RECORDS BUTTON

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: loadingRecords ||
                            selectedTeacher == null ||
                            selectedSemester == null ||
                            selectedSubject == null
                        ? null
                        : loadClassRecords,
                    icon: const Icon(Icons.search),
                    label: const Text(
                      'View Class Records',
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // RECORDS HEADING

                if (selectedTeacher != null)
                  Text(
                    'Class Records - $selectedTeacher',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                const SizedBox(height: 12),

                buildRecordsList(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
