package api

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"math"
	"net/http"
	"regexp"
	"strconv"
	"strings"
)

// Ninho Plus is bought once per account through Mercado Pago Checkout Pro, on the web app. The money goes to the
// Mercado Pago account whose access token the API has. The API never trusts what a notice or a returning browser
// says about a payment: it reads the payment back from Mercado Pago with that token, and only a payment it
// created for Plus (external_reference "ninho-plus:<user id>") approved for the full price grants Plus.

// PlusPriceCents is the price of Plus, in cents of a real.
const PlusPriceCents = 1000

const plusReference = "ninho-plus:"

var paymentID = regexp.MustCompile(`^[0-9]{1,30}$`)

// mercadoPago calls the Mercado Pago API with the access token.
func (s *Server) mercadoPago(ctx context.Context, method, path string, body any) (int, []byte, error) {
	var reader io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		reader = bytes.NewReader(b)
	}
	base := strings.TrimRight(s.cfg.MercadoPagoURL, "/")
	if base == "" {
		base = "https://api.mercadopago.com"
	}
	req, err := http.NewRequestWithContext(ctx, method, base+path, reader)
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Authorization", "Bearer "+s.cfg.MercadoPagoToken)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	res, err := s.client.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer res.Body.Close()
	out, err := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	return res.StatusCode, out, err
}

// hasPlus says whether the signed-in account bought Plus, reading its own row with its own session.
func (s *Server) hasPlus(r *http.Request) (bool, error) {
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, s.cfg.SupabaseURL+"/rest/v1/plus_accounts?select=user_id", nil)
	if err != nil {
		return false, err
	}
	req.Header.Set("Authorization", r.Header.Get("Authorization"))
	req.Header.Set("apikey", s.cfg.PublishableKey)
	res, err := s.client.Do(req)
	if err != nil {
		return false, err
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return false, errors.New("plus lookup failed")
	}
	var rows []json.RawMessage
	if err := json.NewDecoder(io.LimitReader(res.Body, 65536)).Decode(&rows); err != nil {
		return false, err
	}
	return len(rows) > 0, nil
}

