import 'package:echoclip/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop size keeps independent minimum width and height', () {
    expect(
      constrainDesktopWindowSize(const Size(500, 400)),
      const Size(960, 640),
    );
  });

  test('desktop size clamps narrow windows to 4:3', () {
    final result = constrainDesktopWindowSize(const Size(1000, 1000));
    expect(result.width, 1000);
    expect(result.height, 750);
  });

  test('desktop size clamps wide windows to 16:9', () {
    final result = constrainDesktopWindowSize(const Size(1600, 640));
    expect(result.width, closeTo(640 * 16 / 9, 0.001));
    expect(result.height, 640);
  });

  test('desktop size preserves a value already inside the ratio range', () {
    expect(
      constrainDesktopWindowSize(const Size(1200, 800)),
      const Size(1200, 800),
    );
  });
}
