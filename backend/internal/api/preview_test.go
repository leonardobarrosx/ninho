package api

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"
)

func cents(p *int64) int64 {
	if p == nil {
		return -1
	}
	return *p
}

func TestParsePrice(t *testing.T) {
	for in, want := range map[any]int64{
		"1299.90": 129990, "1.299,90": 129990, "R$ 1.299": 129900, "89,9": 8990, "1299": 129900,
		"1,299.00": 129900, "2.499.999": 249999900, float64(349.9): 34990, json.Number("59.99"): 5999,
	} {
		if got := cents(parsePrice(in)); got != want {
			t.Errorf("parsePrice(%v) = %d, want %d", in, got, want)
		}
	}
	for _, in := range []any{"", "grátis", "0", nil, map[string]any{}} {
		if p := parsePrice(in); p != nil {
			t.Errorf("parsePrice(%v) = %d, want nil", in, *p)
		}
	}
}

func TestParseProductJSONLD(t *testing.T) {
	page, _ := url.Parse("https://www.loja.test/carrinho-x")
	body := `<html><head><title>Ignorado</title>
<meta property="og:site_name" content="Loja Teste">
<meta property="og:image" content="/fallback.jpg">
<script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"BreadcrumbList"},
{"@type":["Product"],"name":"Carrinho X &amp; Bebê Conforto","description":"  Leve,\n dobra com uma mão. ",
"image":["//cdn.loja.test/x.jpg"],"offers":[{"@type":"Offer","price":"1899.90","priceCurrency":"BRL",
"priceSpecification":[{"@type":"UnitPriceSpecification","priceType":"https://schema.org/ListPrice","price":2299.9}]},
{"@type":"Offer","price":"1999.00","priceCurrency":"BRL"}]}]}</script></head></html>`
	p := parseProduct([]byte(body), page)
	if p.Title != "Carrinho X & Bebê Conforto" || p.Description != "Leve, dobra com uma mão." || p.Store != "Loja Teste" {
		t.Fatalf("texts: %+v", p)
	}
	if p.Image != "https://cdn.loja.test/x.jpg" {
		t.Fatalf("image: %q", p.Image)
	}
	if cents(p.PriceCents) != 189990 || cents(p.ListPriceCents) != 229990 {
		t.Fatalf("prices: %d %d", cents(p.PriceCents), cents(p.ListPriceCents))
	}
}

func TestParseProductMetaFallback(t *testing.T) {
	page, _ := url.Parse("http://www.outra.test/p/1")
	body := `<head><title> Body manga longa | Outra </title>
<meta name="description" content="Algodão">
<meta property='product:price:amount' content='49,90'><meta property="product:price:currency" content="BRL">
<meta property="product:original_price:amount" content="39.90">
<meta property="og:image" content="http://img.outra.test/b.png"></head>`
	p := parseProduct([]byte(body), page)
	if p.Title != "Body manga longa | Outra" || p.Description != "Algodão" || p.Store != "outra.test" {
		t.Fatalf("texts: %+v", p)
	}
	// A "list price" below the price is not a discount; HTTP images are upgraded to HTTPS.
	if cents(p.PriceCents) != 4990 || p.ListPriceCents != nil || p.Image != "https://img.outra.test/b.png" {
		t.Fatalf("got %+v", p)
	}
	dollars := parseProduct([]byte(`<meta property="og:title" content="X"><meta property="product:price:amount" content="10"><meta property="product:price:currency" content="USD">`), page)
	if dollars.PriceCents != nil {
		t.Fatal("prices in other currencies are dropped")
	}
}

func TestPageClientRefusesPrivateAddresses(t *testing.T) {
	store := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte("<title>x</title>")) }))
	defer store.Close()
	// httptest listens on 127.0.0.1 with a port, so both the port and the dialer must refuse it.
	if _, err := fetchProduct(context.Background(), pageClient(), store.URL); err == nil {
		t.Fatal("a loopback address with a port must be refused")
	}
	client := pageClient()
	for _, raw := range []string{"http://127.0.0.1/", "http://10.0.0.8/", "http://169.254.169.254/latest/meta-data", "http://100.64.1.1/"} {
		if _, err := client.Get(raw); err == nil || !strings.Contains(err.Error(), "not allowed") {
			t.Errorf("%s: %v", raw, err)
		}
	}
	for _, ip := range []string{"::1", "fe80::1", "fd00::1", "::ffff:127.0.0.1", "0.0.0.0"} {
		if publicIP(net.ParseIP(ip)) {
			t.Errorf("%s must not count as public", ip)
		}
	}
	if !publicIP(net.ParseIP("200.147.67.142")) {
		t.Error("a public address must be allowed")
	}
	for _, raw := range []string{"ftp://loja.test/x", "https://user:pw@loja.test/x", "javascript:alert(1)", "loja.test"} {
		if _, err := fetchProduct(context.Background(), client, raw); err == nil || err.Error() != "invalid link" {
			t.Errorf("%s: %v", raw, err)
		}
	}
}

