import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 原型（端侧采集平板.html）里的调色板，逐项对应 CSS 变量。
abstract final class C {
  static const bg = Color(0xff0e1622);
  static const panel = Color(0xff182433);
  static const panel2 = Color(0xff203044);
  static const line = Color(0xff2c4158);
  static const ink = Color(0xffe7eef6);
  static const muted = Color(0xff8ea2b8);
  static const brand = Color(0xff3b82c4);
  static const ok = Color(0xff2f9e62);
  static const bad = Color(0xffd4544a);
  static const warn = Color(0xffd39a3a);
  static const input = Color(0xff101924);
  static const topBar = Color(0xff121c2a);
  static const log = Color(0xff0a1118);
  static const softInk = Color(0xffd5e2ef);
  static const legendInk = Color(0xffb7c8da);
}

ThemeData taviTheme() {
  const scheme = ColorScheme.dark(
    primary: C.brand,
    onPrimary: Colors.white,
    secondary: C.ok,
    surface: C.panel,
    onSurface: C.ink,
    error: C.bad,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.panel,
    fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei'],
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 16, color: C.ink),
      bodyMedium: TextStyle(fontSize: 15, color: C.ink),
      bodySmall: TextStyle(fontSize: 14, color: C.muted),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: C.input,
      hintStyle: TextStyle(color: C.muted, fontSize: 16),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: C.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: C.brand),
      ),
    ),
  );
}

TextStyle tStyle({
  double size = 15,
  Color color = C.ink,
  FontWeight weight = FontWeight.w400,
  double height = 1.5,
}) =>
    TextStyle(fontSize: size, color: color, fontWeight: weight, height: height);

/// 面板：bg panel + 1px line + 12 圆角。
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.color = C.panel,
    this.border = C.line,
    this.radius = 12,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color border;
  final double radius;
  final bool clip;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(radius),
    ),
    clipBehavior: clip ? Clip.antiAlias : Clip.none,
    child: child,
  );
}

enum BtnKind { primary, ghost, ok, bad, danger }

class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = BtnKind.primary,
    this.height = 40,
    this.fontSize = 16,
    this.block = false,
    this.minWidth = 0,
  });

  final String label;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final double height;
  final double fontSize;
  final bool block;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => (C.brand, Colors.white, Colors.transparent),
      BtnKind.ok => (C.ok, Colors.white, Colors.transparent),
      BtnKind.bad => (C.bad, Colors.white, Colors.transparent),
      BtnKind.ghost => (Colors.transparent, C.ink, C.line),
      BtnKind.danger => (Colors.transparent, C.bad, C.bad),
    };
    final button = Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: height,
            constraints: BoxConstraints(minWidth: minWidth),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: fontSize, color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return block ? SizedBox(width: double.infinity, child: button) : button;
  }
}

enum PillKind { plain, run, fix, done }

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.kind = PillKind.plain});

  final String text;
  final PillKind kind;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (kind) {
      PillKind.run => (const Color(0xff1d3d31), const Color(0xff8ddeaf)),
      PillKind.fix => (const Color(0xff43361d), const Color(0xffefd09a)),
      PillKind.done => (const Color(0xff2a3d55), const Color(0xffa8c8e8)),
      PillKind.plain => (const Color(0xff24384e), C.legendInk),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text, style: TextStyle(fontSize: 14, color: fg)),
    );
  }
}

enum ChipTone { ok, bad, warn }

class StatusChip extends StatelessWidget {
  const StatusChip(this.text, {super.key, this.tone = ChipTone.ok});

