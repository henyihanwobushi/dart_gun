import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/gun_dart.dart';

/// Comprehensive performance benchmarking for gun_dart vs Gun.js
/// 
/// Measures and compares performance across various operations including
/// data writes, reads, conflict resolution, network sync, and memory usage.
class PerformanceBenchmark {
  final Gun _gun;
  final List<BenchmarkResult> _results = [];
  
  PerformanceBenchmark(this._gun);
  
  /// Run all benchmark tests
  Future<BenchmarkReport> runAllBenchmarks({
    int iterations = 1000,
    bool includeMemoryTests = true,
    bool includeNetworkTests = false,
  }) async {
    print('🚀 Starting comprehensive performance benchmarks...');
    print('   Iterations: $iterations');
    print('   Memory tests: $includeMemoryTests');
    print('   Network tests: $includeNetworkTests');
    print('');
    
    final report = BenchmarkReport();
    report.startTime = DateTime.now();
    
    // Basic CRUD operations
    await _benchmarkBasicWrites(iterations);
    await _benchmarkBasicReads(iterations);
    await _benchmarkChainedOperations(iterations);
    
    // Advanced operations
    await _benchmarkConflictResolution(iterations ~/ 10);
    await _benchmarkComplexQueries(iterations ~/ 10);
    await _benchmarkUserOperations(iterations ~/ 10);
    
    // Graph operations
    await _benchmarkGraphTraversal(iterations ~/ 10);
    await _benchmarkBulkOperations(iterations ~/ 10);
    
    if (includeMemoryTests) {
      await _benchmarkMemoryUsage(iterations);
    }
    
    if (includeNetworkTests) {
      await _benchmarkNetworkOperations(iterations ~/ 100);
    }
    
    report.endTime = DateTime.now();
    report.results = List.from(_results);
    report.summary = _generateSummary();
    
    return report;
  }
  
  /// Benchmark basic write operations
  Future<void> _benchmarkBasicWrites(int iterations) async {
    print('📝 Benchmarking basic write operations...');
    
    final stopwatch = Stopwatch()..start();
    final random = Random();
    
    for (int i = 0; i < iterations; i++) {
      await _gun.get('benchmark/writes/item$i').put({
        'value': random.nextInt(1000),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'text': 'Sample data item $i',
      });
    }
    
    stopwatch.stop();
    
    _results.add(BenchmarkResult(
      name: 'Basic Writes',
      iterations: iterations,
      totalTime: stopwatch.elapsed,
      operationsPerSecond: iterations / (stopwatch.elapsedMilliseconds / 1000),
      memoryUsage: _getCurrentMemoryUsage(),
    ));
    
    print('✓ Basic writes: ${_results.last.operationsPerSecond.toStringAsFixed(2)} ops/sec');
  }
  
  /// Benchmark basic read operations
  Future<void> _benchmarkBasicReads(int iterations) async {
    print('📖 Benchmarking basic read operations...');
    
    // Prepare data
    for (int i = 0; i < iterations; i++) {
      await _gun.get('benchmark/reads/item$i').put({
        'value': i,
        'data': 'Read test data $i',
      });
    }
    
    final stopwatch = Stopwatch()..start();
    
    for (int i = 0; i < iterations; i++) {
      await _gun.get('benchmark/reads/item$i').once();
    }
    
    stopwatch.stop();
    
    _results.add(BenchmarkResult(
      name: 'Basic Reads',
      iterations: iterations,
      totalTime: stopwatch.elapsed,
      operationsPerSecond: iterations / (stopwatch.elapsedMilliseconds / 1000),
      memoryUsage: _getCurrentMemoryUsage(),
    ));
    
    print('✓ Basic reads: ${_results.last.operationsPerSecond.toStringAsFixed(2)} ops/sec');
  }
  
