import { useState, type FormEvent } from 'react';
import { supabase } from '../supabase.js';

export function SignIn() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (!supabase) return;

    setBusy(true);
    setError(null);

    const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });

    // لا رسالة عامة بلا سبب: نميّز فشل البيانات عن تعذّر الوصول
    if (signInError) {
      setError(
        signInError.message.includes('Invalid')
          ? 'البريد أو كلمة المرور غير صحيحة'
          : `تعذّر تسجيل الدخول: ${signInError.message}`,
      );
    }

    setBusy(false);
  }

  return (
    <div className="signin">
      <form onSubmit={handleSubmit} className="signin-card">
        <h1>دوبي</h1>
        <p className="signin-subtitle">لوحة الموظفين</p>

        <label htmlFor="email">البريد الإلكتروني</label>
        <input
          id="email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          autoComplete="username"
          required
        />

        <label htmlFor="password">كلمة المرور</label>
        <input
          id="password"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          autoComplete="current-password"
          required
        />

        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}

        <button type="submit" disabled={busy}>
          {busy ? 'جارٍ الدخول…' : 'تسجيل الدخول'}
        </button>
      </form>
    </div>
  );
}
