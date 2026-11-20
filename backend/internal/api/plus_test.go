package api

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

const otherUser = "0b8f3a3e-2c1d-4e5f-8a9b-0c1d2e3f4a5b"

func TestPlusPurchase(t *testing.T) {
	var mu sync.Mutex
	owned := false
	var preference map[string]any
	var recorded []map[string]any
	payments := map[string]string{
		"111": `{"id":111,"status":"approved","transaction_amount":10,"currency_id":"BRL","external_reference":"ninho-plus:` + uid + `"}`,
		"222": `{"id":222,"status":"approved","transaction_amount":1,"currency_id":"BRL","external_reference":"ninho-plus:` + uid + `"}`,
		"333": `{"id":333,"status":"approved","transaction_amount":10,"currency_id":"BRL","external_reference":"ninho-plus:` + otherUser + `"}`,
		"444": `{"id":444,"status":"approved","transaction_amount":10,"currency_id":"BRL","external_reference":"pedido-77"}`,
		"555": `{"id":555,"status":"pending","transaction_amount":10.00,"currency_id":"BRL","external_reference":"ninho-plus:` + uid + `"}`,
	}
	mp := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer APP_USR-token" {
			t.Error("Mercado Pago calls must use the access token")
		}
		switch {
		case r.Method == "POST" && r.URL.Path == "/checkout/preferences":
			mu.Lock()
			_ = json.NewDecoder(r.Body).Decode(&preference)
			mu.Unlock()
			w.WriteHeader(201)
			_, _ = w.Write([]byte(`{"id":"pref-1","init_point":"https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=pref-1"}`))
		case r.Method == "GET" && strings.HasPrefix(r.URL.Path, "/v1/payments/"):
			body, ok := payments[strings.TrimPrefix(r.URL.Path, "/v1/payments/")]
			if !ok {
				w.WriteHeader(404)
				return
			}
			_, _ = w.Write([]byte(body))
		default:
			t.Errorf("unexpected Mercado Pago call %s %s", r.Method, r.URL.Path)
		}
	}))
	defer mp.Close()
	db := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/auth/v1/user":
			_, _ = w.Write([]byte(`{"id":"` + uid + `"}`))
		case "/rest/v1/plus_accounts":
			if r.Header.Get("Authorization") != "Bearer valid-user-token" {
				t.Error("the Plus lookup must use the user's session")
			}
			mu.Lock()
			defer mu.Unlock()
			if owned {
				_, _ = w.Write([]byte(`[{"user_id":"` + uid + `"}]`))
				return
			}
			_, _ = w.Write([]byte(`[]`))
		case "/rest/v1/rpc/record_plus_payment":
			if r.Header.Get("Authorization") != "Bearer secret-key" {
				t.Error("payments must be recorded with the secret key")
			}
			var args map[string]any
			_ = json.NewDecoder(r.Body).Decode(&args)
			mu.Lock()
			recorded = append(recorded, args)
			mu.Unlock()
			_, _ = w.Write([]byte(`true`))
		default:
			t.Errorf("unexpected database call %s", r.URL.Path)
		}
	}))
	defer db.Close()
	cfg := Config{SupabaseURL: db.URL, PublishableKey: "public-key", SecretKey: "secret-key", Origins: []string{"https://ninho.example"},
		MercadoPagoToken: "APP_USR-token", MercadoPagoWebhookSecret: "webhook-secret", MercadoPagoURL: mp.URL, AppURL: "https://ninho.example"}
	h := New(cfg)
	call := func(method, path, body string, headers map[string]string) *httptest.ResponseRecorder {
		var reader io.Reader
		if body != "" {
			reader = strings.NewReader(body)
		}
		r := httptest.NewRequest(method, path, reader)
		r.Header.Set("Content-Type", "application/json")
		for k, v := range headers {
			r.Header.Set(k, v)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	user := map[string]string{"Authorization": "Bearer valid-user-token", "Origin": "https://ninho.example"}

	if w := call("POST", "/v1/plus/checkout", "", nil); w.Code != 401 {
		t.Fatalf("checkout without a session: %d", w.Code)
	}
	w := call("POST", "/v1/plus/checkout", "", user)
	if w.Code != 201 || !strings.Contains(w.Body.String(), "https://www.mercadopago.com.br/checkout") {
		t.Fatalf("checkout: %d %s", w.Code, w.Body)
	}
	items := preference["items"].([]any)[0].(map[string]any)
	if preference["external_reference"] != "ninho-plus:"+uid || items["unit_price"] != float64(10) || items["currency_id"] != "BRL" {
		t.Fatalf("preference: %v", preference)
	}
	if back := preference["back_urls"].(map[string]any)["success"]; back != "https://ninho.example/app/?plus=retorno" {
		t.Fatalf("back url: %v", back)
	}

	// The browser comes back with the payment id: only the buyer's own approved payment grants Plus.
	confirm := func(id string) *httptest.ResponseRecorder {
		return call("POST", "/v1/plus/confirm", `{"payment_id":"`+id+`"}`, user)
	}
	if w := confirm("111"); w.Code != 200 || !strings.Contains(w.Body.String(), `"plus":true`) {
		t.Fatalf("confirm: %d %s", w.Code, w.Body)
	}
	if last := recorded[len(recorded)-1]; last["p_paid"] != true || last["p_user_id"] != uid || last["p_amount_cents"] != float64(1000) {
		t.Fatalf("recorded: %v", last)
	}
	if w := confirm("222"); w.Code != 200 || recorded[len(recorded)-1]["p_paid"] != false {
		t.Fatalf("an underpaid payment must not grant Plus: %d %v", w.Code, recorded[len(recorded)-1])
	}
	if w := confirm("555"); w.Code != 200 || recorded[len(recorded)-1]["p_paid"] != false || !strings.Contains(w.Body.String(), "pending") {
		t.Fatalf("a pending payment: %d %s", w.Code, w.Body)
	}
	for _, id := range []string{"333", "444", "999"} {
		if w := confirm(id); w.Code != 404 {
			t.Errorf("payment %s: %d %s", id, w.Code, w.Body)
		}
	}
	if w := call("POST", "/v1/plus/confirm", `{"payment_id":"1 OR 1=1"}`, user); w.Code != 400 {
		t.Fatalf("invalid id: %d", w.Code)
	}
	mu.Lock()
	owned = true
	mu.Unlock()
	if w := call("POST", "/v1/plus/checkout", "", user); w.Code != 409 {
		t.Fatalf("checkout with Plus already: %d", w.Code)
	}

	// The webhook needs Mercado Pago's signature, and records the payment it names.
	sign := func(id, request, ts, secret string) string {
		mac := hmac.New(sha256.New, []byte(secret))
		mac.Write([]byte("id:" + id + ";request-id:" + request + ";ts:" + ts + ";"))
		return "ts=" + ts + ",v1=" + hex.EncodeToString(mac.Sum(nil))
	}
	notice := `{"action":"payment.updated","type":"payment","data":{"id":"111"}}`
	before := len(recorded)
	if w := call("POST", "/webhooks/mercadopago?data.id=111&type=payment", notice, map[string]string{"X-Request-Id": "req-1", "X-Signature": sign("111", "req-1", "1742505638683", "wrong")}); w.Code != 401 {
		t.Fatalf("forged notice: %d", w.Code)
	}
	if w := call("POST", "/webhooks/mercadopago?data.id=111&type=payment", notice, map[string]string{"X-Request-Id": "req-1"}); w.Code != 401 {
		t.Fatalf("unsigned notice: %d", w.Code)
	}
	if len(recorded) != before {
		t.Fatal("a rejected notice must not record anything")
	}
	if w := call("POST", "/webhooks/mercadopago?data.id=111&type=payment", notice, map[string]string{"X-Request-Id": "req-1", "X-Signature": sign("111", "req-1", "1742505638683", "webhook-secret")}); w.Code != 200 || len(recorded) != before+1 {
		t.Fatalf("signed notice: %d %s", w.Code, w.Body)
	}
	if w := call("POST", "/webhooks/mercadopago?data.id=444&type=payment", `{"type":"payment","data":{"id":"444"}}`, map[string]string{"X-Request-Id": "req-2", "X-Signature": sign("444", "req-2", "1", "webhook-secret")}); w.Code != 200 || len(recorded) != before+1 {
		t.Fatalf("another sale of the account is ignored: %d %d", w.Code, len(recorded))
	}
	if w := call("POST", "/webhooks/mercadopago?data.id=9&type=merchant_order", `{}`, nil); w.Code != 200 {
		t.Fatalf("other notices are acknowledged: %d", w.Code)
	}

	// Without the secret, a notice is only a hint: the payment is still read back from Mercado Pago.
	cfg.MercadoPagoWebhookSecret = ""
	unsigned := New(cfg)
	r := httptest.NewRequest("POST", "/webhooks/mercadopago", strings.NewReader(`{"type":"payment","data":{"id":"111"}}`))
	rec := httptest.NewRecorder()
	unsigned.ServeHTTP(rec, r)
	if rec.Code != 200 || len(recorded) != before+2 {
		t.Fatalf("notice without a secret: %d", rec.Code)
	}

	cfg.MercadoPagoToken = ""
	off := New(cfg)
	r = httptest.NewRequest("POST", "/v1/plus/checkout", nil)
	r.Header.Set("Authorization", "Bearer valid-user-token")
	rec = httptest.NewRecorder()
	off.ServeHTTP(rec, r)
	if rec.Code != 503 {
		t.Fatalf("without a token: %d", rec.Code)
	}
}

func TestPlusConfig(t *testing.T) {
	base := Config{SupabaseURL: "https://x.supabase.co", PublishableKey: "sb_publishable_x", SecretKey: "sb_secret_x", Origins: []string{"https://ninho.example"}}
	ok := base
	ok.MercadoPagoToken, ok.AppURL = "APP_USR-token", "https://ninho.example"
	if err := ok.Validate(); err != nil {
		t.Fatal(err)
	}
	for _, app := range []string{"", "http://ninho.example", "https://ninho.example/app", "ninho.example"} {
		c := ok
		c.AppURL = app
		if c.Validate() == nil {
			t.Errorf("APP_URL %q accepted", app)
		}
	}
	c := ok
	c.SecretKey = ""
	if c.Validate() == nil {
		t.Error("a token without the secret key was accepted")
	}
}
