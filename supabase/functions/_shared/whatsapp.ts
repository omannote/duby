/**
 * جسر واتساب خلف واجهة مجرّدة، فيمكن استبدال المزود دون لمس منطق الطلبات.
 */
export type SendResult = { ok: true; messageId: string } | { ok: false; code: string };

export interface NotificationProvider {
  sendTemplate(input: {
    to: string;
    template: string;
    params: string[];
    idempotencyKey: string;
  }): Promise<SendResult>;
}

/** يوحّد الرقم إلى 968XXXXXXXX كما يتوقعه الجسر. */
export function toBridgeNumber(phone: string): string {
  return phone.replace(/^\+/, '');
}

export class WhatsAppBridgeProvider implements NotificationProvider {
  async sendTemplate(input: {
    to: string;
    template: string;
    params: string[];
    idempotencyKey: string;
  }): Promise<SendResult> {
    const baseUrl = Deno.env.get('WHATSAPP_BRIDGE_BASE_URL');
    const apiKey = Deno.env.get('WHATSAPP_BRIDGE_API_KEY');

    if (!baseUrl || !apiKey) return { ok: false, code: 'provider_not_configured' };

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15_000);

    try {
      const response = await fetch(`${baseUrl}/messages/send-notification`, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': apiKey,
          'X-Idempotency-Key': input.idempotencyKey,
        },
        body: JSON.stringify({
          to: toBridgeNumber(input.to),
          template_name: input.template,
          params: input.params,
          language: Deno.env.get('WHATSAPP_LANGUAGE') ?? 'ar',
          image_url: null,
        }),
      });

      if (!response.ok) return { ok: false, code: `provider_http_${response.status}` };

      // استجابة المزود لا تُعاد للعميل ولا تُسجَّل كاملة
      const body = (await response.json().catch(() => ({}))) as { id?: string };
      return { ok: true, messageId: body.id ?? 'unknown' };
    } catch (error) {
      return {
        ok: false,
        code: error instanceof Error && error.name === 'AbortError'
          ? 'provider_timeout'
          : 'provider_error',
      };
    } finally {
      clearTimeout(timeout);
    }
  }
}

/** مزوّد مزيّف للتطوير المحلي والاختبارات — لا يرسل شيئًا. */
export class FakeNotificationProvider implements NotificationProvider {
  sendTemplate(): Promise<SendResult> {
    return Promise.resolve({ ok: true, messageId: 'fake' });
  }
}

export function notificationProvider(): NotificationProvider {
  return Deno.env.get('SMS_PROVIDER') === 'whatsapp_bridge'
    ? new WhatsAppBridgeProvider()
    : new FakeNotificationProvider();
}
