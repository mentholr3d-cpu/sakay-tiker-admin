import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/admin_dashboard.dart';
import 'screens/admin_login.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<bool> _checkLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('adminLoggedIn') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF1B5E20);
    const accentGreen = Color(0xFF2E7D32);
    const softGreenBg = Color(0xFFEAF5EC);

    return MaterialApp(
      title: 'Sakay Tiker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: primaryColor,
        scaffoldBackgroundColor: softGreenBg,

        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF1B3A22)),
          bodyMedium: TextStyle(color: Color(0xFF1B3A22)),
          titleLarge: TextStyle(color: Color(0xFF1B5E20), fontWeight: FontWeight.bold),
          titleMedium: TextStyle(color: Color(0xFF1B5E20), fontWeight: FontWeight.w600),
        ),

        appBarTheme: AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: primaryColor.withValues(alpha: 0.06),
          foregroundColor: primaryColor,
          titleTextStyle: const TextStyle(
            color: primaryColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: Colors.white,
          selectedIconTheme: const IconThemeData(color: primaryColor),
          selectedLabelTextStyle: const TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
          unselectedIconTheme: const IconThemeData(color: Colors.grey),
          unselectedLabelTextStyle: const TextStyle(color: Colors.grey),
        ),

        segmentedButtonTheme: SegmentedButtonThemeData(
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: primaryColor,
            selectedForegroundColor: Colors.white,
            foregroundColor: primaryColor,
            side: const BorderSide(color: primaryColor, width: 1.4),
          ),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryColor,
            side: const BorderSide(color: primaryColor, width: 1.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: primaryColor),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primaryColor, width: 1.2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primaryColor, width: 1.2),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: accentGreen, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),

        cardTheme: CardThemeData(
          elevation: 3,
          shadowColor: primaryColor.withValues(alpha: 0.25),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),

        dataTableTheme: DataTableThemeData(
          headingRowColor: WidgetStateProperty.all(primaryColor.withValues(alpha: 0.15)),
          headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: primaryColor),
          dataRowColor: WidgetStateProperty.all(Colors.white),
          dividerThickness: 0.6,
        ),

        dividerTheme: const DividerThemeData(color: primaryColor, thickness: 0.4),

        iconTheme: const IconThemeData(color: primaryColor),

        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? primaryColor : Colors.transparent,
          ),
          side: const BorderSide(color: primaryColor, width: 1.5),
        ),

        progressIndicatorTheme: const ProgressIndicatorThemeData(color: primaryColor),

        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1B1B1B),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          behavior: SnackBarBehavior.floating,
          actionTextColor: primaryColor,
        ),
      ),
      home: FutureBuilder<bool>(
        future: _checkLoggedIn(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data! ? const AdminDashboardScreen() : const AdminLoginScreen();
        },
      ),
    );
  }
}