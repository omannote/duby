import { describe, expect, it } from 'vitest';
import { atLeast, roleRank } from '../roles.js';

describe('ترتيب الأدوار', () => {
  it('يرتّب المندوب أدنى والمدير أعلى', () => {
    expect(roleRank('courier')).toBeLessThan(roleRank('operator'));
    expect(roleRank('operator')).toBeLessThan(roleRank('manager'));
    expect(roleRank('manager')).toBeLessThan(roleRank('admin'));
  });

  it('يحسم فحوص «فأعلى»', () => {
    expect(atLeast('operator', 'operator')).toBe(true);
    expect(atLeast('admin', 'operator')).toBe(true);
    expect(atLeast('courier', 'operator')).toBe(false); // المندوب لا يعتمد تسويات
    expect(atLeast('manager', 'admin')).toBe(false);
  });
});
