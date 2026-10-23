import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';
import 'map_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // GlobalKey to access CameraScreen state for reloading settings
  final GlobalKey<CameraScreenState> _cameraKey =
      GlobalKey<CameraScreenState>();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      CameraScreen(key: _cameraKey),
      const GalleryScreen(),
      const MapScreen(),
      const SettingsScreen(),
    ];
  }

  void _onTabChanged(int index) {
    final previousIndex = _currentIndex;
    setState(() => _currentIndex = index);

    // When switching TO the Camera tab from any other tab (especially Settings),
    // reload all settings so the stamp reflects the latest changes.
    if (index == 0 && previousIndex != 0) {
      final cameraState = _cameraKey.currentState;
      if (cameraState != null) {
        cameraState.loadSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryMid,
          border: Border(
            top: BorderSide(
              color: AppColors.border.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onTabChanged,
          backgroundColor: Colors.transparent,
          elevation: 0,
          height: 68,
          indicatorColor: AppColors.accent.withValues(alpha: 0.15),
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.camera_alt_outlined,
                  color: _currentIndex == 0
                      ? AppColors.accent
                      : AppColors.textMuted),
              selectedIcon:
                  const Icon(Icons.camera_alt, color: AppColors.accent),
              label: AppStrings.camera,
            ),
            NavigationDestination(
              icon: Icon(Icons.photo_library_outlined,
                  color: _currentIndex == 1
                      ? AppColors.accent
                      : AppColors.textMuted),
              selectedIcon:
                  const Icon(Icons.photo_library, color: AppColors.accent),
              label: AppStrings.gallery,
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined,
                  color: _currentIndex == 2
                      ? AppColors.accent
                      : AppColors.textMuted),
              selectedIcon: const Icon(Icons.map, color: AppColors.accent),
              label: AppStrings.map,
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined,
                  color: _currentIndex == 3
                      ? AppColors.accent
                      : AppColors.textMuted),
              selectedIcon:
                  const Icon(Icons.settings, color: AppColors.accent),
              label: AppStrings.settings,
            ),
          ],
        ),
      ),
    );
  }
}


