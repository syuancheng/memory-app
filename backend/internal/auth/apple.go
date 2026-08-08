package auth

import (
	"context"
	"crypto"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const (
	AppleProvider = "apple"
	appleIssuer   = "https://appleid.apple.com"
	appleTokenURL = "https://appleid.apple.com/auth/token"
)

type AppleSignInInput struct {
	IdentityToken     string
	AuthorizationCode string
	Nonce             string
	FullName          string
	Email             string
}

type AppleWebAuthInput struct {
	Code        string
	IDToken     string
	RedirectURI string
}

type appleTokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	IDToken      string `json:"id_token"`
	ExpiresIn    int    `json:"expires_in"`
	TokenType    string `json:"token_type"`
	Error        string `json:"error"`
	ErrorDesc    string `json:"error_description"`
}

type appleIdentity struct {
	Subject       string
	Email         string
	EmailVerified bool
}

type appleIDTokenClaims struct {
	Issuer        string        `json:"iss"`
	Subject       string        `json:"sub"`
	Audience      audienceClaim `json:"aud"`
	ExpiresAt     int64         `json:"exp"`
	IssuedAt      int64         `json:"iat"`
	Nonce         string        `json:"nonce"`
	Email         string        `json:"email"`
	EmailVerified flexibleBool  `json:"email_verified"`
}

type appleJWTHeader struct {
	Algorithm string `json:"alg"`
	KeyID     string `json:"kid"`
}

type appleKeySet struct {
	Keys []appleJWK `json:"keys"`
}

type appleJWK struct {
	KeyID     string `json:"kid"`
	Algorithm string `json:"alg"`
	KeyType   string `json:"kty"`
	Use       string `json:"use"`
	N         string `json:"n"`
	E         string `json:"e"`
	Curve     string `json:"crv"`
	X         string `json:"x"`
	Y         string `json:"y"`
}

type audienceClaim []string

func (a *audienceClaim) UnmarshalJSON(data []byte) error {
	var single string
	if err := json.Unmarshal(data, &single); err == nil {
		*a = []string{single}
		return nil
	}
	var multiple []string
	if err := json.Unmarshal(data, &multiple); err != nil {
		return err
	}
	*a = multiple
	return nil
}

func (a audienceClaim) Contains(value string) bool {
	for _, item := range a {
		if item == value {
			return true
		}
	}
	return false
}

type flexibleBool bool

func (b *flexibleBool) UnmarshalJSON(data []byte) error {
	var value bool
	if err := json.Unmarshal(data, &value); err == nil {
		*b = flexibleBool(value)
		return nil
	}
	var text string
	if err := json.Unmarshal(data, &text); err != nil {
		return err
	}
	*b = flexibleBool(strings.EqualFold(text, "true"))
	return nil
}

func (s *Service) SignInWithApple(ctx context.Context, input AppleSignInInput) (User, string, error) {
	audience := strings.TrimSpace(s.cfg.Apple.IOSBundleID)
	if audience == "" {
		return User{}, "", errors.New("apple iOS bundle ID is not configured")
	}
	identity, err := s.verifyAppleIDToken(ctx, input.IdentityToken, audience, input.Nonce)
	if err != nil {
		return User{}, "", err
	}

	var tokenResponse appleTokenResponse
	if strings.TrimSpace(input.AuthorizationCode) != "" && s.appleTokenExchangeConfigured() {
		tokenResponse, err = s.exchangeAppleCode(ctx, input.AuthorizationCode, audience, "")
		if err != nil {
			return User{}, "", err
		}
	}

	if input.Email != "" && identity.Email == "" {
		identity.Email = strings.TrimSpace(input.Email)
	}
	user, token, err := s.findOrCreateAppleUser(ctx, identity, input.FullName, audience, tokenResponse)
	if err != nil {
		return User{}, "", err
	}
	return user, token, nil
}

