import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/locale_data.dart';
import '../shell/splash_screen.dart';

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: Theme.of(context).brightness == Brightness.dark ? LBColors.nightGradient : LBColors.softGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: () => context.canPop() ? context.pop() : context.go('/welcome'),
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(child: LovebirdMark(size: 52)),
                    const SizedBox(height: 16),
                    Text(title, style: t.headlineMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    Text(subtitle, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                    const SizedBox(height: 28),
                    ...children,
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _emailValidator(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Enter your email';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return 'That email doesn\'t look right';
  return null;
}

String? _passwordValidator(String? v) {
  final s = v ?? '';
  if (s.length < 10) return 'Use at least 10 characters';
  if (!RegExp(r'[a-z]').hasMatch(s) || !RegExp(r'[A-Z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
    return 'Mix upper & lower case letters and a number';
  }
  return null;
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.controller, this.label = 'Password', this.validator, this.newPassword = false, this.onSubmit});
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final bool newPassword;
  final VoidCallback? onSubmit;
  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        obscureText: _obscure,
        validator: widget.validator,
        autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => widget.onSubmit?.call(),
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: IconButton(
            tooltip: _obscure ? 'Show password' : 'Hide password',
            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await sb.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      // Router redirect takes it from here.
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
        title: 'Welcome back',
        subtitle: 'Your person is waiting ❤️',
        children: [
          Form(
            key: _form,
            child: Column(children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                validator: _emailValidator,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 14),
              _PasswordField(controller: _password, validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null, onSubmit: _submit),
            ]),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => context.push('/reset'), child: const Text('Forgot password?')),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)) : const Text('Sign in'),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: () => context.go('/sign-up'), child: const Text('New here? Create an account')),
        ],
      );
}

// ---------------------------------------------------------------------------

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  DateTime? _dob;
  String _country = 'NG';
  bool _agreed = false;
  bool _busy = false;
  bool _sent = false;

  bool get _isAdult {
    if (_dob == null) return false;
    final now = DateTime.now();
    final eighteen = DateTime(now.year - 18, now.month, now.day);
    return !_dob!.isAfter(eighteen);
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Your date of birth',
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_dob == null) return showToast(context, 'Please add your date of birth.');
    if (!_isAdult) return showToast(context, 'Lovebird is for adults aged 18 and over.');
    if (!_agreed) return showToast(context, 'Please agree to the Terms and Privacy Policy.');
    setState(() => _busy = true);
    try {
      final res = await sb.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        emailRedirectTo: AppConfig.authRedirect,
        data: {
          'display_name': _name.text.trim(),
          'date_of_birth': DateFormat('yyyy-MM-dd').format(_dob!),
          'country_code': _country,
          'currency_code': currencyForCountry(_country),
        },
      );
      if (res.session == null && mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return _AuthScaffold(
        title: 'Check your inbox 💌',
        subtitle: 'We sent a confirmation link to ${_email.text.trim()}. Tap it, then come back and sign in.',
        children: [FilledButton(onPressed: () => context.go('/sign-in'), child: const Text('Go to sign in'))],
      );
    }
    final t = Theme.of(context).textTheme;
    return _AuthScaffold(
      title: 'Create your account',
      subtitle: 'Then invite your person into your private world.',
      children: [
        Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.givenName],
              textInputAction: TextInputAction.next,
              maxLength: 40,
              validator: (v) => (v ?? '').trim().isEmpty ? 'What should your partner call you?' : null,
              decoration: const InputDecoration(labelText: 'Display name', counterText: ''),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              validator: _emailValidator,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 14),
            _PasswordField(controller: _password, validator: _passwordValidator, newPassword: true),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickDob,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date of birth', suffixIcon: Icon(Icons.cake_outlined)),
                child: Text(_dob == null ? 'Select' : DateFormat.yMMMd().format(_dob!)),
              ),
            ),
            if (_dob != null && !_isAdult)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text('Lovebird is for adults aged 18 and over.', style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _country,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Country'),
              items: [for (final c in countries) DropdownMenuItem(value: c.$1, child: Text(c.$2))],
              onChanged: (v) => setState(() => _country = v ?? 'NG'),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('I\'m 18+ and agree to the Terms and Privacy Policy', style: t.bodyMedium),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)) : const Text('Create account'),
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: () => context.go('/sign-in'), child: const Text('Already have an account? Sign in')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await sb.auth.resetPasswordForEmail(_email.text.trim(), redirectTo: AppConfig.authRedirect);
      // Always show success, whether or not the email exists (no account enumeration).
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
        title: _sent ? 'Check your inbox' : 'Reset your password',
        subtitle: _sent
            ? 'If an account exists for that email, a reset link is on its way.'
            : 'We\'ll email you a link to choose a new one.',
        children: _sent
            ? [FilledButton(onPressed: () => context.go('/sign-in'), child: const Text('Back to sign in'))]
            : [
                Form(
                  key: _form,
                  child: TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: _emailValidator,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _submit, child: const Text('Send reset link')),
              ],
      );
}

class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});
  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await sb.auth.updateUser(UserAttributes(password: _password.text));
      if (mounted) {
        showToast(context, 'Password updated ❤️');
        context.go('/home');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
        title: 'Choose a new password',
        subtitle: 'Make it strong — your world is in here.',
        children: [
          Form(key: _form, child: _PasswordField(controller: _password, label: 'New password', validator: _passwordValidator, newPassword: true, onSubmit: _submit)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _submit, child: const Text('Save password')),
        ],
      );
}
