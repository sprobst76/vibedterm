package web

import (
	"embed"
	"fmt"
	"html/template"
	"io"
	"io/fs"
	"path/filepath"
	"strings"
	"time"
)

//go:embed templates/*.html
var templateFS embed.FS

//go:embed static/css/*.css
var staticFS embed.FS

// Templates holds parsed per-page template sets.
// Each page is parsed with its layout to avoid {{define "content"}} collisions.
type Templates struct {
	templates map[string]*template.Template
}

// NewTemplates parses templates into isolated per-page sets.
func NewTemplates() (*Templates, error) {
	funcMap := template.FuncMap{
		"formatTime": formatTime,
		"timeAgo":    timeAgo,
		"deref":      derefTime,
	}

	t := &Templates{
		templates: make(map[string]*template.Template),
	}

	pages, err := fs.Glob(templateFS, "templates/*.html")
	if err != nil {
		return nil, err
	}

	// Identify layout files
	layouts := map[string]bool{
		"layout.html":      true,
		"user_layout.html": true,
	}

	for _, page := range pages {
		name := filepath.Base(page)
		if layouts[name] {
			continue
		}

		// Read the page to determine if it uses a layout
		content, err := fs.ReadFile(templateFS, page)
		if err != nil {
			return nil, fmt.Errorf("reading %s: %w", name, err)
		}
		pageContent := string(content)

		var tmpl *template.Template
		if strings.Contains(pageContent, `{{template "layout"`) {
			// Admin page using layout.html
			tmpl, err = template.New(name).Funcs(funcMap).ParseFS(templateFS, "templates/layout.html", page)
		} else if strings.Contains(pageContent, `{{template "user_layout"`) {
			// User page using user_layout.html
			tmpl, err = template.New(name).Funcs(funcMap).ParseFS(templateFS, "templates/user_layout.html", page)
		} else {
			// Standalone page (login, register, etc.)
			tmpl, err = template.New(name).Funcs(funcMap).ParseFS(templateFS, page)
		}

		if err != nil {
			return nil, fmt.Errorf("parsing %s: %w", name, err)
		}
		t.templates[name] = tmpl
	}

	return t, nil
}

// Render executes a template with the given data.
func (t *Templates) Render(w io.Writer, name string, data interface{}) error {
	tmpl, ok := t.templates[name]
	if !ok {
		return fmt.Errorf("template %s not found", name)
	}
	return tmpl.ExecuteTemplate(w, name, data)
}

// GetStaticFS returns the embedded static file system.
func GetStaticFS() embed.FS {
	return staticFS
}

// Template helper functions

func derefTime(t *time.Time) time.Time {
	if t == nil {
		return time.Time{}
	}
	return *t
}

func formatTime(t time.Time) string {
	if t.IsZero() {
		return "Never"
	}
	return t.Format("2006-01-02 15:04:05")
}

func timeAgo(t time.Time) string {
	if t.IsZero() {
		return "Never"
	}
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
