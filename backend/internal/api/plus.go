package api

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Ninho Plus is bought once per account in the Android app, with Google Play Billing. The app sends the purchase
// token here; the API reads the purchase from the Google Play Developer API with a service account, checks that
// it was made for the signed-in account, and records it. Once a day, with the price check, it reads Google's
// voided purchases and takes Plus back from refunded ones.

// PlusProduct is the id of the one-time product in the Play Console.
const PlusProduct = "ninho_plus"

var purchaseToken = regexp.MustCompile(`^[A-Za-z0-9._-]{10,1000}$`)

// AccountTag is what the app sends to Google Play as the obfuscated account id: a hash of the user id, so the
// purchase is tied to the Ninho account that made it without giving Google the id itself.
func AccountTag(user string) string {
	sum := sha256.Sum256([]byte("ninho-plus:" + strings.ToLower(user)))
	return hex.EncodeToString(sum[:])
}

type serviceAccount struct {
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
	TokenURI    string `json:"token_uri"`
	key         *rsa.PrivateKey
}

// parseServiceAccount reads the JSON key of a Google Cloud service account, as downloaded from the console.
func parseServiceAccount(raw string) (*serviceAccount, error) {
	var a serviceAccount
	if err := json.Unmarshal([]byte(raw), &a); err != nil || a.ClientEmail == "" || a.PrivateKey == "" {
		return nil, errors.New("GOOGLE_PLAY_SERVICE_ACCOUNT must be the service account's JSON key")
	}
	if a.TokenURI == "" {
		a.TokenURI = "https://oauth2.googleapis.com/token"
	}
	block, _ := pem.Decode([]byte(a.PrivateKey))
	if block == nil {
		return nil, errors.New("the service account's private key is invalid")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		parsed, err = x509.ParsePKCS1PrivateKey(block.Bytes)
	}
	key, ok := parsed.(*rsa.PrivateKey)
	if err != nil || !ok {
		return nil, errors.New("the service account's private key is invalid")
	}
	a.key = key
	return &a, nil
}

// googleToken returns an access token for the Android Publisher API, reusing it until a minute before it expires.
func (s *Server) googleToken(ctx context.Context) (string, error) {
	s.mu.Lock()
	if s.playToken != "" && time.Now().Before(s.playTokenUntil) {
		t := s.playToken
		s.mu.Unlock()
		return t, nil
	}
	s.mu.Unlock()
	a := s.play
	now := time.Now()
	enc := base64.RawURLEncoding
	header := enc.EncodeToString([]byte(`{"alg":"RS256","typ":"JWT"}`))
	claims, _ := json.Marshal(map[string]any{
		"iss": a.ClientEmail, "scope": "https://www.googleapis.com/auth/androidpublisher", "aud": a.TokenURI,
		"iat": now.Unix(), "exp": now.Add(time.Hour).Unix(),
	})
	unsigned := header + "." + enc.EncodeToString(claims)
	digest := sha256.Sum256([]byte(unsigned))
	sig, err := rsa.SignPKCS1v15(nil, a.key, crypto.SHA256, digest[:])
	if err != nil {
		return "", err
	}
	form := url.Values{"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"}, "assertion": {unsigned + "." + enc.EncodeToString(sig)}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, a.TokenURI, strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, err := s.client.Do(req)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	var out struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int64  `json:"expires_in"`
	}
	if res.StatusCode != 200 || json.NewDecoder(io.LimitReader(res.Body, 65536)).Decode(&out) != nil || out.AccessToken == "" {
		slog.Error("google token refused", "status", res.StatusCode)
		return "", errors.New("google token refused")
	}
	s.mu.Lock()
	s.playToken, s.playTokenUntil = out.AccessToken, now.Add(time.Duration(max(out.ExpiresIn-60, 0))*time.Second)
	s.mu.Unlock()
	return out.AccessToken, nil
}

// googlePlay calls the Android Publisher API for this app's package.
func (s *Server) googlePlay(ctx context.Context, path string) (int, []byte, error) {
	token, err := s.googleToken(ctx)
	if err != nil {
		return 0, nil, err
	}
	base := strings.TrimRight(s.cfg.GooglePlayURL, "/")
	if base == "" {
		base = "https://androidpublisher.googleapis.com"
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base+"/androidpublisher/v3/applications/"+url.PathEscape(s.cfg.PlayPackage)+path, nil)
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	res, err := s.client.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer res.Body.Close()
	body, err := io.ReadAll(io.LimitReader(res.Body, 4<<20))
	return res.StatusCode, body, err
}

type playRequest struct {
	ProductID     string `json:"product_id"`
	PurchaseToken string `json:"purchase_token"`
}

