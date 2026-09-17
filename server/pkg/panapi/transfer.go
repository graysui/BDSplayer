package panapi

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
	"time"
)

type TransferResponse struct {
	Errno     int    `json:"errno"`
	ErrMsg    string `json:"errmsg"`
	RequestID string `json:"request_id"`
	Data      struct {
		TaskID string `json:"task_id"`
		List   []struct {
			FsID uint64 `json:"fs_id"`
			Path string `json:"path"`
		} `json:"list"`
	} `json:"data"`
}

type TaskQueryResult struct {
	Status string // "running", "success", "failed"
	Files  []TransferredFile
	Error  string
}

type TransferredFile struct {
	FsID uint64 `json:"fs_id"`
	Path string `json:"path"`
}

func (c *Client) TransferSelect(ctx context.Context, shortURL, pwd string, fsids []uint64, targetDir string) (string, []TransferredFile, error) {
	token, err := c.getAccessToken()
	if err != nil {
		return "", nil, err
	}

	if targetDir == "" {
		targetDir = "/apps/bdpan/stream_cache"
	}

	fsidStrs := make([]string, len(fsids))
	for i, id := range fsids {
		fsidStrs[i] = fmt.Sprintf("%d", id)
	}
	fsidJSON, _ := json.Marshal(fsidStrs)

	u := "https://pan.baidu.com/apaas/1.0/share/transfer"
	params := url.Values{
		"product":      {"netdisk"},
		"access_token": {token},
		"short_url":    {shortURL},
		"fsid_list":    {string(fsidJSON)},
		"dir":          {targetDir},
	}
	if pwd != "" {
		params.Set("pwd", pwd)
	}

	fullURL := fmt.Sprintf("%s?%s", u, params.Encode())
	data, err := c.doRequest(ctx, "POST", fullURL, nil, nil)
	if err != nil {
		return "", nil, err
	}

	var resp TransferResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return "", nil, fmt.Errorf("failed to decode transfer response: %w", err)
	}

	if resp.Errno != 0 {
		return "", nil, fmt.Errorf("transfer failed (errno %d): %s", resp.Errno, resp.ErrMsg)
	}

	var files []TransferredFile
	for _, f := range resp.Data.List {
		files = append(files, TransferredFile{
			FsID: f.FsID,
			Path: f.Path,
		})
	}

	return resp.Data.TaskID, files, nil
}

func (c *Client) QueryTask(ctx context.Context, taskID string) (*TaskQueryResult, error) {
	token, err := c.getAccessToken()
	if err != nil {
		return nil, err
	}

	u := "https://pan.baidu.com/apaas/1.0/share/taskquery"
	params := url.Values{
		"product":      {"netdisk"},
		"access_token": {token},
		"task_id":      {taskID},
	}

	fullURL := fmt.Sprintf("%s?%s", u, params.Encode())
	data, err := c.doRequest(ctx, "GET", fullURL, nil, nil)
	if err != nil {
		return nil, err
	}

	var resp struct {
		Errno  int    `json:"errno"`
		ErrMsg string `json:"errmsg"`
		Data   struct {
			Status string `json:"status"` // "running", "success", "failed"
			List   []struct {
				FsID uint64 `json:"fs_id"`
				Path string `json:"path"`
			} `json:"list"`
		} `json:"data"`
	}

	if err := json.Unmarshal(data, &resp); err != nil {
		return nil, fmt.Errorf("failed to decode taskquery response: %w", err)
	}

	result := &TaskQueryResult{
		Status: strings.ToLower(resp.Data.Status),
	}

	if resp.Errno != 0 {
		result.Status = "failed"
		result.Error = fmt.Sprintf("task query error %d: %s", resp.Errno, resp.ErrMsg)
		return result, nil
	}

	for _, it := range resp.Data.List {
		result.Files = append(result.Files, TransferredFile{
			FsID: it.FsID,
			Path: it.Path,
		})
	}

	return result, nil
}

// TransferSingleVideoSynchronous transfers a single video and waits until ready (typically < 1.5s)
func (c *Client) TransferSingleVideoSynchronous(ctx context.Context, shortURL, pwd string, shareFsID uint64, targetDir string) (*TransferredFile, error) {
	taskID, immediateFiles, err := c.TransferSelect(ctx, shortURL, pwd, []uint64{shareFsID}, targetDir)
	if err != nil {
		return nil, err
	}

	if len(immediateFiles) > 0 {
		return &immediateFiles[0], nil
	}

	if taskID == "" {
		return nil, fmt.Errorf("neither files nor task_id returned from transfer")
	}

	// Poll taskquery with 500ms intervals, timeout 15s
	ctxTimeout, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctxTimeout.Done():
			return nil, fmt.Errorf("transfer task %s timed out", taskID)
		case <-ticker.C:
			res, err := c.QueryTask(ctxTimeout, taskID)
			if err != nil {
				continue
			}
			switch res.Status {
			case "success":
				if len(res.Files) > 0 {
					return &res.Files[0], nil
				}
				return nil, fmt.Errorf("transfer task finished but no file returned")
			case "failed":
				return nil, fmt.Errorf("transfer task failed: %s", res.Error)
			case "running":
				// continue polling
			}
		}
	}
}