func (s *Service) SignInWithAppleWeb(ctx context.Context, input AppleWebAuthInput) (User, error) {
	audience := strings.TrimSpace(s.cfg.Apple.WebServicesID)
	if audience == "" {
		return User{}, errors.New("apple web services ID is not configured")
	}
	redirectURI := strings.TrimSpace(input.RedirectURI)
	if redirectURI == "" {
		redirectURI = strings.TrimSpace(s.cfg.Apple.RedirectURI)
	}
	if redirectURI == "" {
		return User{}, errors.New("apple redirect URI is not configured")
	}

	tokenResponse := appleTokenResponse{IDToken: strings.TrimSpace(input.IDToken)}
	var err error
	if strings.TrimSpace(input.Code) != "" {
		tokenResponse, err = s.exchangeAppleCode(ctx, input.Code, audience, redirectURI)
		if err != nil {
			return User{}, err
		}
	}
	identity, err := s.verifyAppleIDToken(ctx, tokenResponse.IDToken, audience, "")
	if err != nil {
		return User{}, err
	}
	user, _, err := s.findOrCreateAppleUser(ctx, identity, "", audience, tokenResponse)
	return user, err
}

func (s *Service) AppleWebAuthorizationURL(state string) (string, error) {
	if strings.TrimSpace(s.cfg.Apple.WebServicesID) == "" {
		return "", errors.New("apple web services ID is not configured")
	}
	if strings.TrimSpace(s.cfg.Apple.RedirectURI) == "" {
		return "", errors.New("apple redirect URI is not configured")
	}
	values := url.Values{
		"response_type": {"code id_token"},
		"response_mode": {"form_post"},
		"client_id":     {s.cfg.Apple.WebServicesID},
		"redirect_uri":  {s.cfg.Apple.RedirectURI},
		"scope":         {"name email"},
		"state":         {state},
	}
	return "https://appleid.apple.com/auth/authorize?" + values.Encode(), nil
}

func (s *Service) findOrCreateAppleUser(ctx context.Context, identity appleIdentity, fullName string, clientID string, tokenResponse appleTokenResponse) (User, string, error) {
	if strings.TrimSpace(identity.Subject) == "" {
		return User{}, "", errors.New("apple subject is required")
	}
	displayName := strings.TrimSpace(fullName)
	if displayName == "" {
		displayName = "Cardly User"
	}
	email := strings.TrimSpace(identity.Email)
	placeholderEmail := applePlaceholderEmail(identity.Subject)

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return User{}, "", err
	}
	defer tx.Rollback(ctx)

	var user User
	err = tx.QueryRow(ctx, `
		SELECT u.id::text, COALESCE(u.primary_email, ac.email, u.email), COALESCE(u.display_name, ac.display_name, u.name, ''), ac.provider
		FROM account_connections ac
		JOIN users u ON u.id = ac.user_id
		WHERE ac.provider = $1
		  AND ac.provider_user_id = $2
		  AND u.deleted_at IS NULL
		  AND u.status = 'active'
	`, AppleProvider, identity.Subject).Scan(&user.ID, &user.Email, &user.Name, &user.Provider)
	if err != nil && err != pgx.ErrNoRows {
		return User{}, "", err
	}

	if err == pgx.ErrNoRows {
		userID := uuid.NewString()
		primaryEmail := nullableText(email)
		if err = tx.QueryRow(ctx, `
			INSERT INTO users (id, email, primary_email, name, display_name, status, deleted_at, last_login_at)
			VALUES ($1, $2, $3, $4, $4, 'active', NULL, now())
			RETURNING id::text, COALESCE(primary_email, email), COALESCE(display_name, name, '')
		`, userID, placeholderEmail, primaryEmail, displayName).Scan(&user.ID, &user.Email, &user.Name); err != nil {
			return User{}, "", err
		}
		user.Provider = AppleProvider
		if _, err = tx.Exec(ctx, `
			INSERT INTO account_connections (
				id, user_id, provider, provider_user_id, email, email_verified,
				display_name, connected_at
			) VALUES ($1, $2, $3, $4, $5, $6, $7, now())
		`, uuid.NewString(), user.ID, AppleProvider, identity.Subject, nullableText(email), bool(identity.EmailVerified), displayName); err != nil {
			return User{}, "", err
		}
	} else {
		if _, err = tx.Exec(ctx, `
			UPDATE users
			SET primary_email = COALESCE($2, primary_email),
			    display_name = COALESCE(NULLIF($3, ''), display_name),
			    last_login_at = now(),
			    updated_at = now()
			WHERE id = $1
		`, user.ID, nullableText(email), displayName); err != nil {
			return User{}, "", err
		}
		if _, err = tx.Exec(ctx, `
			UPDATE account_connections
			SET email = COALESCE($3, email),
			    email_verified = $4,
			    display_name = COALESCE(NULLIF($5, ''), display_name),
			    updated_at = now()
			WHERE provider = $1 AND provider_user_id = $2
		`, AppleProvider, identity.Subject, nullableText(email), bool(identity.EmailVerified), displayName); err != nil {
			return User{}, "", err
		}
	}

	if err = s.storeAppleProviderTokens(ctx, tx, user.ID, identity.Subject, clientID, tokenResponse); err != nil {
		return User{}, "", err
	}
	token, err := s.createSession(ctx, tx, user.ID)
	if err != nil {
		return User{}, "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return User{}, "", err
	}
	return user, token, nil
}

