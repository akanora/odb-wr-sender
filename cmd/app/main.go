package main

import (
	"flag"
	"log"
	"log/slog"
	"os"
	"time"

	"github.com/happydez/sj-wr-sender/internal/config"

	"github.com/gofiber/fiber/v3"
)

type application struct {
	config *config.Config
	server *fiber.App
	logger *slog.Logger
}

func main() {
	var configPath string
	flag.StringVar(&configPath, "config", "config/app.toml", "app config")
	flag.Parse()

	// Config
	config, err := config.Load(configPath)
	if err != nil {
		log.Fatal(err)
	}

	// Logger
	var logLevel slog.Level
	if err := logLevel.UnmarshalText([]byte(config.Logger.Level)); err != nil {
		logLevel = slog.LevelError
	}
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level:     logLevel,
		AddSource: true,
	}))

	slog.Info("app",
		slog.String("version", config.App.Version),
		slog.String("enviroment", config.App.Enviroment),
		slog.String("log-level", config.Logger.Level),
	)

	// App
	app := &application{
		config: config,
		logger: logger,
	}

	// Server
	app.server = fiber.New(fiber.Config{
		ServerHeader: "SourceJump WR Sender",
		IdleTimeout:  1 * time.Minute,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		ErrorHandler: app.globalErrorHandler,
	})

	app.middleware()
	app.routes()

	if err := app.serve(); err != nil {
		logger.Error("application failure", slog.Any("error", err))
		os.Exit(1)
	}
}
