import '../utils/utils.dart';

/// Gun.js protocol version support and compatibility management
/// 
/// Handles version detection, negotiation, and backwards compatibility
/// with different versions of Gun.js protocol.
class ProtocolVersion {
  static const String currentVersion = '0.2020.1235';
  static const String dartImplementationVersion = '0.2.1';
  
  /// Supported Gun.js protocol versions
  static const Map<String, ProtocolCapabilities> supportedVersions = {
    '0.2020.1235': ProtocolCapabilities(
      supportsHAM: true,
      supportsWireProtocol: true,
      supportsSEA: true,
      supportsRelayServers: true,
      supportsDAMErrors: true,
      supportsPeerHandshake: true,
      supportsMetadata: true,
      messageFormat: MessageFormat.v2020,
    ),
    '0.2019.416': ProtocolCapabilities(
      supportsHAM: true,
      supportsWireProtocol: true,
      supportsSEA: true,
      supportsRelayServers: true,
      supportsDAMErrors: false,
      supportsPeerHandshake: true,
      supportsMetadata: true,
      messageFormat: MessageFormat.v2019,
    ),
    '0.2018.1201': ProtocolCapabilities(
      supportsHAM: true,
      supportsWireProtocol: true,
      supportsSEA: true,
      supportsRelayServers: true,
      supportsDAMErrors: false,
      supportsPeerHandshake: false,
      supportsMetadata: true,
      messageFormat: MessageFormat.v2018,
    ),
    '0.9.x': ProtocolCapabilities(
      supportsHAM: true,
      supportsWireProtocol: false,
      supportsSEA: false,
      supportsRelayServers: false,
      supportsDAMErrors: false,
      supportsPeerHandshake: false,
      supportsMetadata: false,
      messageFormat: MessageFormat.legacy,
    ),
  };
  
  /// Parse version string from Gun.js peer
  static String? parseVersion(dynamic versionData) {
    if (versionData is String) {
      return _normalizeVersion(versionData);
    } else if (versionData is Map<String, dynamic>) {
      // Some versions send version info as object
      final version = versionData['gun'] ?? versionData['version'] ?? versionData['v'];
      if (version is String) {
        return _normalizeVersion(version);
      }
    }
    return null;
  }
  
  /// Normalize version string to standard format
  static String _normalizeVersion(String version) {
    // Handle different version formats
    if (version.startsWith('v')) {
      version = version.substring(1);
    }
    
    // Convert semantic version to Gun.js format
    if (RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      // Convert from semantic versioning to Gun.js format
      // Parse semantic version components (currently unused)
      // final parts = version.split('.');
      // final major = int.tryParse(parts[0]) ?? 0;
      // final minor = int.tryParse(parts[1]) ?? 0;
      // final patch = int.tryParse(parts[2]) ?? 0;
      
      // Just return the normalized version as-is for now
      // Gun.js version format is complex and varies
    }
    
    return version;
  }
  
  /// Check if two versions are compatible
  static bool areCompatible(String version1, String version2) {
    final caps1 = getCapabilities(version1);
    final caps2 = getCapabilities(version2);
    
    if (caps1 == null || caps2 == null) {
      return false; // Unknown versions are not compatible
    }
    
    // Check core compatibility requirements
    return caps1.supportsHAM && caps2.supportsHAM &&
           caps1.messageFormat == caps2.messageFormat;
  }
  
  /// Get protocol capabilities for a version
  static ProtocolCapabilities? getCapabilities(String version) {
    final normalized = _normalizeVersion(version);
    
    // Direct match
    if (supportedVersions.containsKey(normalized)) {
      return supportedVersions[normalized];
    }
    
    // Pattern matching for version ranges
    for (final entry in supportedVersions.entries) {
      if (_matchesVersionPattern(normalized, entry.key)) {
        return entry.value;
      }
    }
    
    return null;
  }
  
  /// Check if version matches a pattern (like 0.9.x)
  static bool _matchesVersionPattern(String version, String pattern) {
    if (pattern.endsWith('.x')) {
      final prefix = pattern.substring(0, pattern.length - 2);
      return version.startsWith(prefix);
    }
    return version == pattern;
  }
  
