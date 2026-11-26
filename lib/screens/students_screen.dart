
import 'package:material_ui/material_ui.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../config/supabase_config.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final supabase = SupabaseConfig.client;

  List<Map<String, dynamic>> students = [];

  String selectedSemester = '2nd Semester';
  String selectedGroup = 'DSC';

  String? departmentId;
  bool isDepartmentAdmin = false;

  bool isLoading = false;
  bool isImporting = false;

  final List<String> semesters = [
    '2nd Semester',
    '4th Semester',
    '6th Semester',
  ];

  final List<String> groups = ['DSC', 'DSM'];

  @override
  void initState() {
    super.initState();
    loadStudents();
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // --------------------------------------------------
  // GET DEPARTMENT MEMBERSHIP
  // --------------------------------------------------

  Future<Map<String, dynamic>> getDepartmentAccess() async {
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

    return Map<String, dynamic>.from(membership);
  }

  // --------------------------------------------------
  // LOAD STUDENTS
  // --------------------------------------------------

  Future<void> loadStudents() async {
    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      final access = await getDepartmentAccess();

      final deptId = access['department_id'].toString();
      final role = access['role'].toString();

      final data = await supabase
          .from('students')
          .select()
          .eq('department_id', deptId)
          .eq('semester', selectedSemester)
          .eq('student_group', selectedGroup)
          .order('roll_no');

      if (!mounted) return;

      setState(() {
        departmentId = deptId;
        isDepartmentAdmin = role == 'admin';
        students = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      showMessage('Error loading students: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  // --------------------------------------------------
  // CHECK ADMIN PERMISSION
  // --------------------------------------------------

  Future<Map<String, dynamic>> requireAdminAccess() async {
    final access = await getDepartmentAccess();

    if (access['role'] != 'admin') {
      throw Exception(
        'Only the department administrator can modify student records.',
      );
    }

    return access;
  }

  // --------------------------------------------------
  // ADD / EDIT STUDENT
  // --------------------------------------------------

  Future<void> showStudentDialog({
    Map<String, dynamic>? student,
  }) async {
    if (!isDepartmentAdmin) {
      showMessage('Only the administrator can modify students.');
      return;
    }

    final bool isEditing = student != null;

    final rollController = TextEditingController(
      text: student?['roll_no']?.toString() ?? '',
    );

    final nameController = TextEditingController(
      text: student?['name']?.toString() ?? '',
    );

    String semester = student?['semester'] ?? selectedSemester;
    String group = student?['student_group'] ?? selectedGroup;

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return AlertDialog(
              title: Text(
                isEditing ? 'Edit Student' : 'Add Student',
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: rollController,
                        decoration: const InputDecoration(
                          labelText: 'Roll Number',
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.trim().isEmpty) {
                            return 'Enter roll number';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 12),

                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Student Name',
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.trim().isEmpty) {
                            return 'Enter student name';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        initialValue: semester,
                        decoration: const InputDecoration(
                          labelText: 'Semester',
                        ),
                        items: semesters.map((item) {
                          return DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            dialogSetState(() {
                              semester = value;
                            });
                          }
                        },
                      ),

                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        initialValue: group,
                        decoration: const InputDecoration(
                          labelText: 'Student Group',
                        ),
                        items: groups.map((item) {
                          return DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            dialogSetState(() {
                              group = value;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),

                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) {
                      return;
                    }

                    try {
                      final access = await requireAdminAccess();
                      final user = supabase.auth.currentUser;

                      if (user == null) {
                        throw Exception('Please log in again.');
                      }

                      final deptId =
                          access['department_id'].toString();

                      final values = {
                        'roll_no': rollController.text.trim(),
                        'name': nameController.text.trim(),
                        'semester': semester,
                        'student_group': group,
                      };

                      if (isEditing) {
                        await supabase
                            .from('students')
                            .update(values)
                            .eq('id', student['id'])
                            .eq('department_id', deptId);
                      } else {
                        await supabase.from('students').insert({
                          ...values,
                          'owner_id': user.id,
                          'department_id': deptId,
                        });
                      }

                      if (!dialogContext.mounted) return;

                      Navigator.pop(dialogContext);

                      showMessage(
                        isEditing
                            ? 'Student updated successfully.'
                            : 'Student added successfully.',
                      );

                      await loadStudents();
                    } catch (e) {
                      if (dialogContext.mounted) {
                        showMessage('Error saving student: $e');
                      }
                    }
                  },
                  child: Text(isEditing ? 'Update' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );

    rollController.dispose();
    nameController.dispose();
  }

  // --------------------------------------------------
  // DELETE STUDENT
  // --------------------------------------------------

  Future<void> deleteStudent(
    Map<String, dynamic> student,
  ) async {
    if (!isDepartmentAdmin) {
      showMessage('Only the administrator can delete students.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Student'),
          content: Text(
            'Are you sure you want to delete ${student['name']}?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    try {
      final access = await requireAdminAccess();
      final deptId = access['department_id'].toString();

      await supabase
          .from('students')
          .delete()
          .eq('id', student['id'])
          .eq('department_id', deptId);

      if (!mounted) return;

      showMessage('Student deleted successfully.');

      await loadStudents();
    } catch (e) {
      showMessage('Error deleting student: $e');
    }
  }

  // --------------------------------------------------
  // NORMALIZE EXCEL CELL VALUES
  // --------------------------------------------------

  String cellToString(Data? cell) {
    final value = cell?.value;

    if (value == null) return '';

    if (value is IntCellValue) {
      return value.value.toString();
    }

    if (value is DoubleCellValue) {
      final number = value.value;

      if (number == number.roundToDouble()) {
        return number.toInt().toString();
      }

      return number.toString();
    }

    return value.toString().trim();
  }

  String normalizeHeader(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  // --------------------------------------------------
  // IMPORT STUDENTS FROM EXCEL
  // --------------------------------------------------

  Future<void> importStudentsFromExcel() async {
    if (!isDepartmentAdmin) {
      showMessage('Only the administrator can import students.');
      return;
    }

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (files.isEmpty) return;

      final selectedFile = files.first;
      final bytes = await selectedFile.readAsBytes();

      if (bytes.isEmpty) {
        showMessage('The selected Excel file is empty.');
        return;
      }

      final workbook = Excel.decodeBytes(bytes);

      if (workbook.tables.isEmpty) {
        showMessage('No worksheet found in the Excel file.');
        return;
      }

      final sheetName = workbook.tables.keys.first;
      final sheet = workbook.tables[sheetName];

      if (sheet == null || sheet.rows.isEmpty) {
        showMessage('The selected worksheet is empty.');
        return;
      }

      int headerRowIndex = -1;
      int rollColumn = -1;
      int nameColumn = -1;

      // Find the header row.
      for (int i = 0; i < sheet.rows.length && i < 15; i++) {
        final row = sheet.rows[i];

        for (int j = 0; j < row.length; j++) {
          final header = normalizeHeader(
            cellToString(row[j]),
          );

          if ([
            'rollno',
            'rollnumber',
            'roll',
            'rollnum',
          ].contains(header)) {
            rollColumn = j;
          }

          if ([
            'name',
            'studentname',
            'fullname',
          ].contains(header)) {
            nameColumn = j;
          }
        }

        if (rollColumn != -1 && nameColumn != -1) {
          headerRowIndex = i;
          break;
        }

        rollColumn = -1;
        nameColumn = -1;
      }

      if (headerRowIndex == -1) {
        showMessage(
          'Could not find Roll No and Name columns. '
          'Please check your Excel headings.',
        );
        return;
      }

      final Map<String, Map<String, dynamic>> uniqueStudents = {};

      for (int i = headerRowIndex + 1;
          i < sheet.rows.length;
          i++) {
        final row = sheet.rows[i];

        if (rollColumn >= row.length ||
            nameColumn >= row.length) {
          continue;
        }

        final roll = cellToString(row[rollColumn]).trim();
        final name = cellToString(row[nameColumn]).trim();

        if (roll.isEmpty || name.isEmpty) {
          continue;
        }

        uniqueStudents[roll] = {
          'roll_no': roll,
          'name': name,
        };
      }

      final importedStudents = uniqueStudents.values.toList();

      if (importedStudents.isEmpty) {
        showMessage('No valid student records found in Excel.');
        return;
      }

      if (!mounted) return;

      // Preview before importing.
      final shouldImport = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Preview Excel Import'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('File: ${selectedFile.name}'),

                  const SizedBox(height: 8),

                  Text('Semester: $selectedSemester'),
                  Text('Group: $selectedGroup'),

                  const SizedBox(height: 8),

                  Text(
                    'Total students found: '
                    '${importedStudents.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'First 10 records:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Roll No')),
                          DataColumn(label: Text('Name')),
                        ],
                        rows: importedStudents
                            .take(10)
                            .map((student) {
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(student['roll_no']),
                              ),
                              DataCell(
                                Text(student['name']),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  if (importedStudents.length > 10)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'And ${importedStudents.length - 10} '
                        'more records...',
                      ),
                    ),

                  const SizedBox(height: 12),

                  const Text(
                    'Existing students with matching roll '
                    'numbers will have their names updated.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('Cancel'),
              ),

              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.upload),
                label: const Text('Import Students'),
              ),
            ],
          );
        },
      );

      if (shouldImport != true || !mounted) return;

      await saveImportedStudents(importedStudents);
    } catch (e) {
      showMessage('Excel import failed: $e');
    }
  }

  // --------------------------------------------------
  // SAVE IMPORTED STUDENTS TO SUPABASE
  // --------------------------------------------------

  Future<void> saveImportedStudents(
    List<Map<String, dynamic>> importedStudents,
  ) async {
    if (!mounted) return;

    setState(() => isImporting = true);

    try {
      final access = await requireAdminAccess();
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw Exception('Please log in again.');
      }

      final deptId = access['department_id'].toString();

      final records = importedStudents.map((student) {
        return {
          'owner_id': user.id,
          'department_id': deptId,
          'semester': selectedSemester,
          'student_group': selectedGroup,
          'roll_no': student['roll_no'],
          'name': student['name'],
        };
      }).toList();

      // Upload in batches of 500.
      const batchSize = 500;

      for (int i = 0; i < records.length; i += batchSize) {
        final end = (i + batchSize < records.length)
            ? i + batchSize
            : records.length;

        final batch = records.sublist(i, end);

        await supabase.from('students').upsert(
          batch,
          onConflict:
              'department_id,semester,student_group,roll_no',
        );
      }

      if (!mounted) return;

      showMessage(
        '${records.length} students imported successfully.',
      );

      await loadStudents();
    } catch (e) {
      showMessage('Error saving imported students: $e');
    } finally {
      if (mounted) {
        setState(() => isImporting = false);
      }
    }
  }

  // --------------------------------------------------
  // BUILD SCREEN
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Management'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: isLoading ? null : loadStudents,
            icon: const Icon(Icons.refresh),
          ),
          if (isDepartmentAdmin)
            IconButton(
              tooltip: 'Import from Excel',
              onPressed: isImporting
                  ? null
                  : importStudentsFromExcel,
              icon: const Icon(Icons.upload_file),
            ),
          const SizedBox(width: 8),
        ],
      ),

      floatingActionButton: isDepartmentAdmin
          ? FloatingActionButton.extended(
              onPressed: () => showStudentDialog(),
              icon: const Icon(Icons.person_add),
              label: const Text('Add Student'),
            )
          : null,

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Semester and group selection.
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedSemester,
                    decoration: const InputDecoration(
                      labelText: 'Semester',
                      border: OutlineInputBorder(),
                    ),
                    items: semesters.map((item) {
                      return DropdownMenuItem(
                        value: item,
                        child: Text(item),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedSemester = value;
                        });

                        loadStudents();
                      }
                    },
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedGroup,
                    decoration: const InputDecoration(
                      labelText: 'Group',
                      border: OutlineInputBorder(),
                    ),
                    items: groups.map((item) {
                      return DropdownMenuItem(
                        value: item,
                        child: Text(item),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedGroup = value;
                        });

                        loadStudents();
                      }
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (isDepartmentAdmin) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isImporting
                      ? null
                      : importStudentsFromExcel,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(
                    isImporting
                        ? 'Importing Students...'
                        : 'Import Students from Excel',
                  ),
                ),
              ),
            ] else ...[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'You can view department students. '
                          'Only the administrator can modify records.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (isImporting)
              const LinearProgressIndicator(),

            const SizedBox(height: 16),

            // Student count.
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Total Students: ${students.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Student list.
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : students.isEmpty
                      ? const Center(
                          child: Text('No students found.'),
                        )
                      : ListView.builder(
                          itemCount: students.length,
                          itemBuilder: (context, index) {
                            final student = students[index];

                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(
                                  student['name'].toString(),
                                ),
                                subtitle: Text(
                                  'Roll No: ${student['roll_no']}',
                                ),
                                trailing: isDepartmentAdmin
                                    ? Wrap(
                                        spacing: 4,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit,
                                              color: Colors.blue,
                                            ),
                                            onPressed: () {
                                              showStudentDialog(
                                                student: student,
                                              );
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              color: Colors.red,
                                            ),
                                            onPressed: () {
                                              deleteStudent(student);
                                            },
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
