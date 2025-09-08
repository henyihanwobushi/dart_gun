import 'package:flutter/material.dart';
import '../gun.dart';
import '../types/types.dart';

/// A Flutter widget that provides Gun instance to its descendants via InheritedWidget
class GunProvider extends InheritedWidget {
  /// The Gun instance to provide
  final Gun gun;

  const GunProvider({
    Key? key,
    required this.gun,
    required Widget child,
  }) : super(key: key, child: child);

  /// Get the Gun instance from the widget tree
  static Gun of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<GunProvider>();
    if (provider == null) {
      throw FlutterError(
        'GunProvider.of() called with a context that does not contain a GunProvider.\n'
        'Make sure that GunProvider is an ancestor of the widget that is calling '
        'GunProvider.of().',
      );
    }
    return provider.gun;
  }

  /// Get the Gun instance from the widget tree, returning null if not found
  static Gun? maybeOf(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<GunProvider>();
    return provider?.gun;
  }

  @override
  bool updateShouldNotify(GunProvider oldWidget) {
    return gun != oldWidget.gun;
  }
}

/// A convenience widget that creates and manages a Gun instance
class GunApp extends StatefulWidget {
  /// Options to configure the Gun instance
  final GunOptions? gunOptions;
  
  /// The child widget
  final Widget child;
  
  /// Called when Gun instance is created
  final void Function(Gun gun)? onGunCreated;

  const GunApp({
    Key? key,
    this.gunOptions,
    required this.child,
    this.onGunCreated,
  }) : super(key: key);

  @override
  State<GunApp> createState() => _GunAppState();
}

class _GunAppState extends State<GunApp> {
  late Gun _gun;

  @override
  void initState() {
    super.initState();
    _gun = Gun(widget.gunOptions);
    widget.onGunCreated?.call(_gun);
  }

  @override
  void dispose() {
    _gun.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GunProvider(
      gun: _gun,
      child: widget.child,
    );
  }
}

/// Extension to easily access Gun from BuildContext
extension GunContext on BuildContext {
  /// Get the Gun instance from the widget tree
  Gun get gun => GunProvider.of(this);
  
  /// Get the Gun instance from the widget tree, returning null if not found
  Gun? get gunOrNull => GunProvider.maybeOf(this);
}
