import 'package:docme_core/docme_core.dart';
import 'package:test/test.dart';

void main() {
  group('Result & Failures', () {
    test('Ok result when folds correctly', () {
      const result = Ok<int>(42);
      expect(result.valueOrNull, 42);
      final mapped = result.map((v) => v * 2);
      expect(mapped.valueOrNull, 84);
    });

    test('Err result when folds correctly', () {
      const result = Err<int>(
        DocMeFailure(
          kind: DocMeFailureKind.notFound,
          message: 'Item not found',
        ),
      );
      expect(result.valueOrNull, isNull);
    });
  });
}
