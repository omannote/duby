/**
 * وظيفة دورة حياة الطلب للموظفين.
 *
 * تجمع عميلين لغرضين مختلفين: جلسة الموظف لاستدعاء دوال النطاق (فهويته
 * مرتبطة بالتوقيع ولا تُنتحل)، وservice_role للتخزين وحده.
 */
import { corsHeaders } from '../_shared/cors.ts';
import { err, ok, requestIdFrom } from '../_shared/result.ts';
import { requireStaff, serviceClient } from '../_shared/auth.ts';

const PHOTO_BUCKET = 'order-photos';
const MAX_PHOTO_BYTES = 2 * 1024 * 1024;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type Json = Record<string, unknown>;
type DbResult = { ok: boolean; code?: string; message?: string; data?: Json };

Deno.serve(async (request) => {
  const origin = request.headers.get('Origin');
  const requestId = requestIdFrom(request);

  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  if (request.method !== 'POST') return err('invalid_input', requestId, origin, 'POST فقط');

  const staff = await requireStaff(request);
  if (!staff) return err('forbidden', requestId, origin);

  let body: Json;
  try {
    body = (await request.json()) as Json;
  } catch {
    return err('invalid_input', requestId, origin, 'جسم الطلب غير صالح');
  }

  const route = new URL(request.url).pathname.replace(/^\/staff-orders/, '') || '/';

  try {
    switch (route) {
      case '/advance':
        return relay(
          await staff.client.rpc('fn_advance_status', {
            p_order_id: body.order_id,
            p_expected_status: body.expected_status,
            p_to_status: body.to_status,
          }),
          requestId,
          origin,
        );

      case '/cancel':
        return relay(
          await staff.client.rpc('fn_cancel_order', {
            p_order_id: body.order_id,
            p_reason: body.reason,
          }),
          requestId,
          origin,
        );

      case '/photo-upload-url':
        return await handleUploadUrl(body, requestId, origin);

      case '/field-step':
        return await handleFieldStep(staff, body, requestId, origin);

      case '/photo-url':
        return await handlePhotoUrl(body, requestId, origin);

      default:
        return err('invalid_input', requestId, origin, 'مسار غير معروف');
    }
  } catch (error) {
    console.error(JSON.stringify({
      level: 'error',
      fn: 'staff-orders',
      route,
      request_id: requestId,
      actor_role: staff.role,
      message: error instanceof Error ? error.message : 'unknown',
    }));
    return err('server_error', requestId, origin);
  }
});

function relay(
  response: { data: unknown; error: { message: string } | null },
  requestId: string,
  origin: string | null,
): Response {
  if (response.error) return err('server_error', requestId, origin);

  const result = response.data as DbResult;
  return result.ok
    ? ok(result.data ?? {}, requestId, origin)
    : err(result.code ?? 'server_error', requestId, origin, result.message);
}

async function handleUploadUrl(
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

  const path = `staging/${crypto.randomUUID()}.jpg`;
  const { data, error } = await serviceClient()
    .storage.from(PHOTO_BUCKET)
    .createSignedUploadUrl(path);

  if (error || !data) return err('server_error', requestId, origin);

  return ok(
    { upload_url: data.signedUrl, storage_path: path, token: data.token, expires_in: 300 },
    requestId,
    origin,
  );
}

/**
 * الاستلام والتسليم — أهم مسار في النظام.
 *
 * الصورة تُتحقق وتُنقل أولًا، ثم تُنفَّذ العملية الذرّية. إن فشلت لأي سبب
 * تُحذف الصورة فورًا: لا تبقى صورة يتيمة في التخزين ولا حالة نصف منفَّذة.
 */
async function handleFieldStep(
  staff: NonNullable<Awaited<ReturnType<typeof requireStaff>>>,
  body: Json,
  requestId: string,
  origin: string | null,
): Promise<Response> {
  const step = String(body.step ?? '');
  if (step !== 'pickup' && step !== 'delivery') {
    return err('invalid_input', requestId, origin);
  }

  // يُقبل الرمز UUID مجردًا أو رابط QR كاملًا: القارئ الخارجي يرسل الرابط
  // بينما كاميرا المتصفح قد ترسل الرمز وحده
  const qrToken = normalizeQrToken(String(body.qr_token ?? ''));
  if (!qrToken) return err('qr_mismatch', requestId, origin, 'الرمز الممسوح غير صالح');

  const storagePath = String(body.storage_path ?? '');
  if (!storagePath.startsWith('staging/')) {
    return err('photo_rejected', requestId, origin, 'مسار صورة غير متوقع');
  }

  const db = serviceClient();

  const { data: file } = await db.storage.from(PHOTO_BUCKET).download(storagePath);
  if (!file) return err('photo_rejected', requestId, origin, 'لم تُرفع الصورة');

  const bytes = new Uint8Array(await file.arrayBuffer());

  // البايتات الافتتاحية: الامتداد وحده لا يثبت نوع الملف
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) {
    await db.storage.from(PHOTO_BUCKET).remove([storagePath]);
    return err('photo_rejected', requestId, origin, 'الملف ليس صورة JPEG');
  }

  const digest = await crypto.subtle.digest('SHA-256', bytes);
  const sha256 = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');

  const finalPath = `${step}/${crypto.randomUUID()}.jpg`;
  const { error: moveError } = await db.storage.from(PHOTO_BUCKET).move(storagePath, finalPath);
  if (moveError) return err('server_error', requestId, origin);

  const { data, error } = await staff.client.rpc('fn_confirm_field_step', {
    p_order_id: body.order_id,
    p_step: step,
    p_qr_token: qrToken,
    p_storage_path: finalPath,
    p_byte_size: bytes.byteLength,
    p_sha256: sha256,
    p_latitude: body.latitude ?? null,
    p_longitude: body.longitude ?? null,
  });

  if (error) {
    await db.storage.from(PHOTO_BUCKET).remove([finalPath]);
    return err('server_error', requestId, origin);
  }

  const result = data as DbResult;

  if (!result.ok) {
    await db.storage.from(PHOTO_BUCKET).remove([finalPath]);
    return err(result.code ?? 'server_error', requestId, origin, result.message);
  }

  return ok(result.data ?? {}, requestId, origin);
}

/** رابط قراءة موقّع قصير الصلاحية: الحاوية خاصة ولا رابط دائم لأي صورة. */
async function handlePhotoUrl(
  body: Json,
  requestId: string,
  origin: string | null,
): Promise<Response> {
  const path = String(body.storage_path ?? '');
  if (!path) return err('invalid_input', requestId, origin);

  const { data, error } = await serviceClient()
    .storage.from(PHOTO_BUCKET)
    .createSignedUrl(path, 120);

  if (error || !data) return err('server_error', requestId, origin);

  return ok({ url: data.signedUrl, expires_in: 120 }, requestId, origin);
}

function normalizeQrToken(raw: string): string | null {
  const trimmed = raw.trim();
  if (UUID_PATTERN.test(trimmed)) return trimmed.toLowerCase();

  try {
    const url = new URL(trimmed);
    const token = (url.searchParams.get('t') ?? url.searchParams.get('token') ?? '').trim();
    return UUID_PATTERN.test(token) ? token.toLowerCase() : null;
  } catch {
    return null;
  }
}
