/**
 * وظيفة رحلة العميل العامة — الوظيفة الوحيدة بلا JWT.
 *
 * تحمل سرّين لا يصلان المتصفح: pepper الخاص بـOTP، ومفتاح جسر واتساب.
 * ولهذا وُجدت: العقارات والعملاء لا تحتاج سرًّا فتُستدعى دوالها مباشرةً
 * (ADR-011)، أما هنا فلا بديل عن الخادم.
 */
import { corsHeaders } from '../_shared/cors.ts';
import { err, ok, requestIdFrom } from '../_shared/result.ts';
import { serviceClient } from '../_shared/auth.ts';
import {
  generateOtp,
  generateSubmissionToken,
  hashIp,
  hashOtp,
  hashSubmissionToken,
} from '../_shared/otp.ts';
import { notificationProvider } from '../_shared/whatsapp.ts';

const OTP_TEMPLATE = Deno.env.get('WHATSAPP_OTP_TEMPLATE') ?? 'order_confirmation_v2';
const OTP_GREETING = Deno.env.get('WHATSAPP_OTP_GREETING') ?? 'عميلنا العزيز';
const PHOTO_BUCKET = 'order-photos';
const MAX_PHOTO_BYTES = 2 * 1024 * 1024;

type Json = Record<string, unknown>;

/** نتيجة دوال قاعدة البيانات: {ok, code?, data?} */
type DbResult = { ok: boolean; code?: string; message?: string; data?: Json };

Deno.serve(async (request) => {
  const origin = request.headers.get('Origin');
  const requestId = requestIdFrom(request);

  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  if (request.method !== 'POST') {
    return err('invalid_input', requestId, origin, 'POST فقط');
  }

  const route = new URL(request.url).pathname.replace(/^\/public-qr/, '') || '/';

  let body: Json;
  try {
    body = (await request.json()) as Json;
  } catch {
    return err('invalid_input', requestId, origin, 'جسم الطلب غير صالح');
  }

  const db = serviceClient();
  const clientIp = request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ??
    request.headers.get('cf-connecting-ip');

  /*
   * صفحة العميل لا ترسل property_id إطلاقًا. وصوله يعني تعديل الواجهة،
   * فيُتجاهل ويُسجَّل — ولا يُرفض الطلب، حتى لا يعرف المتلاعب ما الذي رُصد.
   */
  if ('property_id' in body && typeof body.scan_session_id === 'string') {
    await db.rpc('fn_log_tamper_attempt', {
      p_scan_session: body.scan_session_id,
      p_field: 'property_id',
      p_value: String(body.property_id),
      p_request_id: requestId,
    });
  }

  try {
    switch (route) {
      case '/':
      case '/scan':
        return await handleScan(db, body, clientIp, requestId, origin);
      case '/complete-profile':
        return await handleCompleteProfile(db, body, requestId, origin);
      case '/request-otp':
        return await handleRequestOtp(db, body, requestId, origin);
      case '/verify-otp':
        return await handleVerifyOtp(db, body, requestId, origin);
      case '/photo-upload-url':
        return await handleUploadUrl(db, body, requestId, origin);
      case '/submit-order':
        return await handleSubmitOrder(db, body, requestId, origin);
      default:
        return err('invalid_input', requestId, origin, 'مسار غير معروف');
    }
  } catch (error) {
    // لا تفاصيل داخلية للعميل؛ معرّف الطلب يربط بلاغه بالسجل
    console.error(
      JSON.stringify({
        level: 'error',
        fn: 'public-qr',
        route,
        request_id: requestId,
        message: error instanceof Error ? error.message : 'unknown',
      }),
    );
    return err('server_error', requestId, origin);
  }
});

function relay(result: DbResult, requestId: string, origin: string | null): Response {
  return result.ok
    ? ok(result.data ?? {}, requestId, origin)
    : err(result.code ?? 'server_error', requestId, origin, result.message);
}

