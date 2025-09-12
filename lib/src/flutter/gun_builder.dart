import 'package:flutter/material.dart';
import '../gun_chain.dart';

/// A Flutter widget that builds UI based on Gun data and automatically updates
/// when the data changes in real-time
class GunBuilder<T> extends StatefulWidget {
  /// The Gun chain reference to watch for data changes
  final GunChain chain;
  
  /// Builder function that creates UI from the current data
  final Widget Function(BuildContext context, T? data, bool isLoading) builder;
  
  /// Optional transformation function to convert raw data to desired type
  final T Function(dynamic data)? transform;
  
  /// Optional loading widget to show while data is being fetched
  final Widget? loadingWidget;
  
  /// Optional error widget to show when data loading fails
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  
  const GunBuilder({
    Key? key,
    required this.chain,
    required this.builder,
    this.transform,
    this.loadingWidget,
    this.errorBuilder,
  }) : super(key: key);

  @override
  State<GunBuilder<T>> createState() => _GunBuilderState<T>();
}

class _GunBuilderState<T> extends State<GunBuilder<T>> {
  T? _data;
  bool _isLoading = true;
  Object? _error;
  late Stream<dynamic> _dataStream;
  
  @override
  void initState() {
    super.initState();
    _setupDataStream();
    _loadInitialData();
  }
  
  void _setupDataStream() {
    // Create a stream that emits when data changes
    _dataStream = Stream.periodic(Duration(milliseconds: 100))
        .asyncMap((_) => widget.chain.once())
        .distinct();
    
    _dataStream.listen(
      (data) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = null;
            try {
              _data = widget.transform != null && data != null 
                  ? widget.transform!(data) 
                  : data as T?;
            } catch (e) {
              _error = e;
            }
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = error;
          });
        }
      },
    );
  }
  
  void _loadInitialData() async {
    try {
      final data = await widget.chain.once();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _data = widget.transform != null && data != null 
              ? widget.transform!(data) 
              : data as T?;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = error;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_error != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context, _error!);
    }
    
    if (_isLoading && widget.loadingWidget != null) {
      return widget.loadingWidget!;
    }
    
    return widget.builder(context, _data, _isLoading);
  }
}

/// A simplified Gun builder for common use cases
class GunText extends StatelessWidget {
  /// The Gun chain reference to get text data from
  final GunChain chain;
  
  /// Text style to apply
  final TextStyle? style;
  
  /// Text to show while loading
  final String loadingText;
  
  /// Text to show when data is null
  final String emptyText;
  
  const GunText({
    Key? key,
    required this.chain,
    this.style,
    this.loadingText = 'Loading...',
    this.emptyText = '',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GunBuilder<String>(
      chain: chain,
      transform: (data) => data?.toString() ?? emptyText,
      builder: (context, text, isLoading) {
        return Text(
          isLoading ? loadingText : text ?? emptyText,
          style: style,
        );
      },
    );
  }
}

/// A Gun-powered ListView that automatically updates
class GunListView<T> extends StatelessWidget {
  /// The Gun chain reference to get list data from
  final GunChain chain;
  
  /// Builder function for each list item
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  
  /// Transformation function to convert raw data to list items
  final List<T> Function(dynamic data) transform;
  
  /// Widget to show while loading
  final Widget? loadingWidget;
  
  /// Widget to show when list is empty
  final Widget? emptyWidget;
  
  /// ListView properties
  final ScrollController? controller;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  
  const GunListView({
    Key? key,
    required this.chain,
    required this.itemBuilder,
    required this.transform,
    this.loadingWidget,
    this.emptyWidget,
    this.controller,
    this.shrinkWrap = false,
    this.physics,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GunBuilder<List<T>>(
      chain: chain,
      transform: transform,
      loadingWidget: loadingWidget ?? const Center(child: CircularProgressIndicator()),
      builder: (context, items, isLoading) {
        if (isLoading) {
          return loadingWidget ?? const Center(child: CircularProgressIndicator());
        }
        
        if (items == null || items.isEmpty) {
          return emptyWidget ?? SizedBox.shrink();
        }
        
        return ListView.builder(
          controller: controller,
          shrinkWrap: shrinkWrap,
          physics: physics,
          itemCount: items.length,
          itemBuilder: (context, index) => itemBuilder(context, items[index], index),
        );
      },
    );
  }
}
