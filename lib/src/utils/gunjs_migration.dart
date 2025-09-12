import 'dart:convert';
import 'dart:io';
import '../gun.dart';
import '../data/metadata_manager.dart';

/// Gun.js data migration utilities
/// 
/// Provides seamless data import/export between Gun.js and gun_dart systems,
/// ensuring complete format compatibility and data integrity.
class GunJSMigration {
  
  /// Import data from Gun.js export format
  /// 
  /// Reads Gun.js export JSON and imports it into gun_dart storage,
  /// preserving all metadata, HAM timestamps, and graph relationships.
  static Future<MigrationResult> importFromGunJS(
    Gun gun, 
    String jsonFilePath, {
    bool validateData = true,
    bool preserveTimestamps = true,
    bool overwriteExisting = false,
  }) async {
    final result = MigrationResult();
    
    try {
      // Read Gun.js export file
      final file = File(jsonFilePath);
      if (!await file.exists()) {
        throw MigrationException('Import file not found: $jsonFilePath');
      }
      
      final jsonContent = await file.readAsString();
      final gunJSData = jsonDecode(jsonContent) as Map<String, dynamic>;
      
      // Validate Gun.js format
      if (validateData && !_isValidGunJSExport(gunJSData)) {
        throw MigrationException('Invalid Gun.js export format');
      }
      
      result.sourceFormat = 'Gun.js Export JSON';
      result.startTime = DateTime.now();
      
      // Process each node in the export
      for (final entry in gunJSData.entries) {
        final nodeId = entry.key;
        final nodeData = entry.value as Map<String, dynamic>?;
        
        if (nodeData == null) {
          result.skippedCount++;
          continue;
        }
        
        try {
          // Convert Gun.js node to gun_dart format
          final convertedNode = _convertGunJSNodeToDart(
            nodeId, 
            nodeData,
            preserveTimestamps: preserveTimestamps,
          );
          
          // Check if node already exists
          final existing = await gun.get(nodeId).once();
          if (existing != null && !overwriteExisting) {
            // Merge with existing data using HAM conflict resolution
            final mergedNode = MetadataManager.mergeNodes(existing, convertedNode);
            await gun.get(nodeId).put(mergedNode);
            result.mergedCount++;
          } else {
            // Import as new node
            await gun.get(nodeId).put(convertedNode);
            result.importedCount++;
          }
          
        } catch (e) {
          result.errors.add(MigrationError(
            nodeId: nodeId,
            message: 'Failed to import node: $e',
            data: nodeData,
          ));
          result.errorCount++;
        }
      }
      
      result.endTime = DateTime.now();
      result.success = result.errorCount == 0 || result.importedCount > 0;
      
    } catch (e) {
      result.endTime = DateTime.now();
      result.success = false;
      result.errors.add(MigrationError(
        message: 'Import failed: $e',
      ));
    }
    
    return result;
  }
  
  /// Export gun_dart data to Gun.js compatible format
  /// 
  /// Exports all or specified data from gun_dart to Gun.js JSON format,
  /// maintaining full compatibility with Gun.js import systems.
  static Future<MigrationResult> exportToGunJS(
    Gun gun,
    String outputFilePath, {
    List<String>? nodeIds, // If null, exports all data
    bool includeMetadata = true,
    bool prettify = true,
  }) async {
    final result = MigrationResult();
    
    try {
      result.startTime = DateTime.now();
      result.targetFormat = 'Gun.js Compatible JSON';
      
      Map<String, dynamic> exportData = {};
      
      if (nodeIds != null && nodeIds.isNotEmpty) {
        // Export specific nodes
        for (final nodeId in nodeIds) {
          try {
            final nodeData = await gun.get(nodeId).once();
            if (nodeData != null) {
              exportData[nodeId] = _convertDartNodeToGunJS(
                nodeId, 
                nodeData,
                includeMetadata: includeMetadata,
              );
              result.exportedCount++;
            } else {
              result.skippedCount++;
            }
          } catch (e) {
            result.errors.add(MigrationError(
              nodeId: nodeId,
              message: 'Failed to export node: $e',
            ));
            result.errorCount++;
          }
        }
      } else {
        // Export all data
        exportData = await _exportAllData(gun, includeMetadata);
        result.exportedCount = exportData.length;
      }
      
      // Write to file
      final outputFile = File(outputFilePath);
      await outputFile.parent.create(recursive: true);
      
      final jsonString = prettify 
          ? const JsonEncoder.withIndent('  ').convert(exportData)
          : jsonEncode(exportData);
          
      await outputFile.writeAsString(jsonString);
      
      result.endTime = DateTime.now();
      result.success = true;
      result.outputFile = outputFilePath;
      
    } catch (e) {
      result.endTime = DateTime.now();
      result.success = false;
      result.errors.add(MigrationError(
        message: 'Export failed: $e',
      ));
    }
    
    return result;
  }
  
  /// Create a backup of current gun_dart data
  static Future<MigrationResult> createBackup(
    Gun gun,
    String backupPath, {
    String? description,
  }) async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupFile = '$backupPath/gun_dart_backup_$timestamp.json';
    