// storeClient sends every request to the test store, so links can use real-looking hosts without ports.
func storeClient(store *httptest.Server) *http.Client {
	target, _ := url.Parse(store.URL)
	return &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(target)}, Timeout: 5 * time.Second}
}

func TestPreview(t *testing.T) {
	store := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/fora" {
			w.WriteHeader(503)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(`<meta property="og:title" content="Banheira"><meta property="product:price:amount" content="159.90">`))
	}))
	defer store.Close()
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"id":"` + uid + `"}`))
	}))
	defer auth.Close()
	h := New(Config{SupabaseURL: auth.URL, PublishableKey: "public-key", Origins: []string{"https://ninho.example"}, Pages: storeClient(store)})
	call := func(body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(http.MethodPost, "/v1/preview", strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer valid-user-token")
		r.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	w := call(`{"url":"http://loja.test/banheira"}`)
	var p Product
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &p) != nil || p.Title != "Banheira" || cents(p.PriceCents) != 15990 || p.Store != "loja.test" {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	if w := call(`{"url":"http://loja.test/fora"}`); w.Code != 422 {
		t.Fatalf("unreadable page: %d", w.Code)
	}
	if w := call(`{"url":"file:///etc/passwd"}`); w.Code != 400 {
		t.Fatalf("invalid link: %d", w.Code)
	}
	if w := call(`{"url":"https://loja.test/x","extra":1}`); w.Code != 400 {
		t.Fatalf("extra field: %d", w.Code)
	}
	r := httptest.NewRequest(http.MethodPost, "/v1/preview", strings.NewReader(`{"url":"https://loja.test/x"}`))
	r.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	if rec.Code != 401 {
		t.Fatalf("previews need a session: %d", rec.Code)
	}
}

func TestRefreshPrices(t *testing.T) {
	store := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/bloqueada" {
			w.WriteHeader(403)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(`<meta property="og:title" content="Berço"><meta property="og:image" content="https://cdn.loja.test/b.jpg"><meta property="product:price:amount" content="899.00"><meta property="product:original_price:amount" content="999.00">`))
	}))
	defer store.Close()
	var mu sync.Mutex
	patches := map[string]map[string]any{}
	done := make(chan struct{}, 2)
	db := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("apikey") != "secret-key" || r.Header.Get("Authorization") != "Bearer secret-key" {
			t.Error("the daily check must use the secret key")
		}
		switch r.Method {
		case http.MethodGet:
			_, _ = w.Write([]byte(`[{"id":"` + uid + `","url":"http://loja.test/berco","image_url":""},
			{"id":"a8d1a2c4-1b2f-4c3d-9e8f-0123456789ab","url":"http://loja.test/bloqueada","image_url":"https://x.test/a.jpg"}]`))
		case http.MethodPatch:
			var body map[string]any
			_ = json.NewDecoder(r.Body).Decode(&body)
			mu.Lock()
			patches[r.URL.Query().Get("id")] = body
			mu.Unlock()
			w.WriteHeader(204)
			done <- struct{}{}
		}
	}))
	defer db.Close()
	h := New(Config{SupabaseURL: db.URL, PublishableKey: "public-key", SecretKey: "secret-key", CronSecret: "cron-secret",
		Origins: []string{"https://ninho.example"}, Pages: storeClient(store)})
	post := func(auth string) int {
		r := httptest.NewRequest(http.MethodPost, "/internal/refresh-prices", nil)
		if auth != "" {
			r.Header.Set("Authorization", auth)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w.Code
	}
	if post("") != 404 || post("Bearer errado") != 404 {
		t.Fatal("the job needs the cron secret")
	}
	if code := post("Bearer cron-secret"); code != 202 {
		t.Fatalf("start: %d", code)
	}
	for range 2 {
		select {
		case <-done:
		case <-time.After(10 * time.Second):
			t.Fatal("the check did not finish")
		}
	}
	mu.Lock()
	defer mu.Unlock()
	ok := patches["eq."+uid]
	if ok["price_cents"] != float64(89900) || ok["list_price_cents"] != float64(99900) || ok["check_failed"] != false || ok["image_url"] != "https://cdn.loja.test/b.jpg" || ok["checked_at"] == nil {
		t.Fatalf("priced option: %v", ok)
	}
	blocked := patches["eq.a8d1a2c4-1b2f-4c3d-9e8f-0123456789ab"]
	if _, has := blocked["price_cents"]; has || blocked["check_failed"] != true {
		t.Fatalf("a page that fails keeps its last price: %v", blocked)
	}
	_ = io.Discard
}
