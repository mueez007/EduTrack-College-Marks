import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Simple password hashing utility using SHA-256.
/// Used for admin login verification against a Firestore-stored hash.
///
/// NOTE: This is client-side hashing for a simple admin gate.
/// For production-grade auth, use Firebase Auth email/password accounts.
class PasswordHashService {
  /// Hash a password using SHA-256 with a fixed salt.
  /// The salt prevents rainbow table attacks on simple passwords.
  static String hashPassword(String password) {
    const String salt = 'edutrack_mitm_2024_salt';
    final bytes = utf8.encode('$salt:$password');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify a password against a stored hash.
  static bool verifyPassword(String password, String storedHash) {
    final computedHash = hashPassword(password);
    return computedHash == storedHash;
  }
}
