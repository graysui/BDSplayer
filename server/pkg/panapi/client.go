package panapi

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"time"
)

type TokenProvider interface {
	GetAccessToken() (string, error)
}

type Client struct {
	tokenProvider TokenProvider
	httpClient    *http.Client
}

func NewClient(tp TokenProvider) *Client {
	return &Client{
		tokenProvider: tp,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

func (c *Client) getAccessToken() (string, error) {
	if c.tokenProvider == nil {
		return "", fmt.Errorf("no token provider configured")
	}
	return c.tokenProvider.GetAccessToken()
}

func (c *Client) doRequest(ctx context.Context, method, urlStr string, body io.Reader, headers map[string]string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, method, urlStr, body)
	if err != nil {
		return nil, err
	}

	for k, v := range headers {
		req.Header.Set(k, v)
	}

	if req.Header.Get("User-Agent") == "" {
		req.Header.Set("User-Agent", "pan.baidu.com")
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return data, fmt.Errorf("http error %d: %s", resp.StatusCode, string(data))
	}

	return data, nil
}
