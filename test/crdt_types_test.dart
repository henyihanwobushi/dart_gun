import 'package:flutter_test/flutter_test.dart';
import 'package:dart_gun/dart_gun.dart';

void main() {
  group('G-Counter Tests', () {
    test('should create empty counter', () {
      final counter = GCounter('node1');
      expect(counter.value, equals(0));
    });

    test('should increment counter', () {
      final counter = GCounter('node1');
      
      counter.increment();
      expect(counter.value, equals(1));
      
      counter.increment(5);
      expect(counter.value, equals(6));
    });

    test('should not allow negative increments', () {
      final counter = GCounter('node1');
      expect(() => counter.increment(-1), throwsArgumentError);
    });

    test('should merge counters correctly', () {
      final counter1 = GCounter('node1');
      final counter2 = GCounter('node2');
      
      counter1.increment(3);
      counter2.increment(2);
      
      counter1.merge(counter2);
      
      expect(counter1.value, equals(5));
      expect(counter2.value, equals(2));
    });

    test('should handle merging with same node', () {
      final counter1 = GCounter('node1');
      final counter2 = GCounter('node1');
      
      counter1.increment(3);
      counter2.increment(5); // Higher value
      
      counter1.merge(counter2);
      expect(counter1.value, equals(5)); // Takes maximum
    });

    test('should create from state', () {
      final state = {'node1': 5, 'node2': 3};
      final counter = GCounter.fromState('node3', state);
      
      expect(counter.value, equals(8));
      expect(counter.getState(), equals(state));
    });

    test('should compare counters for partial ordering', () {
      final counter1 = GCounter('node1');
      final counter2 = GCounter('node2');
      
      counter1.increment(3);
      counter2.increment(2);
      
      expect(counter2.isLessEqualThan(counter1), isFalse);
      expect(counter1.isLessEqualThan(counter1), isTrue);
      
      final counter3 = GCounter.fromState('node3', counter1.getState());
      expect(counter3.isLessEqualThan(counter1), isTrue);
    });
  });

  group('PN-Counter Tests', () {
    test('should create empty counter', () {
      final counter = PNCounter('node1');
      expect(counter.value, equals(0));
    });

    test('should increment and decrement', () {
      final counter = PNCounter('node1');
      
      counter.increment(5);
      expect(counter.value, equals(5));
      
      counter.decrement(2);
      expect(counter.value, equals(3));
      
      counter.decrement(10);
      expect(counter.value, equals(-7));
    });

    test('should handle negative increment as decrement', () {
      final counter = PNCounter('node1');
      
      counter.increment(-3);
      expect(counter.value, equals(-3));
    });

    test('should handle negative decrement as increment', () {
      final counter = PNCounter('node1');
      
      counter.decrement(-5);
      expect(counter.value, equals(5));
    });

    test('should merge counters correctly', () {
      final counter1 = PNCounter('node1');
      final counter2 = PNCounter('node2');
      
      counter1.increment(10);
      counter1.decrement(3);
      
      counter2.increment(5);
      counter2.decrement(8);
      
      counter1.merge(counter2);
      
      expect(counter1.value, equals(4)); // (10+5) - (3+8)
    });

    test('should create from state', () {
      final positiveState = {'node1': 10, 'node2': 5};
      final negativeState = {'node1': 3, 'node2': 8};
      
      final counter = PNCounter.fromState('node3', positiveState, negativeState);
      expect(counter.value, equals(4)); // 15 - 11
    });
  });

  group('G-Set Tests', () {
    test('should create empty set', () {
      final set = GSet<String>();
      expect(set.isEmpty, isTrue);
      expect(set.length, equals(0));
    });

    test('should add elements', () {
      final set = GSet<String>();
      
      set.add('apple');
      expect(set.contains('apple'), isTrue);
      expect(set.length, equals(1));
      
      set.add('banana');
      set.add('apple'); // Duplicate
      expect(set.length, equals(2));
    });

    test('should add multiple elements', () {
      final set = GSet<String>();
      
      set.addAll(['apple', 'banana', 'cherry']);
      expect(set.length, equals(3));
      expect(set.contains('banana'), isTrue);
    });

    test('should merge sets', () {
      final set1 = GSet<String>();
      final set2 = GSet<String>();
      
      set1.addAll(['apple', 'banana']);
      set2.addAll(['banana', 'cherry']);
      
      set1.merge(set2);
      
      expect(set1.length, equals(3));
      expect(set1.contains('cherry'), isTrue);
    });

    test('should create from elements', () {
      final set = GSet.fromElements(['apple', 'banana', 'cherry']);
      
      expect(set.length, equals(3));
      expect(set.contains('apple'), isTrue);
    });

    test('should get immutable elements', () {
      final set = GSet<String>();
      set.add('test');
      
      final elements = set.elements;
      expect(() => elements.add('new'), throwsUnsupportedError);
    });
  });

  group('2P-Set Tests', () {
    test('should create empty set', () {
      final set = TwoPSet<String>();
      expect(set.isEmpty, isTrue);
      expect(set.length, equals(0));
    });

    test('should add and remove elements', () {
      final set = TwoPSet<String>();
      
      set.add('apple');
      expect(set.contains('apple'), isTrue);
      expect(set.length, equals(1));
      
      set.remove('apple');
      expect(set.contains('apple'), isFalse);
      expect(set.length, equals(0));
    });

    test('should not allow removing non-existent elements', () {
      final set = TwoPSet<String>();
      
      expect(() => set.remove('nonexistent'), throwsStateError);
    });

    test('should not allow re-adding removed elements', () {
      final set = TwoPSet<String>();
      
      set.add('apple');
      set.remove('apple');
      
      // Re-adding should not work (element stays removed)
      set.add('apple');
      expect(set.contains('apple'), isFalse);
    });

    test('should merge sets correctly', () {
      final set1 = TwoPSet<String>();
      final set2 = TwoPSet<String>();
      
      set1.add('apple');
      set2.add('banana');
      set2.add('apple');
      set2.remove('apple');
      
      set1.merge(set2);
      
      expect(set1.contains('apple'), isFalse); // Removed in set2
      expect(set1.contains('banana'), isTrue);
    });

    test('should create from state', () {
      final set = TwoPSet.fromState(['apple', 'banana'], ['apple']);
      
      expect(set.contains('apple'), isFalse);
      expect(set.contains('banana'), isTrue);
      expect(set.length, equals(1));
    });
  });

  group('OR-Set Tests', () {
    test('should create empty set', () {
      final set = ORSet<String>('node1');
      expect(set.isEmpty, isTrue);
      expect(set.length, equals(0));
    });

    test('should add elements with unique tags', () {
      final set = ORSet<String>('node1');
      
      final tag = set.add('apple');
      expect(tag, isA<String>());
      expect(set.contains('apple'), isTrue);
      expect(set.length, equals(1));
    });

    test('should allow re-adding removed elements', () {
      final set = ORSet<String>('node1');
      
      final tag1 = set.add('apple');
      set.removeTag('apple', tag1);
      expect(set.contains('apple'), isFalse);
      
      // Re-add with new tag
      set.add('apple');
      expect(set.contains('apple'), isTrue);
    });

    test('should remove all current tags', () {
      final set = ORSet<String>('node1');
      
      set.add('apple');
      set.add('apple'); // Second tag
      expect(set.contains('apple'), isTrue);
      
      set.remove('apple'); // Removes all current tags
      expect(set.contains('apple'), isFalse);
    });

    test('should merge sets correctly', () {
      final set1 = ORSet<String>('node1');
      final set2 = ORSet<String>('node2');
      
      set1.add('apple');
      set2.add('banana');
      
      final appleTag = set2.add('apple');
      set2.removeTag('apple', appleTag);
      
      set1.merge(set2);
      
      expect(set1.contains('apple'), isTrue); // Still has tag from node1
      expect(set1.contains('banana'), isTrue);
    });

    test('should handle tag counter conflicts', () {
      final set1 = ORSet<String>('node1');
      final set2 = ORSet<String>('node2');
      
      // Generate some tags
      set1.add('a');
      set1.add('b');
      
      set2.add('c');
      
      set1.merge(set2);
      
      // After merge, new tags should not conflict
      final newTag = set1.add('d');
      expect(newTag, contains('node1'));
    });
  });

  group('LWW-Register Tests', () {
    test('should create empty register', () {
      final register = LWWRegister<String>('node1');
      expect(register.value, isNull);
      expect(register.timestamp, equals(0));
    });

    test('should create with initial value', () {
      final register = LWWRegister.withValue('node1', 'hello');
      expect(register.value, equals('hello'));
      expect(register.timestamp, greaterThan(0));
      expect(register.nodeId, equals('node1'));
    });

    test('should set new values', () async {
      final register = LWWRegister<String>('node1');
      
      register.set('hello');
      expect(register.value, equals('hello'));
      
      final oldTimestamp = register.timestamp;
      await Future.delayed(const Duration(milliseconds: 1));
      
      register.set('world');
      expect(register.value, equals('world'));
      expect(register.timestamp, greaterThan(oldTimestamp));
    });

    test('should merge registers with later timestamp', () async {
      final register1 = LWWRegister<String>('node1');
      final register2 = LWWRegister<String>('node2');
      
      register1.set('first');
      await Future.delayed(const Duration(milliseconds: 1));
      register2.set('second');
      
      register1.merge(register2);
      expect(register1.value, equals('second')); // Later timestamp wins
    });

    test('should use node ID as tiebreaker', () {
      final register1 = LWWRegister<String>('node-a');
      final register2 = LWWRegister<String>('node-z');
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      register1.setWithTimestamp('first', timestamp, 'node-a');
      register2.setWithTimestamp('second', timestamp, 'node-z');
      
      register1.merge(register2);
      expect(register1.value, equals('second')); // node-z > node-a
    });

    test('should create from state', () {
      final register = LWWRegister.fromState('node1', 'hello', 12345);
      
      expect(register.value, equals('hello'));
      expect(register.timestamp, equals(12345));
      expect(register.nodeId, equals('node1'));
    });

    test('should serialize state correctly', () {
      final register = LWWRegister.withValue('node1', 42);
      final state = register.getState();
      
      expect(state['value'], equals(42));
      expect(state['timestamp'], isA<int>());
      expect(state['nodeId'], equals('node1'));
    });
  });

  group('CRDT Factory Tests', () {
    test('should create different CRDT types', () {
      expect(CRDTFactory.createGCounter('node1'), isA<GCounter>());
      expect(CRDTFactory.createPNCounter('node1'), isA<PNCounter>());
      expect(CRDTFactory.createGSet<String>(), isA<GSet<String>>());
      expect(CRDTFactory.createTwoPSet<String>(), isA<TwoPSet<String>>());
      expect(CRDTFactory.createORSet<String>('node1'), isA<ORSet<String>>());
      expect(CRDTFactory.createLWWRegister<String>('node1'), isA<LWWRegister<String>>());
    });

    test('should create CRDTs from state', () {
      // Test G-Counter
      final gCounter = CRDTFactory.fromState('GCounter', 'node1', {'node1': 5});
      expect(gCounter, isA<GCounter>());
      expect((gCounter as GCounter).value, equals(5));

      // Test PN-Counter
      final pnCounter = CRDTFactory.fromState('PNCounter', 'node1', {
        'positive': {'node1': 5},
        'negative': {'node1': 2},
      });
      expect(pnCounter, isA<PNCounter>());
      expect((pnCounter as PNCounter).value, equals(3));

      // Test G-Set
      final gSet = CRDTFactory.fromState('GSet', 'node1', {
        'elements': ['a', 'b', 'c'],
      });
      expect(gSet, isA<GSet>());
      expect((gSet as GSet).length, equals(3));

      // Test 2P-Set
      final tpSet = CRDTFactory.fromState('TwoPSet', 'node1', {
        'added': ['a', 'b'],
        'removed': ['b'],
      });
      expect(tpSet, isA<TwoPSet>());
      expect((tpSet as TwoPSet).length, equals(1));

      // Test LWW-Register
      final lwwReg = CRDTFactory.fromState('LWWRegister', 'node1', {
        'value': 'test',
        'timestamp': 12345,
      });
      expect(lwwReg, isA<LWWRegister>());
      expect((lwwReg as LWWRegister).value, equals('test'));
    });

    test('should throw on unknown CRDT type', () {
      expect(
        () => CRDTFactory.fromState('UnknownType', 'node1', {}),
        throwsArgumentError,
      );
    });
  });

  group('CRDT Integration Tests', () {
    test('should work with different data types', () {
      final intSet = GSet<int>();
      intSet.addAll([1, 2, 3]);
      expect(intSet.length, equals(3));

      final doubleRegister = LWWRegister<double>('node1');
      doubleRegister.set(3.14);
      expect(doubleRegister.value, equals(3.14));

      final boolSet = ORSet<bool>('node1');
      boolSet.add(true);
      boolSet.add(false);
      expect(boolSet.length, equals(2));
    });

    test('should handle complex data serialization', () {
      final counter = GCounter('node1');
      counter.increment(42);
      
      final state = counter.getState();
      final restored = GCounter.fromState('node1', state);
      
      expect(restored.value, equals(counter.value));
    });
  });
}
