import 'dart:io';
import 'package:face_verify/src/data/models/user_model.dart';
import 'package:face_verify/src/ui/widgets/camera_view.dart';
import 'package:face_verify/src/ui/widgets/close_camera_button.dart';
import 'package:face_verify/src/ui/widgets/face_painter/face_detector_overlay.dart';
import 'package:face_verify/src/ui/widgets/face_painter/face_detector_painter.dart';
import 'package:face_verify/src/ui/widgets/face_painter/face_overlay_shape.dart';
import 'package:face_verify/src/services/face_detector_service.dart';
import 'package:face_verify/src/services/recognition_service.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class DetectionView extends StatefulWidget {
  final CameraDescription cameraDescription;
  final ResolutionPreset resolutionPreset;
  final int frameSkipCount;
  final double threshold;
  final FaceDetectorMode faceDetectorPerformanceMode;
  final FaceOverlayShapeType faceOverlayShapeType;
  final FaceOverlayShape? customFaceOverlayShape;
  final List<UserModel> users;
  final Widget? loadingWidget;

  const DetectionView({
    super.key,
    required this.users,
    required this.cameraDescription,
    this.resolutionPreset = ResolutionPreset.high,
    this.frameSkipCount = 10,
    this.threshold = 0.8,
    this.faceDetectorPerformanceMode = FaceDetectorMode.accurate,
    this.faceOverlayShapeType = FaceOverlayShapeType.rectangle,
    this.customFaceOverlayShape,
    this.loadingWidget,
  });

  @override
  DetectionViewState createState() => DetectionViewState();
}

class DetectionViewState extends State<DetectionView>
    with WidgetsBindingObserver {
  CameraController? cameraController;
  late FaceDetectorService faceDetectorService;
  late RecognitionService recognitionService;

  List<Face> detectedFaces = [];
  Set<UserModel> recognitions = {};

  int frameCount = 0;
  bool isBusy = false;

  // 👇 ADDED VARIABLES
  String? detectedName;
  double? detectedDistance; // distance from recognition model
  double? matchPercent;

  @override
  void initState() {
    super.initState();
    initializeCamera();
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    await cameraController?.dispose();
    await faceDetectorService.dispose();
    await recognitionService.dispose();
  }

  // CAMERA SETUP
  initializeCamera() async {
    cameraController = CameraController(
      widget.cameraDescription,
      widget.resolutionPreset,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
      enableAudio: false,
    );

    await cameraController!.initialize().then((_) async {
      if (!mounted) return;

      faceDetectorService = FaceDetectorService(
        cameraController: cameraController,
        cameraDescription: widget.cameraDescription,
        faceDetectorPerformanceMode: widget.faceDetectorPerformanceMode,
      );

      recognitionService = RecognitionService(
        users: widget.users,
        rotationCompensation: faceDetectorService.rotationCompensation!,
        sensorOrientation: widget.cameraDescription.sensorOrientation,
        threshold: widget.threshold,
      );

      cameraController!.startImageStream((image) async {
        frameCount++;

        if (frameCount % widget.frameSkipCount == 0) {
          if (!isBusy) {
            isBusy = true;

            detectedFaces = await faceDetectorService.doFaceDetection(
              faceDetectorSource: FaceDetectorSource.cameraFrame,
              cameraFrame: image,
            );

            // PERFORM RECOGNITION
            if (recognitionService.performFaceRecognition(
              recognitions: recognitions,
              cameraImageFrame: image,
              faces: detectedFaces,
            )) {
              // MATCH FOUND
              final user = recognitions.first;

              detectedName = user.name;
              detectedDistance = recognitionService.lastDistance;
              matchPercent = (1 - detectedDistance!) * 100;

              if (mounted) {
                setState(() {});
                Navigator.of(context).pop(recognitions);
              }
            } else {
              // NO MATCH → still update UI for overlay
              detectedName = null;
              detectedDistance = recognitionService.lastDistance;
              matchPercent = detectedDistance != null
                  ? (1 - detectedDistance!) * 100
                  : null;

              isBusy = false;
              setState(() {});
            }
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    Size screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: (cameraController != null && cameraController!.value.isInitialized)
          ? Stack(
              children: [
                CameraView(
                  cameraController: cameraController!,
                  screenSize: screenSize,
                ),

                FaceDetectorOverlay(
                  cameraController: cameraController!,
                  screenSize: screenSize,
                  faces: detectedFaces,
                  customFaceOverlayShape: widget.customFaceOverlayShape,
                  faceOverlayShapeType: widget.faceOverlayShapeType,
                ),

                // 👇 ADDED: SHOW NAME + MATCH %
                if (matchPercent != null)
                  Positioned(
                    top: 50,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: (detectedDistance != null &&
                                  detectedDistance! < widget.threshold)
                              ? Colors.green.withOpacity(0.7)
                              : Colors.red.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          detectedName != null
                              ? "${detectedName!} (${matchPercent!.toStringAsFixed(1)}%)"
                              : "Matching: ${matchPercent!.toStringAsFixed(1)}%",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),

                CloseCameraButton(
                  cameraController: cameraController!,
                ),
              ],
            )
          : widget.loadingWidget ??
              const Center(child: CircularProgressIndicator()),
    );
  }
}