async function handleScan(
  db: ReturnType<typeof serviceClient>,
  body: Json,
  clientIp: string | null,
  requestId: string,
  origin: string | null,
): Promise<Response> {
  const token = typeof body.token === 'string' ? body.token.trim() : '';
  if (!token) return err('invalid_qr', requestId, origin);

  const { data, error } = await db.rpc('fn_scan_qr', {
    p_token: token,
    p_ip_hash: await hashIp(clientIp),
    p_user_agent: null,
    p_request_id: requestId,
  });

  // UUID تالف يصل كخطأ نوع من PostgREST، وهو رمز غير صالح لا عطل خادم
  if (error) return err('invalid_qr', requestId, origin);

  return relay(data as DbResult, requestId, origin);
}

async function handleCompleteProfile(
  db: ReturnType<typeof serviceClient>,
  body: Json,
  requestId: string,
  origin: string | null,
): Promise<Response> {
  const { data, error } = await db.rpc('fn_complete_profile', {
    p_scan_session: body.scan_session_id,
    p_full_name: body.full_name,
    p_phone: normalizeOmaniPhone(String(body.phone ?? '')),
    p_floor_number: body.floor_number,
    p_apartment_number: body.apartment_number,
  });

  if (error) return err('invalid_input', requestId, origin);
  return relay(data as DbResult, requestId, origin);
}

async function handleRequestOtp(
  db: ReturnType<typeof serviceClient>,
  body: Json,
  requestId: string,
  origin: string | null,
): Promise<Response> {
  const scanSession = String(body.scan_session_id ?? '');
  const code = generateOtp();

  const { data, error } = await db.rpc('fn_issue_otp', {
    p_scan_session: scanSession,
    p_code_hash: await hashOtp(scanSession, code),
  });

  if (error) return err('server_error', requestId, origin);

  const result = data as DbResult;
  if (!result.ok) return relay(result, requestId, origin);

  const challengeId = String(result.data?.challenge_id);
  const phone = String(result.data?.phone);

  const sent = await notificationProvider().sendTemplate({
    to: phone,
    template: OTP_TEMPLATE,
    params: [OTP_GREETING, code],
    idempotencyKey: `otp:${challengeId}`,
  });

  await db.rpc('fn_mark_otp_sent', { p_challenge_id: challengeId, p_sent: sent.ok });

  if (!sent.ok) {
    console.error(
      JSON.stringify({
        level: 'error',
        fn: 'public-qr',
        route: '/request-otp',
        request_id: requestId,
        outcome: 'provider_error',
        code: sent.code,
      }),
    );
    return err('provider_error', requestId, origin, 'تعذّر إرسال رمز التحقق');
  }

  // الهاتف لا يعود للمتصفح — هو بيانات العميل لا حاجة لإعادتها إليه
  return ok(
    {
      expires_in: result.data?.expires_in,
      resend_available_in: result.data?.resend_available_in,
      attempts_remaining: result.data?.attempts_remaining,
    },
    requestId,
    origin,
  );
}

async function handleVerifyOtp(
  db: ReturnType<typeof serviceClient>,
  body: Json,
  requestId: string,
  origin: string | null,
): Promise<Response> {
  const scanSession = String(body.scan_session_id ?? '');
  const code = String(body.code ?? '').trim();

  if (!/^\d{6}$/.test(code)) return err('otp_invalid', requestId, origin);

  const submissionToken = generateSubmissionToken();

  const { data, error } = await db.rpc('fn_verify_otp', {
    p_scan_session: scanSession,
    p_code_hash: await hashOtp(scanSession, code),
    p_submission_token_hash: await hashSubmissionToken(submissionToken),
  });

  if (error) return err('server_error', requestId, origin);

  const result = data as DbResult;
  if (!result.ok) return relay(result, requestId, origin);

  // الرمز الصريح يعود مرة واحدة هنا فقط، ولا يُخزَّن في أي مكان
  return ok({ ...result.data, submission_token: submissionToken }, requestId, origin);
}

