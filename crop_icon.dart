import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final file = File('assets/logos/icon 4.png');
  final image = img.decodeImage(file.readAsBytesSync());

  if (image == null) return;

  // Assuming top-left pixel is the background color
  final bgColor = image.getPixel(0, 0);

  int minX = image.width;
  int minY = image.height;
  int maxX = 0;
  int maxY = 0;

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      if (image.getPixel(x, y) != bgColor) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  int bubbleWidth = maxX - minX;
  int bubbleHeight = maxY - minY;

  // We want a square crop with 5% padding around the chat bubble
  // To make it very bold and full.
  double paddingFactor = 0.05;
  int paddingW = (bubbleWidth * paddingFactor).round();
  int paddingH = (bubbleHeight * paddingFactor).round();

  int maxDim = bubbleWidth > bubbleHeight ? bubbleWidth : bubbleHeight;
  int cropSize = maxDim + (paddingW > paddingH ? paddingW : paddingH) * 2;

  int centerX = minX + bubbleWidth ~/ 2;
  int centerY = minY + bubbleHeight ~/ 2;

  int newLeft = centerX - cropSize ~/ 2;
  int newTop = centerY - cropSize ~/ 2;

  final cropped = img.copyCrop(image, x: newLeft, y: newTop, width: cropSize, height: cropSize);
  final resized = img.copyResize(cropped, width: 1024, height: 1024, interpolation: img.Interpolation.cubic);

  File('assets/icon.png').writeAsBytesSync(img.encodePng(resized));
  print('Successfully cropped and saved to assets/icon.png');
}
