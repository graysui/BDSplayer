package player

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

type PlayerType string

const (
	PlayerPotPlayer PlayerType = "potplayer"
	PlayerVLC       PlayerType = "vlc"
	PlayerMPV       PlayerType = "mpv"
)

type InstalledPlayer struct {
	Type PlayerType `json:"type"`
	Name string     `json:"name"`
	Path string     `json:"path"`
}

// DetectInstalledPlayers scans standard paths for supported video players
func DetectInstalledPlayers() []InstalledPlayer {
	var result []InstalledPlayer

	if runtime.GOOS == "windows" {
		programFiles := os.Getenv("ProgramFiles")
		programFilesX86 := os.Getenv("ProgramFiles(x86)")
		localAppData := os.Getenv("LOCALAPPDATA")

		// PotPlayer paths
		potPaths := []string{
			filepath.Join(programFiles, "DAUM", "PotPlayer", "PotPlayer64.exe"),
			filepath.Join(programFilesX86, "DAUM", "PotPlayer", "PotPlayer.exe"),
			filepath.Join(localAppData, "PotPlayer", "PotPlayer64.exe"),
		}
		for _, p := range potPaths {
			if _, err := os.Stat(p); err == nil {
				result = append(result, InstalledPlayer{Type: PlayerPotPlayer, Name: "PotPlayer", Path: p})
				break
			}
		}

		// VLC paths
		vlcPaths := []string{
			filepath.Join(programFiles, "VideoLAN", "VLC", "vlc.exe"),
			filepath.Join(programFilesX86, "VideoLAN", "VLC", "vlc.exe"),
		}
		for _, p := range vlcPaths {
			if _, err := os.Stat(p); err == nil {
				result = append(result, InstalledPlayer{Type: PlayerVLC, Name: "VLC Media Player", Path: p})
				break
			}
		}

		// MPV paths
		if p, err := exec.LookPath("mpv.exe"); err == nil {
			result = append(result, InstalledPlayer{Type: PlayerMPV, Name: "MPV", Path: p})
		}
	} else {
		// Linux / macOS
		if p, err := exec.LookPath("vlc"); err == nil {
			result = append(result, InstalledPlayer{Type: PlayerVLC, Name: "VLC", Path: p})
		}
		if p, err := exec.LookPath("mpv"); err == nil {
			result = append(result, InstalledPlayer{Type: PlayerMPV, Name: "MPV", Path: p})
		}
	}

	return result
}

// LaunchWithDirectLink launches an external player with direct link and required User-Agent headers
func LaunchWithDirectLink(playerPath string, playerType PlayerType, dlink string) error {
	var cmd *exec.Cmd

	switch playerType {
	case PlayerPotPlayer:
		// PotPlayer /user_agent="pan.baidu.com"
		cmd = exec.Command(playerPath, dlink, `/user_agent="pan.baidu.com"`)
	case PlayerVLC:
		// VLC --http-user-agent="pan.baidu.com"
		cmd = exec.Command(playerPath, dlink, `--http-user-agent="pan.baidu.com"`)
	case PlayerMPV:
		// MPV --user-agent="pan.baidu.com"
		cmd = exec.Command(playerPath, dlink, `--user-agent="pan.baidu.com"`)
	default:
		return fmt.Errorf("unsupported player type: %s", playerType)
	}

	return cmd.Start()
}
