package main

import (
	"github.com/gofiber/fiber/v3/middleware/healthcheck"
)

func (app *application) healthcheck() {
	app.server.Get(healthcheck.LivenessEndpoint, healthcheck.New())
}
