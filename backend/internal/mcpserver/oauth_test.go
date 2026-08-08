package mcpserver

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

func TestOAuthMetadataAndAuthorizationCodeFlow(t *testing.T) {
	server := testOAuthServer(t)

	metadataRecorder := httptest.NewRecorder()
	server.HandleProtectedResourceMetadata(metadataRecorder, httptest.NewRequest(http.MethodGet, "/.well-known/oauth-protected-resource", nil))
	if metadataRecorder.Code != http.StatusOK {
		t.Fatalf("protected resource metadata status = %d", metadataRecorder.Code)
	}
	var metadata map[string]any
	if err := json.Unmarshal(metadataRecorder.Body.Bytes(), &metadata); err != nil {
		t.Fatalf("decode metadata: %v", err)
	}
	if metadata["resource"] != "https://mcp.siyuancheng.com/mcp" {
		t.Fatalf("metadata resource = %v", metadata["resource"])
	}

	verifier := "recall-deck-pkce-verifier"
	form := validAuthorizeValues(verifier)
	form.Set("password", "owner-password")
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/oauth/authorize", strings.NewReader(form.Encode()))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	server.HandleAuthorize(recorder, request)
	if recorder.Code != http.StatusFound {
		t.Fatalf("authorize status = %d body=%s", recorder.Code, recorder.Body.String())
	}
	location := recorder.Header().Get("Location")
	redirectURL, err := url.Parse(location)
	if err != nil {
		t.Fatalf("parse redirect: %v", err)
	}
	code := redirectURL.Query().Get("code")
	if code == "" {
		t.Fatalf("redirect missing code: %s", location)
	}
	if state := redirectURL.Query().Get("state"); state != "state-123" {
		t.Fatalf("redirect state = %q", state)
	}

	tokenForm := url.Values{
		"grant_type":    {"authorization_code"},
		"client_id":     {"recall-deck-chatgpt"},
		"redirect_uri":  {"https://chatgpt.com/connector/oauth/test"},
		"code":          {code},
		"code_verifier": {verifier},
		"resource":      {"https://mcp.siyuancheng.com/mcp"},
	}
	tokenRecorder := httptest.NewRecorder()
	tokenRequest := httptest.NewRequest(http.MethodPost, "/oauth/token", strings.NewReader(tokenForm.Encode()))
	tokenRequest.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	server.HandleToken(tokenRecorder, tokenRequest)
	if tokenRecorder.Code != http.StatusOK {
		t.Fatalf("token status = %d body=%s", tokenRecorder.Code, tokenRecorder.Body.String())
	}
	var tokenResponse struct {
		AccessToken string `json:"access_token"`
		TokenType   string `json:"token_type"`
		Scope       string `json:"scope"`
	}
	if err := json.Unmarshal(tokenRecorder.Body.Bytes(), &tokenResponse); err != nil {
		t.Fatalf("decode token response: %v", err)
	}
	if tokenResponse.TokenType != "Bearer" || tokenResponse.AccessToken == "" {
		t.Fatalf("unexpected token response: %+v", tokenResponse)
	}
	if !server.ValidAccessToken(tokenResponse.AccessToken) {
		t.Fatal("issued access token is not valid")
	}

	reuseRecorder := httptest.NewRecorder()
	reuseRequest := httptest.NewRequest(http.MethodPost, "/oauth/token", strings.NewReader(tokenForm.Encode()))
	reuseRequest.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	server.HandleToken(reuseRecorder, reuseRequest)
	if reuseRecorder.Code != http.StatusBadRequest {
		t.Fatalf("reused code status = %d", reuseRecorder.Code)
	}
}

func TestOAuthRejectsInvalidInputs(t *testing.T) {
	server := testOAuthServer(t)

	badRedirect := validAuthorizeValues("verifier")
	badRedirect.Set("redirect_uri", "https://evil.example/callback")
	request := httptest.NewRequest(http.MethodGet, "/oauth/authorize?"+badRedirect.Encode(), nil)
	recorder := httptest.NewRecorder()
	server.HandleAuthorize(recorder, request)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("bad redirect status = %d", recorder.Code)
	}

	wrongPassword := validAuthorizeValues("verifier")
	wrongPassword.Set("password", "wrong")
	request = httptest.NewRequest(http.MethodPost, "/oauth/authorize", strings.NewReader(wrongPassword.Encode()))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	recorder = httptest.NewRecorder()
	server.HandleAuthorize(recorder, request)
	if recorder.Code != http.StatusOK || !strings.Contains(recorder.Body.String(), "Incorrect owner password") {
		t.Fatalf("wrong password response = %d %s", recorder.Code, recorder.Body.String())
	}
	if len(server.codes) != 0 {
		t.Fatal("wrong password created an authorization code")
	}
}

