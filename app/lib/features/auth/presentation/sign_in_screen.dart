import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/auth/presentation/auth_controller.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final state = ref.watch(authControllerProvider);
    final canUseGoogle = ref.watch(firebaseServiceProvider).isAvailable;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(LdSpacing.s5),
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) => (value == null || !value.contains('@'))
                    ? 'Enter a valid email address'
                    : null,
              ),
              const SizedBox(height: LdSpacing.s4),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Enter your password'
                    : null,
              ),
              const SizedBox(height: LdSpacing.s5),
              LdPrimaryButton(
                label: 'Sign in',
                size: LdButtonSize.l,
                loading: state.isLoading,
                onPressed: _submit,
              ),
              const SizedBox(height: LdSpacing.s3),
              LdPrimaryButton(
                label: 'Forgot password',
                variant: LdButtonVariant.ghost,
                onPressed: state.isLoading ? null : _reset,
              ),
              if (canUseGoogle) ...[
                const SizedBox(height: LdSpacing.s5),
                Row(
                  children: [
                    Expanded(child: Divider(color: c.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LdSpacing.s3,
                      ),
                      child: Text(
                        'OR',
                        style: type.labelMono.copyWith(color: c.textTertiary),
                      ),
                    ),
                    Expanded(child: Divider(color: c.border)),
                  ],
                ),
                const SizedBox(height: LdSpacing.s5),
                LdPrimaryButton(
                  label: 'Continue with Google',
                  size: LdButtonSize.l,
                  variant: LdButtonVariant.secondary,
                  icon: Icons.g_mobiledata_rounded,
                  loading: state.isLoading,
                  onPressed: _google,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final failure = await ref
        .read(authControllerProvider.notifier)
        .signIn(email: _email.text, password: _password.text);
    if (failure != null && mounted) showFailureSnack(context, failure);
  }

  Future<void> _google() async {
    final failure = await ref
        .read(authControllerProvider.notifier)
        .signInWithGoogle();
    if (failure != null && mounted) showFailureSnack(context, failure);
  }

  Future<void> _reset() async {
    if (_email.text.isEmpty || !_email.text.contains('@')) {
      showSuccessSnack(context, 'Enter your email address first.');
      return;
    }
    final failure = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordReset(_email.text);
    if (!mounted) return;
    if (failure != null) {
      showFailureSnack(context, failure);
    } else {
      showSuccessSnack(context, 'Password reset email sent.');
    }
  }
}
