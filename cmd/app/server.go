package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gofiber/fiber/v3"
)

func (app *application) serve() error {
	addr := fmt.Sprintf("%s:%d", app.config.Server.Address, app.config.Server.Port)

	shutdown := make(chan os.Signal, 1)
	signal.Notify(shutdown, syscall.SIGINT, syscall.SIGTERM, os.Interrupt)

	// listen
	go func() {
		err := app.server.Listen(addr, fiber.ListenConfig{
			EnablePrefork:         false,
			DisableStartupMessage: true,
		})
		if err != nil {
			app.logger.Error("server listen error", slog.Any("error", err))
		}
	}()

	app.logger.Info("server started", slog.String("addr", addr))

	sig := <-shutdown
	app.logger.Info("shutting down server", slog.String("signal", sig.String()))

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := app.server.ShutdownWithContext(ctx); err != nil {
		return fmt.Errorf("failed to shutdown server: %w", err)
	}

	app.logger.Info("server gracefully stopped")

	return nil
}
