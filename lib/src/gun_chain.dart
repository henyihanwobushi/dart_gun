import 'dart:async';
import 'gun.dart';
import 'network/gun_query.dart';
import 'network/gun_wire_protocol.dart';
import 'types/types.dart';
import 'types/events.dart';
import 'data/metadata_manager.dart';

/// Represents a chainable reference to Gun data
/// Similar to Gun.js chain API
class GunChain {
  final Gun _gun;
  final String _key;
  final List<String> _path;
  
  GunChain(this._gun, this._key, [this._path = const []]);
  
  /// Get a child node by key
  GunChain get(String key) {
    // Build the new path by adding the current key to the existing path
    final currentPath = <String>[..._path, _key];
    return GunChain(_gun, key, currentPath);
  }
  
  /// Put data at this node
  Future<GunChain> put(dynamic data, [Function? callback]) async {
    try {
      final fullKey = [..._path, _key].join('/');
      Map<String, dynamic> dataMap;
      
      if (data is Map<String, dynamic>) {
        dataMap = data;
      } else {
        dataMap = {'_': data};
      }
      
      // IMPORTANT: Flatten nested objects for Gun.js wire protocol compatibility
      // Gun.js expects nested objects to be stored as separate nodes with references
      final flattenedNodes = await _flattenNestedData(fullKey, dataMap);
      
      // Store each flattened node
      for (final entry in flattenedNodes.entries) {
        final nodeKey = entry.key;
        final nodeData = entry.value;
        
        // Storage adapter will handle metadata automatically
        await _gun.storage.put(nodeKey, nodeData);
        
        // Add metadata for the graph as well (if not already present)
        final metaNodeData = MetadataManager.isValidNode(nodeData) 
            ? nodeData 
            : MetadataManager.addMetadata(
                nodeId: MetadataManager.generateNodeId(nodeKey),
                data: nodeData,
              );
        
        // Update the graph
        _gun.graph.putNode(nodeKey, metaNodeData);
        
        // Emit event for subscribers
        _gun.eventController.add(GunEvent(
          type: GunEventType.put,
          key: nodeKey,
          data: metaNodeData,
        ));
        
        // IMPORTANT: Send PUT message to network peers for synchronization
        await _sendPutToPeers(nodeKey, metaNodeData);
      }
      
      // IMPORTANT: For chained operations, we need to create hierarchical structure
      // so Gun.js can traverse the chain properly
      final rootNodeData = flattenedNodes[fullKey];
      if (rootNodeData != null) {
        await _createHierarchicalStructure(fullKey, rootNodeData);
      }
      
      callback?.call(null);
      return this;
    } catch (error) {
      callback?.call(error);
      rethrow;
    }
  }
  
  /// Subscribe to changes on this node
  StreamSubscription on(GunListener listener) {
    final fullKey = [..._path, _key].join('/');
    
    // Listen to gun events and filter for our key
    return _gun.eventController.stream
        .where((event) => event.key == fullKey)
        .listen((event) {
      listener(event.data, event.key);
    });
  }
  
