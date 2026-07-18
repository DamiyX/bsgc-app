import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final file = File('assets/icon2.png');
  if (!file.existsSync()) {
    print('File not found');
    return;
  }
  final image = img.decodeImage(file.readAsBytesSync());
  if (image == null) return;

  // Create an image with transparent background
  final result = img.Image(width: image.width, height: image.height, numChannels: 4);

  int radius = image.width ~/ 6; // roughly 16% border radius
  
  // Very simple rounded rectangle clipping
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      bool isInside = true;
      
      // Top left
      if (x < radius && y < radius) {
        if ((x - radius) * (x - radius) + (y - radius) * (y - radius) > radius * radius) {
          isInside = false;
        }
      }
      // Top right
      else if (x > image.width - radius && y < radius) {
        if ((x - (image.width - radius)) * (x - (image.width - radius)) + (y - radius) * (y - radius) > radius * radius) {
          isInside = false;
        }
      }
      // Bottom left
      else if (x < radius && y > image.height - radius) {
        if ((x - radius) * (x - radius) + (y - (image.height - radius)) * (y - (image.height - radius)) > radius * radius) {
          isInside = false;
        }
      }
      // Bottom right
      else if (x > image.width - radius && y > image.height - radius) {
        if ((x - (image.width - radius)) * (x - (image.width - radius)) + (y - (image.height - radius)) * (y - (image.height - radius)) > radius * radius) {
          isInside = false;
        }
      }

      if (isInside) {
        result.setPixel(x, y, image.getPixel(x, y));
      } else {
        result.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }

  File('assets/splash_icon.png').writeAsBytesSync(img.encodePng(result));
  print('Saved splash_icon.png');
}
