import 'package:esystem_church/config/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('les espacements sont des multiples de 4', () {
    for (final valeur in [
      AppSpacing.xxs,
      AppSpacing.xs,
      AppSpacing.sm,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.xxl,
    ]) {
      expect(valeur % 4, 0);
    }
    expect(AppSpacing.xxs, 4);
    expect(AppSpacing.xxl, 48);
  });

  test('les rayons sont bien 8, 12, 16 et 999', () {
    expect(AppRadii.sm, 8);
    expect(AppRadii.md, 12);
    expect(AppRadii.lg, 16);
    expect(AppRadii.pill, 999);
  });

  test('les tailles incluent les valeurs de la maquette', () {
    expect(AppFontSizes.s11_5, 11.5);
    expect(AppFontSizes.s12_5, 12.5);
    expect(AppFontSizes.s13_5, 13.5);
    expect(AppFontSizes.s10, 10);
    expect(AppFontSizes.s24, 24);
  });
}
