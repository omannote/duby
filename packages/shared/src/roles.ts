/** الأدوار مرتبة. المرجع: docs/plan/06-security.md */
export const STAFF_ROLES = ['courier', 'operator', 'manager', 'admin'] as const;
export type StaffRole = (typeof STAFF_ROLES)[number];

export const ROLE_LABELS: Record<StaffRole, string> = {
  courier: 'مندوب',
  operator: 'مشغّل',
  manager: 'مشرف',
  admin: 'مدير',
};

const RANK: Record<StaffRole, number> = { courier: 1, operator: 2, manager: 3, admin: 4 };

export function roleRank(role: StaffRole): number {
  return RANK[role];
}

export function atLeast(role: StaffRole, minimum: StaffRole): boolean {
  return RANK[role] >= RANK[minimum];
}
