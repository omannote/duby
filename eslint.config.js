import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: [
      '**/dist/**',
      '**/node_modules/**',
      'supabase/functions/**',
      'packages/shared/src/db.ts',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,

  {
    rules: {
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      'no-console': ['warn', { allow: ['warn', 'error'] }],

      /*
       * ADR: refreshSession() داخل معالج حدث في الواجهة كان السبب الجذري لعطل
       * تأكيد التسليم في النظام السابق — يطلق حدث تغيير جلسة فيعيد تركيب الشجرة
       * ويغلق النافذة قبل إرسال الطلب. التجديد مسؤولية طبقة العميل وحدها.
       */
      'no-restricted-syntax': [
        'error',
        {
          selector: "CallExpression[callee.property.name='refreshSession']",
          message:
            'لا تستدعِ refreshSession() في كود الواجهة. التجديد يتم في طبقة عميل Supabase تلقائيًا.',
        },
      ],
    },
  },

  // منطق مشترك وواجهات — يعمل في المتصفح
  {
    files: ['apps/**/src/**/*.{ts,tsx}', 'packages/**/src/**/*.ts'],
    languageOptions: { globals: globals.browser },
  },

  // أدوات ومهام — تعمل في Node
  {
    files: ['scripts/**/*.mjs', '*.config.{js,ts}', 'vitest.config.ts'],
    languageOptions: { globals: globals.node },
    rules: { 'no-console': 'off' },
  },

  // الاختبارات
  {
    files: ['**/*.test.ts', '**/*.test.tsx'],
    languageOptions: { globals: { ...globals.node, ...globals.browser } },
  },
);
