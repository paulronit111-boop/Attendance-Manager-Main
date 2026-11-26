
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final pinController = TextEditingController();
  final adminEmailController = TextEditingController();
  final adminPasswordController = TextEditingController();

  bool loading = false;
  bool hidePin = true;
  bool hideAdminPassword = true;
  bool isAdminLogin = false;

  String selectedTeacher = 'SC';

  final List<String> teachers = [
    'SC',
    'SG',
    'MHB',
    'BB',
    'RP',
  ];

  Future<void> authenticate() async {
    if (loading) return;

    final supabase = Supabase.instance.client;
    final auth = supabase.auth;

    // ADMINISTRATOR LOGIN
    if (isAdminLogin) {
      final email = adminEmailController.text.trim();
      final password = adminPasswordController.text;

      if (email.isEmpty || password.isEmpty) {
        showMessage('Enter administrator email and password.');
        return;
      }

      setState(() => loading = true);

      try {
        await auth.signInWithPassword(
          email: email,
          password: password,
        );
      } on AuthException catch (e) {
        showMessage(e.message);
      } catch (e) {
        showMessage('Administrator login failed: $e');
      } finally {
        if (mounted) {
          setState(() => loading = false);
        }
      }

      return;
    }

    // TEACHER LOGIN
    final pin = pinController.text.trim();

    if (pin.isEmpty) {
      showMessage('Enter the common teacher PIN.');
      return;
    }

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      showMessage('The teacher PIN must contain exactly 4 digits.');
      return;
    }

    setState(() => loading = true);

    try {
      final response = await supabase.functions.invoke(
        'teacher-login',
        body: {
          'teacher_code': selectedTeacher,
          'pin': pin,
        },
      );

      final responseData = response.data;

      if (responseData is! Map) {
        throw Exception('Invalid response from teacher login.');
      }

      final data = Map<String, dynamic>.from(responseData);

      if (data['success'] != true) {
        throw Exception(
          data['error']?.toString() ??
              'Teacher authentication failed.',
        );
      }

      final refreshToken = data['refresh_token']?.toString();

      if (refreshToken == null || refreshToken.isEmpty) {
        throw Exception(
          'Refresh token was not returned by the server.',
        );
      }

      await auth.setSession(refreshToken);

      if (auth.currentUser == null) {
        throw Exception('Unable to establish teacher session.');
      }

      pinController.clear();

      showMessage(
        '${data['display_name'] ?? selectedTeacher} login successful.',
      );
    } on AuthException catch (e) {
      showMessage(e.message);
    } catch (e) {
      showMessage('Teacher login failed: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // TEACHER AVATAR
  Widget teacherAvatar(String teacher) {
    final isSelected = selectedTeacher == teacher;

    return Expanded(
      child: InkWell(
        onTap: loading
            ? null
            : () {
                setState(() {
                  selectedTeacher = teacher;
                });
              },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? Colors.indigo
                        : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: CircleAvatar(
                  radius: 25,
                  backgroundColor: isSelected
                      ? Colors.indigo.shade100
                      : Colors.grey.shade200,
                  child: Icon(
                    Icons.person,
                    size: 29,
                    color: isSelected
                        ? Colors.indigo
                        : Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                teacher,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isSelected
                      ? Colors.indigo
                      : Colors.black87,
                ),
              ),
              const SizedBox(height: 3),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: Colors.indigo,
                  size: 16,
                )
              else
                const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    pinController.dispose();
    adminEmailController.dispose();
    adminPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    // NEW DEPARTMENT LOGO
                    Container(
                      width: 112,
                      height: 112,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.grey.shade200,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/department_logo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.school,
                              size: 55,
                              color: Colors.indigo,
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    const Text(
                      'Gurucharan University',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 5),

                    const Text(
                      'Statistics Department',
                      style: TextStyle(color: Colors.grey),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Attendance Management System',
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 28),

                    // LOGIN TYPE
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Teacher'),
                          icon: Icon(Icons.person),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Administrator'),
                          icon: Icon(Icons.admin_panel_settings),
                        ),
                      ],
                      selected: {isAdminLogin},
                      onSelectionChanged: loading
                          ? null
                          : (value) {
                              setState(() {
                                isAdminLogin = value.first;
                              });
                            },
                    ),

                    const SizedBox(height: 28),

                    // TEACHER LOGIN
                    if (!isAdminLogin) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Select Teacher',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: teachers.map((teacher) {
                          return teacherAvatar(teacher);
                        }).toList(),
                      ),

                      const SizedBox(height: 22),

                      Text(
                        'Selected Teacher: $selectedTeacher',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.indigo,
                        ),
                      ),

                      const SizedBox(height: 18),

                      TextField(
                        controller: pinController,
                        obscureText: hidePin,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: 'Common Teacher PIN',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          counterText: '',
                          suffixIcon: IconButton(
                            icon: Icon(
                              hidePin
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                hidePin = !hidePin;
                              });
                            },
                          ),
                        ),
                      ),
                    ]

                    // ADMINISTRATOR LOGIN
                    else ...[
                      TextField(
                        controller: adminEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Administrator Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 18),

                      TextField(
                        controller: adminPasswordController,
                        obscureText: hideAdminPassword,
                        decoration: InputDecoration(
                          labelText: 'Administrator Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              hideAdminPassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                hideAdminPassword =
                                    !hideAdminPassword;
                              });
                            },
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 26),

                    // LOGIN BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: loading ? null : authenticate,
                        child: loading
                            ? const CircularProgressIndicator()
                            : Text(
                                isAdminLogin
                                    ? 'ADMIN LOGIN'
                                    : 'TEACHER LOGIN',
                              ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      'Statistics Department',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
