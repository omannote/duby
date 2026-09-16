/**
 * عامل إرسال الإشعارات.
 *
 * يُستدعى من الجدولة لا من مستخدم، ويحمل مفتاح جسر واتساب. الإرسال يقع خارج
 * معاملة تغيّر الحالة عمدًا: فشل المزود لا يُرجع حالة الطلب أبدًا.
 */
import { serviceClient } from '../_shared/auth.ts';
import { notificationProvider } from '../_shared/whatsapp.ts';

type OutboxItem = {
  id: number;
  recipient: string;
  template_name: string;
  params: string[];
  idempotency_key: string;
  attempts: number;
};

Deno.serve(async (request) => {
  // لا يُستدعى من الإنترنت: المفتاح هو service_role نفسه
  const authorization = request.headers.get('Authorization') ?? '';
  const expected = `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`;

  if (authorization !== expected) {
    return new Response('forbidden', { status: 403 });
  }

  const db = serviceClient();
  const provider = notificationProvider();

  const { data: batch, error } = await db.rpc('fn_claim_outbox_batch', { p_limit: 50 });

  if (error) {
    console.error(JSON.stringify({
      level: 'error',
      fn: 'notifications',
      outcome: 'claim_failed',
      message: error.message,
    }));
    return Response.json({ ok: false }, { status: 500 });
  }

  const items = (batch ?? []) as OutboxItem[];
  let sent = 0;
  let failed = 0;

  for (const item of items) {
    /*
     * مفتاح معاد الأمان يُمرَّر للمزود: إعادة تشغيل الدورة بعد انقطاع لا
     * ترسل الرسالة مرتين إلى العميل.
     */
    const result = await provider.sendTemplate({
      to: item.recipient,
      template: item.template_name,
      params: item.params,
      idempotencyKey: item.idempotency_key,
    });

    if (result.ok) {
      await db.rpc('fn_mark_outbox_sent', { p_id: item.id, p_provider_msg_id: result.messageId });
      sent += 1;
    } else {
      await db.rpc('fn_mark_outbox_failed', { p_id: item.id, p_error_code: result.code });
      failed += 1;

      // لا محتوى الرسالة ولا رقم المستلم في السجل
      console.error(JSON.stringify({
        level: 'error',
        fn: 'notifications',
        outcome: 'send_failed',
        outbox_id: item.id,
        attempts: item.attempts,
        code: result.code,
      }));
    }
  }

  const { data: health } = await db.rpc('fn_outbox_health');

  console.log(JSON.stringify({
    level: 'info',
    fn: 'notifications',
    claimed: items.length,
    sent,
    failed,
    health,
  }));

  return Response.json({ ok: true, claimed: items.length, sent, failed, health });
});