// plusGoogle answers POST /v1/plus/google with a purchase the app got from Google Play. It answers whether the
// account has Plus now and the purchase's state; the app finishes (acknowledges) the purchase only after a
// "purchased" answer, so Google refunds a purchase the server never recorded.
func (s *Server) plusGoogle(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		fail(w, 405, "Use POST")
		return
	}
	if s.play == nil || s.cfg.SecretKey == "" {
		fail(w, 503, "A compra do Plus ainda não está disponível")
		return
	}
	user, _ := r.Context().Value(userKey{}).(string)
	if !uuid.MatchString(user) {
		fail(w, 401, "Sessão inválida")
		return
	}
	if !s.allowN("plus:"+user, 10) {
		w.Header().Set("Retry-After", "60")
		fail(w, 429, "Muitas tentativas. Tente novamente em um minuto")
		return
	}
	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		fail(w, 400, "Envie JSON")
		return
	}
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	dec.DisallowUnknownFields()
	var p playRequest
	if dec.Decode(&p) != nil || p.ProductID != PlusProduct || !purchaseToken.MatchString(p.PurchaseToken) {
		fail(w, 400, "Compra inválida")
		return
	}
	status, body, err := s.googlePlay(r.Context(), "/purchases/products/"+PlusProduct+"/tokens/"+url.PathEscape(p.PurchaseToken))
	if err != nil || status >= 500 || status == 429 {
		fail(w, 503, "Não foi possível conferir a compra agora. Tente novamente")
		return
	}
	if status == 400 || status == 404 || status == 410 {
		fail(w, 404, "Compra não encontrada")
		return
	}
	if status != 200 {
		slog.Error("google play purchase lookup failed", "status", status)
		fail(w, 503, "Não foi possível conferir a compra agora. Tente novamente")
		return
	}
	var purchase struct {
		PurchaseState *int   `json:"purchaseState"`
		OrderID       string `json:"orderId"`
		Account       string `json:"obfuscatedExternalAccountId"`
	}
	if json.Unmarshal(body, &purchase) != nil || purchase.PurchaseState == nil {
		fail(w, 503, "Não foi possível conferir a compra agora. Tente novamente")
		return
	}
	// A purchase made by another Ninho account on the same Google account stays with that account.
	if purchase.Account != AccountTag(user) {
		fail(w, 404, "Esta compra é de outra conta do Ninho")
		return
	}
	state := map[int]string{0: "purchased", 1: "canceled", 2: "pending"}[*purchase.PurchaseState]
	if state == "" {
		fail(w, 503, "Não foi possível conferir a compra agora. Tente novamente")
		return
	}
	plus, code, err := s.recordPurchase(r.Context(), p.PurchaseToken, purchase.OrderID, user, state)
	if err != nil {
		fail(w, 503, "Não foi possível registrar a compra agora. Tente novamente")
		return
	}
	if code == 409 {
		fail(w, 404, "Esta compra é de outra conta do Ninho")
		return
	}
	if state == "purchased" {
		slog.Info("plus purchased", "order", purchase.OrderID)
	}
	send(w, 200, map[string]any{"plus": plus, "state": state})
}

// recordPurchase stores a purchase's state; an empty user keeps the purchase's own account. It answers whether
// that account has Plus, with 409 for a purchase that belongs to another account.
func (s *Server) recordPurchase(ctx context.Context, token, order, user, state string) (bool, int, error) {
	var account any
	if user != "" {
		account = strings.ToLower(user)
	}
	if len(order) > 200 {
		order = order[:200]
	}
	status, body, err := s.adminRPC(ctx, "record_plus_purchase", map[string]any{
		"p_token": token, "p_order_id": order, "p_product_id": PlusProduct, "p_user_id": account, "p_state": state,
	})
	if err != nil || status >= 500 {
		return false, 0, errors.New("database unavailable")
	}
	if status >= 400 {
		var upstream struct{ Code, Message string }
		_ = json.Unmarshal(body, &upstream)
		if upstream.Code == "P0001" && upstream.Message == "Purchase mismatch" {
			return false, 409, nil
		}
		return false, 0, errors.New("purchase not recorded")
	}
	var plus bool
	if json.Unmarshal(body, &plus) != nil {
		return false, 0, errors.New("unexpected database answer")
	}
	return plus, 200, nil
}

// syncVoided reads the purchases Google voided in the last 30 days (refunds, chargebacks, cancellations) and
// takes Plus back from each one recorded here. Voided purchases this database never saw change nothing.
func (s *Server) syncVoided(ctx context.Context) (int, error) {
	start := strconv.FormatInt(time.Now().Add(-30*24*time.Hour).UnixMilli(), 10)
	next, voided := "", 0
	for range 50 {
		q := url.Values{"startTime": {start}, "maxResults": {"1000"}}
		if next != "" {
			q.Set("token", next)
		}
		status, body, err := s.googlePlay(ctx, "/purchases/voidedpurchases?"+q.Encode())
		if err != nil || status != 200 {
			return voided, errors.New("voided purchases unavailable")
		}
		var page struct {
			VoidedPurchases []struct {
				PurchaseToken string `json:"purchaseToken"`
				OrderID       string `json:"orderId"`
			} `json:"voidedPurchases"`
			TokenPagination struct {
				NextPageToken string `json:"nextPageToken"`
			} `json:"tokenPagination"`
		}
		if err := json.NewDecoder(bytes.NewReader(body)).Decode(&page); err != nil {
			return voided, err
		}
		for _, v := range page.VoidedPurchases {
			if !purchaseToken.MatchString(v.PurchaseToken) {
				continue
			}
			if _, _, err := s.recordPurchase(ctx, v.PurchaseToken, v.OrderID, "", "voided"); err != nil {
				return voided, err
			}
			voided++
		}
		next = page.TokenPagination.NextPageToken
		if next == "" {
			break
		}
	}
	return voided, nil
}
