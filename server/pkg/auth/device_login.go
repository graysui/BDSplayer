package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"
)

type DeviceCodeResponse struct {
	DeviceCode      string `json:"device_code"`
	UserCode        string `json:"user_code"`
	VerificationURL string `json:"verification_url"`
	QrcodeURL       string `json:"qrcode_url"`
	ExpiresIn       int    `json:"expires_in"`
	Interval        int    `json:"interval"`
	Error           string `json:"error,omitempty"`
	ErrorDesc       string `json:"error_description,omitempty"`
}

func RequestDeviceCode(clientID string, scope string) (*DeviceCodeResponse, error) {
	if scope == "" {
		scope = "basic,netdisk"
	}

	endpoint := "https://openapi.baidu.com/oauth/2.0/device/code"
	data := url.Values{
		"client_id":     {clientID},
		"response_type": {"device_code"},
		"scope":         {scope},
	}

	resp, err := http.PostForm(endpoint, data)
	if err != nil {
		return nil, fmt.Errorf("device code request failed: %w", err)
	}
	defer resp.Body.Close()

	var result DeviceCodeResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to parse device code response: %w", err)
	}

	if result.Error != "" {
		return nil, fmt.Errorf("device code error: %s (%s)", result.Error, result.ErrorDesc)
	}

	if result.Interval <= 0 {
		result.Interval = 5
	}

	return &result, nil
}

func PollDeviceToken(ctx context.Context, clientID, clientSecret, deviceCode string, interval time.Duration) (*TokenInfo, error) {
	endpoint := "https://openapi.baidu.com/oauth/2.0/token"

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-ticker.C:
			data := url.Values{
				"grant_type":    {"device_token"},
				"code":          {deviceCode},
				"client_id":     {clientID},
				"client_secret": {clientSecret},
			}

			resp, err := http.PostForm(endpoint, data)
			if err != nil {
				continue
			}

			var tokenResp struct {
				AccessToken  string `json:"access_token"`
				RefreshToken string `json:"refresh_token"`
				ExpiresIn    int64  `json:"expires_in"`
				Scope        string `json:"scope"`
				Error        string `json:"error"`
				ErrorDesc    string `json:"error_description"`
			}

			_ = json.NewDecoder(resp.Body).Decode(&tokenResp)
			resp.Body.Close()

			switch tokenResp.Error {
			case "":
				if tokenResp.AccessToken != "" {
					return &TokenInfo{
						AccessToken:  tokenResp.AccessToken,
						RefreshToken: tokenResp.RefreshToken,
						ExpiresIn:    tokenResp.ExpiresIn,
						Scope:        tokenResp.Scope,
						CreatedAt:    time.Now(),
					}, nil
				}
			case "authorization_pending":
				// User has not yet authorized; continue polling
				continue
			case "slow_down":
				// Server requested slower polling
				time.Sleep(2 * time.Second)
				continue
			default:
				return nil, fmt.Errorf("authorization failed: %s (%s)", tokenResp.Error, tokenResp.ErrorDesc)
			}
		}
	}
}
