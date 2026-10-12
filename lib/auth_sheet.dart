import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'google_auth.dart';
import 'session.dart';
import 'signup.dart';
import 'signup_api.dart';
import 'turnstile_field.dart';

const _ink = Color(0xFF1B2340);
const _muted = Color(0xFF8E97A8);
const _accent = Color(0xFF4C6FFF);
const _accentEnd = Color(0xFF9B6DFF);
const _line = Color(0xFFE4E8F0);
const _errorColor = Color(0xFFD14343);

/// Login keeps a Turnstile token for POST /api/v1/auth/token/.
/// Sign up does not send one.
Future<void> showAuthSheet(BuildContext context, {required bool signUp}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final topInset = MediaQuery.paddingOf(context).top + 64;
      return Padding(
        padding: EdgeInsets.only(top: topInset),
        child: AuthSheet(signUp: signUp),
      );
    },
  );
}

class AuthSheet extends StatefulWidget {
  const AuthSheet({super.key, required this.signUp});

  final bool signUp;

  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<AuthSheet> {
  late bool _signUp = widget.signUp;
  bool _obscurePassword = true;
  bool _promotionalEmails = false;
  bool _verifying = false;
  bool _busy = false;
  bool _emailTouched = false;
  String? _error;
  Map<String, String> _fieldErrors = {};
  String? _turnstileToken;
  int _turnstileGeneration = 0;

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _referral = TextEditingController();
  final _emailFocus = FocusNode();
  final _digits = List.generate(4, (_) => TextEditingController());
  final _digitFocus = List.generate(4, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    _firstName.addListener(() => _onFieldEdited('first_name'));
    _lastName.addListener(() => _onFieldEdited('last_name'));
    _email.addListener(() => _onFieldEdited('email'));
    _password.addListener(() => _onFieldEdited('password'));
    _emailFocus.addListener(_onEmailFocus);
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onFieldEdited(String key) {
    if (_fieldErrors.containsKey(key)) {
      _fieldErrors.remove(key);
    }
    _refresh();
  }

  void _onEmailFocus() {
    if (!_emailFocus.hasFocus && _email.text.trim().isNotEmpty) {
      _emailTouched = true;
    }
    _refresh();
  }

  String? get _emailError {
    final invalid =
        _emailTouched &&
        !_emailFocus.hasFocus &&
        _email.text.trim().isNotEmpty &&
        !signupEmailLooksValid(_email.text);
    if (invalid) {
      return 'Enter a valid email.';
    }
    return _fieldErrors['email'];
  }

  void _applyFailure(SignupFailure error) {
    final banner = <String>[
      if (error.message.isNotEmpty) error.message,
      if (_verifying) ...error.fields.values.where((text) => text.isNotEmpty),
    ];
    _busy = false;
    _error = banner.isEmpty ? null : banner.join(' ');
    _fieldErrors = _verifying ? {} : Map<String, String>.from(error.fields);
  }

  @override
  void dispose() {
    _emailFocus.removeListener(_onEmailFocus);
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _emailFocus.dispose();
    _password.dispose();
    _referral.dispose();
    for (final controller in _digits) {
      controller.dispose();
    }
    for (final node in _digitFocus) {
      node.dispose();
    }
    super.dispose();
  }

  bool get _canSignUp {
    return _firstName.text.trim().isNotEmpty &&
        signupEmailLooksValid(_email.text) &&
        passwordMeetsRules(_password.text);
  }

  bool get _canLogIn {
    return signupEmailLooksValid(_email.text) && _password.text.isNotEmpty;
  }

  String get _enteredCode => _digits.map((digit) => digit.text).join();

  Future<void> _submitSignup() async {
    if (!_canSignUp || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = {};
    });
    try {
      await startSignup(
        firstName: _firstName.text,
        lastName: _lastName.text,
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _verifying = true;
      });
    } on SignupFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _applyFailure(error));
    }
  }

  Future<void> _submitGoogle() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = {};
    });
    try {
      final session = await signInWithGoogle();
      if (!mounted) {
        return;
      }
      if (session == null) {
        setState(() => _busy = false);
        return;
      }
      await AppSession.instance.signIn(
        displayName: session.displayName.isEmpty
            ? 'Google'
            : session.displayName,
        accessToken: session.access,
        refreshToken: session.refresh,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).maybePop();
    } on SignupFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _applyFailure(error));
    }
  }

  Future<void> _submitLogin() async {
    if (!_canLogIn || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = {};
    });
    try {
      final tokens = await logIn(
        email: _email.text,
        password: _password.text,
        turnstileToken: _turnstileToken,
      );
      final name = await currentDisplayName(tokens.access);
      if (!mounted) {
        return;
      }
      await AppSession.instance.signIn(
        displayName: name.isEmpty ? _email.text.trim() : name,
        accessToken: tokens.access,
        refreshToken: tokens.refresh,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).maybePop();
    } on SignupFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _applyFailure(error);
        if (error.message.toLowerCase().contains('human verification')) {
          _turnstileToken = null;
          _turnstileGeneration += 1;
        }
      });
    }
  }

  Future<void> _resend() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await resendSignupCode(_email.text);
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
    } on SignupFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _applyFailure(error));
    }
  }

  Future<void> _confirm() async {
    if (_enteredCode.length != 4 || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tokens = await confirmSignup(
        email: _email.text,
        code: _enteredCode,
      );
      if (!mounted) {
        return;
      }
      await AppSession.instance.signIn(
        displayName: signupDisplayName(_firstName.text, _lastName.text),
        accessToken: tokens.access,
        refreshToken: tokens.refresh,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).maybePop();
    } on SignupFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _applyFailure(error));
    }
  }

  void _onDigit(int index, String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      for (var offset = 0; offset < 4; offset += 1) {
        final source = index + offset;
        _digits[offset].text = source < digits.length ? digits[source] : '';
      }
      final next = digits.length >= 4 ? 3 : digits.length;
      _digitFocus[next].requestFocus();
    } else {
      _digits[index].text = digits;
      if (digits.isNotEmpty && index < 3) {
        _digitFocus[index + 1].requestFocus();
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final navBar = MediaQueryData.fromView(View.of(context)).viewPadding.bottom;
    final bottomInset = keyboard > navBar ? keyboard : navBar;
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          children: [
            const _SheetHeader(),
            if (_verifying)
              Expanded(child: _verificationBody())
            else ...[
              _AuthTabs(
                signUp: _signUp,
                onSelect: (signUp) => setState(() {
                  _signUp = signUp;
                  if (signUp) {
                    _turnstileToken = null;
                  }
                }),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  children: [
                    _ProviderDivider(
                      label: _signUp ? 'Sign up with' : 'Log in with',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _SocialButton(
                            mark: 'G',
                            label: 'Google',
                            onTap: _busy ? null : _submitGoogle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: _SocialButton(mark: 'f', label: 'Facebook'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_signUp) ...[
                      _SheetField(
                        controller: _firstName,
                        hint: 'First name',
                        error: _fieldErrors['first_name'],
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      _SheetField(
                        controller: _lastName,
                        hint: 'Last name (Optional)',
                        error: _fieldErrors['last_name'],
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _SheetField(
                      controller: _email,
                      hint: 'Email',
                      error: _emailError,
                      focusNode: _emailFocus,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    _SheetField(
                      controller: _password,
                      hint: 'Password',
                      error: _fieldErrors['password'],
                      obscure: _obscurePassword,
                      onToggleObscure: () => setState(() {
                        _obscurePassword = !_obscurePassword;
                      }),
                    ),
                    if (_signUp && _password.text.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _PasswordRulesView(password: _password.text),
                      const SizedBox(height: 12),
                    ],
                    if (_signUp) ...[
                      _SheetField(
                        controller: _referral,
                        hint: 'Referral or voucher code',
                      ),
                      const SizedBox(height: 16),
                      _PromoCheckbox(
                        value: _promotionalEmails,
                        onChanged: (value) => setState(() {
                          _promotionalEmails = value;
                        }),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: _UnderlinedLabel('Forgot password'),
                      ),
                      const SizedBox(height: 16),
                      TurnstileField(
                        key: ValueKey('login-$_turnstileGeneration'),
                        onToken: (token) => setState(() {
                          _turnstileToken = token;
                        }),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: _ink)),
                    ],
                    const SizedBox(height: 20),
                    _SubmitPill(
                      label: _signUp ? 'Agree and sign up' : 'Log in',
                      enabled: _signUp
                          ? _canSignUp && !_busy
                          : _canLogIn && !_busy,
                      onTap: _signUp
                          ? (_canSignUp && !_busy ? _submitSignup : null)
                          : (_canLogIn && !_busy ? _submitLogin : null),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: _UnderlinedLabel(
                        _signUp ? 'Continue with SSO' : 'Log in with SSO',
                      ),
                    ),
                    if (_signUp) ...[
                      const SizedBox(height: 18),
                      const _TermsNotice(),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _verificationBody() {
    final complete = _enteredCode.length == 4;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const Text(
          'Enter verification code',
          style: TextStyle(
            color: _ink,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Check your email for the next step.',
          style: TextStyle(color: _ink, fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < 4; index += 1) ...[
              if (index > 0) const SizedBox(width: 10),
              _DigitBox(
                controller: _digits[index],
                focusNode: _digitFocus[index],
                onChanged: (value) => _onDigit(index, value),
              ),
            ],
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: _ink)),
        ],
        const SizedBox(height: 22),
        const Text(
          'If the email says you already have an account, return to Log in.',
          style: TextStyle(color: _muted, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 16),
        Center(
          child: _OutlinePill(
            label: 'Resend code',
            onTap: _busy ? null : _resend,
          ),
        ),
        const SizedBox(height: 16),
        _SubmitPill(
          label: 'Continue',
          enabled: complete && !_busy,
          onTap: complete && !_busy ? _confirm : null,
        ),
      ],
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 10, bottom: 6),
      child: Center(
        child: SizedBox(
          width: 36,
          height: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFD5DBE8),
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthTabs extends StatelessWidget {
  const _AuthTabs({required this.signUp, required this.onSelect});

  final bool signUp;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AuthTab(
              label: 'Log in',
              selected: !signUp,
              onTap: () => onSelect(false),
            ),
          ),
          Expanded(
            child: _AuthTab(
              label: 'Sign up',
              selected: signUp,
              onTap: () => onSelect(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthTab extends StatelessWidget {
  const _AuthTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: selected ? _ink : _muted,
              fontSize: 16,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 3,
            width: selected ? 72 : 0,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(colors: [_accent, _accentEnd]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderDivider extends StatelessWidget {
  const _ProviderDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: _line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Expanded(child: Divider(color: _line)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.mark, required this.label, this.onTap});

  final String mark;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          shape: const StadiumBorder(side: BorderSide(color: _line)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  mark,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.onToggleObscure,
    this.error,
    this.focusNode,
    this.keyboardType,
    this.autocorrect = true,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final String? error;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      autocorrect: autocorrect,
      textInputAction: textInputAction,
      obscureText: obscure,
      style: const TextStyle(color: _ink, fontSize: 15),
      cursorColor: _accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _muted, fontSize: 15),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        errorText: error,
        errorMaxLines: 4,
        errorStyle: const TextStyle(color: _errorColor, fontSize: 13),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: _muted,
                ),
              ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _errorColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _errorColor, width: 1.5),
        ),
      ),
    );
  }
}

class _PromoCheckbox extends StatelessWidget {
  const _PromoCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: value ? _accent : Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: value ? _accent : _muted),
            ),
            child: value
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "I'd like to receive promotional emails.",
              style: TextStyle(color: _ink, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmitPill extends StatelessWidget {
  const _SubmitPill({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? _accent : Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: enabled ? null : Border.all(color: _line),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: enabled ? Colors.white : _muted,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlinePill extends StatelessWidget {
  const _OutlinePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(side: BorderSide(color: _line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          child: Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _DigitBox extends StatelessWidget {
  const _DigitBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
          color: _ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        cursorColor: _accent,
        onChanged: onChanged,
        decoration: InputDecoration(
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _accent, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _PasswordRulesView extends StatelessWidget {
  const _PasswordRulesView({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final rule in passwordRules(password))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  rule.met ? Icons.check : Icons.close,
                  size: 16,
                  color: rule.met ? _accent : _muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rule.label,
                    style: TextStyle(
                      color: rule.met ? _accent : _muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _UnderlinedLabel extends StatelessWidget {
  const _UnderlinedLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: _ink,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        decoration: TextDecoration.underline,
      ),
    );
  }
}

class _TermsNotice extends StatelessWidget {
  const _TermsNotice();

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(color: _muted, fontSize: 13, height: 1.4);
    const link = TextStyle(
      color: _ink,
      fontSize: 13,
      height: 1.4,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    return const Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(
            text: 'By signing up for a RoamKit account, I agree to the ',
          ),
          TextSpan(text: 'Terms and conditions', style: link),
          TextSpan(
            text: '. Learn more about how we use and protect your data in our ',
          ),
          TextSpan(text: 'Privacy policy', style: link),
          TextSpan(text: '.'),
        ],
      ),
    );
  }
}
