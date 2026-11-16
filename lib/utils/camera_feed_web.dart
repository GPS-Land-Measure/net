// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
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
  State<RealCameraFeed> createState() => _RealCameraFeedWebState();
}

class _RealCameraFeedWebState extends State<RealCameraFeed> {
  static int _viewIdCounter = 0;
  late final String _viewType;
  html.VideoElement? _videoElement;
  html.MediaStream? _mediaStream;
  bool _isCameraActive = false;
  String? _errorMessage;
  bool _isFrontCamera = false;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'real-camera-video-${++_viewIdCounter}';
    _attachController();
    _initCamera();
  }

  @override
  void didUpdateWidget(covariant RealCameraFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoom != widget.zoom) {
      _applyZoom();
    }
    if (oldWidget.isFlashOn != widget.isFlashOn) {
      _applyTorch();
    }
  }

  void _applyZoom() {
    if (_videoElement != null) {
      _videoElement!.style.transform = 'scale(${widget.zoom})';
      _videoElement!.style.transformOrigin = 'center center';
    }
  }

  void _applyTorch() {
    try {
      if (_mediaStream != null) {
        final tracks = _mediaStream!.getVideoTracks();
        if (tracks.isNotEmpty) {
          tracks.first.applyConstraints({
            'advanced': [{'torch': widget.isFlashOn}]
          });
        }
      }
    } catch (_) {}
  }

  void _attachController() {
    if (widget.controller != null) {
      widget.controller!.onStartCamera = () {
        _initCamera();
      };

      widget.controller!.onCaptureFrame = () {
        if (_videoElement != null && _videoElement!.videoWidth > 0) {
          final canvas = html.CanvasElement(
            width: _videoElement!.videoWidth,
            height: _videoElement!.videoHeight,
          );
          canvas.context2D.drawImage(_videoElement!, 0, 0);
          return canvas.toDataUrl('image/jpeg', 0.92);
        }
        return null;
      };

      widget.controller!.onNativeCameraCapture = (onCaptured) {
        final input = html.FileUploadInputElement()
          ..accept = 'image/*'
          ..setAttribute('capture', 'environment')
          ..style.display = 'none';

        html.document.body?.children.add(input);

        input.onChange.listen((_) {
          final file = input.files?.first;
          if (file != null) {
            final reader = html.FileReader();
            reader.readAsDataUrl(file);
            reader.onLoadEnd.listen((_) {
              input.remove();
              onCaptured(reader.result as String);
            });
          } else {
            input.remove();
          }
        });

        input.onError.listen((_) {
          input.remove();
        });

        // Trigger user click event immediately
        input.click();
      };

      widget.controller!.onSwitchCamera = () {
        _switchCamera();
      };
    }
  }

  Future<void> _initCamera() async {
    if (_isStarting) return;
    _isStarting = true;

    if (mounted) {
      setState(() {
        _errorMessage = null;
      });
    }

    try {
      if (_videoElement == null) {
        _videoElement = html.VideoElement()
          ..autoplay = true
          ..muted = true
          ..setAttribute('playsinline', 'true')
          ..setAttribute('webkit-playsinline', 'true')
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover'
          ..style.position = 'absolute'
          ..style.top = '0'
          ..style.left = '0'
          ..style.pointerEvents = 'none';

        _applyZoom();

        ui_web.platformViewRegistry.registerViewFactory(
          _viewType,
          (int id) => _videoElement!,
        );
      }

      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        if (mounted) {
          setState(() {
            _errorMessage = 'កម្មវិធីរុករកនេះមិនទាន់គាំទ្រ Web Camera ផ្ទាល់ទេ សូមប្រើប៊ូតុង "ថតរូបដីតាមទូរស័ព្ទ" ខាងក្រោម។';
            _isStarting = false;
          });
        }
        widget.onCameraStatusChanged?.call(false);
        return;
      }

      _mediaStream?.getTracks().forEach((t) => t.stop());

      final stream = await mediaDevices.getUserMedia({
        'video': {
          'facingMode': _isFrontCamera ? 'user' : {'ideal': 'environment'},
          'width': {'ideal': 1920},
          'height': {'ideal': 1080},
        },
        'audio': false,
      });

      _mediaStream = stream;
      if (_videoElement != null) {
        _videoElement!.srcObject = stream;
        try {
          await _videoElement!.play();
        } catch (_) {}
        _applyZoom();
        _applyTorch();
      }

      if (mounted) {
        setState(() {
          _isCameraActive = true;
          _errorMessage = null;
          _isStarting = false;
        });
        widget.onCameraStatusChanged?.call(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '$e';
          _isCameraActive = false;
          _isStarting = false;
        });
        widget.onCameraStatusChanged?.call(false);
      }
    }
  }

  void _switchCamera() {
    _isFrontCamera = !_isFrontCamera;
    _initCamera();
  }

  @override
  void dispose() {
    try {
      _mediaStream?.getTracks().forEach((track) => track.stop());
      _videoElement?.pause();
      _videoElement?.srcObject = null;
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.capturedPhotoUrl != null) {
      return Image.network(
        widget.capturedPhotoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => widget.fallback ?? const SizedBox.shrink(),
      );
    }

    if (_isCameraActive) {
      return HtmlElementView(viewType: _viewType);
    }

    // When camera is not yet active, show fallback with action buttons!
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.fallback != null) widget.fallback!,
        _buildPermissionRequest(),
      ],
    );
  }

  Widget _buildPermissionRequest() {
    return Container(
      color: Colors.black.withOpacity(0.6),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _initCamera,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF10B981).withOpacity(0.5), blurRadius: 20),
                  ],
                ),
                child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 40),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'ចុចដើម្បីបើក Camera ឬថតរូបដី',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage != null
                  ? 'សូមអនុញ្ញាត (Allow) Camera លើ Browser ឬថតរូបតាមកាមេរ៉ាទូរស័ព្ទផ្ទាល់'
                  : 'កម្មវិធីត្រូវការ Camera ដើម្បីឆ្លុះមើលទេសភាពដី និងវាស់ប្រវែងជាក់ស្តែង',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _initCamera,
              icon: const Icon(Icons.videocam_rounded, size: 20),
              label: const Text('បើក Live Camera', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                widget.controller?.openNativeCamera((dataUrl) {});
              },
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: const Text('ថតរូបដីតាមកាមេរ៉ាទូរស័ព្ទ (Camera App)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
