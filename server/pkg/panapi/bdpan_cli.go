package panapi

import (
	"bufio"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// FetchDeviceQRCode downloads only Baidu's device QR image. The strict host
// and path check keeps the local proxy from becoming an open URL fetcher.
func FetchDeviceQRCode(rawURL string) ([]byte, string, error) {
	u, err := url.Parse(rawURL)
	if err != nil || u.Scheme != "https" || u.Hostname() != "openapi.baidu.com" || !strings.HasPrefix(u.Path, "/device/qrcode/") {
		return nil, "", fmt.Errorf("二维码地址无效")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, "", fmt.Errorf("创建二维码请求失败：%w", err)
	}
	req.Header.Set("User-Agent", "BaiduSharePlayer/1.0")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, "", fmt.Errorf("获取二维码图片失败：%w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, "", fmt.Errorf("获取二维码图片失败（HTTP %d）", resp.StatusCode)
	}
	contentType := resp.Header.Get("Content-Type")
	if !strings.HasPrefix(strings.ToLower(contentType), "image/") {
		return nil, "", fmt.Errorf("授权服务返回的不是二维码图片")
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return nil, "", fmt.Errorf("读取二维码图片失败：%w", err)
	}
	if len(data) == 0 {
		return nil, "", fmt.Errorf("授权服务返回了空二维码图片")
	}
	return data, contentType, nil
}

var (
	qrRegex            = regexp.MustCompile(`https://openapi\.baidu\.com/device/qrcode/[^\s]+`)
	userCodeRegex      = regexp.MustCompile(`用户码[:：]\s*([a-zA-Z0-9]+)`)
	ansiEscapeRegex    = regexp.MustCompile(`\x1b\[[0-?]*[ -/]*[@-~]`)
	diagnosticURLRegex = regexp.MustCompile(`https?://[^\s]+`)
)

type BDPANCli struct {
	mu           sync.Mutex
	exePath      string
	configPath   string
	loginCmd     *exec.Cmd
	loginCancel  context.CancelFunc
	lastQR       string
	lastUserCode string
	isLoggingIn  bool
}

var (
	defaultCLI     *BDPANCli
	defaultCLIOnce sync.Once
)

func GetBDPANCli() *BDPANCli {
	defaultCLIOnce.Do(func() {
		defaultCLI = &BDPANCli{
			exePath: findBDPANExe(),
		}
	})
	return defaultCLI
}

func (b *BDPANCli) SetConfigPath(path string) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.configPath = path
}

func findBDPANExe() string {
	// Prefer the CLI shipped with the player, including on a fresh computer.
	var candidates []string
	if exe, err := os.Executable(); err == nil {
		dir := filepath.Dir(exe)
		candidates = append(candidates,
			filepath.Join(dir, "bdpan.exe"),
			filepath.Join(dir, "..", "bdpan.exe"),
			filepath.Join(dir, "payload", "bdpan.exe"),
			filepath.Join(dir, "..", "payload", "bdpan.exe"),
		)
	}
	if localAppData := os.Getenv("LOCALAPPDATA"); localAppData != "" {
		candidates = append(candidates,
			filepath.Join(localAppData, "Programs", "BDSplayer", "bdpan.exe"),
			filepath.Join(localAppData, "bdpan", "bdpan.exe"),
		)
	}
	if progFiles := os.Getenv("ProgramFiles"); progFiles != "" {
		candidates = append(candidates,
			filepath.Join(progFiles, "BDSplayer", "bdpan.exe"),
		)
	}
	if progFilesX86 := os.Getenv("ProgramFiles(x86)"); progFilesX86 != "" {
		candidates = append(candidates,
			filepath.Join(progFilesX86, "BDSplayer", "bdpan.exe"),
		)
	}
	if home, err := os.UserHomeDir(); err == nil {
		candidates = append(candidates,
			filepath.Join(home, "Desktop", "baidu-drive", "bdpan.exe"),
			filepath.Join(home, "Desktop", "baidu-drive", "dist", "payload", "bdpan.exe"),
			filepath.Join(home, ".local", "bin", "bdpan.exe"),
		)
	}

	for _, p := range candidates {
		if fi, err := os.Stat(p); err == nil && !fi.IsDir() {
			return p
		}
	}

	if lp, err := exec.LookPath("bdpan.exe"); err == nil {
		return lp
	}
	if lp, err := exec.LookPath("bdpan"); err == nil {
		return lp
	}
	return "bdpan.exe"
}

func (b *BDPANCli) GetExePath() string {
	return b.exePath
}

