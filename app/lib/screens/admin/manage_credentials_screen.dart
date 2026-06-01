import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../config/department_config.dart';
import '../../services/firestore_helper.dart';

class ManageCredentialsScreen extends StatefulWidget {
  const ManageCredentialsScreen({super.key});

  @override
  State<ManageCredentialsScreen> createState() =>
      _ManageCredentialsScreenState();
}

class _ManageCredentialsScreenState extends State<ManageCredentialsScreen> {
  String? _selectedDepartmentId;

  @override
  void initState() {
    super.initState();
    if (DepartmentConfig.departments.isNotEmpty) {
      _selectedDepartmentId = DepartmentConfig.departments.first.id;
    }
  }

  void _addCredential() {
    if (_selectedDepartmentId == null) return;

    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;
    bool obscurePassword = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Add Teacher for ${DepartmentConfig.getById(_selectedDepartmentId!)?.name ?? _selectedDepartmentId}',
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Teacher Email',
                        hintText: 'e.g., teacher@college.com',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Email is required';
                        }
                        if (!value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Min 6 characters',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password is required';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This will create a Firebase Auth account and register the teacher for this department.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSaving = true);

                          final email = emailController.text.trim();
                          final password = passwordController.text;

                          try {
                            // Check for duplicates in this department
                            final existing = await FirestoreHelper
                                .deptCollection(
                                    _selectedDepartmentId!, 'teacher_credentials')
                                .where('email', isEqualTo: email)
                                .limit(1)
                                .get();

                            if (existing.docs.isNotEmpty) {
                              setDialogState(() => isSaving = false);
                              if (!dialogContext.mounted) return;
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '$email is already registered for this department.',
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }

                            // Also check if this email is registered in another department
                            // and warn the admin (but still allow it — a teacher CAN teach
                            // in multiple departments)
                            String? existingDeptName;
                            for (final dept in DepartmentConfig.departments) {
                              if (dept.id == _selectedDepartmentId) continue;
                              try {
                                final otherQuery = await FirestoreHelper
                                    .deptCollection(dept.id, 'teacher_credentials')
                                    .where('email', isEqualTo: email)
                                    .limit(1)
                                    .get();
                                if (otherQuery.docs.isNotEmpty) {
                                  existingDeptName = dept.name;
                                  break;
                                }
                              } catch (_) {}
                            }

                            // Create Firebase Auth account for the teacher
                            String? newUid;
                            try {
                              final userCredential = await FirebaseAuth.instance
                                  .createUserWithEmailAndPassword(
                                email: email,
                                password: password,
                              );
                              newUid = userCredential.user!.uid;

                              // Sign out the newly created user immediately
                              await FirebaseAuth.instance.signOut();

                              // Re-authenticate as admin (anonymous) BEFORE writing docs
                              await FirebaseAuth.instance.signInAnonymously();

                              // NOW write the users doc with faculty role (as admin)
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(newUid)
                                  .set({
                                'role': 'faculty',
                                'email': email,
                                'departmentId': _selectedDepartmentId,
                                'createdAt': FieldValue.serverTimestamp(),
                              });
                            } on FirebaseAuthException catch (authErr) {
                              if (authErr.code == 'email-already-in-use') {
                                // Account already exists in Firebase Auth.
                                // Try signing in to get the existing UID.
                                debugPrint('Auth account already exists for $email, retrieving UID.');
                                try {
                                  final existingCred = await FirebaseAuth.instance
                                      .signInWithEmailAndPassword(
                                    email: email,
                                    password: password,
                                  );
                                  newUid = existingCred.user!.uid;
                                  await FirebaseAuth.instance.signOut();
                                  await FirebaseAuth.instance.signInAnonymously();
                                } catch (signInErr) {
                                  debugPrint('Could not sign in as existing user: $signInErr');
                                  // Password might differ — proceed without UID
                                  if (FirebaseAuth.instance.currentUser == null) {
                                    await FirebaseAuth.instance.signInAnonymously();
                                  }
                                }
                              } else {
                                rethrow;
                              }
                            }

                            // Add to department's teacher_credentials
                            await FirestoreHelper.deptCollection(
                              _selectedDepartmentId!,
                              'teacher_credentials',
                            ).add({
                              'email': email,
                              'uid': newUid,
                              'departmentId': _selectedDepartmentId,
                              'createdAt': FieldValue.serverTimestamp(),
                            });

                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (mounted) {
                              final msg = existingDeptName != null
                                  ? '$email added. Note: This email is also registered in "$existingDeptName".'
                                  : '$email added with login credentials.';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(msg),
                                  backgroundColor: existingDeptName != null ? Colors.orange : Colors.green,
                                  duration: Duration(seconds: existingDeptName != null ? 5 : 3),
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            // Re-authenticate as admin if needed
                            try {
                              if (FirebaseAuth.instance.currentUser == null) {
                                await FirebaseAuth.instance.signInAnonymously();
                              }
                            } catch (_) {}
                            if (!dialogContext.mounted) return;
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create & Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteCredential(String docId, String email) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove Teacher?'),
          content: Text(
            'Remove $email from ${DepartmentConfig.getById(_selectedDepartmentId!)?.name ?? _selectedDepartmentId}?\n\nThis will prevent them from logging into this department.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                try {
                  await FirestoreHelper.deptCollection(
                    _selectedDepartmentId!,
                    'teacher_credentials',
                  ).doc(docId).delete();

                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$email removed.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Remove',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Teacher Credentials'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Department Selector
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedDepartmentId,
              decoration: const InputDecoration(
                labelText: 'Select Department',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              items: DepartmentConfig.departments.map((dept) {
                return DropdownMenuItem<String>(
                  value: dept.id,
                  child: Text(dept.name),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDepartmentId = value;
                });
              },
            ),
          ),
          const Divider(),

          // Credentials List
          if (_selectedDepartmentId != null)
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirestoreHelper.deptCollection(
                  _selectedDepartmentId!,
                  'teacher_credentials',
                ).orderBy('createdAt', descending: true).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                        child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off,
                                size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              'No teachers registered for ${DepartmentConfig.getById(_selectedDepartmentId!)?.name ?? _selectedDepartmentId}.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Tap + to add a teacher.',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final docs = snapshot.data!.docs;
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final email = data['email'] ?? 'Unknown';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title: Text(email),
                          subtitle: Text(
                            'Department: ${DepartmentConfig.getById(_selectedDepartmentId!)?.name ?? _selectedDepartmentId}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                _deleteCredential(doc.id, email),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCredential,
        tooltip: 'Add Teacher',
        child: const Icon(Icons.add),
      ),
    );
  }
}
