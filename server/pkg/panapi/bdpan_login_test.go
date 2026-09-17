package panapi

import (
	"context"
	"fmt"
	"image"
	_ "image/png"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// A real child process exercises pipe handling and cancellation without accounts.
func TestLoginProcessHelper(t *testing.T) {
	mode := os.Getenv("SHARE_PLAYER_LOGIN_HELPER")
	if mode == "" {
		return
	}
	switch mode {
	case "stdout", "stderr":
		out := os.Stdout
		if mode == "stderr" {
			out = os.Stderr
		}
		fmt.Fprintln(out, "二维码链接: https://openapi.baidu.com/device/qrcode/test-only")
		fmt.Fprintln(out, "\x1b[32m用户码： TEST123\x1b[0m")
	case "error":
		fmt.Fprintln(os.Stderr, "Error: 无法连接授权服务器 https://example.invalid/?secret=private")
		os.Exit(7)
	case "empty":
		os.Exit(0)
	case "timeout":
	default:
		os.Exit(2)
	}
	time.Sleep(time.Minute)
	os.Exit(0)
}

func helperLogin(t *testing.T, cli *BDPANCli, mode string, timeout time.Duration) (string, string, error) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	t.Cleanup(cancel)
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.CommandContext(ctx, exe, "-test.run=^TestLoginProcessHelper$")
	cmd.Env = append(os.Environ(), "SHARE_PLAYER_LOGIN_HELPER="+mode)
	return cli.startDeviceLogin(ctx, cancel, cmd, timeout)
}

func TestDeviceLoginReadsBothOutputStreams(t *testing.T) {
	for _, stream := range []string{"stdout", "stderr"} {
		t.Run(stream, func(t *testing.T) {
			cli := &BDPANCli{}
			t.Cleanup(cli.CancelLogin)
			qr, code, err := helperLogin(t, cli, stream, 3*time.Second)
			if err != nil || qr != "https://openapi.baidu.com/device/qrcode/test-only" || code != "TEST123" {
				t.Fatalf("unexpected prompt: %q, %q, %v", qr, code, err)
			}
		})
	}
}

func TestDeviceLoginReportsEarlyExit(t *testing.T) {
	for _, mode := range []string{"error", "empty"} {
		t.Run(mode, func(t *testing.T) {
			cli := &BDPANCli{}
			t.Cleanup(cli.CancelLogin)
			_, _, err := helperLogin(t, cli, mode, 5*time.Second)
			if err == nil || strings.Contains(err.Error(), "超时") {
				t.Fatalf("expected process error, got %v", err)
			}
			if mode == "error" && (!strings.Contains(err.Error(), "无法连接授权服务器") || strings.Contains(err.Error(), "private")) {
				t.Fatalf("missing diagnostic or leaked URL: %v", err)
			}
		})
	}
}

func TestDeviceLoginTimeoutStopsChild(t *testing.T) {
	cli := &BDPANCli{}
	t.Cleanup(cli.CancelLogin)
	_, _, err := helperLogin(t, cli, "timeout", 100*time.Millisecond)
	if err == nil || !strings.Contains(err.Error(), "超时") {
		t.Fatalf("expected timeout, got %v", err)
	}
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		cli.mu.Lock()
		stopped := cli.loginCmd == nil && !cli.isLoggingIn
		cli.mu.Unlock()
		if stopped {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("timed-out login process was not reaped")
}

func TestDeviceLoginRetryKeepsNewAttempt(t *testing.T) {
	cli := &BDPANCli{}
	t.Cleanup(cli.CancelLogin)
	for i := 0; i < 3; i++ {
		if _, _, err := helperLogin(t, cli, "stdout", 3*time.Second); err != nil {
			t.Fatal(err)
		}
	}
	cli.mu.Lock()
	defer cli.mu.Unlock()
	if !cli.isLoggingIn || cli.loginCmd == nil {
		t.Fatal("previous process completion cleared current login")
	}
}

func TestFetchDeviceQRCodeRejectsUntrustedURL(t *testing.T) {
	for _, rawURL := range []string{
		"http://openapi.baidu.com/device/qrcode/test",
		"https://example.com/device/qrcode/test",
		"https://openapi.baidu.com/other/test",
	} {
		if _, _, err := FetchDeviceQRCode(rawURL); err == nil {
			t.Fatalf("expected QR URL validation failure for %q", rawURL)
		}
	}
}

// Opt-in network test: a fresh config requests a QR image without authorizing
// an account or touching the developer's existing login state.
func TestBDPANDeviceLoginFreshConfig(t *testing.T) {
	exe := os.Getenv("SHARE_PLAYER_TEST_BDPAN_EXE")
	if exe == "" {
		t.Skip("set SHARE_PLAYER_TEST_BDPAN_EXE to test a packaged CLI")
	}
	cli := &BDPANCli{exePath: exe}
	t.Cleanup(cli.CancelLogin)
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	t.Cleanup(cancel)
	cmd := cli.newCommand(ctx, "--config-path", filepath.Join(t.TempDir(), "config.json"), "--no-check-update", "login", "--accept-disclaimer", "--device-code")
	qr, code, err := cli.startDeviceLogin(ctx, cancel, cmd, 30*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(qr, "https://openapi.baidu.com/device/qrcode/") || code == "" {
		t.Fatal("CLI did not return a usable QR URL and user code")
	}
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Get(qr)
	if err != nil {
		t.Fatal("QR image request failed")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("QR image HTTP status: %d", resp.StatusCode)
	}
	config, _, err := image.DecodeConfig(resp.Body)
	if err != nil || config.Width < 100 || config.Height < 100 {
		t.Fatalf("invalid QR image: %v", err)
	}
	t.Logf("fresh profile QR image verified: %dx%d", config.Width, config.Height)
}
