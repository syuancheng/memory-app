package mcpserver

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	defaultAccessTokenTTL = 30 * 24 * time.Hour
	authCodeTTL           = 5 * time.Minute
)

var recallDeckScopes = []string{"recall.cards.read", "recall.cards.write"}

type OAuthConfig struct {
	PublicURL               string
	ClientID                string
	OwnerPassword           string
	TokenSecret             string
	AllowedRedirectPrefixes []string
}

type OAuthServer struct {
	publicURL               string
	resourceURL             string
	clientID                string
	ownerPassword           string
	tokenSecret             []byte
	allowedRedirectPrefixes []string
	now                     func() time.Time

	mu    sync.Mutex
	codes map[string]authCode
}

type authCode struct {
	ClientID            string
	RedirectURI         string
	Scope               string
	Resource            string
	CodeChallenge       string
	CodeChallengeMethod string
	ExpiresAt           time.Time
	Used                bool
}

type tokenClaims struct {
	Subject  string `json:"sub"`
	Audience string `json:"aud"`
	Scope    string `json:"scope"`
	IssuedAt int64  `json:"iat"`
	Expires  int64  `json:"exp"`
	ID       string `json:"jti"`
}

func NewOAuthServer(cfg OAuthConfig) (*OAuthServer, error) {
	if strings.TrimSpace(cfg.PublicURL) == "" {
		return nil, errors.New("oauth public URL is required")
	}
	if strings.TrimSpace(cfg.ClientID) == "" {
		return nil, errors.New("oauth client ID is required")
	}
	if strings.TrimSpace(cfg.OwnerPassword) == "" {
		return nil, errors.New("oauth owner password is required")
	}
	if strings.TrimSpace(cfg.TokenSecret) == "" {
		return nil, errors.New("oauth token secret is required")
	}
	publicURL := strings.TrimRight(cfg.PublicURL, "/")
	prefixes := make([]string, 0, len(cfg.AllowedRedirectPrefixes))
	for _, prefix := range cfg.AllowedRedirectPrefixes {
		prefix = strings.TrimSpace(prefix)
		if prefix != "" {
			prefixes = append(prefixes, prefix)
		}
	}
	if len(prefixes) == 0 {
		return nil, errors.New("oauth allowed redirect prefixes are required")
	}
	return &OAuthServer{
		publicURL:               publicURL,
		resourceURL:             publicURL + "/mcp",
		clientID:                strings.TrimSpace(cfg.ClientID),
		ownerPassword:           cfg.OwnerPassword,
		tokenSecret:             []byte(cfg.TokenSecret),
		allowedRedirectPrefixes: prefixes,
		now:                     time.Now,
		codes:                   map[string]authCode{},
	}, nil
}

func (s *OAuthServer) ClientID() string {
	return s.clientID
}

func (s *OAuthServer) HandleProtectedResourceMetadata(w http.ResponseWriter, _ *http.Request) {
	writeOAuthJSON(w, http.StatusOK, map[string]any{
		"resource":                 s.resourceURL,
		"authorization_servers":    []string{s.publicURL},
		"scopes_supported":         recallDeckScopes,
		"bearer_methods_supported": []string{"header"},
		"resource_documentation":   s.publicURL + "/oauth/docs",
	})
}

func (s *OAuthServer) HandleAuthorizationServerMetadata(w http.ResponseWriter, _ *http.Request) {
	writeOAuthJSON(w, http.StatusOK, map[string]any{
		"issuer":                                s.publicURL,
		"authorization_endpoint":                s.publicURL + "/oauth/authorize",
		"token_endpoint":                        s.publicURL + "/oauth/token",
		"response_types_supported":              []string{"code"},
		"grant_types_supported":                 []string{"authorization_code"},
		"code_challenge_methods_supported":      []string{"S256"},
		"token_endpoint_auth_methods_supported": []string{"none"},
		"scopes_supported":                      recallDeckScopes,
		"protected_resources":                   []string{s.resourceURL},
	})
}

