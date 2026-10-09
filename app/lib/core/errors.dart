import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns any error into a short, kind sentence (brief §48).
/// Server-side RPCs raise human-readable messages; we pass those through.
String friendlyError(Object error) {
  if (kDebugMode) debugPrint('Lovebird error: $error');

  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login')) return 'That email and password don\'t match.';
    if (m.contains('email not confirmed')) return 'Please confirm your email first — check your inbox.';
    if (m.contains('already registered')) return 'An account with this email already exists.';
    if (m.contains('password')) return error.message;
    if (m.contains('email rate limit')) {
      return 'Lovebird can\'t send sign-up emails right now (hourly limit reached). Please try again later.';
    }
    if (m.contains('rate limit')) return 'Too many tries. Please wait a minute.';
    if (m.contains('jwt') || m.contains('session')) return 'Your session expired. Please sign in again.';
    return error.message;
  }
  if (error is PostgrestException) {
    switch (error.code) {
      case '42501':
        return error.message.contains('row-level security')
            ? 'You don\'t have access to that.'
            : error.message;
      case '23505':
      case '22023':
      case '23514':
      case '54000':
      case 'P0002':
        return error.message;
      case 'PGRST301':
        return 'Your session expired. Please sign in again.';
    }
    if (error.message.contains('Lovebird is for adults')) return error.message;
    return 'Something went wrong. Please try again.';
  }
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] is String) return details['error'] as String;
    return 'Something went wrong. Please try again.';
  }
  if (error is StorageException) {
    if (error.statusCode == '413') return 'That file is too large.';
    return 'Upload failed. Check your connection and try again.';
  }
  if (error is TimeoutException) return 'This is taking too long. Check your connection.';
  final s = error.toString();
  if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException')) {
    return 'You\'re offline. Check your connection and try again.';
  }
  return 'Something went wrong. Please try again.';
}

void showError(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(friendlyError(error))));
}

void showToast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Runs [action], showing a friendly error on failure. Returns null if it failed.
Future<T?> guard<T>(BuildContext context, Future<T> Function() action) async {
  try {
    return await action();
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}
