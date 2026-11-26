
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Basic Flutter tests', () {
    test('Addition works correctly', () {
      expect(1 + 1, 2);
    });

    test('Student groups are correct', () {
      const groups = ['DSC', 'DSM'];

      expect(groups.length, 2);
      expect(groups, contains('DSC'));
      expect(groups, contains('DSM'));
    });

    test('Semesters are correct', () {
      const semesters = [
        '2nd Semester',
        '4th Semester',
        '6th Semester',
      ];

      expect(semesters.length, 3);
    });
  });
}
