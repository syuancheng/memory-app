package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/smtp"
	"strings"
)

// CodeSender 投递验证码。identifierType 决定通道：
// email 走邮件，将来 phone 走短信 —— 加手机号时在这里多一个实现即可。
type CodeSender interface {
	SendCode(ctx context.Context, identifierType, identifier, code, purpose string) error
}

// errSenderNotConfigured 的文案必须含 "not configured"：
// writeAuthError 靠这个子串把它分流成 501 而不是 400。
var errSenderNotConfigured = errors.New("email delivery is not configured")

func newCodeSender(cfg Config, client *http.Client) CodeSender {
	switch {
	case cfg.DevCodeLog:
		return devLogSender{}
	case cfg.Resend.APIKey != "" && cfg.Resend.From != "":
		return &resendSender{cfg: cfg.Resend, client: client, baseURL: resendAPIBase}
	case cfg.SMTP.Host != "" && cfg.SMTP.From != "":
		return smtpSender{cfg: cfg.SMTP}
	default:
		return notConfiguredSender{}
	}
}

type notConfiguredSender struct{}

func (notConfiguredSender) SendCode(context.Context, string, string, string, string) error {
	return errSenderNotConfigured
}

// devLogSender 把验证码打进服务端日志，不投递。仅用于本地开发。
type devLogSender struct{}

func (devLogSender) SendCode(_ context.Context, identifierType, identifier, code, purpose string) error {
	log.Printf("auth verification code for %s %s (%s): %s", identifierType, identifier, purpose, code)
	return nil
}

const resendAPIBase = "https://api.resend.com"

type resendSender struct {
	cfg    ResendConfig
	client *http.Client
	// baseURL 可覆盖，便于测试用 httptest 顶替（同 appleJWKSURL 的做法）。
	baseURL string
}

type resendPayload struct {
	From    string   `json:"from"`
	To      []string `json:"to"`
	Subject string   `json:"subject"`
	Text    string   `json:"text"`
	HTML    string   `json:"html"`
}

func (s *resendSender) SendCode(ctx context.Context, identifierType, identifier, code, purpose string) error {
	if identifierType != IdentityEmail {
		return fmt.Errorf("resend cannot deliver to %s identifiers", identifierType)
	}

	body, err := json.Marshal(resendPayload{
		From:    s.cfg.From,
		To:      []string{identifier},
		Subject: codeSubject(purpose),
		Text:    codeTextBody(code, purpose),
		HTML:    codeHTMLBody(code, purpose),
	})
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.baseURL+"/emails", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+s.cfg.APIKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.client.Do(req)
	if err != nil {
		// 上游错误可能带主机名等细节，不能直接回给终端用户。
		log.Printf("resend: request failed: %v", err)
		return errors.New("could not send the verification email, please try again")
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	detail, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
	log.Printf("resend: status %d: %s", resp.StatusCode, strings.TrimSpace(string(detail)))
	return errors.New("could not send the verification email, please try again")
}

// smtpSender 保留给仍在用 SMTP 的部署。
type smtpSender struct {
	cfg SMTPConfig
}

func (s smtpSender) SendCode(_ context.Context, identifierType, identifier, code, purpose string) error {
	if identifierType != IdentityEmail {
		return fmt.Errorf("smtp cannot deliver to %s identifiers", identifierType)
	}
	message := strings.Join([]string{
		"From: " + s.cfg.From,
		"To: " + identifier,
		"Subject: " + codeSubject(purpose),
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=UTF-8",
		"",
		codeTextBody(code, purpose),
	}, "\r\n")

	var smtpAuth smtp.Auth
	if s.cfg.User != "" || s.cfg.Pass != "" {
		smtpAuth = smtp.PlainAuth("", s.cfg.User, s.cfg.Pass, s.cfg.Host)
	}
	if err := smtp.SendMail(s.cfg.Host+":"+s.cfg.Port, smtpAuth, s.cfg.From, []string{identifier}, []byte(message)); err != nil {
		log.Printf("smtp: send failed: %v", err)
		return errors.New("could not send the verification email, please try again")
	}
	return nil
}

func codeSubject(purpose string) string {
	switch purpose {
	case PurposeDeleteAccount:
		return "Confirm your Cardly account deletion"
	case PurposePasswordReset:
		return "Reset your Cardly password"
	default:
		return "Your Cardly verification code"
	}
}

// 有效期从 CodeTTL 渲染，避免文案与常量各写一份而失步。
func expiryPhrase() string {
	return fmt.Sprintf("%d minutes", int(CodeTTL.Minutes()))
}

func codeTextBody(code, purpose string) string {
	return fmt.Sprintf("%s\n\nYour code is %s. It expires in %s.\n\nIf you didn't request this, you can ignore this email.",
		codeIntro(purpose), code, expiryPhrase())
}

func codeHTMLBody(code, purpose string) string {
	return fmt.Sprintf(`<div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;font-size:15px;color:#111827">
  <p>%s</p>
  <p style="font-size:30px;font-weight:700;letter-spacing:6px;margin:24px 0">%s</p>
  <p style="color:#646B7A">It expires in %s.</p>
  <p style="color:#646B7A">If you didn't request this, you can ignore this email.</p>
</div>`, codeIntro(purpose), code, expiryPhrase())
}

func codeIntro(purpose string) string {
	switch purpose {
	case PurposeDeleteAccount:
		return "Use this code to confirm deleting your Cardly account."
	case PurposePasswordReset:
		return "Use this code to reset your Cardly password."
	default:
		return "Use this code to sign in to Cardly."
	}
}
