import 'package:flutter/services.dart';

class DeviceSettingsService {
  static const _channel = MethodChannel('app.braid/device_settings');

  Future<void> openNotificationSettings() {
    return _channel.invokeMethod<void>('openNotificationSettings');
  }
}
