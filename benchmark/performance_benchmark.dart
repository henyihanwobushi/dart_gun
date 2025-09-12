import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:gun_dart/gun_dart.dart';

class SimpleBenchmarkResult {
  final String name;
  final int iterations;
  final Duration totalTime;
  final double opsPerSecond;

  SimpleBenchmarkResult(this.name, this.iterations, this.totalTime)
      : opsPerSecond = iterations / (totalTime.inMilliseconds / 1000).clamp(0.001, double.infinity);

  Map<String, dynamic> toJson() => {
        'name': name,
        'iterations': iterations,
        'totalTimeMs': totalTime.inMilliseconds,
        'opsPerSecond': opsPerSecond,
      };
}

Future<SimpleBenchmarkResult> benchmarkWrites(Gun gun, int iterations) async {
  final rnd = Random();
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    await gun.get('bench/write/$i').put({
      'v': rnd.nextInt(1000),
      't': DateTime.now().millisecondsSinceEpoch,
    });
  }
  sw.stop();
  return SimpleBenchmarkResult('writes', iterations, sw.elapsed);
}

Future<SimpleBenchmarkResult> benchmarkReads(Gun gun, int iterations) async {
  for (var i = 0; i < iterations; i++) {
    await gun.get('bench/read/$i').put({'v': i});
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    await gun.get('bench/read/$i').once();
  }
  sw.stop();
  return SimpleBenchmarkResult('reads', iterations, sw.elapsed);
}

Future<void> main(List<String> args) async {
  final iterations = args.isNotEmpty ? int.tryParse(args.first) ?? 200 : 200;
  final gun = Gun(GunOptions(storage: MemoryStorage()));

  final results = <SimpleBenchmarkResult>[];
  results.add(await benchmarkWrites(gun, iterations));
  results.add(await benchmarkReads(gun, iterations));

  await gun.close();

  final jsonOut = const JsonEncoder.withIndent('  ').convert({
    'iterations': iterations,
    'results': results.map((r) => r.toJson()).toList(),
  });

  stdout.writeln(jsonOut);

  final outFile = Platform.environment['GUN_BENCH_OUT'] ?? '/tmp/gun_dart_benchmark.json';
  await File(outFile).writeAsString(jsonOut);
  stdout.writeln('Saved benchmark to: $outFile');
}


