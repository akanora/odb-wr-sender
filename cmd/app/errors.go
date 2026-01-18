package main

import (
	"errors"
	"net/http"

	"github.com/gofiber/fiber/v3"
)

func (app *application) globalErrorHandler(c fiber.Ctx, err error) error {
	code := fiber.StatusInternalServerError

	var fiberErr *fiber.Error
	if errors.As(err, &fiberErr) {
		code = fiberErr.Code
	}

	logAttrs := []any{
		"status", code,
		"method", c.Method(),
		"path", c.Path(),
		"error", err.Error(),
		"ip", c.IP(),
	}

	if code >= fiber.StatusInternalServerError {
		app.logger.Error("server_error", logAttrs...)
	} else {
		app.logger.Warn("client_error", logAttrs...)
	}

	return c.Status(code).JSON(fiber.Map{
		"error": http.StatusText(code),
	})
}
