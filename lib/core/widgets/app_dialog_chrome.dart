import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

const _purpleLight = Color(0xFFF6F3FF);
const _purpleBorder = Color(0xFFE8E0FF);
const _purpleText = Color(0xFF8572B8);

Future<T?> showAppCardDialog<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  bool barrierDismissible = true,
  bool showCloseButton = true,
  required WidgetBuilder builder,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_purpleLight, Colors.white],
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _purpleBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF201B2D),
                          ),
                        ),
                        if (subtitle != null && subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _purpleText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showCloseButton)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F0FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE4DAFF)),
                        ),
                        child: const Text(
                          '×',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: 120,
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: const LinearGradient(
                    colors: [
                      AppColors.primary,
                      Color(0xFFA98CF7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(child: builder(context)),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<T?> showAppMenuCardPopup<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required List<Widget> children,
}) {
  return showAppCardDialog<T>(
    context: context,
    title: title,
    subtitle: subtitle,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(height: 8),
              children[index],
            ],
          ],
        ),
      ),
    ),
  );
}

class AppDialogActionButton extends StatelessWidget {
  const AppDialogActionButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.primary = true,
    this.danger = false,
  });

  final String text;
  final VoidCallback onPressed;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final foreground = primary
        ? Colors.white
        : (danger ? AppColors.danger : AppColors.primary);
    return SizedBox(
      height: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: primary
              ? LinearGradient(
                  colors: danger
                      ? const [Color(0xFFD94A4A), Color(0xFFB3261E)]
                      : const [AppColors.primaryAlt, Color(0xFF8067C8)],
                )
              : null,
          color: primary ? null : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: primary
                ? Colors.transparent
                : (danger ? const Color(0xFFF1B8B8) : const Color(0xFFDCE3F1)),
          ),
        ),
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: foreground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

class AppDialogActionRow extends StatelessWidget {
  const AppDialogActionRow({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    this.cancelText = '取消',
    this.confirmText = '确定',
    this.danger = false,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String cancelText;
  final String confirmText;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppDialogActionButton(
            text: cancelText,
            primary: false,
            onPressed: onCancel,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppDialogActionButton(
            text: confirmText,
            danger: danger,
            onPressed: onConfirm,
          ),
        ),
      ],
    );
  }
}

class AppDialogListItem extends StatelessWidget {
  const AppDialogListItem({
    super.key,
    required this.label,
    this.subtitle,
    this.trailing,
    this.selected = false,
    this.accent = false,
    this.danger = false,
    this.onTap,
  });

  final String label;
  final String? subtitle;
  final Widget? trailing;
  final bool selected;
  final bool accent;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? AppColors.danger
        : (selected || accent ? AppColors.primary : AppColors.textPrimary);
    final fill = danger
        ? const Color(0xFFFFF4F4)
        : (selected
              ? const Color(0xFFF1EAFF)
              : (accent ? const Color(0xFFFAF7FF) : Colors.white));
    final stroke = danger
        ? const Color(0xFFF1B8B8)
        : (selected ? const Color(0xFFBBA7F2) : const Color(0xFFE7EAF3));
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: stroke),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE4DDF8),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  '当前',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

void showAppToast(
  BuildContext context,
  String message, {
  double bottomMargin = 24,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomMargin),
      elevation: 0,
      backgroundColor: Colors.transparent,
      content: Center(
        heightFactor: 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5E46A8), Color(0xFF8F6DF2)],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      duration: const Duration(seconds: 2),
    ),
  );
}