// plus answers POST /v1/plus/checkout, which opens a payment for the signed-in account, and POST
// /v1/plus/confirm, which the web app calls with the payment_id Mercado Pago adds to the address it returns to.
func (s *Server) plus(w http.ResponseWriter, r *http.Request, action string) {
	if r.Method != http.MethodPost {
		fail(w, 405, "Use POST")
		return
	}
	if s.cfg.MercadoPagoToken == "" || s.cfg.SecretKey == "" || s.cfg.AppURL == "" {
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
	switch action {
	case "checkout":
		owned, err := s.hasPlus(r)
		if err != nil {
			fail(w, 503, "Serviço temporariamente indisponível")
			return
		}
		if owned {
			fail(w, 409, "Sua conta já tem o Ninho Plus")
			return
		}
		back := strings.TrimRight(s.cfg.AppURL, "/") + "/app/?plus=retorno"
		status, body, err := s.mercadoPago(r.Context(), http.MethodPost, "/checkout/preferences", map[string]any{
			"items": []map[string]any{{
				"id": "ninho-plus", "title": "Ninho Plus", "description": "Lista de presentes com Pix. Pagamento único.",
				"category_id": "services", "quantity": 1, "currency_id": "BRL", "unit_price": float64(PlusPriceCents) / 100,
			}},
			"external_reference":   plusReference + user,
			"back_urls":            map[string]string{"success": back, "pending": back, "failure": back},
			"auto_return":          "approved",
			"statement_descriptor": "NINHO PLUS",
			// Pix and cards confirm in minutes. A boleto takes days, and the buyer would wait for the list.
			"payment_methods": map[string]any{"installments": 1, "excluded_payment_types": []map[string]string{{"id": "ticket"}, {"id": "atm"}}},
		})
		if err != nil || status >= 300 {
			slog.Error("mercado pago preference failed", "status", status, "error", err)
			fail(w, 503, "Não foi possível abrir o pagamento agora. Tente novamente")
			return
		}
		var pref struct {
			InitPoint string `json:"init_point"`
		}
		if json.Unmarshal(body, &pref) != nil || !strings.HasPrefix(pref.InitPoint, "https://") {
			fail(w, 503, "Não foi possível abrir o pagamento agora. Tente novamente")
			return
		}
		send(w, 201, map[string]string{"url": pref.InitPoint})
	case "confirm":
		obj, err := decode(w, r, "payment_id")
		if err != nil {
			fail(w, 400, err.Error())
			return
		}
		id, _ := obj["payment_id"].(string)
		if !paymentID.MatchString(id) {
			fail(w, 400, "Pagamento inválido")
			return
		}
		p, err := s.syncPayment(r.Context(), id)
		if err != nil {
			fail(w, 503, "Não foi possível conferir o pagamento agora. Tente novamente")
			return
		}
		// Someone else's payment, or not one for Plus, is as good as missing.
		if p == nil || p.user != user {
			fail(w, 404, "Pagamento não encontrado")
			return
		}
		send(w, 200, map[string]any{"plus": p.plus, "status": p.status})
	default:
		fail(w, 404, "Operação não encontrada")
	}
}

type plusPayment struct {
	user, status string
	plus         bool
}

// syncPayment reads a payment from Mercado Pago and records it. It returns nil for a payment that does not
// exist or is not for Plus, and an error when Mercado Pago or the database could not answer.
func (s *Server) syncPayment(ctx context.Context, id string) (*plusPayment, error) {
	status, body, err := s.mercadoPago(ctx, http.MethodGet, "/v1/payments/"+id, nil)
	if err != nil || status >= 500 || status == 429 {
		return nil, errors.New("mercado pago unavailable")
	}
	if status == 404 {
		return nil, nil
	}
	if status != 200 {
		slog.Error("mercado pago payment lookup failed", "status", status)
		return nil, errors.New("mercado pago refused")
	}
	var pay struct {
		ID        json.Number `json:"id"`
		Status    string      `json:"status"`
		Amount    json.Number `json:"transaction_amount"`
		Currency  string      `json:"currency_id"`
		Reference string      `json:"external_reference"`
	}
	dec := json.NewDecoder(bytes.NewReader(body))
	dec.UseNumber()
	if err := dec.Decode(&pay); err != nil {
		return nil, err
	}
	user, ok := strings.CutPrefix(pay.Reference, plusReference)
	if !ok || !uuid.MatchString(user) || pay.ID.String() != id || pay.Status == "" || len(pay.Status) > 40 {
		return nil, nil
	}
	amount, err := strconv.ParseFloat(pay.Amount.String(), 64)
	if err != nil || amount < 0 || amount > 1e6 {
		return nil, nil
	}
	cents := int64(math.Round(amount * 100))
	paid := pay.Status == "approved" && pay.Currency == "BRL" && cents >= PlusPriceCents
	code, out, err := s.adminRPC(ctx, "record_plus_payment", map[string]any{
		"p_payment_id": id, "p_user_id": strings.ToLower(user), "p_status": pay.Status, "p_amount_cents": cents, "p_paid": paid,
	})
	if err != nil || code >= 500 {
		return nil, errors.New("database unavailable")
	}
	if code >= 400 {
		slog.Error("plus payment not recorded", "payment", id, "status", code)
		return nil, nil
	}
	var plus bool
	if json.Unmarshal(out, &plus) != nil {
		return nil, errors.New("unexpected database answer")
	}
	if paid {
		slog.Info("plus granted", "payment", id)
	}
	return &plusPayment{user: strings.ToLower(user), status: pay.Status, plus: plus}, nil
}

// mercadoPagoWebhook answers POST /webhooks/mercadopago, which Mercado Pago calls when a payment of the account
// changes. With MERCADOPAGO_WEBHOOK_SECRET set, a notice must carry Mercado Pago's signature. Either way the
// payment is read back from Mercado Pago, so a notice only says which payment to look at.
func (s *Server) mercadoPagoWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		fail(w, 405, "Use POST")
		return
	}
	if s.cfg.MercadoPagoToken == "" || s.cfg.SecretKey == "" {
		fail(w, 503, "Pagamentos indisponíveis")
		return
	}
	if !s.allowN("mp:"+clientIP(r), 120) {
		w.Header().Set("Retry-After", "60")
		fail(w, 429, "Muitas solicitações")
		return
	}
	var notice struct {
		Type string `json:"type"`
		Data struct {
			ID json.RawMessage `json:"id"`
		} `json:"data"`
	}
	_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, 65536)).Decode(&notice)
	q := r.URL.Query()
	kind := q.Get("type")
	if kind == "" {
		kind = notice.Type
	}
	id := q.Get("data.id")
	if id == "" {
		id = strings.Trim(string(notice.Data.ID), `"`)
	}
	// Mercado Pago sends other kinds of notices too, and every payment of the account, not only Plus.
	if kind != "payment" {
		send(w, 200, map[string]bool{"ok": true})
		return
	}
	if s.cfg.MercadoPagoWebhookSecret != "" && !validSignature(r, q.Get("data.id"), s.cfg.MercadoPagoWebhookSecret) {
		fail(w, 401, "Assinatura inválida")
		return
	}
	if !paymentID.MatchString(id) {
		fail(w, 400, "Pagamento inválido")
		return
	}
	if _, err := s.syncPayment(r.Context(), id); err != nil {
		// Mercado Pago tries again later.
		fail(w, 503, "Tente novamente")
		return
	}
	send(w, 200, map[string]bool{"ok": true})
}

// validSignature checks the x-signature header of a Mercado Pago notice: an HMAC-SHA256, with the webhook
// secret, of "id:<data.id>;request-id:<x-request-id>;ts:<ts>;", leaving out the parts that are missing.
func validSignature(r *http.Request, dataID, secret string) bool {
	var ts, v1 string
	for _, part := range strings.Split(r.Header.Get("X-Signature"), ",") {
		k, v, _ := strings.Cut(strings.TrimSpace(part), "=")
		switch k {
		case "ts":
			ts = v
		case "v1":
			v1 = v
		}
	}
	if ts == "" || v1 == "" {
		return false
	}
	var manifest strings.Builder
	if dataID != "" {
		manifest.WriteString("id:" + strings.ToLower(dataID) + ";")
	}
	if rid := r.Header.Get("X-Request-Id"); rid != "" {
		manifest.WriteString("request-id:" + rid + ";")
	}
	manifest.WriteString("ts:" + ts + ";")
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(manifest.String()))
	got, err := hex.DecodeString(v1)
	return err == nil && hmac.Equal(got, mac.Sum(nil))
}
