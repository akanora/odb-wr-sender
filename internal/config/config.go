package config

import (
	"fmt"
	"os"

	"github.com/BurntSushi/toml"
)

type App struct {
	Version    string `toml:"version"`
	Enviroment string `toml:"enviroment"`
}

type Server struct {
	Port        int         `toml:"port"`
	Address     string      `toml:"address"`
	AuthKeys    []string    `toml:"auth_keys"`
	RateLimiter RateLimiter `toml:"rate_limiter"`
}

type RateLimiter struct {
	MaxRequests int    `toml:"max_requests"`
	Expiration  string `toml:"expiration"`
}

type Logger struct {
	Level string `toml:"level"`
}

type SourceJump struct {
	MaxFileSize int64  `toml:"max_file_size"`
	Receiver    string `toml:"receiver"`
}

type Config struct {
	App        App        `toml:"app"`
	Server     Server     `toml:"server"`
	Logger     Logger     `toml:"logger"`
	SourceJump SourceJump `toml:"sourcejump"`
}

func Load(path string) (*Config, error) {
	var cfg Config
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return nil, fmt.Errorf("config file not found: %s", path)
	}

	_, err := toml.DecodeFile(path, &cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to decode toml: %w", err)
	}

	return &cfg, nil
}