  /// Negotiate best compatible version between peers
  static VersionNegotiationResult negotiateVersion({
    required String localVersion,
    required List<String> remoteVersions,
  }) {
    final localCaps = getCapabilities(localVersion);
    if (localCaps == null) {
      return VersionNegotiationResult(
        success: false,
        error: 'Unknown local version: $localVersion',
      );
    }
    
    // Find best compatible version
    String? bestVersion;
    ProtocolCapabilities? bestCaps;
    int bestScore = -1;
    
    for (final remoteVersion in remoteVersions) {
      if (areCompatible(localVersion, remoteVersion)) {
        final remoteCaps = getCapabilities(remoteVersion);
        if (remoteCaps != null) {
          final score = _calculateVersionScore(remoteCaps);
          if (score > bestScore) {
            bestScore = score;
            bestVersion = remoteVersion;
            bestCaps = remoteCaps;
          }
        }
      }
    }
    
    if (bestVersion != null && bestCaps != null) {
      return VersionNegotiationResult(
        success: true,
        negotiatedVersion: bestVersion,
        capabilities: bestCaps,
        localVersion: localVersion,
        remoteVersions: remoteVersions,
      );
    }
    
    return VersionNegotiationResult(
      success: false,
      error: 'No compatible version found',
      localVersion: localVersion,
      remoteVersions: remoteVersions,
    );
  }
  
  /// Calculate score for version capabilities (higher is better)
  static int _calculateVersionScore(ProtocolCapabilities caps) {
    int score = 0;
    if (caps.supportsHAM) score += 100;
    if (caps.supportsWireProtocol) score += 50;
    if (caps.supportsSEA) score += 30;
    if (caps.supportsRelayServers) score += 20;
    if (caps.supportsDAMErrors) score += 15;
    if (caps.supportsPeerHandshake) score += 10;
    if (caps.supportsMetadata) score += 5;
    return score;
  }
  
  /// Create version-specific message format
  static Map<String, dynamic> formatMessage(
    Map<String, dynamic> message,
    ProtocolCapabilities capabilities,
  ) {
    switch (capabilities.messageFormat) {
      case MessageFormat.v2020:
        return _formatV2020Message(message);
      case MessageFormat.v2019:
        return _formatV2019Message(message);
      case MessageFormat.v2018:
        return _formatV2018Message(message);
      case MessageFormat.legacy:
        return _formatLegacyMessage(message);
    }
  }
  
  /// Format message for Gun.js v2020+ format
  static Map<String, dynamic> _formatV2020Message(Map<String, dynamic> message) {
    final formatted = Map<String, dynamic>.from(message);
    
    // Ensure message has proper structure
    if (!formatted.containsKey('@')) {
      formatted['@'] = Utils.randomString(8);
    }
    
    // Add version-specific fields if needed
    if (formatted.containsKey('hi')) {
      final hi = formatted['hi'] as Map<String, dynamic>;
      hi['gun'] = currentVersion;
      hi['pid'] = Utils.randomString(8);
    }
    
    return formatted;
  }
  
  /// Format message for Gun.js v2019 format
  static Map<String, dynamic> _formatV2019Message(Map<String, dynamic> message) {
    final formatted = Map<String, dynamic>.from(message);
    
    // v2019 doesn't support some DAM error features
    if (formatted.containsKey('dam') && formatted['dam'] is Map) {
      // Convert DAM map to simple string for older versions
      final damMap = formatted['dam'] as Map<String, dynamic>;
      formatted['dam'] = damMap['message'] ?? damMap.toString();
    }
    
    return formatted;
  }
  
  /// Format message for Gun.js v2018 format
  static Map<String, dynamic> _formatV2018Message(Map<String, dynamic> message) {
    final formatted = Map<String, dynamic>.from(message);
    
    // v2018 has more limited capabilities
    if (formatted.containsKey('hi')) {
      final hi = formatted['hi'] as Map<String, dynamic>;
      // Remove newer handshake fields
      hi.remove('pid');
      hi.remove('capabilities');
    }
    
    return formatted;
  }
  
  /// Format message for legacy Gun.js format
  static Map<String, dynamic> _formatLegacyMessage(Map<String, dynamic> message) {
    // Convert to very basic format for oldest Gun.js versions
    final formatted = <String, dynamic>{};
    
    if (message.containsKey('put')) {
      formatted['put'] = message['put'];
    } else if (message.containsKey('get')) {
      formatted['get'] = message['get'];
    }
    
    return formatted;
  }
  
