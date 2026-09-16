import { describe, expect, it } from 'vitest';
import {
  ORDER_STATUSES,
  canCancel,
  canTransition,
  isFinal,
  nextStatus,
  transitionKind,
} from '../order-status.js';

describe('مصفوفة انتقالات الطلب', () => {
  it('تغطي كل الخانات الـ64 بقرار صريح', () => {
    let checked = 0;
    for (const from of ORDER_STATUSES) {
      for (const to of ORDER_STATUSES) {
        expect(typeof canTransition(from, to)).toBe('boolean');
        checked += 1;
      }
    }
    expect(checked).toBe(64);
  });

  it('تسمح بالمسار الطبيعي', () => {
    expect(canTransition('new', 'confirmed')).toBe(true);
    expect(canTransition('confirmed', 'picked_up')).toBe(true);
    expect(canTransition('picked_up', 'processing')).toBe(true);
    expect(canTransition('processing', 'ready')).toBe(true);
    expect(canTransition('ready', 'out_for_delivery')).toBe(true);
    expect(canTransition('out_for_delivery', 'completed')).toBe(true);
  });

  it('ترفض القفز فوق المراحل', () => {
    expect(canTransition('new', 'picked_up')).toBe(false);
    expect(canTransition('ready', 'completed')).toBe(false);
    expect(canTransition('confirmed', 'out_for_delivery')).toBe(false);
  });

  it('ترفض الرجوع للخلف', () => {
    expect(canTransition('processing', 'picked_up')).toBe(false);
    expect(canTransition('completed', 'out_for_delivery')).toBe(false);
  });

  it('تقفل الحالات النهائية', () => {
    expect(isFinal('completed')).toBe(true);
    expect(isFinal('cancelled')).toBe(true);
    for (const to of ORDER_STATUSES) {
      expect(canTransition('completed', to)).toBe(false);
      expect(canTransition('cancelled', to)).toBe(false);
    }
  });

  it('تصنّف الاستلام والتسليم كانتقالين ميدانيين', () => {
    expect(transitionKind('confirmed', 'picked_up')).toBe('field');
    expect(transitionKind('out_for_delivery', 'completed')).toBe('field');
    expect(transitionKind('picked_up', 'processing')).toBe('manual');
  });

  it('تسمح بالإلغاء حتى ما قبل الاكتمال فقط', () => {
    expect(canCancel('new')).toBe(true);
    expect(canCancel('out_for_delivery')).toBe(true);
    expect(canCancel('completed')).toBe(false);
    expect(canCancel('cancelled')).toBe(false);
  });

  it('تعطي حالة تالية واحدة لا قائمة', () => {
    expect(nextStatus('new')?.to).toBe('confirmed');
    expect(nextStatus('out_for_delivery')?.to).toBe('completed');
    expect(nextStatus('completed')).toBeNull();
  });
});
