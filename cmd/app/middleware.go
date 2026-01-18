package main

import (
	"slices"
	"strings"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/gofiber/fiber/v3/middleware/helmet"
	"github.com/gofiber/fiber/v3/middleware/limiter"
	"github.com/gofiber/fiber/v3/middleware/recover"
)

func (app *application) middleware() {
	app.server.Use(recover.New())
	app.server.Use(helmet.New())

	expiration, err := time.ParseDuration(app.config.Server.RateLimiter.Expiration)
	if err != nil {
		expiration = 30 * time.Second
		app.logger.Warn("invalid limiter expiration, using default", "error", err)
	}
	app.server.Use(limiter.New(limiter.Config{
		Max:            app.config.Server.RateLimiter.MaxRequests,
		Expiration:     expiration,
		DisableHeaders: false,
	}))

	app.server.Use(requireAuthKey(app.config.Server.AuthKeys))
}

func requireAuthKey(allowedAuthKeys []string) fiber.Handler {
	return func(c fiber.Ctx) error {
		authKey := strings.TrimSpace(c.Get("X-API-Key"))
		if !slices.Contains(allowedAuthKeys, authKey) {
			return c.Status(fiber.StatusUnauthorized).SendString("unauthorized")
		}

		return c.Next()
	}
}