// newCommand creates a command configured with hidden window flags on Windows
func (b *BDPANCli) newCommand(ctx context.Context, args ...string) *exec.Cmd {
	var finalArgs []string
	if b.configPath != "" {
		finalArgs = append(finalArgs, "--config-path", b.configPath)
	}
	finalArgs = append(finalArgs, args...)

	cmd := exec.CommandContext(ctx, b.exePath, finalArgs...)
	if filepath.IsAbs(b.exePath) {
		cmd.Dir = filepath.Dir(b.exePath)
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow:    true,
		CreationFlags: 0x08000000, // CREATE_NO_WINDOW
	}
	return cmd
}

// Whoami checks if bdpan is authenticated
func (b *BDPANCli) Whoami() (bool, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cmd := b.newCommand(ctx, "whoami", "--json")
	out, err := cmd.Output()
	if err != nil {
		return false, err
	}

	var res struct {
		Authenticated bool `json:"authenticated"`
		HasValidToken bool `json:"has_valid_token"`
	}
	if err := json.Unmarshal(out, &res); err != nil {
		return false, err
	}

	return res.Authenticated && res.HasValidToken, nil
}

// StartDeviceLogin starts an isolated, bounded CLI login attempt.
func (b *BDPANCli) StartDeviceLogin() (qrURL string, userCode string, err error) {
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Minute)
	cmd := b.newCommand(ctx, "--no-check-update", "login", "--accept-disclaimer", "--device-code")
	return b.startDeviceLogin(ctx, cancel, cmd, 45*time.Second)
}

func (b *BDPANCli) startDeviceLogin(ctx context.Context, cancel context.CancelFunc, cmd *exec.Cmd, timeout time.Duration) (string, string, error) {
	b.mu.Lock()
	if b.loginCancel != nil {
		b.loginCancel()
	}
	if b.loginCmd != nil && b.loginCmd.Process != nil {
		_ = b.loginCmd.Process.Kill()
	}
	b.loginCmd = nil
	b.isLoggingIn = false
	b.lastQR, b.lastUserCode = "", ""
	// Ensure no lingering bdpan process is locking resources
	_ = exec.Command("taskkill", "/F", "/IM", "bdpan.exe").Run()

	stdout, stdoutWriter, err := os.Pipe()
	if err != nil {
		b.mu.Unlock()
		cancel()
		return "", "", fmt.Errorf("无法读取网盘授权程序输出：%w", err)
	}
	// The CLI may write diagnostics (or a prompt) to stderr. Merge both into
	// one pipe so errors cannot disappear and scanning has a single owner.
	cmd.Stdout = stdoutWriter
	cmd.Stderr = stdoutWriter
	if err := cmd.Start(); err != nil {
		b.mu.Unlock()
		_ = stdout.Close()
		_ = stdoutWriter.Close()
		cancel()
		return "", "", fmt.Errorf("无法启动网盘授权组件，请重新安装播放器：%w", err)
	}
	// The child owns the inherited writer after Start; keeping the parent's
	// handle open would prevent the scanner from ever receiving EOF.
	_ = stdoutWriter.Close()
	b.loginCmd, b.loginCancel, b.isLoggingIn = cmd, cancel, true
	b.mu.Unlock()

	type loginPrompt struct{ qr, code string }
	found := make(chan loginPrompt, 1)
	finished := make(chan error, 1)
	go func() {
		defer cancel()
		defer stdout.Close()
		scanner := bufio.NewScanner(stdout)
		scanner.Buffer(make([]byte, 4096), 1024*1024)
		var q, c, diagnostic string
		promptSent := false
		for scanner.Scan() {
			line := ansiEscapeRegex.ReplaceAllString(scanner.Text(), "")
			if m := qrRegex.FindString(line); m != "" {
				q = m
			}
			if m := userCodeRegex.FindStringSubmatch(line); len(m) > 1 {
				c = m[1]
			}
			// Fallback: extract userCode directly from the qrcode URL path if needed
			if c == "" && q != "" {
				parts := strings.Split(q, "/")
				if len(parts) > 0 {
					last := parts[len(parts)-1]
					if len(last) >= 4 && len(last) <= 16 {
						c = last
					}
				}
			}
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(strings.ToLower(trimmed), "error:") || strings.HasPrefix(trimmed, "错误:") || strings.HasPrefix(trimmed, "错误：") {
				// Do not return URLs containing temporary authorization data.
				diagnostic = diagnosticURLRegex.ReplaceAllString(trimmed, "[请求地址]")
				runes := []rune(diagnostic)
				if len(runes) > 400 {
					diagnostic = string(runes[:400])
				}
			}
			if !promptSent && q != "" && c != "" {
				promptSent = true
				found <- loginPrompt{q, c}
			}
		}
		scanErr := scanner.Err()
		if scanErr != nil {
			cancel()
		}
		waitErr := cmd.Wait()
		var result error
		switch {
		case diagnostic != "":
			result = fmt.Errorf("网盘授权失败：%s", diagnostic)
		case scanErr != nil:
			result = fmt.Errorf("读取网盘授权信息失败：%w", scanErr)
		case waitErr != nil:
			result = fmt.Errorf("网盘授权程序退出：%w", waitErr)
		case !promptSent:
			result = fmt.Errorf("网盘授权程序未返回二维码，请重试")
		}
		b.mu.Lock()
		// A previous attempt must not clear a newer attempt's state.
		if b.loginCmd == cmd {
			b.loginCmd = nil
			b.isLoggingIn = false
		}
		b.mu.Unlock()
		finished <- result
	}()

	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case prompt := <-found:
		b.mu.Lock()
		defer b.mu.Unlock()
		if b.loginCmd != cmd || ctx.Err() != nil {
			return "", "", fmt.Errorf("本次授权已结束，请重试")
		}
		b.lastQR, b.lastUserCode = prompt.qr, prompt.code
		return prompt.qr, prompt.code, nil
	case err := <-finished:
		if err == nil {
			err = fmt.Errorf("网盘授权程序已结束，请重试")
		}
		return "", "", err
	case <-ctx.Done():
		select {
		case err := <-finished:
			if err != nil {
				return "", "", err
			}
		default:
		}
		return "", "", fmt.Errorf("本次授权已取消或过期，请重试")
	case <-timer.C:
		cancel()
		return "", "", fmt.Errorf("等待二维码响应超时（%d 秒），请检查网络后重试", int(timeout.Seconds()))
	}
}