func TestOAuthRejectsInvalidPKCEVerifier(t *testing.T) {
	server := testOAuthServer(t)

	form := validAuthorizeValues("correct-verifier")
	form.Set("password", "owner-password")
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/oauth/authorize", strings.NewReader(form.Encode()))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	server.HandleAuthorize(recorder, request)
	location := recorder.Header().Get("Location")
	redirectURL, err := url.Parse(location)
	if err != nil {
		t.Fatalf("parse redirect: %v", err)
	}

	tokenForm := url.Values{
		"grant_type":    {"authorization_code"},
		"client_id":     {"recall-deck-chatgpt"},
		"redirect_uri":  {"https://chatgpt.com/connector/oauth/test"},
		"code":          {redirectURL.Query().Get("code")},
		"code_verifier": {"wrong-verifier"},
	}
	tokenRecorder := httptest.NewRecorder()
	tokenRequest := httptest.NewRequest(http.MethodPost, "/oauth/token", strings.NewReader(tokenForm.Encode()))
	tokenRequest.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	server.HandleToken(tokenRecorder, tokenRequest)
	if tokenRecorder.Code != http.StatusBadRequest {
		t.Fatalf("invalid PKCE status = %d body=%s", tokenRecorder.Code, tokenRecorder.Body.String())
	}
}

func TestOAuthAuthorizePostKeepsQueryParameters(t *testing.T) {
	server := testOAuthServer(t)

	verifier := "query-param-verifier"
	values := validAuthorizeValues(verifier)
	request := httptest.NewRequest(http.MethodPost, "/oauth/authorize?"+values.Encode(), strings.NewReader("password=owner-password"))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	recorder := httptest.NewRecorder()
	server.HandleAuthorize(recorder, request)
	if recorder.Code != http.StatusFound {
		t.Fatalf("authorize status = %d body=%s", recorder.Code, recorder.Body.String())
	}
	redirectURL, err := url.Parse(recorder.Header().Get("Location"))
	if err != nil {
		t.Fatalf("parse redirect: %v", err)
	}

	tokenForm := url.Values{
		"grant_type":    {"authorization_code"},
		"client_id":     {"recall-deck-chatgpt"},
		"redirect_uri":  {"https://chatgpt.com/connector/oauth/test"},
		"code":          {redirectURL.Query().Get("code")},
		"code_verifier": {verifier},
		"resource":      {"https://mcp.siyuancheng.com/mcp"},
	}
	tokenRecorder := httptest.NewRecorder()
	tokenRequest := httptest.NewRequest(http.MethodPost, "/oauth/token", strings.NewReader(tokenForm.Encode()))
	tokenRequest.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	server.HandleToken(tokenRecorder, tokenRequest)
	if tokenRecorder.Code != http.StatusOK {
		t.Fatalf("token status = %d body=%s", tokenRecorder.Code, tokenRecorder.Body.String())
	}
}

func TestOAuthAuthMiddleware(t *testing.T) {
	server := testOAuthServer(t)
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})
	handler := withAuth("static-token", server, next)

	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, httptest.NewRequest(http.MethodPost, "/mcp", nil))
	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("missing token status = %d", recorder.Code)
	}
	if !strings.Contains(recorder.Header().Get("WWW-Authenticate"), ".well-known/oauth-protected-resource") {
		t.Fatalf("missing WWW-Authenticate metadata: %s", recorder.Header().Get("WWW-Authenticate"))
	}

	recorder = httptest.NewRecorder()
	staticRequest := httptest.NewRequest(http.MethodPost, "/mcp", nil)
	staticRequest.Header.Set("Authorization", "Bearer static-token")
	handler.ServeHTTP(recorder, staticRequest)
	if recorder.Code != http.StatusNoContent {
		t.Fatalf("static token status = %d", recorder.Code)
	}

	token, err := server.issueAccessToken("", "https://mcp.siyuancheng.com/mcp")
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}
	recorder = httptest.NewRecorder()
	oauthRequest := httptest.NewRequest(http.MethodPost, "/mcp", nil)
	oauthRequest.Header.Set("Authorization", "Bearer "+token)
	handler.ServeHTTP(recorder, oauthRequest)
	if recorder.Code != http.StatusNoContent {
		t.Fatalf("oauth token status = %d", recorder.Code)
	}

	wrongAudience, err := server.issueAccessToken("", "https://mcp.siyuancheng.com")
	if err != nil {
		t.Fatalf("issue wrong audience token: %v", err)
	}
	if server.ValidAccessToken(wrongAudience) {
		t.Fatal("wrong audience token validated")
	}
}

func testOAuthServer(t *testing.T) *OAuthServer {
	t.Helper()
	server, err := NewOAuthServer(OAuthConfig{
		PublicURL:               "https://mcp.siyuancheng.com",
		ClientID:                "recall-deck-chatgpt",
		OwnerPassword:           "owner-password",
		TokenSecret:             "test-token-secret",
		AllowedRedirectPrefixes: []string{"https://chatgpt.com/connector/oauth/"},
	})
	if err != nil {
		t.Fatalf("NewOAuthServer: %v", err)
	}
	fixedNow := time.Unix(1786150000, 0)
	server.now = func() time.Time {
		return fixedNow
	}
	return server
}

func validAuthorizeValues(verifier string) url.Values {
	challengeBytes := sha256.Sum256([]byte(verifier))
	return url.Values{
		"response_type":         {"code"},
		"client_id":             {"recall-deck-chatgpt"},
		"redirect_uri":          {"https://chatgpt.com/connector/oauth/test"},
		"scope":                 {"recall.cards.read recall.cards.write"},
		"state":                 {"state-123"},
		"resource":              {"https://mcp.siyuancheng.com/mcp"},
		"code_challenge":        {base64.RawURLEncoding.EncodeToString(challengeBytes[:])},
		"code_challenge_method": {"S256"},
	}
}