  /// Get data once from this node
  Future<dynamic> once([Function? callback]) async {
    try {
      final fullKey = [..._path, _key].join('/');
      
      // Always try network query first to get the most up-to-date data
      // (including conflict resolutions from peers), then fall back to local
      
      // Create a Gun.js compatible query
      final rootNode = _path.isNotEmpty ? _path.first : _key;
      final queryPath = _path.length > 1 
          ? [..._path.skip(1), _key]
          : _path.isEmpty 
              ? <String>[]
              : [_key];
      
      final query = GunQuery(
        nodeId: rootNode,
        path: queryPath,
        callback: callback,
      );
      
      // Execute the query through Gun instance
      final result = await _gun.executeQuery(query);
      
      // If query found data, prefer fresh data over potentially stale local state
      if (result.isSuccess && result.data != null) {
        // If the just-fetched data looks potentially stale (e.g., older timestamps),
        // retry once to allow any in-flight broadcasts/resolutions to land.
        if (_shouldRetryForStaleData(result.data!)) {
          print('GunChain: Network result may be stale, retrying once for fresher data');
          await Future.delayed(const Duration(milliseconds: 800));
          final retryResult = await _gun.executeQuery(query);
          if (retryResult.isSuccess && retryResult.data != null) {
            // Use fresher data if available
            await _gun.storage.put(fullKey, retryResult.data!);
            _gun.graph.putNode(fullKey, retryResult.data!);
            _gun.eventController.add(GunEvent(
              type: GunEventType.put,
              key: fullKey,
              data: retryResult.data!,
            ));
            final unflattenedRetry = await _unflattenData(fullKey, retryResult.data!);
            return unflattenedRetry;
          }
        }

        // Store the successful query result locally for future access
        await _gun.storage.put(fullKey, result.data!);
        
        // Also update the graph
        _gun.graph.putNode(fullKey, result.data!);
        
        // Emit event for subscribers to know about the new data
        _gun.eventController.add(GunEvent(
          type: GunEventType.put,
          key: fullKey,
          data: result.data!,
        ));
        
        // Unflatten the data to reconstruct nested structure
        final unflattenedData = await _unflattenData(fullKey, result.data!);
        return unflattenedData;
      }
      
      // If network query failed or returned no data, check local storage
      final local = await _gun.storage.get(fullKey);
      if (local != null) {
        // For interoperability with Gun.js conflict resolution, 
        // retry the network query once if local data seems stale
        // (this handles cases where Gun.js resolves conflicts after our initial query)
        if (result.error == null && _shouldRetryForStaleData(local)) {
          print('GunChain: Retrying network query for potentially stale data');
          await Future.delayed(Duration(milliseconds: 1000)); // Wait for potential broadcasts
          
          final retryResult = await _gun.executeQuery(query);
          if (retryResult.isSuccess && retryResult.data != null) {
            // Got fresher data from network
            await _gun.storage.put(fullKey, retryResult.data!);
            _gun.graph.putNode(fullKey, retryResult.data!);
            
            _gun.eventController.add(GunEvent(
              type: GunEventType.put,
              key: fullKey,
              data: retryResult.data!,
            ));
            
            // Unflatten the data to reconstruct nested structure
            final unflattenedData = await _unflattenData(fullKey, retryResult.data!);
            callback?.call(unflattenedData, null);
            return unflattenedData;
          }
        }
        
        // Unflatten the local data to reconstruct nested structure
        final unflattenedLocal = await _unflattenData(fullKey, local);
        callback?.call(unflattenedLocal, null);
        return unflattenedLocal;
      }
      
      // If query completed but no data, wait briefly for potential WebSocket sync
      if (result.data == null && result.error == null) {
        // Wait longer for WebSocket data to arrive (Gun.js interop timing)
        await Future.delayed(Duration(seconds: 2));
        
        // Check local storage one more time after delay
        final retryLocal = await _gun.storage.get(fullKey);
        if (retryLocal != null) {
          // Unflatten the delayed retry data to reconstruct nested structure
          final unflattenedRetry = await _unflattenData(fullKey, retryLocal);
          callback?.call(unflattenedRetry, null);
          return unflattenedRetry;
        }
        
        // No data found - this is normal Gun.js behavior
        callback?.call(null, null);
        return null;
      }
      
      // Handle query errors
      if (result.error != null) {
        final error = result.error!;
        callback?.call(null, error);
        throw Exception(error);
      }
      
      // This should not be reached, but handle gracefully
      callback?.call(null, null);
      return null;
    } catch (error) {
      callback?.call(null, error.toString());
      rethrow;
    }
  }
  
  /// Map over a set of data
  /// 
  /// Iterates over child nodes and calls the provided callback for each.
  /// This is useful for working with collections of data.
  Future<List<MapEntry<String, dynamic>>> map([Function? callback]) async {
    final fullKey = [..._path, _key].join('/');
    final results = <MapEntry<String, dynamic>>[];
    
    try {
      // Get all keys that start with our path
      final allKeys = await _gun.storage.keys();
      final childKeys = allKeys
          .where((key) => key.startsWith('$fullKey/'))
          .map((key) => key.substring('$fullKey/'.length))
          .where((subKey) => !subKey.contains('/')) // Only direct children
          .toList();
      
      // Process each child
      for (final childKey in childKeys) {
        final childData = await _gun.storage.get('$fullKey/$childKey');
        if (childData != null) {
          final entry = MapEntry(childKey, childData);
          results.add(entry);
          callback?.call(childData, childKey);
        }
      }
    } catch (error) {
      callback?.call(null, error);
    }
    
    return results;
  }
  
