import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore
import 'package:provider/provider.dart'; // Import Provider

// Import your state management class (we'll create this)
import '../../providers/app_state.dart';

// Import the next screen (we'll create this)
import 'teacher_home_screen.dart';

// Import the Login screen for logout navigation
import '../login_screen.dart';


class BatchSelectScreen extends StatefulWidget {
  const BatchSelectScreen({super.key});

  @override
  State<BatchSelectScreen> createState() => _BatchSelectScreenState();
}

class _BatchSelectScreenState extends State<BatchSelectScreen> {
  // Stream to listen for batch changes in Firestore
  Stream<QuerySnapshot>? _batchesStream;
  String? _selectedBatchId; // Store the ID (e.g., "2023")
  String? _selectedBatchName; // Store the name (e.g., "2023 Batch")

  @override
  void initState() {
    super.initState();
    // Start listening to the 'batches' collection, ordered by name
    _batchesStream = FirebaseFirestore.instance
        .collection('batches')
        .orderBy('yearName', descending: true) // Show newest first
        .snapshots();
  }

  // Function to handle batch selection
  void _selectBatch(String batchId, String batchName) {
    if (!mounted) return;
    setState(() {
      _selectedBatchId = batchId;
      _selectedBatchName = batchName;
    });
    print("Selected Batch ID: $batchId, Name: $batchName");

    // --- Save the selected batch using Provider ---
    // We use 'listen: false' because we're inside a button press/function
    Provider.of<AppState>(context, listen: false).setSelectedBatch(batchId, batchName);

    // --- Navigate to the TeacherHomeScreen ---
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const TeacherHomeScreen()),
    );
  }

  // Function to handle adding a new batch
  void _addNewBatch() {
    final TextEditingController yearController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Add New Batch Year"),
          content: TextField(
            controller: yearController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: "Enter Year (e.g., 2026)"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text("Add"),
              onPressed: () async {
                final String year = yearController.text.trim();
                if (year.isNotEmpty && year.length == 4 && int.tryParse(year) != null) {
                  // Use the year as the document ID
                  String batchId = year;
                  String batchName = "$year Batch";

                  try {
                    // Check if batch already exists (optional but good)
                    final doc = await FirebaseFirestore.instance.collection('batches').doc(batchId).get();
                    if (doc.exists) {
                       if(mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(content: Text('Batch $year already exists.'), backgroundColor: Colors.orange),
                         );
                       }
                    } else {
                       // Add the new batch to Firestore
                       await FirebaseFirestore.instance.collection('batches').doc(batchId).set({
                         'yearName': batchName,
                         'createdAt': FieldValue.serverTimestamp(), // Optional sort field
                       });
                       if(mounted) Navigator.of(context).pop(); // Close dialog on success
                    }

                  } catch (e) {
                     print("Error adding batch: $e");
                     if(mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(content: Text('Failed to add batch. Error: $e'), backgroundColor: Colors.red),
                       );
                     }
                  }
                } else {
                   // Show error if input is invalid
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text('Please enter a valid 4-digit year.'), backgroundColor: Colors.red),
                   );
                }
              },
            ),
          ],
        );
      },
    );
  }

  // Function to handle logout
  void _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        // Clear selected batch on logout
        Provider.of<AppState>(context, listen: false).clearSelectedBatch();
        // Go back to Login Screen and remove all previous routes
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (Route<dynamic> route) => false, // Remove all routes
        );
      }
    } catch (e) {
      print("Error logging out: $e");
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? 'Teacher';

    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, $userEmail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Please Select Your Batch Year',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // --- StreamBuilder to display batches from Firestore ---
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _batchesStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(child: Text('No batches found. Add one below.'));
                    }

                    // Display list of batches
                    final batches = snapshot.data!.docs;
                    return ListView.builder(
                      itemCount: batches.length,
                      itemBuilder: (context, index) {
                        final batchDoc = batches[index];
                        final batchId = batchDoc.id; // e.g., "2023"
                        final batchName = batchDoc['yearName']; // e.g., "2023 Batch"

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: ElevatedButton(
                            onPressed: () => _selectBatch(batchId, batchName),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              textStyle: const TextStyle(fontSize: 18),
                            ),
                            child: Text(batchName),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              // --- End of StreamBuilder ---

              const SizedBox(height: 20),

              // Add New Batch Button
              TextButton.icon(
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add New Batch Year'),
                onPressed: _addNewBatch,
                 style: TextButton.styleFrom(
                   textStyle: const TextStyle(fontSize: 16),
                 ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}