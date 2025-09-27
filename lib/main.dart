import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:camera/camera.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  var images = <Uint8List>[];
  var cameras = <String>[];

  late cv.PredefinedDictionaryType predefinedDictionaryType;
  String selectedCamera = "";
  bool isCameraRunning = false;
  bool requestStopCamera = false;
  late CameraController cameraController;
  late String cvVersion;

  @override
  void initState() {
    super.initState();

    predefinedDictionaryType = cv.PredefinedDictionaryType.DICT_4X4_100;

    availableCameras().then((value) {
      setState(() {
        cameras = value.map((e) => e.name).toList();
        if (cameras.isNotEmpty) {
          selectedCamera = cameras[0];
        }
      });
    });

    cameraController = CameraController(
    CameraDescription(
          name: "none",
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 0),
      ResolutionPreset.low,
      enableAudio: false,
    );

    cvVersion = cv.openCvVersion();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<cv.Mat> detectMarkers(cv.Mat im) async {
    late cv.Mat gray;
    gray = cv.cvtColor(im, cv.COLOR_BGR2GRAY);
    var detector = cv.ArucoDetector.create(
        cv.ArucoDictionary.predefined(predefinedDictionaryType),
        cv.ArucoDetectorParameters.empty());
    var result = await detector.detectMarkersAsync(gray);
    var overlay = await im.cloneAsync();

    for (int i = 0; i < result.$2.length; i++) {
      var corners = result.$1[i];
      var id = result.$2[i];
      // draw the marker border
      for (int j = 0; j < 4; j++) {
        cv.Point p1 = cv.Point(corners[j].x.toInt(), corners[j].y.toInt());
        cv.Point p2 = cv.Point(
            corners[(j + 1) % 4].x.toInt(), corners[(j + 1) % 4].y.toInt());

        await cv.lineAsync(overlay, p1, p2, cv.Scalar(0, 255, 0), thickness: 6);
      }
      // put the marker id text
      cv.Point corners0 = cv.Point(corners[0].x.toInt(), corners[0].y.toInt());
      // find bottom left corner
      for (int j = 1; j < 4; j++) {
        if (corners[j].x - corners[j].y < corners0.x - corners0.y) {
          corners0 = cv.Point(corners[j].x.toInt(), corners[j].y.toInt());
        }
      }
      cv.Point offset = cv.Point(10, -10);
      corners0 = cv.Point(corners0.x + offset.x, corners0.y + offset.y);
      await cv.putTextAsync(overlay, id.toString(), corners0,
          cv.FONT_HERSHEY_SIMPLEX, 5, cv.Scalar(255, 0, 255),
          thickness: 8);
    }

    return overlay;
  }

  Future<void> processCameraStream() async {
    bool imageProcesessed = false;
    if (cameraController != null && !cameraController.value.hasError) {
      final capturedImage = await cameraController.takePicture();
      if (await capturedImage.length() > 0) {
        var newImages = [
          await processImageBytes(await capturedImage.readAsBytes())
        ];
        setState(() {
          images = newImages;
        });
        imageProcesessed = true;
      }
    }

    if (requestStopCamera || !imageProcesessed) {
      requestStopCamera = false;
      await stopCamera(true);
      return;
    }
    await processCameraStream();
  }

  Future<void> initializeCamera() async {
    WakelockPlus.enable();
    setState(() {
      isCameraRunning = true;
    });
    final cameras = await availableCameras();
    final firstCamera =
        cameras.firstWhere((element) => element.name == selectedCamera);

    cameraController = CameraController(
      firstCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await cameraController.initialize();
  }

  Future<void> stopCamera(bool immediately) async {
    if (immediately) {
      await cameraController.dispose();
      setState(() {
        isCameraRunning = false;
      });
      WakelockPlus.disable();
    } else {
      requestStopCamera = true;
      Future.delayed(const Duration(seconds: 2), () async {
        if (requestStopCamera) {
          requestStopCamera = false;
          await stopCamera(true);
          return;
        }
      });
    }
  }

  Future<Uint8List> processImageBytes(Uint8List bytes) async {
    final mat = await cv.imdecodeAsync(bytes, cv.IMREAD_COLOR);
    final overlay = await detectMarkers(mat);
    cv.VecI32 pngParams = cv.VecI32.fromList([
      cv.IMWRITE_PNG_COMPRESSION,
      1,
      cv.IMWRITE_PNG_STRATEGY,
      cv.IMWRITE_PNG_STRATEGY_HUFFMAN_ONLY
    ]);
    final overlayBytes =
        await cv.imencodeAsync(".png", overlay, params: pngParams);
    return overlayBytes.$2;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('MarkID')),
        body: Container(
          alignment: Alignment.center,
          child: Column(
            children: [
              Text("OpenCV version: $cvVersion"),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Dictionary: "),
                  DropdownButton<cv.PredefinedDictionaryType>(
                    value: predefinedDictionaryType,
                    items: cv.PredefinedDictionaryType.values
                        .map((e) => DropdownMenuItem(
                              value: e,
                              child: Text(e.toString().split('.').last),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        predefinedDictionaryType = v!;
                      });
                    },
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Camera: "),
                  DropdownButton<String>(
                    value: selectedCamera,
                    items: cameras
                        .map((e) => DropdownMenuItem(
                              value: e,
                              child: Text(e),
                            ))
                        .toList(),
                    onChanged: isCameraRunning
                        ? null
                        : (v) {
                            setState(() {
                              selectedCamera = v!;
                            });
                          },
                  )
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                      onPressed: isCameraRunning
                          ? null
                          : () async {
                              await initializeCamera();
                              await processCameraStream();
                            },
                      child: Text("Start")),
                  ElevatedButton(
                      onPressed: isCameraRunning
                          ? () async {
                              await stopCamera(false);
                            }
                          : null,
                      child: Text("Stop")),
                  ElevatedButton(
                      onPressed: isCameraRunning
                          ? null
                          : () async {
                              await initializeCamera();
                              final capturedImage =
                                  await cameraController.takePicture();
                              await stopCamera(true);
                              if (await capturedImage.length() > 0) {
                                var newImages = [
                                  await processImageBytes(
                                      await capturedImage.readAsBytes())
                                ];
                                setState(() {
                                  images = newImages;
                                });
                              }
                            },
                      child: const Text("Single")),
                  ElevatedButton(
                    onPressed: images.isEmpty
                        ? null
                        : () {
                            setState(() {
                              images = [];
                            });
                          },
                    child: const Text("Clear"),
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: images.length,
                  itemBuilder: (ctx, idx) => Card(
                      child: Image.memory(
                    images[idx],
                    gaplessPlayback: true,
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
