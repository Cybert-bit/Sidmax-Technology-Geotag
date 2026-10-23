import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/photo_data.dart';
import 'package:flutter_application_1/utils/constants.dart';

void main() {
  test('PhotoData serialization and formatting test', () {
    final photo = PhotoData(
      id: 'test_1',
      imagePath: '/path/to/test.jpg',
      latitude: 14.599512,
      longitude: 120.984222,
      altitude: 15.0,
      address: 'Rizal Park, Manila, Philippines',
      city: 'Manila',
      country: 'Philippines',
      timestamp: DateTime(2026, 1, 1, 12, 0, 0),
      stampTemplate: 'modern',
    );

    expect(photo.formattedCoordinates, contains('14.599512° N'));
    expect(photo.formattedCoordinates, contains('120.984222° E'));
    expect(photo.shortAddress, 'Rizal Park, Manila');

    final json = photo.toJson();
    final restored = PhotoData.fromJson(json);

    expect(restored.id, photo.id);
    expect(restored.latitude, photo.latitude);
    expect(restored.longitude, photo.longitude);
    expect(restored.address, photo.address);
    expect(restored.stampTemplate, 'modern');
  });

  test('AppColors palette test', () {
    expect(AppColors.primaryDark, const Color(0xFF0D1117));
    expect(AppColors.accent, const Color(0xFF58A6FF));
    expect(AppColors.accentGreen, const Color(0xFF3FB950));
    expect(AppColors.textPrimary, const Color(0xFFE6EDF3));
  });

  test('AppStrings constants test', () {
    expect(AppStrings.appName, 'Sidmax Technology Geotag');
    expect(AppStrings.appVersion, '1.0.0');
    expect(AppStrings.camera, 'Camera');
    expect(AppStrings.gallery, 'Gallery');
    expect(AppStrings.map, 'Map');
    expect(AppStrings.settings, 'Settings');
  });

  test('StampTemplate display name and icon test', () {
    expect(StampTemplate.classic.displayName, 'Classic');
    expect(StampTemplate.modern.displayName, 'Modern');
    expect(StampTemplate.minimal.displayName, 'Minimal');
    expect(StampTemplate.explorer.displayName, 'Explorer');
  });
}