func (s *Service) verifyAppleIDToken(ctx context.Context, idToken string, audience string, rawNonce string) (appleIdentity, error) {
	idToken = strings.TrimSpace(idToken)
	if idToken == "" {
		return appleIdentity{}, errors.New("apple identity token is required")
	}
	parts := strings.Split(idToken, ".")
	if len(parts) != 3 {
		return appleIdentity{}, errors.New("invalid apple identity token")
	}
	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return appleIdentity{}, errors.New("invalid apple identity token header")
	}
	var header appleJWTHeader
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		return appleIdentity{}, errors.New("invalid apple identity token header")
	}
	payloadBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return appleIdentity{}, errors.New("invalid apple identity token payload")
	}
	var claims appleIDTokenClaims
	if err := json.Unmarshal(payloadBytes, &claims); err != nil {
		return appleIdentity{}, errors.New("invalid apple identity token payload")
	}
	if claims.Issuer != appleIssuer {
		return appleIdentity{}, errors.New("invalid apple token issuer")
	}
	if !claims.Audience.Contains(audience) {
		return appleIdentity{}, errors.New("invalid apple token audience")
	}
	now := s.now().Unix()
	if claims.ExpiresAt <= now || claims.IssuedAt > now+300 {
		return appleIdentity{}, errors.New("expired apple identity token")
	}
	if strings.TrimSpace(rawNonce) != "" {
		sum := sha256.Sum256([]byte(rawNonce))
		if claims.Nonce != hex.EncodeToString(sum[:]) {
			return appleIdentity{}, errors.New("invalid apple token nonce")
		}
	}
	if err := s.verifyAppleSignature(ctx, header, parts[0]+"."+parts[1], parts[2]); err != nil {
		return appleIdentity{}, err
	}
	return appleIdentity{
		Subject:       claims.Subject,
		Email:         claims.Email,
		EmailVerified: bool(claims.EmailVerified),
	}, nil
}

func (s *Service) verifyAppleSignature(ctx context.Context, header appleJWTHeader, signingInput string, encodedSignature string) error {
	signature, err := base64.RawURLEncoding.DecodeString(encodedSignature)
	if err != nil {
		return errors.New("invalid apple identity token signature")
	}
	keys, err := s.applePublicKeys(ctx)
	if err != nil {
		return err
	}
	var jwk *appleJWK
	for index := range keys.Keys {
		if keys.Keys[index].KeyID == header.KeyID {
			jwk = &keys.Keys[index]
			break
		}
	}
	if jwk == nil {
		return errors.New("apple signing key not found")
	}
	digest := sha256.Sum256([]byte(signingInput))
	switch header.Algorithm {
	case "RS256":
		publicKey, err := jwk.rsaPublicKey()
		if err != nil {
			return err
		}
		if err := rsa.VerifyPKCS1v15(publicKey, crypto.SHA256, digest[:], signature); err != nil {
			return errors.New("invalid apple identity token signature")
		}
	case "ES256":
		publicKey, err := jwk.ecdsaPublicKey()
		if err != nil {
			return err
		}
		if len(signature) != 64 {
			return errors.New("invalid apple identity token signature")
		}
		r := new(big.Int).SetBytes(signature[:32])
		ss := new(big.Int).SetBytes(signature[32:])
		if !ecdsa.Verify(publicKey, digest[:], r, ss) {
			return errors.New("invalid apple identity token signature")
		}
	default:
		return errors.New("unsupported apple token algorithm")
	}
	return nil
}

