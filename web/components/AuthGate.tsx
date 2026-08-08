"use client";

import { ReactNode, useEffect, useState } from "react";
import { api, AuthUser, sessionToken } from "@/lib/api";

export default function AuthGate({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [checking, setChecking] = useState(true);
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [codeSent, setCodeSent] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    const token = sessionToken.get();
    if (!token) {
      setChecking(false);
      return;
    }

    api
      .getCurrentUser()
      .then((response) => setUser(response.user))
      .catch(() => sessionToken.clear())
      .finally(() => setChecking(false));
  }, []);

  async function sendCode() {
    const normalizedEmail = email.trim();
    if (!normalizedEmail) {
      return;
    }
    setSubmitting(true);
    setError("");
    setMessage("");
    try {
      await api.requestAuthCode(normalizedEmail);
      setCodeSent(true);
      setMessage("Code sent. Check your email.");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not send code");
    } finally {
      setSubmitting(false);
    }
  }

  async function signIn() {
    const normalizedEmail = email.trim();
    const normalizedCode = code.trim();
    if (!normalizedEmail || !normalizedCode) {
      return;
    }
    setSubmitting(true);
    setError("");
    setMessage("");
    try {
      const response = await api.verifyAuthCode(normalizedEmail, normalizedCode);
      if (!response.session_token) {
        throw new Error("Missing session token");
      }
      sessionToken.set(response.session_token);
      setUser(response.user);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not sign in");
    } finally {
      setSubmitting(false);
    }
  }

  async function signOut() {
    try {
      await api.logout();
    } catch {
      // Local sign-out should still complete if the API is unreachable.
    }
    sessionToken.clear();
    setUser(null);
    setCode("");
    setCodeSent(false);
  }

  if (checking) {
    return (
      <div className="authScreen">
        <div className="authCard">
          <h1>Cardly</h1>
          <p className="subtle">Checking session...</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return (
      <div className="authScreen">
        <div className="authCard">
          <p className="eyebrow">Cardly</p>
          <h1>Sign in</h1>
          <p className="subtle">Use your email verification code to manage your flashcards.</p>

          <div className="field">
            <label htmlFor="authEmail">Email</label>
            <input
              id="authEmail"
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="you@example.com"
              autoComplete="email"
            />
          </div>

          {codeSent && (
            <div className="field">
              <label htmlFor="authCode">Verification code</label>
              <input
                id="authCode"
                value={code}
                onChange={(event) => setCode(event.target.value)}
                placeholder="6-digit code"
                autoComplete="one-time-code"
              />
            </div>
          )}

          <div className="actions">
            <button
              className="primaryButton"
              onClick={codeSent ? signIn : sendCode}
              disabled={submitting || !email.trim() || (codeSent && !code.trim())}
            >
              {submitting ? "Working..." : codeSent ? "Sign in" : "Send code"}
            </button>
            {codeSent && (
              <button className="secondary" onClick={sendCode} disabled={submitting || !email.trim()}>
                Resend
              </button>
            )}
          </div>

          {message && <div className="authMessage">{message}</div>}
          {error && <div className="error">{error}</div>}
        </div>
      </div>
    );
  }

  return (
    <>
      <div className="sessionBar">
        <span>{user.email}</span>
        <button className="ghost" onClick={signOut}>
          Log out
        </button>
      </div>
      {children}
    </>
  );
}
