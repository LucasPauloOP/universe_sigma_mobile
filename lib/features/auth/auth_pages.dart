import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exception.dart';
import '../../core/providers.dart';
import '../../shared/ui.dart';

class _AuthFrame extends StatelessWidget {
  const _AuthFrame({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.emoji_events, size: 56, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 8),
                    Text('Universe Sigma',
                        textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 24),
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null;
String? _validEmail(String? v) =>
    (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) ? 'E-mail inválido' : null;
String? _password(String? v) => (v == null || v.length < 8) ? 'Mínimo de 8 caracteres' : null;

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _hide = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    try {
      await ref.read(authProvider.notifier).login(_email.text.trim(), _pass.text);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = ref.watch(authProvider).message;
    return _AuthFrame(title: 'Entrar', children: [
      if (message != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      Form(
        key: _form,
        child: Column(children: [
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'E-mail'),
            validator: _validEmail,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pass,
            obscureText: _hide,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Senha',
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
            validator: _required,
            onFieldSubmitted: (_) => _submit(),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      BusyButton(label: 'Entrar', icon: Icons.login, onPressed: _submit),
      TextButton(onPressed: () => context.go('/forgot'), child: const Text('Esqueci a senha')),
      TextButton(onPressed: () => context.go('/register'), child: const Text('Criar conta')),
    ]);
  }
}

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});
  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _template = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    try {
      await ref.read(authProvider.notifier).register(
            _email.text.trim(),
            _pass.text,
            name: _name.text.trim(),
            useTemplate: _template,
          );
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthFrame(title: 'Criar conta', children: [
        Form(
          key: _form,
          child: Column(children: [
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nome (opcional)')),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
              validator: _validEmail,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha (mín. 8 caracteres)'),
              validator: _password,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Começar com o universe padrão'),
              subtitle: const Text('Elenco, títulos, shows e episódios prontos'),
              value: _template,
              onChanged: (v) => setState(() => _template = v),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        BusyButton(label: 'Criar conta', icon: Icons.person_add, onPressed: _submit),
        TextButton(onPressed: () => context.go('/login'), child: const Text('Já tenho conta')),
      ]);
}

/// Recuperação de senha atual do backend: confere o e-mail e já define a nova senha
/// (fluxo temporário, sem e-mail — ver authController.js).
class ForgotPage extends ConsumerStatefulWidget {
  const ForgotPage({super.key});
  @override
  ConsumerState<ForgotPage> createState() => _ForgotPageState();
}

class _ForgotPageState extends ConsumerState<ForgotPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _confirmed = false;

  Future<void> _check() async {
    try {
      await ref.read(apiProvider).post('/auth/forgot-password', body: {'email': _email.text.trim()});
      setState(() => _confirmed = true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _reset() async {
    if (_password(_pass.text) != null) return showError(context, 'A senha precisa ter 8 caracteres ou mais.');
    try {
      await ref
          .read(apiProvider)
          .post('/auth/reset-password', body: {'email': _email.text.trim(), 'password': _pass.text});
      if (!mounted) return;
      showInfo(context, 'Senha alterada. Entre com a nova senha.');
      context.go('/login');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthFrame(title: 'Recuperar senha', children: [
        TextField(
          controller: _email,
          enabled: !_confirmed,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-mail'),
        ),
        if (_confirmed) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Nova senha (mín. 8 caracteres)'),
          ),
        ],
        const SizedBox(height: 16),
        BusyButton(
          label: _confirmed ? 'Salvar nova senha' : 'Continuar',
          icon: Icons.lock_reset,
          onPressed: _confirmed ? _reset : _check,
        ),
        TextButton(onPressed: () => context.go('/login'), child: const Text('Voltar')),
      ]);
}
