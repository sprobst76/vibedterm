package web

import (
	"embed"
	"fmt"
	"html/template"
	"io"
	"time"
)

//go:embed templates/*.html
var templateFS embed.FS

//go:embed static/css/*.css
var staticFS embed.FS

// Templates holds all parsed templates
type Templates struct {
	templates *template.Template
}

// NewTemplates parses and returns all templates
func NewTemplates() (*Templates, error) {
	funcMap := template.FuncMap{
		"formatTime": formatTime,
		"timeAgo":    timeAgo,
	}

	tmpl, err := template.New("").Funcs(funcMap).ParseFS(templateFS, "templates/*.html")
	if err != nil {
		return nil, err
	}

	return &Templates{templates: tmpl}, nil
}

// Render executes a template with the given data
func (t *Templates) Render(w io.Writer, name string, data interface{}) error {
	return t.templates.ExecuteTemplate(w, name, data)
}

// GetStaticFS returns the embedded static file system
func GetStaticFS() embed.FS {
	return staticFS
}

// Template helper functions

func formatTime(t time.Time) string {
	return t.Format("2006-01-02 15:04:05")
}

func timeAgo(t time.Time) string {
	diff := time.Since(t)

	if diff < time.Minute {
		return "just now"
	}
	if diff < time.Hour {
		mins := int(diff.Minutes())
		if mins == 1 {
			return "1 minute ago"
		}
		return fmt.Sprintf("%d minutes ago", mins)
	}
	if diff < 24*time.Hour {
		hours := int(diff.Hours())
		if hours == 1 {
			return "1 hour ago"
		}
		return fmt.Sprintf("%d hours ago", hours)
	}
	days := int(diff.Hours() / 24)
	if days == 1 {
		return "1 day ago"
	}
	return fmt.Sprintf("%d days ago", days)
}
