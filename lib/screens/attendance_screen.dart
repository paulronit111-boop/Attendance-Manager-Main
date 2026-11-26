
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../config/supabase_config.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final supabase = SupabaseConfig.client;
  final classNumberController = TextEditingController();

  final semesters = [
    '2nd Semester',
    '4th Semester',
    '6th Semester',
  ];

  final groups = ['DSC', 'DSM'];

  final teachers = ['SC', 'SG', 'MHB', 'BB', 'RP'];

  String? selectedSemester;
  String? selectedGroup;
  String? selectedSubject;

  String selectedTeacher = 'RP';

  String? departmentId;
  String? userRole;

  DateTime selectedDate = DateTime.now();

  List<Map<String, dynamic>> subjects = [];
  List<Map<String, dynamic>> students = [];

  Map<String, String> attendanceStatus = {};

  String? currentSessionId;
  int? currentClassNumber;

  bool loadingAccess = true;
  bool loadingSubjects = false;
  bool loadingStudents = false;
  bool saving = false;
  bool studentsLoaded = false;

  bool get isAdmin => userRole == 'admin';

  bool get isTeacher => userRole == 'teacher';

  String get effectiveTeacher {
    if (isTeacher) {
      return supabase.auth.currentUser
              ?.userMetadata?['teacher_code']
              ?.toString() ??
          '';
    }

    return selectedTeacher;
  }

  @override
  void initState() {
    super.initState();
    initializeAccess();
  }

  @override
  void dispose() {
    classNumberController.dispose();
    super.dispose();
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String get dateString =>
      DateFormat('yyyy-MM-dd').format(selectedDate);

  // --------------------------------------------------
  // LOAD DEPARTMENT ACCESS
  // --------------------------------------------------

  Future<void> initializeAccess() async {
    if (!mounted) return;

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
        throw Exception(
          'You are not registered as a department member.',
        );
      }

      final role = membership['role'].toString();

      final metadata = user.userMetadata ?? {};
      final teacherCode = metadata['teacher_code']?.toString();

      if (role == 'teacher') {
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

      if (!mounted) return;

      setState(() {
        departmentId =
            membership['department_id'].toString();
        userRole = role;

        if (role == 'teacher') {
          selectedTeacher = teacherCode!;
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
  // RESET SESSION
  // --------------------------------------------------

  void resetSession() {
    currentSessionId = null;
    currentClassNumber = null;
    classNumberController.clear();

    studentsLoaded = false;
    students = [];
    attendanceStatus = {};
  }

  // --------------------------------------------------
  // SELECT CLASS DATE
  // --------------------------------------------------

  Future<void> pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (date != null && mounted) {
      setState(() {
        selectedDate = date;
        resetSession();
      });
    }
  }

  // --------------------------------------------------
  // LOAD SUBJECTS USING DEPARTMENT ID
  // --------------------------------------------------

  Future<void> loadSubjects() async {
    if (selectedSemester == null ||
        selectedGroup == null) {
      return;
    }

    if (departmentId == null) {
      showMessage('Department information is not available.');
      return;
    }

    setState(() {
      loadingSubjects = true;
      subjects = [];
      selectedSubject = null;
      resetSession();
    });

    try {
      final data = await supabase
          .from('subjects')
          .select()
          .eq('department_id', departmentId!)
          .eq('semester', selectedSemester!)
          .eq('student_group', selectedGroup!)
          .order('code');

      if (!mounted) return;

      setState(() {
        subjects = List<Map<String, dynamic>>.from(data);
      });

      if (subjects.isEmpty) {
        showMessage('No subjects found for this selection.');
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
  // LOAD STUDENTS AND CREATE CLASS SESSION
  // --------------------------------------------------

  Future<void> loadStudents() async {
    if (selectedSemester == null ||
        selectedGroup == null ||
        selectedSubject == null) {
      showMessage(
        'Select semester, group and subject first.',
      );
      return;
    }

    if (departmentId == null) {
      showMessage('Department information is not available.');
      return;
    }

    if (effectiveTeacher.isEmpty ||
        !teachers.contains(effectiveTeacher)) {
      showMessage('Invalid teacher profile.');
      return;
    }

    if (studentsLoaded || currentSessionId != null) {
      showMessage('This class session is already loaded.');
      return;
    }

    setState(() {
      loadingStudents = true;
      resetSession();
    });

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('Please log in again.');
      }

      // 1. Fetch shared department students.
      final studentData = await supabase
          .from('students')
          .select()
          .eq('department_id', departmentId!)
          .eq('semester', selectedSemester!)
          .eq('student_group', selectedGroup!)
          .order('roll_no');

      final loadedStudents =
          List<Map<String, dynamic>>.from(studentData);

      if (loadedStudents.isEmpty) {
        showMessage(
          'No students found for this semester and group.',
        );
        return;
      }

      // 2. Create session and allocate class number.
      //
      // The RPC must assign the next class number
      // department-wide for the selected date.

      final response = await supabase.rpc(
        'create_class_session',
        params: {
          'p_semester': selectedSemester,
          'p_subject_id': selectedSubject,
          'p_class_date': dateString,
          'p_teacher': effectiveTeacher,
        },
      );

      if (response == null || response is! Map) {
        throw Exception(
          'Invalid response from create_class_session.',
        );
      }

      final sessionData =
          Map<String, dynamic>.from(response);

      if (sessionData['id'] == null ||
          sessionData['class_number'] == null) {
        throw Exception(
          'Class session ID or class number was not returned.',
        );
      }

      final sessionId = sessionData['id'].toString();

      final classNumber =
          (sessionData['class_number'] as num).toInt();

      // 3. Load existing attendance for this session.
      final attendanceData = await supabase
          .from('attendance')
          .select('student_id, status')
          .eq('department_id', departmentId!)
          .eq('session_id', sessionId);

      final savedStatuses = <String, String>{};

      for (final record in attendanceData) {
        savedStatuses[record['student_id'].toString()] =
            record['status'].toString();
      }

      if (!mounted) return;

      // 4. Update interface.
      setState(() {
        currentSessionId = sessionId;
        currentClassNumber = classNumber;

        classNumberController.text =
            classNumber.toString();

        students = loadedStudents;

        attendanceStatus = {
          for (final student in students)
            student['id'].toString():
                savedStatuses[
                      student['id'].toString()
                    ] ??
                    'Absent',
        };

        studentsLoaded = true;
      });

      showMessage(
        'Class $classNumber created. '
        '${students.length} students loaded.',
      );
    } catch (e) {
      showMessage('Error loading attendance: $e');
    } finally {
      if (mounted) {
        setState(() => loadingStudents = false);
      }
    }
  }

  // --------------------------------------------------
  // SAVE ATTENDANCE
  // --------------------------------------------------

  Future<void> saveAttendance() async {
    if (!studentsLoaded || students.isEmpty) {
      showMessage(
        'Load the students before saving attendance.',
      );
      return;
    }

    if (currentSessionId == null) {
      showMessage(
        'No class session found. Load students again.',
      );
      return;
    }

    if (departmentId == null) {
      showMessage('Department information is missing.');
      return;
    }

    setState(() => saving = true);

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('Please log in again.');
      }

      final sessionId = currentSessionId!;

      // Prepare attendance records.
      final records = students.map((student) {
        final studentId = student['id'].toString();

        return {
          'owner_id': user.id,
          'department_id': departmentId,
          'student_id': studentId,
          'subject_id': selectedSubject,
          'attendance_date': dateString,
          'session_id': sessionId,
          'status': attendanceStatus[studentId] ?? 'Absent',
        };
      }).toList();

      // Save or update using department-level unique key.
      await supabase
          .from('attendance')
          .upsert(
            records,
            onConflict:
                'department_id,student_id,session_id',
          );

      if (!mounted) return;

      final presentCount = attendanceStatus.values
          .where((status) => status == 'Present')
          .length;

      final absentCount = students.length - presentCount;

      showMessage(
        'Attendance saved for Class $currentClassNumber! '
        'Present: $presentCount, Absent: $absentCount',
      );
    } catch (e) {
      showMessage('Error saving attendance: $e');
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  // --------------------------------------------------
  // CHECKBOX WIDGET
  // --------------------------------------------------

  Widget selectionCheckbox({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: selected,
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: loadingStudents || saving
          ? null
          : (_) => onTap(),
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
          title: const Text('Mark Attendance'),
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
        title: const Text('Mark Attendance'),
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
                // --------------------------------------
                // SEMESTER SELECTION
                // --------------------------------------

                const Text(
                  'Select Semester',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                ...semesters.map((semester) {
                  return selectionCheckbox(
                    title: semester,
                    selected:
                        selectedSemester == semester,
                    onTap: () {
                      setState(() {
                        selectedSemester = semester;
                        selectedSubject = null;
                        resetSession();
                      });

                      loadSubjects();
                    },
                  );
                }),

                const Divider(),

                // --------------------------------------
                // GROUP SELECTION
                // --------------------------------------

                const Text(
                  'Select Student Group',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                ...groups.map((group) {
                  return selectionCheckbox(
                    title: group,
                    selected: selectedGroup == group,
                    onTap: () {
                      setState(() {
                        selectedGroup = group;
                        selectedSubject = null;
                        resetSession();
                      });

                      loadSubjects();
                    },
                  );
                }),

                const Divider(),

                // --------------------------------------
                // SUBJECT SELECTION
                // --------------------------------------

                const Text(
                  'Select Subject',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                if (loadingSubjects)
                  const LinearProgressIndicator(),

                if (!loadingSubjects && subjects.isEmpty)
                  const Text(
                    'Select semester and group to load subjects.',
                  ),

                ...subjects.map((subject) {
                  final code = subject['code'].toString();
                  final id = subject['id'].toString();

                  return selectionCheckbox(
                    title: code,
                    selected: selectedSubject == id,
                    onTap: () {
                      setState(() {
                        selectedSubject = id;
                        resetSession();
                      });
                    },
                  );
                }),

                const Divider(),

                // --------------------------------------
                // CLASS DETAILS
                // --------------------------------------

                const Text(
                  'Class Details',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                // DATE
                OutlinedButton.icon(
                  onPressed:
                      loadingStudents || studentsLoaded
                          ? null
                          : pickDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    'Date: ${DateFormat('dd-MM-yyyy').format(selectedDate)}',
                  ),
                ),

                const SizedBox(height: 12),

                // AUTOMATIC CLASS NUMBER
                TextField(
                  controller: classNumberController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText:
                        'Automatically Assigned Class Number',
                    hintText:
                        'Assigned when students are loaded',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.numbers),
                  ),
                ),

                const SizedBox(height: 12),

                // --------------------------------------
                // TEACHER
                // --------------------------------------

                if (isAdmin) ...[
                  DropdownButtonFormField<String>(
                    initialValue: selectedTeacher,
                    decoration: const InputDecoration(
                      labelText: 'Teacher',
                      border: OutlineInputBorder(),
                    ),
                    items: teachers.map((teacher) {
                      return DropdownMenuItem(
                        value: teacher,
                        child: Text(teacher),
                      );
                    }).toList(),
                    onChanged:
                        loadingStudents || studentsLoaded
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() {
                                    selectedTeacher = value;
                                    resetSession();
                                  });
                                }
                              },
                  ),
                ] else ...[
                  TextField(
                    readOnly: true,
                    controller: TextEditingController(
                      text: effectiveTeacher,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Logged-in Teacher',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // --------------------------------------
                // LOAD STUDENTS BUTTON
                // --------------------------------------

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        loadingStudents || studentsLoaded
                            ? null
                            : loadStudents,
                    icon: const Icon(Icons.people),
                    label: Text(
                      loadingStudents
                          ? 'Loading...'
                          : studentsLoaded
                              ? 'Students Loaded'
                              : 'Load Students',
                    ),
                  ),
                ),

                // --------------------------------------
                // STUDENT ATTENDANCE
                // --------------------------------------

                if (studentsLoaded) ...[
                  const SizedBox(height: 20),

                  Text(
                    'Class $currentClassNumber',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    '${selectedSemester!} | '
                    '${selectedGroup!} | '
                    '${selectedSubject != null ? subjects.firstWhere((s) => s['id'].toString() == selectedSubject)['code'] : ''} | '
                    '$effectiveTeacher | '
                    '${DateFormat('dd-MM-yyyy').format(selectedDate)}',
                    style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.secondary,
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text(
                    'Student Attendance (${students.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  ...students.map((student) {
                    final id = student['id'].toString();
                    final status =
                        attendanceStatus[id] ?? 'Absent';

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${student['roll_no']} - '
                              '${student['name']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            Row(
                              children: [
                                // PRESENT CHECKBOX
                                Expanded(
                                  child: CheckboxListTile(
                                    dense: true,
                                    contentPadding:
                                        EdgeInsets.zero,
                                    title: const Text('Present'),
                                    value: status == 'Present',
                                    activeColor: Colors.green,
                                    controlAffinity:
                                        ListTileControlAffinity
                                            .leading,
                                    onChanged: saving
                                        ? null
                                        : (value) {
                                            setState(() {
                                              attendanceStatus[id] =
                                                  value == true
                                                      ? 'Present'
                                                      : 'Absent';
                                            });
                                          },
                                  ),
                                ),

                                // ABSENT CHECKBOX
                                Expanded(
                                  child: CheckboxListTile(
                                    dense: true,
                                    contentPadding:
                                        EdgeInsets.zero,
                                    title: const Text('Absent'),
                                    value: status == 'Absent',
                                    activeColor: Colors.red,
                                    controlAffinity:
                                        ListTileControlAffinity
                                            .leading,
                                    onChanged: saving
                                        ? null
                                        : (value) {
                                            setState(() {
                                              attendanceStatus[id] =
                                                  value == true
                                                      ? 'Absent'
                                                      : 'Present';
                                            });
                                          },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 16),

                  // --------------------------------------
                  // SAVE ATTENDANCE BUTTON
                  // --------------------------------------

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          saving ? null : saveAttendance,
                      icon: const Icon(Icons.save),
                      label: Text(
                        saving
                            ? 'Saving...'
                            : 'Save Attendance',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
