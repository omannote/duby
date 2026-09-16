import { createClient } from '@supabase/supabase-js';
import { APP_VERSION } from './version.js';

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const isConfigured = Boolean(url && anonKey);

/*
 * anon key هو السر الوحيد الذي يصل المتصفح، وأمانه يعتمد كليًا على RLS.
 * لا مفتاح آخر هنا — service_role وOTP_PEPPER ومفاتيح المزودين مكانها أسرار
 * Edge Functions وحدها (ADR-007).
 */
export const supabase = isConfigured
  ? createClient(url, anonKey, {
      auth: { persistSession: true, autoRefreshToken: true },
      global: { headers: { 'X-App-Version': APP_VERSION } },
    })
  : null;
