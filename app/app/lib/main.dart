import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Import Firebase Core
import 'firebase_options.dart'; // Import the generated Firebase options
import 'package:provider/provider.dart';
import 'providers/app_state.dart'; // Import your AppState

// Import your future login screen
import 'screens/login_screen.dart'; // We will create this next

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Wrap MyApp with ChangeNotifierProvider
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(), // Create an instance of AppState
      child: const MyApp(),
    ),
  );
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'College Marks App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), // Modern theme
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // Set the home screen to your login screen
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false, // Hide debug banner
    );
  }
}