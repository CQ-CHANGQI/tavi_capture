// Mock MCAP HTTP server: serves one .mcap file with Range support.
//
//	go run . -file /Users/changqi/Desktop/data.mcap
//	go run . -file /Users/changqi/Desktop/data.mcap -addr 0.0.0.0:8080 -mbps 20
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:8080", "listen address")
	file := flag.String("file", "", "path to the .mcap file")
	mbps := flag.Int("mbps", 0, "optional bandwidth limit in MiB/s (0 = unlimited)")
	flag.Parse()

	if *file == "" {
		log.Fatal("-file is required")
	}
	info, err := os.Stat(*file)
	if err != nil {
		log.Fatalf("stat %s: %v", *file, err)
	}
	if info.IsDir() {
		log.Fatalf("%s is a directory", *file)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		fmt.Fprintln(w, "ok")
	})
	mux.HandleFunc("/data.mcap", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		f, err := os.Open(*file)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		defer f.Close()

		log.Printf("%s %s range=%q", r.Method, r.URL.Path, r.Header.Get("Range"))
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set(
			"Access-Control-Expose-Headers",
			"Content-Length, Content-Range, Accept-Ranges",
		)

		var out http.ResponseWriter = w
		if *mbps > 0 {
			out = &rateWriter{
				ResponseWriter: w,
				bytesPerSec:    int64(*mbps) * 1024 * 1024,
				start:          time.Now(),
			}
		}
		http.ServeContent(out, r, filepath.Base(*file), info.ModTime(), f)
	})

	log.Printf(
		"serving %s (%d bytes) at http://%s/data.mcap",
		*file, info.Size(), *addr,
	)
	log.Fatal(http.ListenAndServe(*addr, mux))
}

type rateWriter struct {
	http.ResponseWriter
	bytesPerSec int64
	start       time.Time
	sent        int64
}

func (w *rateWriter) Write(p []byte) (int, error) {
	n, err := w.ResponseWriter.Write(p)
	w.sent += int64(n)
	if w.bytesPerSec > 0 {
		expected := time.Duration(
			float64(w.sent) / float64(w.bytesPerSec) * float64(time.Second),
		)
		if sleep := expected - time.Since(w.start); sleep > 0 {
			time.Sleep(sleep)
		}
	}
	return n, err
}
