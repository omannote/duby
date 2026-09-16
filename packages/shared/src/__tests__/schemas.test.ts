import { describe, expect, it } from 'vitest';
import { normalizeOmaniPhone, normalizeQrToken, toBaisa } from '../schemas.js';

describe('normalizeOmaniPhone', () => {
  it('يقبل ثمانية أرقام', () => {
    expect(normalizeOmaniPhone('91234567')).toBe('+96891234567');
    expect(normalizeOmaniPhone('71234567')).toBe('+96871234567');
  });

  it('يقبل الصيغ المسبوقة', () => {
    expect(normalizeOmaniPhone('+968 9123 4567')).toBe('+96891234567');
    expect(normalizeOmaniPhone('0096891234567')).toBe('+96891234567');
  });

  it('يرفض غير الصالح', () => {
    expect(normalizeOmaniPhone('12345678')).toBeNull(); // لا يبدأ بـ 7 أو 9
    expect(normalizeOmaniPhone('9123456')).toBeNull(); // قصير
    expect(normalizeOmaniPhone('+971501234567')).toBeNull(); // غير عماني
    expect(normalizeOmaniPhone('')).toBeNull();
  });
});

describe('normalizeQrToken', () => {
  const token = '3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b';

  it('يقبل UUID مجردًا', () => {
    expect(normalizeQrToken(token)).toBe(token);
    expect(normalizeQrToken(`  ${token.toUpperCase()}  `)).toBe(token);
  });

  it('يقبل رابط QR كاملًا بالوسيطين t و token', () => {
    expect(normalizeQrToken(`https://qr.myduby.com/?t=${token}`)).toBe(token);
    expect(normalizeQrToken(`https://myduby.com/qr/?token=${token}`)).toBe(token);
  });

  it('يرفض ما ليس رمزًا', () => {
    expect(normalizeQrToken('https://qr.myduby.com/')).toBeNull();
    expect(normalizeQrToken('not-a-uuid')).toBeNull();
  });
});

describe('toBaisa', () => {
  it('يحوّل الريال إلى بيسة بلا خطأ عشري', () => {
    expect(toBaisa(4.5)).toBe(4500);
    expect(toBaisa(0.1)).toBe(100);
    expect(toBaisa(18.75)).toBe(18750);
    expect(toBaisa(0.007)).toBe(7);
  });
});