  /// Benchmark chained operations
  Future<void> _benchmarkChainedOperations(int iterations) async {
    print('🔗 Benchmarking chained operations...');
    
    final stopwatch = Stopwatch()..start();
    
    for (int i = 0; i < iterations; i++) {
      await _gun
          .get('benchmark')
          .get('chains')
          .get('level1')
          .get('level2')
          .get('item$i')
          .put({'value': i});
    }
    
    stopwatch.stop();
    
    _results.add(BenchmarkResult(
      name: 'Chained Operations',
      iterations: iterations,
      totalTime: stopwatch.elapsed,
      operationsPerSecond: iterations / (stopwatch.elapsedMilliseconds / 1000),
      memoryUsage: _getCurrentMemoryUsage(),
    ));
    
    print('✓ Chained ops: ${_results.last.operationsPerSecond.toStringAsFixed(2)} ops/sec');
  }
  
  /// Benchmark conflict resolution
  Future<void> _benchmarkConflictResolution(int iterations) async {
    print('⚔️ Benchmarking conflict resolution...');
    
    final stopwatch = Stopwatch()..start();
    final random = Random();
    
    for (int i = 0; i < iterations; i++) {
      final nodeKey = 'benchmark/conflicts/node${i % 100}'; // Create conflicts
      
      // Write conflicting data with different timestamps
      final baseTime = DateTime.now().millisecondsSinceEpoch;
      await _gun.get(nodeKey).put({
        'value': random.nextInt(1000),
        'source': 'test1',
        '_': {
          '#': nodeKey,
          '>': {'value': baseTime - random.nextInt(1000)},
        }
      });
      
      await _gun.get(nodeKey).put({
        'value': random.nextInt(1000),
        'source': 'test2',
        '_': {
          '#': nodeKey,
          '>': {'value': baseTime + random.nextInt(1000)},
        }
      });
    }
    
    stopwatch.stop();
    
    _results.add(BenchmarkResult(
      name: 'Conflict Resolution',
      iterations: iterations * 2, // Two operations per iteration
      totalTime: stopwatch.elapsed,
      operationsPerSecond: (iterations * 2) / (stopwatch.elapsedMilliseconds / 1000),
      memoryUsage: _getCurrentMemoryUsage(),
    ));
    
    print('✓ Conflict resolution: ${_results.last.operationsPerSecond.toStringAsFixed(2)} ops/sec');
  }
  
  /// Benchmark complex graph queries
  Future<void> _benchmarkComplexQueries(int iterations) async {
    print('🔍 Benchmarking complex queries...');
    
    // Setup linked data structure
    for (int i = 0; i < 100; i++) {
      await _gun.get('benchmark/users/user$i').put({
        'name': 'User $i',
        'profile': {'#': 'benchmark/profiles/profile$i'}
      });
      
      await _gun.get('benchmark/profiles/profile$i').put({
        'bio': 'Bio for user $i',
        'posts': {'#': 'benchmark/posts/user$i'}
      });
    }
    
    final stopwatch = Stopwatch()..start();
    final random = Random();
    
    for (int i = 0; i < iterations; i++) {
      final userId = random.nextInt(100);
      
      // Query user -> profile -> posts chain
      final user = await _gun.get('benchmark/users/user$userId').once();
      if (user != null && user['profile'] != null) {
        final profileId = user['profile']['#'];
        final profile = await _gun.get(profileId).once();
        if (profile != null && profile['posts'] != null) {
          final postsId = profile['posts']['#'];
          await _gun.get(postsId).once();
        }
      }
    }
    
    stopwatch.stop();
    
    _results.add(BenchmarkResult(
      name: 'Complex Queries',
      iterations: iterations,
      totalTime: stopwatch.elapsed,
      operationsPerSecond: iterations / (stopwatch.elapsedMilliseconds / 1000),
      memoryUsage: _getCurrentMemoryUsage(),
    ));
    
    print('✓ Complex queries: ${_results.last.operationsPerSecond.toStringAsFixed(2)} ops/sec');
  }
  
  /// Benchmark user operations
  Future<void> _benchmarkUserOperations(int iterations) async {
    print('👤 Benchmarking user operations...');
    
    final stopwatch = Stopwatch()..start();
    
    for (int i = 0; i < iterations; i++) {
      final user = _gun.user();
      await user.create('benchuser$i', 'password$i');
      await user.getUserPath('data').put({'test': i});
      await user.leave();
    }
    
    stopwatch.stop();
    
    _results.add(BenchmarkResult(
      name: 'User Operations',
      iterations: iterations * 3, // Create, put, leave
      totalTime: stopwatch.elapsed,
      operationsPerSecond: (iterations * 3) / (stopwatch.elapsedMilliseconds / 1000),
      memoryUsage: _getCurrentMemoryUsage(),
    ));
    
    print('✓ User operations: ${_results.last.operationsPerSecond.toStringAsFixed(2)} ops/sec');
  }
  