// CancelLogin cancels running login process
func (b *BDPANCli) CancelLogin() {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.loginCancel != nil {
		b.loginCancel()
	}
	if b.loginCmd != nil && b.loginCmd.Process != nil {
		_ = b.loginCmd.Process.Kill()
		b.loginCmd = nil
	}
	_ = exec.Command("taskkill", "/F", "/IM", "bdpan.exe").Run()
	b.isLoggingIn = false
}

// DecryptTokens reads and decrypts tokens from bdpan config
func (b *BDPANCli) DecryptTokens() (accessToken, refreshToken string, err error) {
	var cfgPath, keyPath string
	if b.configPath != "" {
		cfgPath = b.configPath
		keyPath = filepath.Join(filepath.Dir(b.configPath), ".token_key")
	} else {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", "", err
		}
		configDir := filepath.Join(home, ".config", "BDSplayer")
		cfgPath = filepath.Join(configDir, "bdpan.json")
		keyPath = filepath.Join(configDir, ".token_key")
	}

	cfgData, err := os.ReadFile(cfgPath)
	if err != nil {
		return "", "", fmt.Errorf("bdpan config not found: %w", err)
	}
	keyData, err := os.ReadFile(keyPath)
	if err != nil {
		return "", "", fmt.Errorf(".token_key not found: %w", err)
	}

	hexKey := strings.TrimSpace(string(keyData))
	keyBytes, err := hex.DecodeString(hexKey)
	if err != nil || len(keyBytes) != 32 {
		return "", "", fmt.Errorf("invalid key: %w", err)
	}

	var root struct {
		Auth struct {
			AccessToken  string `json:"access_token"`
			RefreshToken string `json:"refresh_token"`
		} `json:"auth"`
	}
	if err := json.Unmarshal(cfgData, &root); err != nil {
		return "", "", err
	}

	decryptField := func(cipherStr string) (string, error) {
		if !strings.HasPrefix(cipherStr, "enc:v1:") {
			return cipherStr, nil
		}
		b64Part := strings.TrimPrefix(cipherStr, "enc:v1:")
		cipherBytes, err := base64.StdEncoding.DecodeString(b64Part)
		if err != nil {
			return "", err
		}
		block, err := aes.NewCipher(keyBytes)
		if err != nil {
			return "", err
		}
		gcm, err := cipher.NewGCM(block)
		if err != nil {
			return "", err
		}
		if len(cipherBytes) < gcm.NonceSize() {
			return "", fmt.Errorf("ciphertext too short")
		}
		nonce := cipherBytes[:gcm.NonceSize()]
		ciphertext := cipherBytes[gcm.NonceSize():]
		plain, err := gcm.Open(nil, nonce, ciphertext, nil)
		if err != nil {
			return "", err
		}
		return string(plain), nil
	}

	at, err := decryptField(root.Auth.AccessToken)
	if err != nil {
		return "", "", fmt.Errorf("decrypt access_token failed: %w", err)
	}
	rt, _ := decryptField(root.Auth.RefreshToken)
	return at, rt, nil
}

