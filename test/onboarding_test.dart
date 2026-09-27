import 'package:flutter_test/flutter_test.dart';
import 'package:frida_link_v2/core/models/app_settings.dart';
import 'package:frida_link_v2/core/models/connection.dart';

void main() {
  test('AppSettings round-trips onboarding and appearance fields', () {
    const settings = AppSettings(
      onboardingCompleted: true,
      darkMode: false,
      accentColor: 0xFF7CFA6F,
      defaultDevice: '192.168.1.50:5555',
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.onboardingCompleted, isTrue);
    expect(restored.darkMode, isFalse);
    expect(restored.accentColor, 0xFF7CFA6F);
    expect(restored.defaultDevice, '192.168.1.50:5555');
  });

  test('AppSettings without onboarding key starts the guide', () {
    final restored = AppSettings.fromJson(const <String, dynamic>{});

    expect(restored.onboardingCompleted, isFalse);
  });

  test('wireless address helpers validate input and default the port', () {
    expect(isValidIpv4Address('192.168.1.50'), isTrue);
    expect(isValidIpv4Address('192.168.1.999'), isFalse);
    expect(isValidIpv4Address('not-an-ip'), isFalse);
    expect(isValidPortNumber('5555'), isTrue);
    expect(isValidPortNumber('0'), isFalse);
    expect(isValidPortNumber('70000'), isFalse);
    expect(buildWirelessAddress('192.168.1.50', ''), '192.168.1.50:5555');
    expect(buildWirelessAddress('192.168.1.50', ' 5556 '), '192.168.1.50:5556');
  });
}
