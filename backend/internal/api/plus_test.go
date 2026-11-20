package api

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

const otherUser = "0b8f3a3e-2c1d-4e5f-8a9b-0c1d2e3f4a5b"

func TestAccountTag(t *testing.T) {
	// Same vector as app/test/billing_test.dart.
	if got := AccountTag(strings.ToUpper(uid)); got != "ff5d845404b541036a69263de085205eec5ba006fa5e3b083479cae0671b7544" {
		t.Fatal(got)
	}
}

func serviceAccountJSON(t *testing.T, tokenURI string) (string, *rsa.PrivateKey) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, _ := x509.MarshalPKCS8PrivateKey(key)
	raw, _ := json.Marshal(map[string]string{
		"type": "service_account", "client_email": "ninho@exemplo.iam.gserviceaccount.com", "token_uri": tokenURI,
		"private_key": string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})),
	})
	return string(raw), key
}

func TestPlusGooglePlay(t *testing.T) {
	var mu sync.Mutex
	var recorded []map[string]any
	tokens := 0
	purchases := map[string]string{
		"token-bought-1": `{"purchaseState":0,"orderId":"GPA.1111","obfuscatedExternalAccountId":"` + AccountTag(uid) + `"}`,
		"token-pending1": `{"purchaseState":2,"orderId":"GPA.2222","obfuscatedExternalAccountId":"` + AccountTag(uid) + `"}`,
		"token-others-1": `{"purchaseState":0,"orderId":"GPA.3333","obfuscatedExternalAccountId":"` + AccountTag(otherUser) + `"}`,
		"token-no-tag-1": `{"purchaseState":0,"orderId":"GPA.4444"}`,
		"token-taken--1": `{"purchaseState":0,"orderId":"GPA.5555","obfuscatedExternalAccountId":"` + AccountTag(uid) + `"}`,
	}
	var key *rsa.PrivateKey
	google := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/token" {
			_ = r.ParseForm()
			parts := strings.Split(r.Form.Get("assertion"), ".")
			sig, _ := base64.RawURLEncoding.DecodeString(parts[2])
			digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
			if len(parts) != 3 || rsa.VerifyPKCS1v15(&key.PublicKey, crypto.SHA256, digest[:], sig) != nil {
				t.Error("the token request must carry a JWT signed with the service account's key")
			}
			claims, _ := base64.RawURLEncoding.DecodeString(parts[1])
			if !strings.Contains(string(claims), "androidpublisher") {
				t.Errorf("claims: %s", claims)
			}
			mu.Lock()
			tokens++
			mu.Unlock()
			_, _ = w.Write([]byte(`{"access_token":"google-access","expires_in":3600}`))
			return
		}
		if r.Header.Get("Authorization") != "Bearer google-access" {
			t.Error("Google Play calls must use the access token")
		}
		const prefix = "/androidpublisher/v3/applications/br.com.ninho.app/purchases/"
		switch path := strings.TrimPrefix(r.URL.Path, prefix); {
		case strings.HasPrefix(path, "products/ninho_plus/tokens/"):
			body, ok := purchases[strings.TrimPrefix(path, "products/ninho_plus/tokens/")]
			if !ok {
				w.WriteHeader(404)
				return
			}
			_, _ = w.Write([]byte(body))
		case path == "voidedpurchases":
			if r.URL.Query().Get("token") == "" {
				_, _ = w.Write([]byte(`{"voidedPurchases":[{"purchaseToken":"token-bought-1","orderId":"GPA.1111"}],"tokenPagination":{"nextPageToken":"page2"}}`))
				return
			}
			_, _ = w.Write([]byte(`{"voidedPurchases":[{"purchaseToken":"token-unknown1"},{"purchaseToken":"bad token"}]}`))
		default:
			t.Errorf("unexpected Google call %s", r.URL.Path)
		}
	}))
	defer google.Close()
	account, k := serviceAccountJSON(t, google.URL+"/token")
	key = k
	db := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/auth/v1/user":
			_, _ = w.Write([]byte(`{"id":"` + uid + `"}`))
		case "/rest/v1/rpc/record_plus_purchase":
			if r.Header.Get("Authorization") != "Bearer secret-key" {
				t.Error("purchases must be recorded with the secret key")
			}
			var args map[string]any
			_ = json.NewDecoder(r.Body).Decode(&args)
			mu.Lock()
			recorded = append(recorded, args)
			mu.Unlock()
			if args["p_token"] == "token-taken--1" {
				w.WriteHeader(400)
				_, _ = w.Write([]byte(`{"code":"P0001","message":"Purchase mismatch"}`))
				return
			}
			_, _ = w.Write([]byte(`true`))
		default:
			t.Errorf("unexpected database call %s", r.URL.Path)
		}
	}))
	defer db.Close()
	cfg := Config{SupabaseURL: db.URL, PublishableKey: "public-key", SecretKey: "secret-key", Origins: []string{"https://ninho.example"},
		PlayServiceAccount: account, PlayPackage: "br.com.ninho.app", GooglePlayURL: google.URL}
	if err := cfg.Validate(); err != nil {
		t.Fatal(err)
	}
	h := New(cfg)
	send := func(body string, auth bool) *httptest.ResponseRecorder {
		r := httptest.NewRequest("POST", "/v1/plus/google", strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		if auth {
			r.Header.Set("Authorization", "Bearer valid-user-token")
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	buy := func(token string) *httptest.ResponseRecorder {
		return send(`{"product_id":"ninho_plus","purchase_token":"`+token+`"}`, true)
	}

	if w := send(`{"product_id":"ninho_plus","purchase_token":"token-bought-1"}`, false); w.Code != 401 {
		t.Fatalf("without a session: %d", w.Code)
	}
	w := buy("token-bought-1")
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"plus":true`) || !strings.Contains(w.Body.String(), `"state":"purchased"`) {
		t.Fatalf("purchase: %d %s", w.Code, w.Body)
	}
	if last := recorded[len(recorded)-1]; last["p_user_id"] != uid || last["p_state"] != "purchased" || last["p_order_id"] != "GPA.1111" || last["p_product_id"] != "ninho_plus" {
		t.Fatalf("recorded: %v", last)
	}
	if w := buy("token-pending1"); w.Code != 200 || recorded[len(recorded)-1]["p_state"] != "pending" {
		t.Fatalf("pending: %d %s", w.Code, w.Body)
	}
	before := len(recorded)
	for token, want := range map[string]int{"token-others-1": 404, "token-no-tag-1": 404, "token-missing1": 404, "token-taken--1": 404} {
		if w := buy(token); w.Code != want {
			t.Errorf("%s: %d %s", token, w.Code, w.Body)
		}
	}
	if len(recorded) != before+1 {
		t.Fatalf("only the purchase made for this account reaches the database: %d", len(recorded)-before)
	}
	for _, body := range []string{`{"product_id":"other","purchase_token":"token-bought-1"}`, `{"product_id":"ninho_plus","purchase_token":"a b"}`, `{"product_id":"ninho_plus","purchase_token":"token-bought-1","user":"x"}`} {
		if w := send(body, true); w.Code != 400 {
			t.Errorf("%s: %d", body, w.Code)
		}
	}
	if tokens != 1 {
		t.Fatalf("the access token is reused until it expires: %d requests", tokens)
	}

	// The daily check takes Plus back from voided purchases, across pages, keeping the purchase's own account.
	s := &Server{cfg: cfg, client: http.DefaultClient, limits: map[string]quota{}}
	s.play, _ = parseServiceAccount(account)
	before = len(recorded)
	n, err := s.syncVoided(context.Background())
	if err != nil || n != 2 || len(recorded) != before+2 {
		t.Fatalf("voided: %d %v %d", n, err, len(recorded)-before)
	}
	if v := recorded[before]; v["p_user_id"] != nil || v["p_state"] != "voided" || v["p_token"] != "token-bought-1" {
		t.Fatalf("voided record: %v", v)
	}

	cfg.PlayServiceAccount = ""
	off := New(cfg)
	r := httptest.NewRequest("POST", "/v1/plus/google", strings.NewReader(`{"product_id":"ninho_plus","purchase_token":"token-bought-1"}`))
	r.Header.Set("Authorization", "Bearer valid-user-token")
	r.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	off.ServeHTTP(rec, r)
	if rec.Code != 503 {
		t.Fatalf("without a service account: %d", rec.Code)
	}
}

func TestPlusConfig(t *testing.T) {
	account, _ := serviceAccountJSON(t, "")
	base := Config{SupabaseURL: "https://x.supabase.co", PublishableKey: "sb_publishable_x", SecretKey: "sb_secret_x", Origins: []string{"https://ninho.example"},
		PlayServiceAccount: account, PlayPackage: "br.com.ninho.app"}
	if err := base.Validate(); err != nil {
		t.Fatal(err)
	}
	for name, change := range map[string]func(*Config){
		"no package":      func(c *Config) { c.PlayPackage = "" },
		"bad package":     func(c *Config) { c.PlayPackage = "ninho" },
		"not JSON":        func(c *Config) { c.PlayServiceAccount = "abc" },
		"bad key":         func(c *Config) { c.PlayServiceAccount = `{"client_email":"a@b","private_key":"x"}` },
		"no secret key":   func(c *Config) { c.SecretKey = "" },
		"no client email": func(c *Config) { c.PlayServiceAccount = strings.Replace(account, "client_email", "email", 1) },
	} {
		c := base
		change(&c)
		if c.Validate() == nil {
			t.Errorf("%s: accepted", name)
		}
	}
}