  /// Benchmark graph traversal
  Future<void> _benchmarkGraphTraversal(int iterations) async {
    print('🕸️ Benchmarking graph traversal...');
    
    // Create a complex graph structure
    const depth = 5;
    const breadth = 10;
    
    for (int level = 0; level < depth; level++) {
      for (int item = 0; item < breadth; item++) {
        final nodeKey = 'benchmark/graph/level$level/item$item';
        final data = <String, dynamic>{'level': level, 'item': item};
        
        // Add links to next level
        if (level < depth - 1) {
          for (int next = 0; next < breadth; next++) {
            data['link$next'] = {'#': 'benchmark/graph/level${level + 1}/item$next'};
          }
        }
        
        await _gun.get(nodeKey).put(data);
      }
    }
    
    final stopwatch = Stopwatch()..start();
    final random = Random();
    
    for (int i = 0; i < iterations; i++) {
      // Traverse random path through graph
      String currentNode = 'benchmark/graph/level0/item${random.nextInt(breadth)}';
      
      for (int level = 0; level < depth - 1; level++) {
        final node = await _gun.get(currentNode).once();
        if (node != null) {
          final linkKey = 'link${random.nextInt(breadth)}';
          if (node[linkKey] != null) {
            currentNode = node[linkKey]['#'];
          } else {
            break;
          }
        }
      }
    }
    
    stopwatch.stop();
    
    _results.add(BenchmarkResult(
      name: 'Graph Traversal',
      iterations: iterations,
      totalTime: stopwatch.elapsed,
      operationsPerSecond: iterations / (stopwatch.elapsedMilliseconds / 1000),
      memoryUsage: _getCurrentMemoryUsage(),
    ));
    
    print('✓ Graph traversal: ${_results.last.operationsPerSecond.toStringAsFixed(2)} ops/sec');
  }
  
  /// Benchmark bulk operations
  Future<void> _benchmarkBulkOperations(int iterations) async {
    print('📦 Benchmarking bulk operations...');
    
    final stopwatch = Stopwatch()..start();
    final batchSize = 50;
    
    for (int batch = 0; batch < iterations ~/ batchSize; batch++) {
      final futures = <Future>[];
      
      for (int i = 0; i < batchSize; i++) {
        final itemKey = 'benchmark/bulk/batch$batch/item$i';
        futures.add(_gun.get(itemKey).put({
          'batch': batch,
          'item': i,
          'data': 'Bulk data for batch $batch item $i',
        }));
      }
      
      await Future.wait(futures);
    }
    
    stopwatch.stop();
    
    _results.add(BenchmarkResult(
      name: 'Bulk Operations',
      iterations: iterations,
      totalTime: stopwatch.elapsed,
      operationsPerSecond: iterations / (stopwatch.elapsedMilliseconds / 1000),
      memoryUsage: _getCurrentMemoryUsage(),
    ));
    
    print('✓ Bulk operations: ${_results.last.operationsPerSecond.toStringAsFixed(2)} ops/sec');
  }
  
