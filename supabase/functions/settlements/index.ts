/**
 * وظيفة الصندوق: الإيداع الموثَّق والاعتماد عن بُعد.
 *
 * وُجدت لسببين يحتاجان الخادم: توقيع رفع إيصال الإيداع وفحص بايتاته، وتوقيع
 * رابط قراءته للمدقّق. ما عدا ذلك تُستدعى الدوال بجلسة الموظف (ADR-011).
 */
import { corsHeaders } from '../_shared/cors.ts';
import { err, ok, requestIdFrom } from '../_shared/result.ts';
import { requireStaff, serviceClient } from '../_shared/auth.ts';

const PHOTO_BUCKET = 'order-photos';
const MAX_PHOTO_BYTES = 2 * 1024 * 1024;

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

  const route = new URL(request.url).pathname.replace(/^\/settlements/, '') || '/';

  try {
    switch (route) {
      case '/proof-upload-url':
        return await handleUploadUrl(
          requestId,
          origin,
          Number(body.byte_size ?? 0),
          body.content_type,
        );

      case '/handover':
        return await handleHandover(staff, body, requestId, origin);

      case '/verify':
        return relay(
          await staff.client.rpc('fn_verify_settlement', {
            p_settlement_id: body.settlement_id,
            p_confirmed_amount: body.confirmed_amount,
            p_variance_reason: body.variance_reason ?? null,
          }),
          requestId,
          origin,
        );

      case '/approve-variance':
        return relay(
          await staff.client.rpc('fn_approve_variance', {
            p_settlement_id: body.settlement_id,
            p_reason: body.reason,
          }),
          requestId,
          origin,
        );

      case '/match-bank':
        return relay(
          await staff.client.rpc('fn_match_bank_deposit', {
            p_settlement_id: body.settlement_id,
            p_bank_reference: body.bank_reference,
          }),
          requestId,
          origin,
        );

      case '/reverse-collection':
        return relay(
          await staff.client.rpc('fn_reverse_cash_collection', {
            p_collection_id: body.collection_id,
            p_reason: body.reason,
          }),
          requestId,
          origin,
        );

      case '/proof-url':
        return await handleProofUrl(body, requestId, origin);

      default:
        return err('invalid_input', requestId, origin, 'مسار غير معروف');
    }
  } catch (error) {
    console.error(JSON.stringify({
      level: 'error',
      fn: 'settlements',
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
  requestId: string,
  origin: string | null,
  byteSize: number,
  contentType: unknown,
): Promise<Response> {
  if (contentType !== 'image/jpeg') {
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
    { upload_url: data.signedUrl, storage_path: path, expires_in: 300 },
    requestId,
    origin,
  );
}

/**
 * الإيداع: يُتحقق من الإيصال ويُنقل، ثم تُنفَّذ العملية. إن فشلت تُحذف الصورة
 * فلا يبقى إيصال يتيم في التخزين.
 */
async function handleHandover(
  staff: NonNullable<Awaited<ReturnType<typeof requireStaff>>>,
  body: Json,
  requestId: string,
  origin: string | null,
): Promise<Response> {
  const db = serviceClient();
  const storagePath = body.storage_path ? String(body.storage_path) : null;

  let finalPath: string | null = null;
  let byteSize: number | null = null;
  let sha256: string | null = null;

  if (storagePath) {
    if (!storagePath.startsWith('staging/')) {
      return err('photo_rejected', requestId, origin, 'مسار صورة غير متوقع');
    }

    const { data: file } = await db.storage.from(PHOTO_BUCKET).download(storagePath);
    if (!file) return err('photo_rejected', requestId, origin, 'لم يُرفع الإيصال');

    const bytes = new Uint8Array(await file.arrayBuffer());

    if (bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) {
      await db.storage.from(PHOTO_BUCKET).remove([storagePath]);
      return err('photo_rejected', requestId, origin, 'الملف ليس صورة JPEG');
    }

    const digest = await crypto.subtle.digest('SHA-256', bytes);
    sha256 = Array.from(new Uint8Array(digest))
      .map((byte) => byte.toString(16).padStart(2, '0'))
      .join('');
    byteSize = bytes.byteLength;

    finalPath = `cash/${crypto.randomUUID()}.jpg`;
    const { error: moveError } = await db.storage.from(PHOTO_BUCKET).move(storagePath, finalPath);
    if (moveError) return err('server_error', requestId, origin);
  }

  const { data, error } = await staff.client.rpc('fn_hand_over_settlement', {
    p_settlement_id: body.settlement_id,
    p_declared_amount: body.declared_amount,
    p_method: body.handover_method ?? 'bank_deposit',
    p_reference: body.handover_reference ?? null,
    p_photo_path: finalPath,
    p_byte_size: byteSize,
    p_sha256: sha256,
    p_exception_reason: body.exception_reason ?? null,
    p_note: body.note ?? null,
  });

  const cleanup = async () => {
    if (finalPath) await db.storage.from(PHOTO_BUCKET).remove([finalPath]);
  };

  if (error) {
    await cleanup();
    return err('server_error', requestId, origin);
  }

  const result = data as DbResult;

  if (!result.ok) {
    await cleanup();
    return err(result.code ?? 'server_error', requestId, origin, result.message);
  }

  return ok(result.data ?? {}, requestId, origin);
}

/** رابط قراءة موقّع: هو ما يمكّن الاعتماد عن بُعد من الهاتف. */
async function handleProofUrl(
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
