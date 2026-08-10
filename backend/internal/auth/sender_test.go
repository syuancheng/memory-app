package auth

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func newTestResendSender(t *testing.T, handler http.HandlerFunc) (*resendSender, *httptest.Server) {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	return &resendSender{
		cfg:     ResendConfig{APIKey: "re_test_key", From: "Cardly <noreply@example.com>"},
		client:  srv.Client(),
		baseURL: srv.URL,
	}, srv
}

func TestResendSenderPayload(t *testing.T) {
	var got resendPayload
	var authHeader string

	sender, _ := newTestResendSender(t, func(w http.ResponseWriter, r *http.Request) {
		authHeader = r.Header.Get("Authorization")
		body, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(body, &got)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"id":"abc"}`))
	})

	if err := sender.SendCode(context.Background(), IdentityEmail, "user@example.com", "123456", PurposeLogin); err != nil {
		t.Fatalf("SendCode: %v", err)
	}

	if authHeader != "Bearer re_test_key" {
		t.Fatalf("unexpected auth header: %q", authHeader)
	}
	if len(got.To) != 1 || got.To[0] != "user@example.com" {
		t.Fatalf("unexpected recipients: %v", got.To)
	}
	if !strings.Contains(got.Text, "123456") || !strings.Contains(got.HTML, "123456") {
		t.Fatal("code must appear in both the text and html bodies")
	}
	// 有效期文案从 CodeTTL 渲染，不是第二份写死的常量。
	if !strings.Contains(got.Text, expiryPhrase()) {
		t.Fatalf("expiry phrase missing from body: %q", got.Text)
	}
}

func TestResendSubjectVariesByPurpose(t *testing.T) {
	subjects := map[string]string{}
	sender, _ := newTestResendSender(t, func(w http.ResponseWriter, r *http.Request) {
		var p resendPayload
		body, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(body, &p)
		subjects[p.Subject] = p.Subject
		w.WriteHeader(http.StatusOK)
	})

	for _, purpose := range []string{PurposeLogin, PurposeDeleteAccount, PurposePasswordReset} {
		if err := sender.SendCode(context.Background(), IdentityEmail, "u@example.com", "000000", purpose); err != nil {
			t.Fatalf("SendCode(%s): %v", purpose, err)
		}
	}
	if len(subjects) != 3 {
		t.Fatalf("expected a distinct subject per purpose, got %d: %v", len(subjects), subjects)
	}
}

// 上游 4xx/5xx 的原文可能含 API key 或账号细节，绝不能透传给终端用户 ——
// 这条路径此前把 SMTP 的原始错误直接渲染在登录表单里。
func TestResendErrorIsRedacted(t *testing.T) {
	for _, status := range []int{http.StatusUnauthorized, http.StatusUnprocessableEntity, http.StatusInternalServerError} {
		sender, _ := newTestResendSender(t, func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(status)
			_, _ = w.Write([]byte(`{"message":"key re_secret_leak is invalid for domain internal.example"}`))
		})

		err := sender.SendCode(context.Background(), IdentityEmail, "u@example.com", "000000", PurposeLogin)
		if err == nil {
			t.Fatalf("status %d should surface an error", status)
		}
		msg := err.Error()
		for _, leak := range []string{"re_secret_leak", "internal.example", "invalid for domain"} {
			if strings.Contains(msg, leak) {
				t.Fatalf("status %d leaked upstream detail %q in %q", status, leak, msg)
			}
		}
	}
}

func TestResendRejectsNonEmailIdentifiers(t *testing.T) {
	sender, _ := newTestResendSender(t, func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("must not call the API for a phone identifier")
	})
	if err := sender.SendCode(context.Background(), IdentityPhone, "+8613800138000", "000000", PurposeLogin); err == nil {
		t.Fatal("expected an error for a phone identifier")
	}
}

// 通道优先级：DevCodeLog > Resend > SMTP > 未配置。
// 顺序错了会导致生产误用 devlog（只打日志、永不发信）。
func TestNewCodeSenderPrecedence(t *testing.T) {
	full := Config{
		DevCodeLog: true,
		Resend:     ResendConfig{APIKey: "k", From: "f"},
		SMTP:       SMTPConfig{Host: "h", From: "f"},
	}
	if _, ok := newCodeSender(full, http.DefaultClient).(devLogSender); !ok {
		t.Fatal("DevCodeLog must win over every real channel")
	}

	full.DevCodeLog = false
	if _, ok := newCodeSender(full, http.DefaultClient).(*resendSender); !ok {
		t.Fatal("Resend must win over SMTP")
	}

	full.Resend = ResendConfig{}
	if _, ok := newCodeSender(full, http.DefaultClient).(smtpSender); !ok {
		t.Fatal("SMTP is the remaining fallback")
	}

	full.SMTP = SMTPConfig{}
	sender := newCodeSender(full, http.DefaultClient)
	if _, ok := sender.(notConfiguredSender); !ok {
		t.Fatal("nothing configured must yield notConfiguredSender")
	}
	// writeAuthError 靠 "not configured" 子串分流成 501；改了文案会退化成 400。
	err := sender.SendCode(context.Background(), IdentityEmail, "u@example.com", "1", PurposeLogin)
	if err == nil || !strings.Contains(err.Error(), "not configured") {
		t.Fatalf("error must contain \"not configured\", got %v", err)
	}
}

// Resend 只有在 key 与发件人都齐全时才可用；只配一半应回落而不是发出去必失败的请求。
func TestResendNeedsBothKeyAndFrom(t *testing.T) {
	onlyKey := Config{Resend: ResendConfig{APIKey: "k"}, SMTP: SMTPConfig{Host: "h", From: "f"}}
	if _, ok := newCodeSender(onlyKey, http.DefaultClient).(smtpSender); !ok {
		t.Fatal("a Resend key without a From address must fall back to SMTP")
	}
}
