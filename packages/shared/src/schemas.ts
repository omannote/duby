import { z } from 'zod';

/**
 * مخططات التحقق — تُستخدم في الواجهة وفي الوظيفة معًا، فلا تتباعدان.
 * التحقق في الواجهة لتجربة الاستخدام، وفي الخادم للحماية.
 */

/** الهاتف العماني: 8 أرقام، أو +968/00968 مسبوقة. التخزين دائمًا +968XXXXXXXX. */
export function normalizeOmaniPhone(raw: string): string | null {
  const digits = raw.replace(/\D/g, '');
  if (/^[79]\d{7}$/.test(digits)) return `+968${digits}`;
  if (/^968[79]\d{7}$/.test(digits)) return `+${digits}`;
  if (/^00968[79]\d{7}$/.test(digits)) return `+${digits.slice(2)}`;
  return null;
}

export const omaniPhone = z.string().transform((value, ctx) => {
  const normalized = normalizeOmaniPhone(value);
  if (!normalized) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'رقم هاتف عماني غير صالح' });
    return z.NEVER;
  }
  return normalized;
});

/** المبالغ بثلاث منازل — DECIMAL لا FLOAT. الحد الأدنى 0.100 ر.ع. */
export const omrAmount = z
  .number()
  .min(0.1, 'الحد الأدنى 0.100 ر.ع')
  .max(9_999_999.999)
  .refine((n) => Number.isInteger(Math.round(n * 1000)), 'ثلاث منازل عشرية كحد أقصى');

/** ريال عماني ← بيسة، للإرسال إلى ثواني. */
export function toBaisa(omr: number): number {
  return Math.round(omr * 1000);
}

export const uuid = z.string().uuid();

/**
 * رمز QR: يُقبل UUID مجردًا أو رابطًا كاملًا من القارئ، ويُطبَّع في الخادم.
 * قبول الصيغتين كان إصلاحًا حقيقيًا في النظام السابق — القارئ الخارجي يرسل
 * الرابط كاملًا بينما كاميرا المتصفح قد ترسل الرمز وحده.
 */
export function normalizeQrToken(raw: string): string | null {
  const trimmed = raw.trim();
  const direct = uuid.safeParse(trimmed.toLowerCase());
  if (direct.success) return direct.data;

  try {
    const url = new URL(trimmed);
    const token = url.searchParams.get('t') ?? url.searchParams.get('token');
    if (!token) return null;
    const parsed = uuid.safeParse(token.trim().toLowerCase());
    return parsed.success ? parsed.data : null;
  } catch {
    return null;
  }
}

export const customerProfileSchema = z.object({
  full_name: z.string().trim().min(2).max(120),
  phone: omaniPhone,
  floor_number: z.string().trim().min(1).max(10),
  apartment_number: z.string().trim().min(1).max(10),
});
export type CustomerProfile = z.infer<typeof customerProfileSchema>;

export const handoverMethods = [
  'bank_deposit',
  'transfer',
  'office_handover',
  'safe_drop',
] as const;
export type HandoverMethod = (typeof handoverMethods)[number];

/** الإيداع البنكي هو الطريقة المعتمدة؛ ما عداه استثناء يتطلب سببًا. */
export const DEFAULT_HANDOVER_METHOD: HandoverMethod = 'bank_deposit';

export function requiresProof(method: HandoverMethod): boolean {
  return method === 'bank_deposit' || method === 'transfer';
}

export function requiresExceptionReason(method: HandoverMethod): boolean {
  return method !== DEFAULT_HANDOVER_METHOD;
}