func (s *OAuthServer) HandleAuthorize(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.showAuthorize(w, r, "")
	case http.MethodPost:
		s.submitAuthorize(w, r)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (s *OAuthServer) showAuthorize(w http.ResponseWriter, r *http.Request, message string) {
	params := r.URL.Query()
	if err := s.validateAuthorizeParams(params); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Authorize RecallDeck</title>
  <style>
    body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#f8f7f4;color:#111827;margin:0;min-height:100vh;display:grid;place-items:center}
    main{width:min(420px,calc(100vw - 32px));background:#fff;border:1px solid #ece8df;border-radius:24px;padding:28px;box-shadow:0 18px 50px rgba(17,24,39,.08)}
    h1{font-size:24px;margin:0 0 8px} p{color:#6b7280;line-height:1.45} label{display:block;font-weight:650;margin:22px 0 8px}
    input{width:100%%;box-sizing:border-box;border:1px solid #ddd7cc;border-radius:14px;padding:13px 14px;font-size:16px}
    button{width:100%%;border:0;border-radius:16px;margin-top:18px;padding:14px 16px;background:#111827;color:white;font-size:16px;font-weight:700}
    .error{color:#b42318;background:#fff1f0;border-radius:12px;padding:10px 12px}
    small{display:block;color:#8a8f98;margin-top:14px}
  </style>
</head>
<body><main>
  <h1>Authorize RecallDeck</h1>
  <p>ChatGPT is requesting access to your RecallDeck flashcards.</p>
  %s
  <form method="post" action="%s">
    %s
    <label for="password">Owner password</label>
    <input id="password" name="password" type="password" autocomplete="current-password" autofocus required>
    <button type="submit">Authorize ChatGPT</button>
  </form>
  <small>Only continue if you started this connection from ChatGPT.</small>
</main></body></html>`,
		errorBlock(message),
		html.EscapeString(r.URL.RequestURI()),
		hiddenInputs(params),
	)
}

func (s *OAuthServer) submitAuthorize(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "invalid form", http.StatusBadRequest)
		return
	}
	if err := s.validateAuthorizeParams(r.Form); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if subtle.ConstantTimeCompare([]byte(r.PostForm.Get("password")), []byte(s.ownerPassword)) != 1 {
		s.showAuthorize(w, formAsRequest(r), "Incorrect owner password.")
		return
	}

	code, err := randomURLToken(32)
	if err != nil {
		http.Error(w, "failed to create authorization code", http.StatusInternalServerError)
		return
	}
	resource := r.Form.Get("resource")
	if resource == "" {
		resource = s.resourceURL
	}
	s.mu.Lock()
	s.codes[code] = authCode{
		ClientID:            r.Form.Get("client_id"),
		RedirectURI:         r.Form.Get("redirect_uri"),
		Scope:               normalizeScope(r.Form.Get("scope")),
		Resource:            resource,
		CodeChallenge:       r.Form.Get("code_challenge"),
		CodeChallengeMethod: r.Form.Get("code_challenge_method"),
		ExpiresAt:           s.now().Add(authCodeTTL),
	}
	s.mu.Unlock()

	redirectURL, err := url.Parse(r.Form.Get("redirect_uri"))
	if err != nil {
		http.Error(w, "invalid redirect URI", http.StatusBadRequest)
		return
	}
	query := redirectURL.Query()
	query.Set("code", code)
	if state := r.Form.Get("state"); state != "" {
		query.Set("state", state)
	}
	redirectURL.RawQuery = query.Encode()
	http.Redirect(w, r, redirectURL.String(), http.StatusFound)
}

func (s *OAuthServer) HandleToken(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if err := r.ParseForm(); err != nil {
		writeOAuthError(w, http.StatusBadRequest, "invalid_request", "invalid form")
		return
	}
	if r.Form.Get("grant_type") != "authorization_code" {
		writeOAuthError(w, http.StatusBadRequest, "unsupported_grant_type", "grant_type must be authorization_code")
		return
	}
	code := r.Form.Get("code")
	if code == "" {
		writeOAuthError(w, http.StatusBadRequest, "invalid_request", "code is required")
		return
	}

	authCode, err := s.consumeCode(code)
	if err != nil {
		writeOAuthError(w, http.StatusBadRequest, "invalid_grant", err.Error())
		return
	}
	if r.Form.Get("client_id") != authCode.ClientID || authCode.ClientID != s.clientID {
		writeOAuthError(w, http.StatusBadRequest, "invalid_client", "invalid client_id")
		return
	}
	if r.Form.Get("redirect_uri") != authCode.RedirectURI {
		writeOAuthError(w, http.StatusBadRequest, "invalid_grant", "redirect_uri mismatch")
		return
	}
	if authCode.CodeChallenge != "" && !validPKCE(authCode.CodeChallenge, authCode.CodeChallengeMethod, r.Form.Get("code_verifier")) {
		writeOAuthError(w, http.StatusBadRequest, "invalid_grant", "invalid code_verifier")
		return
	}

	token, err := s.issueAccessToken(authCode.Scope, authCode.Resource)
	if err != nil {
		writeOAuthError(w, http.StatusInternalServerError, "server_error", "failed to issue token")
		return
	}
	writeOAuthJSON(w, http.StatusOK, map[string]any{
		"access_token": token,
		"token_type":   "Bearer",
		"expires_in":   int(defaultAccessTokenTTL.Seconds()),
		"scope":        authCode.Scope,
	})
}

func (s *OAuthServer) ValidAccessToken(token string) bool {
	if token == "" {
		return false
	}
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return false
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return false
	}
	signature, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return false
	}
	expected := signPayload(s.tokenSecret, parts[0])
	if hmac.Equal(signature, expected) == false {
		return false
	}
	var claims tokenClaims
	if err := json.Unmarshal(payload, &claims); err != nil {
		return false
	}
	now := s.now().Unix()
	return claims.Subject == "owner" &&
		claims.Audience == s.resourceURL &&
		claims.Expires > now &&
		claims.IssuedAt <= now
}

func (s *OAuthServer) WriteUnauthorized(w http.ResponseWriter) {
	w.Header().Set("WWW-Authenticate", fmt.Sprintf(`Bearer realm="mcp", resource_metadata="%s/.well-known/oauth-protected-resource"`, s.publicURL))
	http.Error(w, "unauthorized", http.StatusUnauthorized)
}

func (s *OAuthServer) validateAuthorizeParams(params url.Values) error {
	if params.Get("response_type") != "code" {
		return errors.New("response_type must be code")
	}
	if params.Get("client_id") != s.clientID {
		return errors.New("invalid client_id")
	}
	redirectURI := params.Get("redirect_uri")
	if redirectURI == "" || !s.redirectAllowed(redirectURI) {
		return errors.New("redirect_uri is not allowed")
	}
	if params.Get("code_challenge") != "" && params.Get("code_challenge_method") != "S256" {
		return errors.New("code_challenge_method must be S256")
	}
	resource := params.Get("resource")
	if resource != "" && resource != s.resourceURL && resource != s.publicURL {
		return errors.New("invalid resource")
	}
	return nil
}

func (s *OAuthServer) redirectAllowed(redirectURI string) bool {
	parsed, err := url.Parse(redirectURI)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
		return false
	}
	for _, prefix := range s.allowedRedirectPrefixes {
		if strings.HasPrefix(redirectURI, prefix) {
			return true
		}
	}
	return false
}

func (s *OAuthServer) consumeCode(code string) (authCode, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	value, ok := s.codes[code]
	if !ok {
		return authCode{}, errors.New("authorization code not found")
	}
	if value.Used {
		return authCode{}, errors.New("authorization code already used")
	}
	if s.now().After(value.ExpiresAt) {
		delete(s.codes, code)
		return authCode{}, errors.New("authorization code expired")
	}
	value.Used = true
	s.codes[code] = value
	return value, nil
}

func (s *OAuthServer) issueAccessToken(scope string, resource string) (string, error) {
	if resource == "" {
		resource = s.resourceURL
	}
	now := s.now()
	jti, err := randomURLToken(16)
	if err != nil {
		return "", err
	}
	claims := tokenClaims{
		Subject:  "owner",
		Audience: resource,
		Scope:    normalizeScope(scope),
		IssuedAt: now.Unix(),
		Expires:  now.Add(defaultAccessTokenTTL).Unix(),
		ID:       jti,
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	encodedPayload := base64.RawURLEncoding.EncodeToString(payload)
	signature := signPayload(s.tokenSecret, encodedPayload)
	return encodedPayload + "." + base64.RawURLEncoding.EncodeToString(signature), nil
}

func signPayload(secret []byte, payload string) []byte {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(payload))
	return mac.Sum(nil)
}

func validPKCE(challenge string, method string, verifier string) bool {
	if challenge == "" {
		return true
	}
	if method != "S256" || verifier == "" {
		return false
	}
	sum := sha256.Sum256([]byte(verifier))
	actual := base64.RawURLEncoding.EncodeToString(sum[:])
	return subtle.ConstantTimeCompare([]byte(actual), []byte(challenge)) == 1
}

func randomURLToken(bytes int) (string, error) {
	buffer := make([]byte, bytes)
	if _, err := rand.Read(buffer); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buffer), nil
}

func normalizeScope(scope string) string {
	fields := strings.Fields(scope)
	if len(fields) == 0 {
		return strings.Join(recallDeckScopes, " ")
	}
	return strings.Join(fields, " ")
}

func hiddenInputs(values url.Values) string {
	names := []string{"response_type", "client_id", "redirect_uri", "scope", "state", "resource", "code_challenge", "code_challenge_method"}
	var builder strings.Builder
	for _, name := range names {
		if value := values.Get(name); value != "" {
			fmt.Fprintf(&builder, `<input type="hidden" name="%s" value="%s">`, html.EscapeString(name), html.EscapeString(value))
		}
	}
	return builder.String()
}

func errorBlock(message string) string {
	if message == "" {
		return ""
	}
	return `<p class="error">` + html.EscapeString(message) + `</p>`
}

func formAsRequest(r *http.Request) *http.Request {
	clone := r.Clone(r.Context())
	query := url.Values{}
	for key, values := range r.PostForm {
		if key == "password" {
			continue
		}
		for _, value := range values {
			query.Add(key, value)
		}
	}
	clone.URL.RawQuery = query.Encode()
	return clone
}

func writeOAuthJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeOAuthError(w http.ResponseWriter, status int, code string, description string) {
	writeOAuthJSON(w, status, map[string]string{
		"error":             code,
		"error_description": description,
	})
}