  /// Create hierarchical structure for proper Gun.js traversal
  /// 
  /// For chained operations like gun.get('chat').get('messages').get('latest'),
  /// we need to ensure each level in the hierarchy points to the next level
  Future<void> _createHierarchicalStructure(String fullKey, Map<String, dynamic> finalData) async {
    final pathSegments = fullKey.split('/');
    
    // Only create hierarchy if we have a multi-level path
    if (pathSegments.length <= 1) return;
    
    try {
      // Work backwards from the final level to create parent links
      for (int i = pathSegments.length - 1; i > 0; i--) {
        final currentPath = pathSegments.take(i).join('/');
        final childKey = pathSegments[i];
        final childPath = pathSegments.take(i + 1).join('/');
        
        // Get or create parent node
        final existingParent = await _gun.storage.get(currentPath);
        final parentData = existingParent ?? <String, dynamic>{};
        
        // Create link to child - Gun.js uses node references
        parentData[childKey] = {'#': childPath};
        
        // Ensure parent has proper metadata
        final parentNodeData = MetadataManager.isValidNode(parentData)
            ? parentData
            : MetadataManager.addMetadata(
                nodeId: MetadataManager.generateNodeId(currentPath),
                data: parentData,
              );
        
        // Store the parent node
        await _gun.storage.put(currentPath, parentNodeData);
        _gun.graph.putNode(currentPath, parentNodeData);
        
        // Send parent node to peers as well
        await _sendPutToPeers(currentPath, parentNodeData);
      }
    } catch (e) {
      print('GunChain: Failed to create hierarchical structure: $e');
      // Don't throw - the main data is still stored
    }
  }
  
  /// Send PUT message to network peers for synchronization
  Future<void> _sendPutToPeers(String nodeKey, Map<String, dynamic> nodeData) async {
    try {
      // Create Gun.js compatible PUT message using wire protocol
      final putMessage = GunWireProtocol.createPutMessage(nodeKey, nodeData);
      
      // Send to all connected peers
      for (final peer in _gun.peers) {
        if (peer.isConnected) {
          await peer.send(putMessage);
        }
      }
    } catch (e) {
      print('GunChain: Failed to send PUT to peers: $e');
      // Don't throw - local operation should still succeed
    }
  }
  
  /// Flatten nested data structures into separate Gun nodes with references
  /// 
  /// Gun.js wire protocol expects nested objects to be stored as separate nodes
  /// with references between them rather than as single nested structures.
  /// 
  /// For example:
  /// {
  ///   'user': {
  ///     'profile': {
  ///       'name': 'Alice'
  ///     }
  ///   }
  /// }
  /// 
  /// Becomes:
  /// - 'key' -> { 'user': {'#': 'key/user'} }
  /// - 'key/user' -> { 'profile': {'#': 'key/user/profile'} }
  /// - 'key/user/profile' -> { 'name': 'Alice' }
  Future<Map<String, Map<String, dynamic>>> _flattenNestedData(
    String baseKey, 
    Map<String, dynamic> data,
  ) async {
    final result = <String, Map<String, dynamic>>{};
    final rootData = <String, dynamic>{};
    
    for (final entry in data.entries) {
      final fieldKey = entry.key;
      final fieldValue = entry.value;
      
      // Skip Gun.js metadata fields
      if (fieldKey == '_') {
        rootData[fieldKey] = fieldValue;
        continue;
      }
      
      // If the value is a nested object, flatten it recursively
      if (fieldValue is Map<String, dynamic>) {
        final nestedKey = '$baseKey/$fieldKey';
        
        // Store reference to nested node in root
        rootData[fieldKey] = {'#': nestedKey};
        
        // Recursively flatten the nested structure
        final nestedResults = await _flattenNestedData(nestedKey, fieldValue);
        result.addAll(nestedResults);
      } else {
        // Simple value, store directly in root
        rootData[fieldKey] = fieldValue;
      }
    }
    
    // Store the root node
    result[baseKey] = rootData;
    
    return result;
  }
  