async function handleUploadUrl(
  db: ReturnType<typeof serviceClient>,
  body: Json,
  requestId: string,
  origin: string | null,
): Promise<Response> {
  const byteSize = Number(body.byte_size ?? 0);

  if (body.content_type !== 'image/jpeg') {
    return err('photo_rejected', requestId, origin, 'JPEG فقط');
  }

  if (!Number.isFinite(byteSize) || byteSize <= 0 || byteSize > MAX_PHOTO_BYTES) {
    return err('photo_rejected', requestId, origin, 'حجم الصورة خارج الحد المسموح');
  }

  /*
   * الرفع يذهب من المتصفح إلى التخزين مباشرة: يتجنّب حد حجم الطلب على
   * وظائف Edge ويقلّل زمن الاستجابة. المسار عشوائي غير قابل للتوقع.
   */
  const path = `staging/${crypto.randomUUID()}.jpg`;
  const { data, error } = await db.storage.from(PHOTO_BUCKET).createSignedUploadUrl(path);

  if (error || !data) return err('server_error', requestId, origin);

  return ok(
    { upload_url: data.signedUrl, storage_path: path, token: data.token, expires_in: 300 },
    requestId,
    origin,
  );
}

async function handleSubmitOrder(
  db: ReturnType<typeof serviceClient>,
  body: Json,
  requestId: string,
  origin: string | null,
): Promise<Response> {
  const storagePath = String(body.storage_path ?? '');

  if (!storagePath.startsWith('staging/')) {
    return err('photo_rejected', requestId, origin, 'مسار صورة غير متوقع');
  }

  // التحقق من وجود الملف فعلًا قبل إنشاء الطلب
  const { data: file } = await db.storage
    .from(PHOTO_BUCKET)
    .download(storagePath)
    .catch(() => ({ data: null }));

  if (!file) return err('photo_rejected', requestId, origin, 'لم تُرفع الصورة');

  const bytes = new Uint8Array(await file.arrayBuffer());

  // فحص البايتات الافتتاحية: الامتداد وحده لا يثبت نوع الملف
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) {
    await db.storage.from(PHOTO_BUCKET).remove([storagePath]);
    return err('photo_rejected', requestId, origin, 'الملف ليس صورة JPEG');
  }

  const digest = await crypto.subtle.digest('SHA-256', bytes);
  const sha256 = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');

  const finalPath = `intake/${crypto.randomUUID()}.jpg`;
  const { error: moveError } = await db.storage.from(PHOTO_BUCKET).move(storagePath, finalPath);
  if (moveError) return err('server_error', requestId, origin);

  const { data, error } = await db.rpc('fn_submit_order', {
    p_submission_token_hash: await hashSubmissionToken(String(body.submission_token ?? '')),
    p_storage_path: finalPath,
    p_byte_size: bytes.byteLength,
    p_sha256: sha256,
  });

  if (error) {
    await db.storage.from(PHOTO_BUCKET).remove([finalPath]);
    return err('server_error', requestId, origin);
  }

  const result = data as DbResult;

  // فشل إنشاء الطلب لا يترك صورة يتيمة في التخزين
  if (!result.ok) {
    await db.storage.from(PHOTO_BUCKET).remove([finalPath]);
    return relay(result, requestId, origin);
  }

  return ok(result.data ?? {}, requestId, origin);
}

/** يُقبل الرقم بثمانية أرقام أو مسبوقًا، ويُخزَّن دائمًا بصيغة +968XXXXXXXX. */
function normalizeOmaniPhone(raw: string): string {
  const digits = raw.replace(/\D/g, '');
  if (/^[79]\d{7}$/.test(digits)) return `+968${digits}`;
  if (/^968[79]\d{7}$/.test(digits)) return `+${digits}`;
  if (/^00968[79]\d{7}$/.test(digits)) return `+${digits.slice(2)}`;
  return raw;
}