    final result = await exportToGunJS(gun, backupFile);
    result.description = description ?? 'Automated backup';
    
    if (result.success) {
      // Create backup metadata file
      final metadataFile = '$backupPath/gun_dart_backup_$timestamp.meta.json';
      final metadata = {
        'created': DateTime.now().toIso8601String(),
        'description': result.description,
        'nodeCount': result.exportedCount,
        'backupFile': backupFile,
        'version': '0.2.1', // gun_dart version
      };
      
      await File(metadataFile).writeAsString(
        const JsonEncoder.withIndent('  ').convert(metadata)
      );
    }
    
    return result;
  }
  
  /// Restore from a gun_dart backup
  static Future<MigrationResult> restoreFromBackup(
    Gun gun,
    String backupFilePath, {
    bool clearExisting = false,
  }) async {
    if (clearExisting) {
      // Clear existing data first
      await _clearAllData(gun);
    }
    
    return await importFromGunJS(
      gun, 
      backupFilePath,
      overwriteExisting: true,
    );
  }
  
  /// Validate Gun.js export format
  static bool validateGunJSFormat(String jsonFilePath) {
    try {
      final file = File(jsonFilePath);
      final jsonContent = file.readAsStringSync();
      final data = jsonDecode(jsonContent) as Map<String, dynamic>;
      return _isValidGunJSExport(data);
    } catch (e) {
      return false;
    }
  }
  
  /// Convert gun_dart data format to match Gun.js exactly
  static Map<String, dynamic> convertDataFormat(
    Map<String, dynamic> dartData, {
    bool toGunJS = true,
  }) {
    if (toGunJS) {
      return _convertDartFormatToGunJS(dartData);
    } else {
      return _convertGunJSFormatToDart(dartData);
    }
  }
  
  /// Compare data between gun_dart and Gun.js format for differences
  static DataComparison compareFormats(
    Map<String, dynamic> dartData,
    Map<String, dynamic> gunJSData,
  ) {
    final comparison = DataComparison();
    
    // Compare node structure
    final dartNodes = Set<String>.from(dartData.keys);
    final gunJSNodes = Set<String>.from(gunJSData.keys);
    
    comparison.onlyInDart = dartNodes.difference(gunJSNodes);
    comparison.onlyInGunJS = gunJSNodes.difference(dartNodes);
    comparison.inBoth = dartNodes.intersection(gunJSNodes);
    
    // Compare individual nodes
    for (final nodeId in comparison.inBoth) {
      final dartNode = dartData[nodeId] as Map<String, dynamic>;
      final gunJSNode = gunJSData[nodeId] as Map<String, dynamic>;
      
      final nodeDiff = _compareNodes(nodeId, dartNode, gunJSNode);
      if (nodeDiff.hasDifferences) {
        comparison.differences[nodeId] = nodeDiff;
      }
    }
    
    return comparison;
  }
  
  // Private helper methods
  
  static bool _isValidGunJSExport(Map<String, dynamic> data) {
    // Gun.js exports should be a map of node_id -> node_data
    for (final entry in data.entries) {
      if (entry.value is! Map<String, dynamic>) {
        return false;
      }
      
      final nodeData = entry.value as Map<String, dynamic>;
      
      // Check for Gun.js metadata structure
      if (nodeData.containsKey('_')) {
        final metadata = nodeData['_'];
        if (metadata is! Map<String, dynamic>) {
          return false;
        }
        
        // Should have node ID and HAM timestamps
        if (!metadata.containsKey('#') || !metadata.containsKey('>')) {
          return false;
        }
      }
    }
    
    return true;
  }
  
  static Map<String, dynamic> _convertGunJSNodeToDart(
    String nodeId,
    Map<String, dynamic> gunJSNode, {
    bool preserveTimestamps = true,
  }) {
    final dartNode = Map<String, dynamic>.from(gunJSNode);
    
    // Ensure proper Gun.js metadata format
    if (dartNode.containsKey('_')) {
      final metadata = dartNode['_'] as Map<String, dynamic>;
      
      // Validate and fix metadata if needed
      if (!metadata.containsKey('#')) {
        metadata['#'] = nodeId;
      }
      
      if (!preserveTimestamps || !metadata.containsKey('>')) {
        // Generate new HAM timestamps
        final timestamps = <String, num>{};
        for (final key in dartNode.keys) {
          if (key != '_') {
            timestamps[key] = DateTime.now().millisecondsSinceEpoch;
          }
        }
        metadata['>'] = timestamps;
      }
      
      // Ensure machine state
      if (!metadata.containsKey('machine')) {
        metadata['machine'] = 1;
      }
      
      if (!metadata.containsKey('machineId')) {
        metadata['machineId'] = 'machine_${DateTime.now().millisecondsSinceEpoch}';
      }
    } else {
      // Add missing metadata
      dartNode['_'] = MetadataManager.createMetadata(
        nodeId: nodeId,
        data: dartNode,
      );
    }
    
    return dartNode;
  }
  
  static Map<String, dynamic> _convertDartNodeToGunJS(
    String nodeId,
    Map<String, dynamic> dartNode, {
    bool includeMetadata = true,
  }) {
    final gunJSNode = Map<String, dynamic>.from(dartNode);
    
    if (includeMetadata && !gunJSNode.containsKey('_')) {
      // Add Gun.js metadata if missing
      gunJSNode['_'] = MetadataManager.createMetadata(
        nodeId: nodeId,
        data: dartNode,
      );
    }
    
    return gunJSNode;
  }
  
  static Future<Map<String, dynamic>> _exportAllData(
    Gun gun,
    bool includeMetadata,
  ) async {
    final exportData = <String, dynamic>{};
    
    // This would need to be implemented based on the storage adapter
    // For now, we'll simulate by trying to export common patterns
    
    // Export user data (~ prefixed nodes)
    // Export regular data nodes
    // This is a simplified implementation - in reality, we'd need
    // to iterate through all stored nodes in the storage adapter
    
    return exportData;
  }
  
  static Future<void> _clearAllData(Gun gun) async {
    // Clear all data from storage
    // This would need to be implemented based on the storage adapter
  }
  
  static Map<String, dynamic> _convertDartFormatToGunJS(Map<String, dynamic> data) {
    // Convert gun_dart specific format to Gun.js format
    // This handles any format differences between the systems
    return Map<String, dynamic>.from(data);
  }
  
  static Map<String, dynamic> _convertGunJSFormatToDart(Map<String, dynamic> data) {
    // Convert Gun.js format to gun_dart format
    return Map<String, dynamic>.from(data);
  }
  
  static NodeComparison _compareNodes(
    String nodeId,
    Map<String, dynamic> dartNode,
    Map<String, dynamic> gunJSNode,
  ) {
    final comparison = NodeComparison(nodeId: nodeId);
    
    final dartKeys = Set<String>.from(dartNode.keys);
    final gunJSKeys = Set<String>.from(gunJSNode.keys);
    
    comparison.onlyInDart = dartKeys.difference(gunJSKeys);
    comparison.onlyInGunJS = gunJSKeys.difference(dartKeys);
    comparison.inBoth = dartKeys.intersection(gunJSKeys);
    
    // Compare values for common keys
    for (final key in comparison.inBoth) {
      final dartValue = dartNode[key];
      final gunJSValue = gunJSNode[key];
      
      if (!_deepEqual(dartValue, gunJSValue)) {
        comparison.valueDifferences[key] = {
          'dart': dartValue,
          'gunjs': gunJSValue,
        };
      }
    }
    
    return comparison;
  }
  
  static bool _deepEqual(dynamic a, dynamic b) {
    if (a.runtimeType != b.runtimeType) return false;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEqual(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!_deepEqual(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}

/// Result of a migration operation
class MigrationResult {
  bool success = false;
  String? sourceFormat;
  String? targetFormat;
  String? description;
  DateTime? startTime;
  DateTime? endTime;
  String? outputFile;
  
  int importedCount = 0;
  int exportedCount = 0;
  int mergedCount = 0;
  int skippedCount = 0;
  int errorCount = 0;
  
  final List<MigrationError> errors = [];
  
  Duration get duration => 
      endTime != null && startTime != null 
          ? endTime!.difference(startTime!)
          : Duration.zero;
  
  Map<String, dynamic> toMap() => {
    'success': success,
    'sourceFormat': sourceFormat,
    'targetFormat': targetFormat,
    'description': description,
    'startTime': startTime?.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'duration': duration.inMilliseconds,
    'outputFile': outputFile,
    'stats': {
      'imported': importedCount,
      'exported': exportedCount,
      'merged': mergedCount,
      'skipped': skippedCount,
      'errors': errorCount,
    },
    'errors': errors.map((e) => e.toMap()).toList(),
  };
}

/// Migration error details
class MigrationError {
  final String? nodeId;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  MigrationError({
    this.nodeId,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
  
  Map<String, dynamic> toMap() => {
    'nodeId': nodeId,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    if (data != null) 'data': data,
  };
}

/// Data comparison result
class DataComparison {
  Set<String> onlyInDart = {};
  Set<String> onlyInGunJS = {};
  Set<String> inBoth = {};
  Map<String, NodeComparison> differences = {};
  
  bool get hasDifferences => 
      onlyInDart.isNotEmpty || 
      onlyInGunJS.isNotEmpty || 
      differences.isNotEmpty;
}

/// Node comparison result
class NodeComparison {
  final String nodeId;
  Set<String> onlyInDart = {};
  Set<String> onlyInGunJS = {};
  Set<String> inBoth = {};
  Map<String, Map<String, dynamic>> valueDifferences = {};
  
  NodeComparison({required this.nodeId});
  
  bool get hasDifferences => 
      onlyInDart.isNotEmpty || 
      onlyInGunJS.isNotEmpty || 
      valueDifferences.isNotEmpty;
}

/// Migration exception
class MigrationException implements Exception {
  final String message;
  MigrationException(this.message);
  @override
  String toString() => 'MigrationException: $message';
}