  /// Unflatten Gun.js flattened data to reconstruct original nested structure
  /// 
  /// Takes flattened Gun nodes with references and reconstructs the original
  /// nested object structure that the user expects.
  /// 
  /// For example, given flattened nodes:
  /// - 'key' -> { 'user': {'#': 'key/user'} }
  /// - 'key/user' -> { 'profile': {'#': 'key/user/profile'} }
  /// - 'key/user/profile' -> { 'name': 'Alice' }
  /// 
  /// Reconstructs:
  /// {
  ///   'user': {
  ///     'profile': {
  ///       'name': 'Alice'
  ///     }
  ///   }
  /// }
  Future<Map<String, dynamic>> _unflattenData(
    String baseKey,
    Map<String, dynamic> data,
  ) async {
    final result = <String, dynamic>{};
    
    for (final entry in data.entries) {
      final fieldKey = entry.key;
      final fieldValue = entry.value;
      
      // Skip Gun.js metadata fields (preserve them as-is)
      if (fieldKey == '_') {
        result[fieldKey] = fieldValue;
        continue;
      }
      
      // Check if this is a reference to another node
      if (fieldValue is Map<String, dynamic> && fieldValue.containsKey('#')) {
        final referencedKey = fieldValue['#'] as String;
        
        try {
          // Try to load the referenced node
          final referencedData = await _gun.storage.get(referencedKey);
          
          if (referencedData != null) {
            // Recursively unflatten the referenced node
            final unflattenedRef = await _unflattenData(referencedKey, referencedData);
            result[fieldKey] = unflattenedRef;
          } else {
            // Referenced node not found, keep the reference as-is
            result[fieldKey] = fieldValue;
          }
        } catch (e) {
          // Error loading referenced node, keep the reference as-is
          result[fieldKey] = fieldValue;
        }
      } else {
        // Simple value, store directly
        result[fieldKey] = fieldValue;
      }
    }
    
    return result;
  }
  
  /// Check if local data might be stale and warrant a network retry
  /// This helps with Gun.js interoperability where conflict resolution happens asynchronously
  bool _shouldRetryForStaleData(Map<String, dynamic> localData) {
    try {
      // Check if this looks like data that might have been resolved by Gun.js conflict resolution
      final meta = localData['_'] as Map<String, dynamic>?;
      if (meta == null) return false;
      
      final timestamps = meta['>'] as Map<String, dynamic>?;
      if (timestamps == null) return false;
      
      // If the data was written recently (within last 30 seconds), it might be part of
      // a conflict resolution scenario where Gun.js is still processing newer updates
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      for (final timestampValue in timestamps.values) {
        if (timestampValue is num) {
          final dataAge = currentTime - timestampValue;
          if (dataAge < 30000) { // Less than 30 seconds old
            return true; // Might be stale due to ongoing conflict resolution
          }
        }
      }
      return false;
    } catch (e) {
      // If we can't parse metadata, don't retry
      return false;
    }
  }
  
  /// Set data (for sets/arrays)
  /// 
  /// Adds data to a set-like structure using a unique key.
  /// Unlike put(), set() generates unique keys for each item.
  Future<GunChain> set(dynamic data, [Function? callback]) async {
    try {
      final fullKey = [..._path, _key].join('/');
      
      // Generate a unique key for this set item
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = (timestamp * 1000 + (data.hashCode & 0xFFFF)) & 0xFFFFFFFF;
      final uniqueKey = '$fullKey/${random.toRadixString(36)}';
      
      Map<String, dynamic> dataMap;
      if (data is Map<String, dynamic>) {
        dataMap = data;
      } else {
        dataMap = {'_': data};
      }
      
      // Store the data with the unique key
      await _gun.storage.put(uniqueKey, dataMap);
      
      // Update the graph
      _gun.graph.putNode(uniqueKey, dataMap);
      
      // Create a reference in the parent to maintain set structure
      final setRef = {'#': uniqueKey};
      final parentKey = [..._path, _key].join('/');
      final existing = await _gun.storage.get(parentKey) ?? <String, dynamic>{};
      
      // Add to the set structure
      existing[random.toRadixString(36)] = setRef;
      await _gun.storage.put(parentKey, existing);
      
      // Emit event for subscribers
      _gun.eventController.add(GunEvent(
        type: GunEventType.put,
        key: uniqueKey,
        data: data,
      ));
      
      callback?.call(null);
      return this;
    } catch (error) {
      callback?.call(error);
      rethrow;
    }
  }
}
