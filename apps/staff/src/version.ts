/**
 * رقم الإصدار يُحقن عند البناء ويُعرض في الواجهة ويُرسل في X-App-Version.
 * هذا ما يجعل سؤال «أي نسخة تعمل عليها؟» بلا معنى — النظام يعرف.
 */
export const APP_VERSION = import.meta.env.VITE_APP_VERSION ?? 'dev';
