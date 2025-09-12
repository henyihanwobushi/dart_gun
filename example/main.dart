import 'package:dart_gun/dart_gun.dart';

Future<void> main() async {
  final gun = Gun(GunOptions(storage: MemoryStorage()));

  await gun.get('example').put({'hello': 'world'});
  final data = await gun.get('example').once();
  print('example read: $data');

  await gun.close();
}


