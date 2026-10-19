import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_panel.dart';

/// 登录页。按原型的弹窗面板布局：云端 / 本地两种登录。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController(text: '张三');
  final _pass = TextEditingController(text: '1234');
  final _localPass = TextEditingController(text: '1234');
  String _localRole = '采集员';
  bool _local = false;
  String? _error;

  static const _roles = {'张三': '工程师', '李四': '采集员'};

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _localPass.dispose();
    super.dispose();
  }

  void _next(String role) {
    final next = role == '工程师' ? Routes.home : Routes.tasks;
    Navigator.pushNamedAndRemoveUntil(context, next, (route) => false);
  }

  void _cloudLogin() {
    final name = _user.text.trim();
    final role = _roles[name];

    if (role == null || _pass.text != '1234') {
      setState(() => _error = '账号或密码不对');
      return;
    }

    appState.userName = name;
    appState.role = role;
    _next(role);
  }

  void _localLogin() {
    if (_localPass.text != '1234') {
      setState(() => _error = '密码不对');
      return;
    }

    final name = _localRole == '工程师' ? '张三' : '李四';
    appState.userName = name;
    appState.role = _localRole;
    _next(_localRole);
  }

  void _close() {
    Navigator.maybePop(context);
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppColors.input,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.brand),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppColors.muted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AppPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '登录',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        AppButton(
                          '关闭',
                          kind: AppButtonKind.secondary,
                          onPressed: _close,
                          height: 32,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _local
                          ? '现场没网：选择角色并输入本地密码登录。'
                          : '有网：用云端账号和密码登录，登录后拉取该账号任务。',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            '云端登录',
                            kind: _local
                                ? AppButtonKind.secondary
                                : AppButtonKind.primary,
                            onPressed: () => setState(() {
                              _local = false;
                              _error = null;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppButton(
                            '本地登录',
                            kind: _local
                                ? AppButtonKind.primary
                                : AppButtonKind.secondary,
                            onPressed: () => setState(() {
                              _local = true;
                              _error = null;
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!_local) ...[
                      _label('账号'),
                      TextField(
                        key: const Key('loginUser'),
                        controller: _user,
                        style: const TextStyle(color: AppColors.ink),
                        decoration: _decoration('云端账号'),
                      ),
                      const SizedBox(height: 10),
                      _label('密码'),
                      TextField(
                        key: const Key('loginPass'),
                        controller: _pass,
                        obscureText: true,
                        style: const TextStyle(color: AppColors.ink),
                        decoration: _decoration('密码'),
                        onSubmitted: (_) => _cloudLogin(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.badInk,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      AppButton(
                        '登录',
                        key: const Key('loginButton'),
                        onPressed: _cloudLogin,
                        height: 44,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '原型：张三 / 1234 为工程师，可看本机数据；李四 / 1234 为采集员，只看自己的任务。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ] else ...[
                      _label('角色'),
                      RadioGroup<String>(
                        groupValue: _localRole,
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _localRole = value);
                          }
                        },
                        child: Row(
                          children: [
                            _roleRadio('工程师'),
                            const SizedBox(width: 18),
                            _roleRadio('采集员'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _label('密码'),
                      TextField(
                        key: const Key('localPass'),
                        controller: _localPass,
                        obscureText: true,
                        style: const TextStyle(color: AppColors.ink),
                        decoration: _decoration('本地登录密码'),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.badInk,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      AppButton(
                        '登录',
                        key: const Key('localLoginButton'),
                        onPressed: _localLogin,
                        height: 44,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleRadio(String role) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(value: role),
        Text(role, style: const TextStyle(fontSize: 14, color: AppColors.ink)),
      ],
    );
  }
}