func (s *Service) applePublicKeys(ctx context.Context) (appleKeySet, error) {
	s.appleKeysMu.Lock()
	if len(s.appleKeys.Keys) > 0 && s.now().Before(s.appleKeysAt.Add(6*time.Hour)) {
		keys := s.appleKeys
		s.appleKeysMu.Unlock()
		return keys, nil
	}
	s.appleKeysMu.Unlock()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, s.appleJWKSURL, nil)
	if err != nil {
		return appleKeySet{}, err
	}
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return appleKeySet{}, fmt.Errorf("fetch apple public keys: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return appleKeySet{}, fmt.Errorf("fetch apple public keys: status %d", resp.StatusCode)
	}
	var keys appleKeySet
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&keys); err != nil {
		return appleKeySet{}, fmt.Errorf("decode apple public keys: %w", err)
	}
	if len(keys.Keys) == 0 {
		return appleKeySet{}, errors.New("apple public keys response is empty")
	}

	s.appleKeysMu.Lock()
	s.appleKeys = keys
	s.appleKeysAt = s.now()
	s.appleKeysMu.Unlock()
	return keys, nil
}

func (s *Service) exchangeAppleCode(ctx context.Context, code string, clientID string, redirectURI string) (appleTokenResponse, error) {
	clientSecret, err := s.appleClientSecret(clientID)
	if err != nil {
		return appleTokenResponse{}, err
	}
	form := url.Values{
		"client_id":     {clientID},
		"client_secret": {clientSecret},
		"code":          {code},
		"grant_type":    {"authorization_code"},
	}
	if strings.TrimSpace(redirectURI) != "" {
		form.Set("redirect_uri", redirectURI)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, appleTokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return appleTokenResponse{}, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return appleTokenResponse{}, fmt.Errorf("exchange apple authorization code: %w", err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return appleTokenResponse{}, err
	}
	var tokenResponse appleTokenResponse
	if err := json.Unmarshal(data, &tokenResponse); err != nil {
		return appleTokenResponse{}, fmt.Errorf("decode apple token response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		if tokenResponse.ErrorDesc != "" {
			return appleTokenResponse{}, errors.New(tokenResponse.ErrorDesc)
		}
		if tokenResponse.Error != "" {
			return appleTokenResponse{}, errors.New(tokenResponse.Error)
		}
		return appleTokenResponse{}, fmt.Errorf("apple token endpoint status %d", resp.StatusCode)
	}
	return tokenResponse, nil
}

func (s *Service) appleClientSecret(clientID string) (string, error) {
	if strings.TrimSpace(s.cfg.Apple.TeamID) == "" ||
		strings.TrimSpace(s.cfg.Apple.KeyID) == "" ||
		strings.TrimSpace(s.cfg.Apple.PrivateKey) == "" {
		return "", errors.New("apple client secret is not configured")
	}
	privateKey, err := parseApplePrivateKey(s.cfg.Apple.PrivateKey)
	if err != nil {
		return "", err
	}
	now := s.now()
	header := map[string]string{
		"alg": "ES256",
		"kid": s.cfg.Apple.KeyID,
	}
	claims := map[string]any{
		"iss": s.cfg.Apple.TeamID,
		"iat": now.Unix(),
		"exp": now.Add(180 * 24 * time.Hour).Unix(),
		"aud": appleIssuer,
		"sub": clientID,
	}
	headerJSON, _ := json.Marshal(header)
	claimsJSON, _ := json.Marshal(claims)
	signingInput := base64.RawURLEncoding.EncodeToString(headerJSON) + "." + base64.RawURLEncoding.EncodeToString(claimsJSON)
	digest := sha256.Sum256([]byte(signingInput))
	r, ss, err := ecdsa.Sign(rand.Reader, privateKey, digest[:])
	if err != nil {
		return "", err
	}
	signature := make([]byte, 64)
	r.FillBytes(signature[:32])
	ss.FillBytes(signature[32:])
	return signingInput + "." + base64.RawURLEncoding.EncodeToString(signature), nil
}

func (s *Service) storeAppleProviderTokens(ctx context.Context, tx txSessionWriter, userID string, appleSub string, clientID string, tokenResponse appleTokenResponse) error {
	if tokenResponse.RefreshToken == "" && tokenResponse.AccessToken == "" {
		return nil
	}
	refreshCiphertext, err := s.encryptToken(tokenResponse.RefreshToken)
	if err != nil {
		return err
	}
	accessCiphertext, err := s.encryptToken(tokenResponse.AccessToken)
	if err != nil {
		return err
	}
	var expiresAt any
	if tokenResponse.ExpiresIn > 0 {
		expiresAt = s.now().Add(time.Duration(tokenResponse.ExpiresIn) * time.Second)
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO auth_provider_tokens (
			id, user_id, provider, provider_user_id, client_id,
			refresh_token_ciphertext, access_token_ciphertext, expires_at, revoked_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULL, now())
		ON CONFLICT (provider, provider_user_id, client_id) DO UPDATE
		SET user_id = EXCLUDED.user_id,
		    refresh_token_ciphertext = COALESCE(EXCLUDED.refresh_token_ciphertext, auth_provider_tokens.refresh_token_ciphertext),
		    access_token_ciphertext = COALESCE(EXCLUDED.access_token_ciphertext, auth_provider_tokens.access_token_ciphertext),
		    expires_at = EXCLUDED.expires_at,
		    revoked_at = NULL,
		    updated_at = now()
	`, uuid.NewString(), userID, AppleProvider, appleSub, clientID, nullableText(refreshCiphertext), nullableText(accessCiphertext), expiresAt)
	return err
}

func (s *Service) encryptToken(token string) (string, error) {
	if token == "" {
		return "", nil
	}
	key := sha256.Sum256([]byte(s.cfg.TokenSecret + ":provider-token"))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return "", err
	}
	ciphertext := gcm.Seal(nil, nonce, []byte(token), nil)
	return base64.RawURLEncoding.EncodeToString(append(nonce, ciphertext...)), nil
}

func (s *Service) appleTokenExchangeConfigured() bool {
	return strings.TrimSpace(s.cfg.Apple.TeamID) != "" &&
		strings.TrimSpace(s.cfg.Apple.KeyID) != "" &&
		strings.TrimSpace(s.cfg.Apple.PrivateKey) != ""
}

func (j appleJWK) rsaPublicKey() (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(j.N)
	if err != nil {
		return nil, err
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(j.E)
	if err != nil {
		return nil, err
	}
	e := 0
	for _, b := range eBytes {
		e = e<<8 + int(b)
	}
	if e == 0 {
		return nil, errors.New("invalid apple rsa exponent")
	}
	return &rsa.PublicKey{N: new(big.Int).SetBytes(nBytes), E: e}, nil
}

func (j appleJWK) ecdsaPublicKey() (*ecdsa.PublicKey, error) {
	if j.Curve != "P-256" {
		return nil, errors.New("unsupported apple ecdsa curve")
	}
	xBytes, err := base64.RawURLEncoding.DecodeString(j.X)
	if err != nil {
		return nil, err
	}
	yBytes, err := base64.RawURLEncoding.DecodeString(j.Y)
	if err != nil {
		return nil, err
	}
	return &ecdsa.PublicKey{
		Curve: elliptic.P256(),
		X:     new(big.Int).SetBytes(xBytes),
		Y:     new(big.Int).SetBytes(yBytes),
	}, nil
}

func parseApplePrivateKey(value string) (*ecdsa.PrivateKey, error) {
	value = strings.TrimSpace(value)
	value = strings.ReplaceAll(value, `\n`, "\n")
	block, _ := pem.Decode([]byte(value))
	if block == nil {
		return nil, errors.New("invalid apple private key pem")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	privateKey, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, errors.New("apple private key must be ECDSA")
	}
	return privateKey, nil
}

func applePlaceholderEmail(sub string) string {
	sum := sha256.Sum256([]byte(sub))
	return "apple-" + hex.EncodeToString(sum[:8]) + "@apple.cardly.local"
}

func nullableText(value string) any {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	return value
}
