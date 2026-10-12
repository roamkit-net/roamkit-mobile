import 'package:flutter/material.dart';

import 'store_screen.dart';

void main() {
  runApp(const RoamKitStoreApp());
}

class RoamKitStoreApp extends StatelessWidget {
  const RoamKitStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoamKit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4C6FFF)),
        splashFactory: NoSplash.splashFactory,
      ),
      home: const StoreScreen(loadCatalog: true),
    );
  }
}
