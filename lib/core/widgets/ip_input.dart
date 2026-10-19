import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// 四段式 IP 输入框。
///
/// 控制器和焦点由组件自己管理，父页面只需要关心：
/// - onChanged：完整 IP 变了
/// - onSubmitted：最后一段按了回车
class IpInput extends StatefulWidget {
  const IpInput({
    super.key,
    required this.initialIp,
    required this.enabled,
    required this.onChanged,
    this.onSubmitted,
  });

  /// 只在组件第一次创建时使用；之后父页面再改这个值不会刷新输入框。
  final String initialIp;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;

  @override
  State<IpInput> createState() => _IpInputState();
}

class _IpInputState extends State<IpInput> {
  late final List<TextEditingController> _controllers;
  final List<FocusNode> _focus = List.generate(4, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    final parts = widget.initialIp.split('.');
    _controllers = List.generate(
      4,
      (index) =>
          TextEditingController(text: index < parts.length ? parts[index] : ''),
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  String get _ip => _controllers.map((controller) => controller.text).join('.');

  void _onChanged(int index, String value) {
    widget.onChanged(_ip);

    // 输满 3 位自动跳到下一段。
    if (value.length == 3 && index < 3) {
      _focus[index + 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('.', style: TextStyle(color: AppColors.muted)),
            ),
          Expanded(child: _field(i)),
        ],
      ],
    );
  }

  Widget _field(int index) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.line),
    );

    return SizedBox(
      height: 40,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focus[index],
        enabled: widget.enabled,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        textInputAction: index == 3
            ? TextInputAction.done
            : TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        style: const TextStyle(fontSize: 14, color: AppColors.ink),
        onChanged: (value) => _onChanged(index, value),
        onSubmitted: index == 3
            ? (_) {
                widget.onSubmitted?.call();
              }
            : null,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.input,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
          enabledBorder: border,
          disabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: AppColors.brand),
          ),
        ),
      ),
    );
  }
}
