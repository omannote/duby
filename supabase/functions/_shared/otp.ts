/**
 * توليد رمز التحقق وتجزئته.
 *
 * قاعدة مطلقة: الرمز الصريح لا يغادر هذه الوحدة إلى أي سجل أو جدول أو
 * استثناء. قاعدة البيانات ترى التجزئة وحدها؛ واتساب يرى الرمز مرة واحدة.
 *
 * التجزئة مربوطة بـ qr_token وجلسة المسح معًا، فرمز صالح لجلسة لا يصلح لأخرى
 * ولا لعميل آخر.
 */
const encoder = new TextEncoder();

async function hmac(key: string, message: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    encoder.encode(key),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign('HMAC', cryptoKey, encoder.encode(message));

  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function pepper(): string {
  const value = Deno.env.get('OTP_PEPPER');
  if (!value || value.length < 32) {
    throw new Error('OTP_PEPPER missing or too short');
  }
  return value;
}

/** ستة أرقام من مولّد آمن تشفيريًا، لا Math.random. */
export function generateOtp(): string {
  const buffer = new Uint32Array(1);
  crypto.getRandomValues(buffer);
  return String(buffer[0]! % 1_000_000).padStart(6, '0');
}

export function hashOtp(scanSession: string, code: string): Promise<string> {
  return hmac(pepper(), `otp:${scanSession}:${code}`);
}

/** رمز إرسال الطلب: يُعاد للعميل مرة، ويُخزَّن مجزَّأً. */
export function generateSubmissionToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

export function hashSubmissionToken(token: string): Promise<string> {
  return hmac(pepper(), `submission:${token}`);
}

/** عنوان الشبكة يُخزَّن مجزَّأً لا صريحًا. */
export function hashIp(ip: string | null): Promise<string | null> {
  return ip ? hmac(pepper(), `ip:${ip}`) : Promise.resolve(null);
}
