part of 'main_page.dart';

extension _MainPageDialogs on _MainPageState {
  Future<T?> _showAnchoredMenu<T>({
    required BuildContext anchorContext,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchorBox == null || overlayBox == null) {
      return showAppMenuCardPopup<T>(
        context: context,
        title: title,
        subtitle: subtitle,
        children: children,
      );
    }
    final anchorOffset = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final anchorRect = anchorOffset & anchorBox.size;
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 90),
      pageBuilder: (dialogContext, _, _) {
        final screenSize = MediaQuery.sizeOf(dialogContext);
        final popupWidth = (screenSize.width - 24).clamp(0.0, 320.0);
        final preferredLeft =
            anchorRect.left + (anchorRect.width - popupWidth) / 2;
        final left = preferredLeft.clamp(
          12.0,
          screenSize.width - popupWidth - 12.0,
        );
        const gap = 10.0;
        final maxHeight = (screenSize.height * 0.55).clamp(0.0, 390.0);
        final belowTop = anchorRect.bottom + gap;
        final aboveTop = anchorRect.top - gap - maxHeight;
        final hasBelowSpace = belowTop + maxHeight <= screenSize.height - 12;
        final top = hasBelowSpace
            ? belowTop
            : aboveTop.clamp(12.0, screenSize.height - maxHeight - 12.0);
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: popupWidth,
              child: _AnchoredMenuCard(
                title: title,
                subtitle: subtitle,
                maxHeight: maxHeight,
                children: children,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<T?> _showAnchoredCard<T>({
    required BuildContext anchorContext,
    required Widget child,
    required double width,
    double maxHeight = 390,
  }) {
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchorBox == null || overlayBox == null) {
      return showDialog<T>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (_) =>
            Dialog(backgroundColor: Colors.transparent, child: child),
      );
    }
    final anchorOffset = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final anchorRect = anchorOffset & anchorBox.size;
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 90),
      pageBuilder: (dialogContext, _, _) {
        final screenSize = MediaQuery.sizeOf(dialogContext);
        final popupWidth = (screenSize.width - 24).clamp(0.0, width);
        final preferredLeft =
            anchorRect.left + (anchorRect.width - popupWidth) / 2;
        final left = preferredLeft.clamp(
          12.0,
          screenSize.width - popupWidth - 12.0,
        );
        const gap = 8.0;
        final popupHeight = maxHeight.clamp(0.0, screenSize.height - 24.0);
        final belowTop = anchorRect.bottom + gap;
        final aboveTop = anchorRect.top - gap - popupHeight;
        final hasBelowSpace = belowTop + popupHeight <= screenSize.height - 12;
        final top = hasBelowSpace
            ? belowTop
            : aboveTop.clamp(12.0, screenSize.height - popupHeight - 12.0);
        return Stack(
          children: [
            Positioned(left: left, top: top, width: popupWidth, child: child),
          ],
        );
      },
    );
  }
}
