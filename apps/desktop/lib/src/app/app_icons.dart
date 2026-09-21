import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

@immutable
class AppIconData {
  const AppIconData(this.asset) : materialIcon = null;
  const AppIconData.material(this.materialIcon) : asset = null;
  final String? asset;
  final IconData? materialIcon;
}

class AppIcons {
  AppIcons._();

  static const airdrop = AppIconData('assets/icons/airdrop-svgrepo-com.svg');
  static const analytics =
      AppIconData('assets/icons/analytics-line-svgrepo-com.svg');
  static const clipboard = AppIconData('assets/icons/clipboard.svg');
  static const delete = AppIconData('assets/icons/delete-2-svgrepo-com.svg');
  static const edit = AppIconData('assets/icons/edit-4-svgrepo-com.svg');
  static const filter = AppIconData('assets/icons/filter.svg');
  static const files = AppIconData('assets/icons/files-svgrepo-com.svg');
  static const gallery =
      AppIconData('assets/icons/gallery-wide-svgrepo-com.svg');
  static const handTap = AppIconData('assets/icons/hand-tap.svg');
  static const keyboard = AppIconData('assets/icons/keyboard.svg');
  static const monitorPlay = AppIconData('assets/icons/monitor-play.svg');
  static const monitorSmartphone =
      AppIconData('assets/icons/monitor-smartphone-svgrepo-com.svg');
  static const mouse = AppIconData('assets/icons/mouse.svg');
  static const option = AppIconData('assets/icons/option.svg');
  static const paragraph = AppIconData('assets/icons/paragraph-rtl.svg');
  static const pin = AppIconData('assets/icons/pin-svgrepo-com.svg');
  static const protection =
      AppIconData('assets/icons/protection-safety-security-svgrepo-com.svg');
  static const qrCode = AppIconData('assets/icons/qr-code-svgrepo-com.svg');
  static const receive = AppIconData('assets/icons/receive-svgrepo-com.svg');
  static const send = AppIconData('assets/icons/send.svg');
  static const sendToDevice =
      AppIconData('assets/icons/send-1-to-local-device-com.svg');
  static const settings = AppIconData('assets/icons/settings.svg');
  static const textSquare =
      AppIconData('assets/icons/text-square-2-svgrepo-com.svg');
  static const zoomOut = AppIconData('assets/icons/zomm-out.svg');

  static const materialSettings = AppIconData.material(Icons.settings_outlined);
  static const materialAnalytics =
      AppIconData.material(Icons.monitor_heart_outlined);
  static const materialClipboard =
      AppIconData.material(Icons.content_paste_outlined);
  static const materialDelete =
      AppIconData.material(Icons.delete_outline_rounded);
  static const materialDeleteSweep =
      AppIconData.material(Icons.delete_sweep_rounded);
  static const materialFiles =
      AppIconData.material(Icons.insert_drive_file_outlined);
  static const materialGallery = AppIconData.material(Icons.image_outlined);
  static const materialKeyboard =
      AppIconData.material(Icons.keyboard_alt_outlined);
  static const materialMonitorPlay =
      AppIconData.material(Icons.monitor_heart_outlined);
  static const materialMonitorSmartphone =
      AppIconData.material(Icons.devices_outlined);
  static const materialMouse = AppIconData.material(Icons.mouse_outlined);
  static const materialPin = AppIconData.material(Icons.push_pin_outlined);
  static const materialPinFilled = AppIconData.material(Icons.push_pin);
  static const materialReceive = AppIconData.material(Icons.download_rounded);
  static const materialSend = AppIconData.material(Icons.near_me_outlined);
  static const materialZoomOut =
      AppIconData.material(Icons.open_in_full_rounded);
  static const materialLock = AppIconData.material(Icons.lock_outline_rounded);
  static const materialMemory = AppIconData.material(Icons.memory_rounded);
  static const materialLink = AppIconData.material(Icons.link_rounded);
  static const materialCode = AppIconData.material(Icons.code_rounded);
  static const materialNotes = AppIconData.material(Icons.notes_rounded);
  static const materialQrCode = AppIconData.material(Icons.qr_code_2_rounded);
  static const materialWarning =
      AppIconData.material(Icons.warning_amber_rounded);
  static const materialInfo = AppIconData.material(Icons.info_outline);
  static const materialChevronRight = AppIconData.material(Icons.chevron_right);
  static const materialClose = AppIconData.material(Icons.close_rounded);
  static const materialError = AppIconData.material(Icons.error_outline);
}

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.data, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final AppIconData data;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24.0;
    final resolvedColor = color ??
        iconTheme.color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    if (data.materialIcon != null) {
      return Icon(
        data.materialIcon,
        size: resolvedSize,
        color: resolvedColor,
        semanticLabel: semanticLabel,
      );
    }
    return SizedBox(
      width: resolvedSize,
      height: resolvedSize,
      child: Center(
        child: SvgPicture.asset(
          data.asset!,
          width: resolvedSize,
          height: resolvedSize,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(resolvedColor, BlendMode.srcIn),
          semanticsLabel: semanticLabel,
        ),
      ),
    );
  }
}