  /// Benchmark memory usage
  Future<void> _benchmarkMemoryUsage(int dataSize) async {
    print('🧠 Benchmarking memory usage...');
    
    final initialMemory = _getCurrentMemoryUsage();
    
    // Create large dataset
    for (int i = 0; i < dataSize; i++) {
      await _gun.get('benchmark/memory/large$i').put({
        'data': 'A' * 1000, // 1KB of data per item
        'index': i,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
    
    final finalMemory = _getCurrentMemoryUsage();
    final memoryDelta = finalMemory - initialMemory;
    
    _results.add(BenchmarkResult(
      name: 'Memory Usage',
      iterations: dataSize,
      totalTime: Duration.zero,
      operationsPerSecond: 0,
      memoryUsage: finalMemory,
      additionalMetrics: {
        'initialMemory': initialMemory,
        'finalMemory': finalMemory,
        'memoryDelta': memoryDelta,
        'memoryPerItem': memoryDelta / dataSize,
      },
    ));
    
    print('✓ Memory usage: ${(memoryDelta / 1024 / 1024).toStringAsFixed(2)} MB for $dataSize items');
  }
  
  /// Benchmark network operations (requires network setup)
  Future<void> _benchmarkNetworkOperations(int iterations) async {
    print('🌐 Benchmarking network operations...');
    
    // This would require actual network peers setup
    // For now, we'll simulate network latency
    final stopwatch = Stopwatch()..start();
    final random = Random();
    
    for (int i = 0; i < iterations; i++) {
      // Simulate network delay
      await Future.delayed(Duration(milliseconds: random.nextInt(10) + 5));
      
      await _gun.get('benchmark/network/item$i').put({
        'networkData': 'Network synchronized data $i',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
      // Simulate read with network delay
      await Future.delayed(Duration(milliseconds: random.nextInt(5) + 2));
      await _gun.get('benchmark/network/item$i').once();
    }
    
    stopwatch.stop();
    
    _results.add(BenchmarkResult(
      name: 'Network Operations',
      iterations: iterations * 2, // Put and get
      totalTime: stopwatch.elapsed,
      operationsPerSecond: (iterations * 2) / (stopwatch.elapsedMilliseconds / 1000),
      memoryUsage: _getCurrentMemoryUsage(),
      additionalMetrics: {
        'averageLatency': stopwatch.elapsedMilliseconds / iterations,
      },
    ));
    
    print('✓ Network ops: ${_results.last.operationsPerSecond.toStringAsFixed(2)} ops/sec');
  }
  
  /// Get current memory usage (simplified - in real implementation would use platform-specific APIs)
  int _getCurrentMemoryUsage() {
    // This is a placeholder - real implementation would use:
    // - ProcessInfo.currentRss on some platforms
    // - Platform-specific memory APIs
    // For now, return a simulated value
    return DateTime.now().millisecondsSinceEpoch % 100000000; // Simulated memory usage
  }
  
  /// Generate benchmark summary
  BenchmarkSummary _generateSummary() {
    final summary = BenchmarkSummary();
    
    if (_results.isNotEmpty) {
      summary.totalOperations = _results.fold(0, (sum, r) => sum + r.iterations);
      summary.totalTime = _results.fold(Duration.zero, (sum, r) => sum + r.totalTime);
      summary.averageOpsPerSecond = _results.fold(0.0, (sum, r) => sum + r.operationsPerSecond) / _results.length;
      summary.fastestOperation = _results.reduce((a, b) => a.operationsPerSecond > b.operationsPerSecond ? a : b).name;
      summary.slowestOperation = _results.reduce((a, b) => a.operationsPerSecond < b.operationsPerSecond ? a : b).name;
      
      final memoryResults = _results.where((r) => r.memoryUsage > 0);
      if (memoryResults.isNotEmpty) {
        summary.peakMemoryUsage = memoryResults.map((r) => r.memoryUsage).reduce(max);
      }
    }
    
    return summary;
  }
  
  /// Generate Gun.js comparison (would require actual Gun.js benchmarks)
  static Future<ComparisonReport> compareWithGunJS(
    BenchmarkReport dartReport,
    Map<String, dynamic> gunJSResults,
  ) async {
    // This would compare gun_dart results with Gun.js benchmark results
    // For now, return a placeholder comparison
    return ComparisonReport(
      dartReport: dartReport,
      gunJSResults: gunJSResults,
      improvements: {},
      regressions: {},
      similarPerformance: {},
    );
  }
}

/// Individual benchmark result
class BenchmarkResult {
  final String name;
  final int iterations;
  final Duration totalTime;
  final double operationsPerSecond;
  final int memoryUsage;
  final Map<String, dynamic>? additionalMetrics;
  
  BenchmarkResult({
    required this.name,
    required this.iterations,
    required this.totalTime,
    required this.operationsPerSecond,
    this.memoryUsage = 0,
    this.additionalMetrics,
  });
  
  Map<String, dynamic> toMap() => {
    'name': name,
    'iterations': iterations,
    'totalTimeMs': totalTime.inMilliseconds,
    'operationsPerSecond': operationsPerSecond,
    'memoryUsage': memoryUsage,
    if (additionalMetrics != null) ...additionalMetrics!,
  };
}

/// Complete benchmark report
class BenchmarkReport {
  DateTime? startTime;
  DateTime? endTime;
  List<BenchmarkResult> results = [];
  BenchmarkSummary? summary;
  
  Duration get totalDuration => 
      endTime != null && startTime != null
          ? endTime!.difference(startTime!)
          : Duration.zero;
  
  Map<String, dynamic> toMap() => {
    'startTime': startTime?.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'totalDurationMs': totalDuration.inMilliseconds,
    'results': results.map((r) => r.toMap()).toList(),
    'summary': summary?.toMap(),
  };
  
  /// Export report to JSON file
  Future<void> saveToFile(String filePath) async {
    final json = const JsonEncoder.withIndent('  ').convert(toMap());
    await File(filePath).writeAsString(json);
  }
}

/// Benchmark summary statistics
class BenchmarkSummary {
  int totalOperations = 0;
  Duration totalTime = Duration.zero;
  double averageOpsPerSecond = 0;
  String fastestOperation = '';
  String slowestOperation = '';
  int peakMemoryUsage = 0;
  
  Map<String, dynamic> toMap() => {
    'totalOperations': totalOperations,
    'totalTimeMs': totalTime.inMilliseconds,
    'averageOpsPerSecond': averageOpsPerSecond,
    'fastestOperation': fastestOperation,
    'slowestOperation': slowestOperation,
    'peakMemoryUsage': peakMemoryUsage,
  };
}

/// Comparison report between gun_dart and Gun.js
class ComparisonReport {
  final BenchmarkReport dartReport;
  final Map<String, dynamic> gunJSResults;
  final Map<String, double> improvements;
  final Map<String, double> regressions;
  final Map<String, double> similarPerformance;
  
  ComparisonReport({
    required this.dartReport,
    required this.gunJSResults,
    required this.improvements,
    required this.regressions,
    required this.similarPerformance,
  });
  
  Map<String, dynamic> toMap() => {
    'dartReport': dartReport.toMap(),
    'gunJSResults': gunJSResults,
    'improvements': improvements,
    'regressions': regressions,
    'similarPerformance': similarPerformance,
  };
}

/// Main benchmark runner for testing
void main() async {
  group('Performance Benchmarks', () {
    late Gun gun;
    late PerformanceBenchmark benchmark;
    
    setUpAll(() {
      gun = Gun(GunOptions(storage: MemoryStorage()));
      benchmark = PerformanceBenchmark(gun);
    });
    
    tearDownAll(() async {
      await gun.close();
    });
    
    test('run comprehensive benchmark suite', () async {
      final report = await benchmark.runAllBenchmarks(
        iterations: 100, // Reduced for testing
        includeMemoryTests: true,
        includeNetworkTests: false,
      );
      
      expect(report.results.isNotEmpty, true);
      expect(report.summary, isNotNull);
      expect(report.totalDuration.inMilliseconds, greaterThan(0));
      
      // Save report
      await report.saveToFile('/tmp/gun_dart_benchmark_report.json');
      
      print('\n📊 Benchmark Summary:');
      print('   Total operations: ${report.summary!.totalOperations}');
      print('   Total time: ${report.totalDuration.inMilliseconds}ms');
      print('   Average ops/sec: ${report.summary!.averageOpsPerSecond.toStringAsFixed(2)}');
      print('   Fastest: ${report.summary!.fastestOperation}');
      print('   Slowest: ${report.summary!.slowestOperation}');
      print('   Peak memory: ${(report.summary!.peakMemoryUsage / 1024 / 1024).toStringAsFixed(2)}MB');
    });
    
    test('individual operation benchmarks', () async {
      // Test individual operations for detailed profiling
      await benchmark._benchmarkBasicWrites(50);
      await benchmark._benchmarkBasicReads(50);
      await benchmark._benchmarkChainedOperations(25);
      
      expect(benchmark._results.length, 3);
      
      for (final result in benchmark._results) {
        expect(result.operationsPerSecond, greaterThan(0));
        expect(result.totalTime.inMilliseconds, greaterThan(0));
      }
    });
  });
}
