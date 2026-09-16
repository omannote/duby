/**
 * حالات الطلب ومصفوفة الانتقالات المسموحة.
 * المرجع: docs/plan/04-domain-flows.md
 *
 * `delivered` محذوفة عمدًا: كانت تعني شيئين مختلفين في النظام السابق فأنتجت
 * طلبات عالقة. بديلها out_for_delivery (خرج للتوصيل) و completed (سُلِّم فعلًا).
 */
export const ORDER_STATUSES = [
  'new',
  'confirmed',
  'picked_up',
  'processing',
  'ready',
  'out_for_delivery',
  'completed',
  'cancelled',
] as const;

export type OrderStatus = (typeof ORDER_STATUSES)[number];

export const ORDER_STATUS_LABELS: Record<OrderStatus, string> = {
  new: 'جديد',
  confirmed: 'مؤكد',
  picked_up: 'تم الاستلام',
  processing: 'قيد التنفيذ',
  ready: 'جاهز',
  out_for_delivery: 'خرج للتوصيل',
  completed: 'مكتمل',
  cancelled: 'ملغي',
};

/** كيف يقع الانتقال — لا كل الانتقالات بضغطة زر. */
export type TransitionKind = 'manual' | 'field' | 'conditional';

type Transition = { to: OrderStatus; kind: TransitionKind };

export const TRANSITIONS: Record<OrderStatus, Transition[]> = {
  new: [
    { to: 'confirmed', kind: 'manual' },
    { to: 'cancelled', kind: 'conditional' },
  ],
  confirmed: [
    { to: 'picked_up', kind: 'field' }, // QR + صورة في موقع العميل
    { to: 'cancelled', kind: 'conditional' },
  ],
  picked_up: [
    { to: 'processing', kind: 'manual' },
    { to: 'cancelled', kind: 'conditional' },
  ],
  processing: [
    { to: 'ready', kind: 'manual' },
    { to: 'cancelled', kind: 'conditional' },
  ],
  ready: [
    { to: 'out_for_delivery', kind: 'conditional' }, // يتطلب فاتورة
    { to: 'cancelled', kind: 'conditional' },
  ],
  out_for_delivery: [
    { to: 'completed', kind: 'field' }, // دفع + QR + صورة تسليم
    { to: 'cancelled', kind: 'conditional' },
  ],
  completed: [], // نهائية ومقفلة
  cancelled: [], // نهائية ومقفلة
};

export function canTransition(from: OrderStatus, to: OrderStatus): boolean {
  return TRANSITIONS[from].some((t) => t.to === to);
}

export function transitionKind(from: OrderStatus, to: OrderStatus): TransitionKind | null {
  return TRANSITIONS[from].find((t) => t.to === to)?.kind ?? null;
}

/** الحالة التالية في المسار — زر واحد باتجاه واحد، لا قائمة منسدلة. */
export function nextStatus(from: OrderStatus): Transition | null {
  return TRANSITIONS[from].find((t) => t.to !== 'cancelled') ?? null;
}

export function isFinal(status: OrderStatus): boolean {
  return TRANSITIONS[status].length === 0;
}

export function canCancel(status: OrderStatus): boolean {
  return canTransition(status, 'cancelled');
}