// NormalizeShareURL ensures full https://pan.baidu.com/s/... format
func NormalizeShareURL(raw string) string {
	raw = strings.TrimSpace(raw)
	if strings.HasPrefix(raw, "http://") || strings.HasPrefix(raw, "https://") {
		// Strip query parameters if present, bdpan accepts clean url
		idx := strings.Index(raw, "?")
		if idx != -1 {
			return raw[:idx]
		}
		return raw
	}
	// It's a key
	key := strings.TrimPrefix(raw, "1")
	return "https://pan.baidu.com/s/1" + key
}

// TransferList runs bdpan transfer list <shareURL>
func (b *BDPANCli) TransferList(shareInput, pwd, sourceDir string) ([]ShareFileItem, error) {
	fullURL := NormalizeShareURL(shareInput)

	args := []string{"transfer", "list", fullURL, "--json"}
	if pwd != "" {
		args = append(args, "-p", pwd)
	}
	if sourceDir != "" {
		args = append(args, "--source-dir", sourceDir)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	cmd := b.newCommand(ctx, args...)
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("transfer list failed: %w (output: %s)", err, string(out))
	}

	var resp struct {
		Dir   string `json:"dir"`
		Count int    `json:"count"`
		Items []struct {
			Index int    `json:"index"`
			FsID  any    `json:"fs_id"`
			Name  string `json:"name"`
			IsDir bool   `json:"is_dir"`
			Size  int64  `json:"size"`
			Path  string `json:"path"`
		} `json:"items"`
		Error string `json:"error"`
		Code  int    `json:"code"`
	}

	if err := json.Unmarshal(out, &resp); err != nil {
		return nil, fmt.Errorf("failed to parse bdpan transfer list output: %w", err)
	}
	if resp.Error != "" {
		return nil, fmt.Errorf("bdpan transfer list error: %s", resp.Error)
	}

	items := make([]ShareFileItem, 0, len(resp.Items))
	for _, it := range resp.Items {
		var fsid uint64
		switch v := it.FsID.(type) {
		case string:
			fsid, _ = strconv.ParseUint(v, 10, 64)
		case float64:
			fsid = uint64(v)
		case int64:
			fsid = uint64(v)
		}

		isVideo := !it.IsDir && (IsVideoFile(it.Name))
		items = append(items, ShareFileItem{
			FsID:     fsid,
			Name:     it.Name,
			IsDir:    it.IsDir,
			Size:     it.Size,
			Path:     it.Path,
			Category: 0,
			IsVideo:  isVideo,
		})
	}
	return items, nil
}

// TransferSelect transfers a single file to targetDir
func (b *BDPANCli) TransferSelect(shareInput, pwd string, fsid uint64, targetDir string) error {
	if targetDir == "" {
		targetDir = "/apps/bdpan/stream_cache"
	}
	fullURL := NormalizeShareURL(shareInput)

	args := []string{"transfer", "select", fullURL, "--fsid", fmt.Sprintf("%d", fsid), "-d", targetDir, "--json"}
	if pwd != "" {
		args = append(args, "-p", pwd)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	cmd := b.newCommand(ctx, args...)
	out, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("transfer select failed: %w (output: %s)", err, string(out))
	}

	var resp struct {
		Code  int    `json:"code"`
		Error string `json:"error"`
	}
	if err := json.Unmarshal(out, &resp); err == nil && resp.Error != "" {
		return fmt.Errorf("transfer select error: %s", resp.Error)
	}
	return nil
}

// FindTransferredFile searches targetDir for transferred video and returns its user FsID
func (b *BDPANCli) FindTransferredFile(targetDir, filename string) (uint64, error) {
	if targetDir == "" {
		targetDir = "/apps/bdpan/stream_cache"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	cmd := b.newCommand(ctx, "ls", targetDir, "--json")
	out, err := cmd.Output()
	if err != nil {
		return 0, fmt.Errorf("ls %s failed: %w", targetDir, err)
	}

	var items []struct {
		FsID           uint64 `json:"fs_id"`
		ServerFilename string `json:"server_filename"`
	}
	if err := json.Unmarshal(out, &items); err != nil {
		return 0, fmt.Errorf("failed to parse ls output: %w", err)
	}

	for _, it := range items {
		if it.ServerFilename == filename {
			return it.FsID, nil
		}
	}
	if len(items) > 0 {
		// Return latest if direct match not found
		return items[len(items)-1].FsID, nil
	}
	return 0, fmt.Errorf("file %s not found in %s", filename, targetDir)
}

func (b *BDPANCli) Logout() error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := b.newCommand(ctx, "logout")
	_ = cmd.Run()
	if b.configPath != "" {
		_ = os.Remove(b.configPath)
		_ = os.Remove(filepath.Join(filepath.Dir(b.configPath), ".token_key"))
	}
	return nil
}