  final String text;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, border, dot) = switch (tone) {
      ChipTone.ok => (C.softInk, C.line, C.ok),
      ChipTone.bad => (const Color(0xffffd0cb), const Color(0xff6e322d), C.bad),
      ChipTone.warn => (
        const Color(0xffefd09a),
        const Color(0xff6e5a2d),
        C.warn,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: C.input,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(fontSize: 14, color: fg)),
        ],
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.width,
    this.height = 8,
    this.track = C.muted,
  });

  final double value;
  final double? width;
  final double height;
  final Color track;

  @override
  Widget build(BuildContext context) => Container(
    width: width ?? double.infinity,
    height: height,
    decoration: BoxDecoration(
      color: track,
      borderRadius: BorderRadius.circular(99),
    ),
    clipBehavior: Clip.antiAlias,
    child: FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: value.clamp(0, 1),
      child: Container(color: C.ok),
    ),
  );
}

class AppTabs extends StatelessWidget {
  const AppTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.dense = false,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: C.line)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < labels.length; i++)
          InkWell(
            onTap: () => onChanged(i),
            child: Container(
              height: dense ? 30 : 34,
              padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    width: 2,
                    color: i == index ? C.brand : Colors.transparent,
                  ),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: dense ? 14 : 16,
                  color: i == index ? C.brand : C.muted,
                  fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width,
    this.enabled = true,
    this.fontSize = 15,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T?>? onChanged;
  final double? width;
  final bool enabled;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: C.input,
      border: Border.all(color: C.line),
      borderRadius: BorderRadius.circular(8),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: width != null,
        isDense: true,
        dropdownColor: C.panel2,
        style: TextStyle(fontSize: fontSize, color: C.ink),
        icon: const Icon(Icons.expand_more, size: 18, color: C.muted),
        items: [
          for (final (v, label) in items)
            DropdownMenuItem(value: v, child: Text(label)),
        ],
        onChanged: enabled ? onChanged : null,
      ),
    ),
  );
}

/// 四个 IP 段，自动跳格，退格回上一格。
class IpSegments extends StatefulWidget {
  const IpSegments({
    super.key,
    required this.initialIp,
    required this.onChanged,
    this.enabled = true,
  });

  final String initialIp;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<IpSegments> createState() => _IpSegmentsState();
}

class _IpSegmentsState extends State<IpSegments> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    final parts = widget.initialIp.split('.');
    _controllers = [
      for (var i = 0; i < 4; i++)
        TextEditingController(text: i < parts.length ? parts[i] : ''),
    ];
    _nodes = [for (var i = 0; i < 4; i++) FocusNode()];
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _ip => _controllers.map((c) => c.text.trim()).join('.');

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('.', style: TextStyle(fontSize: 18)),
            ),
          SizedBox(
            width: 64,
            height: 44,
            child: TextField(
              controller: _controllers[i],
              focusNode: _nodes[i],
              enabled: widget.enabled,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              style: const TextStyle(fontSize: 17),
              onChanged: (value) {
                if (value.length == 3 && i < 3) _nodes[i + 1].requestFocus();
                widget.onChanged(_ip);
              },
              onSubmitted: (_) {
                if (i < 3) _nodes[i + 1].requestFocus();
              },
            ),
          ),
        ],
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.size = 15});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: size,
      color: C.legendInk,
      fontWeight: FontWeight.w600,
    ),
  );
}

class StatRow extends StatelessWidget {
  const StatRow(this.label, this.value, {super.key, this.valueColor = C.ink});

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 4),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xff24364a))),
    ),
    child: Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 15)),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 15, color: valueColor)),
      ],
    ),
  );
}

class Hint extends StatelessWidget {
  const Hint(this.text, {super.key, this.size = 14, this.color = C.muted});

  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: size, color: color, height: 1.5),
  );
}

/// 主按钮高度的方格：3x3 底盘方向键用。
class SquareButton extends StatelessWidget {
  const SquareButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.size = 104,
    this.radius = 20,
    this.fontSize = 46,
    this.color = C.brand,
  });

  final String label;
  final VoidCallback? onPressed;
  final double size;
  final double radius;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? 0.35 : 1,
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Text(
              label,
              style: TextStyle(fontSize: fontSize, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
}
