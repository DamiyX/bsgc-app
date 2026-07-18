import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final file = File('assets/icon2.png');
  final original = img.decodeImage(file.readAsBytesSync());
  if (original == null) return;
  
  // Make a canvas 1.5x larger so the icon is centered in the "safe zone"
  int newWidth = (original.width * 1.5).toInt();
  int newHeight = (original.height * 1.5).toInt();
  
  final paddedIcon = img.Image(width: newWidth, height: newHeight, numChannels: 4);
  int offsetX = (newWidth - original.width) ~/ 2;
  int offsetY = (newHeight - original.height) ~/ 2;
  
  for (int y = 0; y < newHeight; y++) {
    for (int x = 0; x < newWidth; x++) {
      if (x >= offsetX && x < offsetX + original.width && y >= offsetY && y < offsetY + original.height) {
        paddedIcon.setPixel(x, y, original.getPixel(x - offsetX, y - offsetY));
      } else {
        paddedIcon.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
  File('assets/padded_icon.png').writeAsBytesSync(img.encodePng(paddedIcon));
  
  final splashFile = File('assets/splash_icon.png');
  if (splashFile.existsSync()) {
    final roundedSplash = img.decodeImage(splashFile.readAsBytesSync());
    if (roundedSplash != null) {
      final paddedSplash = img.Image(width: newWidth, height: newHeight, numChannels: 4);
      for (int y = 0; y < newHeight; y++) {
        for (int x = 0; x < newWidth; x++) {
          if (x >= offsetX && x < offsetX + original.width && y >= offsetY && y < offsetY + original.height) {
            paddedSplash.setPixel(x, y, roundedSplash.getPixel(x - offsetX, y - offsetY));
          } else {
            paddedSplash.setPixelRgba(x, y, 0, 0, 0, 0);
          }
        }
      }
      File('assets/splash_icon_padded.png').writeAsBytesSync(img.encodePng(paddedSplash));
    }
  }
}
