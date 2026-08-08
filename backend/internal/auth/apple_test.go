package auth

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"testing"
	"time"
)

func TestVerifyAppleIDToken(t *testing.T) {
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	keyID := "apple-test-key"
	keys := appleKeySet{Keys: []appleJWK{{
		KeyID:     keyID,
		Algorithm: "RS256",
		KeyType:   "RSA",
		Use:       "sig",
		N:         base64.RawURLEncoding.EncodeToString(privateKey.PublicKey.N.Bytes()),
		E:         base64.RawURLEncoding.EncodeToString([]byte{0x01, 0x00, 0x01}),
	}}}

	now := time.Unix(1786150000, 0)
	service := &Service{
		now:         func() time.Time { return now },
		appleKeys:   keys,
		appleKeysAt: now,
	}
	nonce := "raw-nonce"
	nonceHash := sha256.Sum256([]byte(nonce))
	token := signTestAppleIDToken(t, privateKey, keyID, map[string]any{
		"iss":            appleIssuer,
		"sub":            "apple-user-123",
		"aud":            "com.siyuancheng.MemoryApp",
		"exp":            now.Add(time.Hour).Unix(),
		"iat":            now.Unix(),
		"nonce":          hex.EncodeToString(nonceHash[:]),
		"email":          "user@example.com",
		"email_verified": "true",
	})

	identity, err := service.verifyAppleIDToken(context.Background(), token, "com.siyuancheng.MemoryApp", nonce)
	if err != nil {
		t.Fatalf("verify token: %v", err)
	}
	if identity.Subject != "apple-user-123" || identity.Email != "user@example.com" || !identity.EmailVerified {
		t.Fatalf("unexpected identity: %+v", identity)
	}

	if _, err := service.verifyAppleIDToken(context.Background(), token, "wrong-audience", nonce); err == nil {
		t.Fatal("wrong audience verified")
	}
	if _, err := service.verifyAppleIDToken(context.Background(), token, "com.siyuancheng.MemoryApp", "wrong-nonce"); err == nil {
		t.Fatal("wrong nonce verified")
	}
}

func signTestAppleIDToken(t *testing.T, privateKey *rsa.PrivateKey, keyID string, claims map[string]any) string {
	t.Helper()
	header := map[string]string{"alg": "RS256", "kid": keyID}
	headerJSON, err := json.Marshal(header)
	if err != nil {
		t.Fatalf("marshal header: %v", err)
	}
	claimsJSON, err := json.Marshal(claims)
	if err != nil {
		t.Fatalf("marshal claims: %v", err)
	}
	signingInput := base64.RawURLEncoding.EncodeToString(headerJSON) + "." + base64.RawURLEncoding.EncodeToString(claimsJSON)
	digest := sha256.Sum256([]byte(signingInput))
	signature, err := rsa.SignPKCS1v15(rand.Reader, privateKey, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}
	return signingInput + "." + base64.RawURLEncoding.EncodeToString(signature)
}
