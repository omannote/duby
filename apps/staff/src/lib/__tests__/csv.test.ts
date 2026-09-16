import { describe, expect, it } from 'vitest';
import { formatCell, toCsv } from '../csv.js';

const spec = {
  columns: [
    { key: 'name', label: 'الاسم' },
    { key: 'amount', label: 'المبلغ', format: 'amount' as const },
  ],
};

describe('formatCell', () => {
  it('يعرض الفراغ بشرطة لا بكلمة null', () => {
    expect(formatCell(null)).toBe('—');
  });

  it('يعرض المبلغ بثلاث خانات كما هو عرف الريال', () => {
    expect(formatCell(12.5, 'amount')).toBe('12.500 ر.ع');
  });

  it('يعرض النسبة والساعات بخانة واحدة', () => {
    expect(formatCell(66.66, 'percent')).toBe('66.7%');
    expect(formatCell(3.14, 'hours')).toBe('3.1 س');
  });
});

describe('toCsv', () => {
  it('يبدأ بـBOM ليقرأ Excel العربية صحيحة', () => {
    expect(toCsv(spec, [])).toMatch(/^\uFEFF/);
  });

  it('يقتبس الفاصلة والاقتباس وسطر جديد', () => {
    const csv = toCsv(spec, [{ name: 'أحمد, "أبو علي"\nسالم', amount: 1 }]);

    expect(csv).toContain('"أحمد, ""أبو علي""\nسالم"');
  });

  /*
   * حقن الصيغ: خلية تبدأ بـ= يفسّرها Excel أمرًا. أسماء العملاء مدخلات
   * خارجية، فالاختبار يثبّت التحييد لا يصفه فحسب.
   */
  it('يحيّد الخلايا التي تبدأ برموز الصيغ', () => {
    const csv = toCsv(spec, [
      { name: '=1+1', amount: 0 },
      { name: '+971', amount: 0 },
      { name: '-5', amount: 0 },
      { name: '@SUM(A1)', amount: 0 },
    ]);

    expect(csv).toContain("'=1+1");
    expect(csv).toContain("'+971");
    expect(csv).toContain("'-5");
    expect(csv).toContain("'@SUM(A1)");
  });

  it('يكتب رؤوس الأعمدة بالعربية ويصدّر القيمة الخام لا المنسّقة', () => {
    const csv = toCsv(spec, [{ name: 'سالم', amount: 12.5 }]);

    expect(csv.split('\r\n')[0]).toBe('\uFEFFالاسم,المبلغ');
    expect(csv).toContain('سالم,12.5');
  });

  it('يكتب الفراغ خلية خالية لا شرطة', () => {
    expect(toCsv(spec, [{ name: null, amount: null }])).toContain('\r\n,\r\n');
  });
});
