import 'package:flutter/material.dart';

class CameraFeedController {
  String? Function()? onCaptureFrame;
  void Function(Function(String dataUrl))? onNativeCameraCapture;
  void Function()? onSwitchCamera;
  void Function()? onStartCamera;

  String? captureFrame() => onCaptureFrame?.call();
  void openNativeCamera(Function(String dataUrl) onCaptured) => onNativeCameraCapture?.call(onCaptured);
  void switchCamera() => onSwitchCamera?.call();
  void startCamera() => onStartCamera?.call();
}

class RealCameraFeed extends StatefulWidget {
  final Widget? fallback;
  final Function(bool isLive)? onCameraStatusChanged;
  final CameraFeedController? controller;
  final String? capturedPhotoUrl;
  final double zoom;
  final bool isFlashOn;

  const RealCameraFeed({
    super.key,
    this.fallback,
    this.onCameraStatusChanged,
    this.controller,
    this.capturedPhotoUrl,
    this.zoom = 1.0,
    this.isFlashOn = false,
  });

  @override
  State<RealCameraFeed> createState() => _RealCameraFeedStubState();
}

class _RealCameraFeedStubState extends State<RealCameraFeed> {
  @override
  Widget build(BuildContext context) {
    if (widget.capturedPhotoUrl != null) {
      return Image.network(
        widget.capturedPhotoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => widget.fallback ?? const SizedBox.shrink(),
      );
    }
    return widget.fallback ?? const SizedBox.shrink();
  }
}