  /// Parse incoming message based on detected version
  static ParsedMessage parseMessage(
    Map<String, dynamic> message,
    ProtocolCapabilities? capabilities,
  ) {
    final parsed = ParsedMessage(
      rawMessage: message,
      capabilities: capabilities,
    );
    
    // Detect message type
    if (message.containsKey('hi')) {
      parsed.type = MessageType.handshake;
      parsed.handshakeData = message['hi'] as Map<String, dynamic>?;
      
      // Extract version info from handshake
      final hi = parsed.handshakeData;
      if (hi != null) {
        parsed.remoteVersion = parseVersion(hi['gun'] ?? hi['version']);
      }
    } else if (message.containsKey('put')) {
      parsed.type = MessageType.put;
      parsed.putData = message['put'] as Map<String, dynamic>?;
    } else if (message.containsKey('get')) {
      parsed.type = MessageType.get;
      parsed.getData = message['get'] as Map<String, dynamic>?;
    } else if (message.containsKey('dam')) {
      parsed.type = MessageType.dam;
      parsed.errorData = message['dam'];
    } else if (message.containsKey('bye')) {
      parsed.type = MessageType.bye;
    } else {
      parsed.type = MessageType.unknown;
    }
    
    // Extract common fields
    parsed.messageId = message['@'] as String?;
    parsed.ackId = message['#'] as String?;
    
    return parsed;
  }
  
  /// Create handshake message with version info
  static Map<String, dynamic> createHandshakeMessage({
    String? peerId,
    List<String>? supportedVersions,
  }) {
    final versions = supportedVersions ?? [currentVersion];
    
    return {
      'hi': {
        'gun': currentVersion,
        'pid': peerId ?? Utils.randomString(8),
        'versions': versions,
        'dart': dartImplementationVersion,
      },
      '@': Utils.randomString(8),
    };
  }
}

/// Protocol capabilities for different Gun.js versions
class ProtocolCapabilities {
  final bool supportsHAM;
  final bool supportsWireProtocol;
  final bool supportsSEA;
  final bool supportsRelayServers;
  final bool supportsDAMErrors;
  final bool supportsPeerHandshake;
  final bool supportsMetadata;
  final MessageFormat messageFormat;
  
  const ProtocolCapabilities({
    required this.supportsHAM,
    required this.supportsWireProtocol,
    required this.supportsSEA,
    required this.supportsRelayServers,
    required this.supportsDAMErrors,
    required this.supportsPeerHandshake,
    required this.supportsMetadata,
    required this.messageFormat,
  });
  
  Map<String, dynamic> toMap() => {
    'supportsHAM': supportsHAM,
    'supportsWireProtocol': supportsWireProtocol,
    'supportsSEA': supportsSEA,
    'supportsRelayServers': supportsRelayServers,
    'supportsDAMErrors': supportsDAMErrors,
    'supportsPeerHandshake': supportsPeerHandshake,
    'supportsMetadata': supportsMetadata,
    'messageFormat': messageFormat.name,
  };
}

/// Message format versions
enum MessageFormat {
  v2020,
  v2019,
  v2018,
  legacy,
}

/// Version negotiation result
class VersionNegotiationResult {
  final bool success;
  final String? negotiatedVersion;
  final ProtocolCapabilities? capabilities;
  final String? localVersion;
  final List<String>? remoteVersions;
  final String? error;
  
  VersionNegotiationResult({
    required this.success,
    this.negotiatedVersion,
    this.capabilities,
    this.localVersion,
    this.remoteVersions,
    this.error,
  });
  
  Map<String, dynamic> toMap() => {
    'success': success,
    'negotiatedVersion': negotiatedVersion,
    'capabilities': capabilities?.toMap(),
    'localVersion': localVersion,
    'remoteVersions': remoteVersions,
    'error': error,
  };
}

/// Parsed message with version context
class ParsedMessage {
  final Map<String, dynamic> rawMessage;
  final ProtocolCapabilities? capabilities;
  
  MessageType type = MessageType.unknown;
  String? messageId;
  String? ackId;
  String? remoteVersion;
  
  // Type-specific data
  Map<String, dynamic>? handshakeData;
  Map<String, dynamic>? putData;
  Map<String, dynamic>? getData;
  dynamic errorData;
  
  ParsedMessage({
    required this.rawMessage,
    this.capabilities,
  });
}

/// Message types
enum MessageType {
  handshake,
  put,
  get,
  dam,
  bye,
  unknown,
}

/// Version compatibility matrix
class VersionMatrix {
  static const Map<String, List<String>> compatibilityMatrix = {
    '0.2020.1235': ['0.2020.1235', '0.2019.416', '0.2018.1201'],
    '0.2019.416': ['0.2019.416', '0.2018.1201'],
    '0.2018.1201': ['0.2018.1201'],
    '0.9.x': ['0.9.x'],
  };
  
  /// Check if version1 is compatible with version2
  static bool isCompatible(String version1, String version2) {
    final compatible = compatibilityMatrix[version1];
    return compatible?.contains(version2) ?? false;
  }
  
  /// Get all compatible versions for a given version
  static List<String> getCompatibleVersions(String version) {
    return compatibilityMatrix[version] ?? [];
  }
}
