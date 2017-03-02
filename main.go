package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"log"
	"os"
	"strings"

	"net/http"

	nmea "github.com/adrianmo/go-nmea"
)

type latLng struct {
	Lat float64
	Lng float64
}

var coordsChannel = make(chan latLng)

// Encode coords to json and send to backend
func send() {
	for coords := range coordsChannel {
		b := new(bytes.Buffer)
		json.NewEncoder(b).Encode(coords)
		http.Post("https://rokkacar.fi/coords/put", "application/json; charset=utf-8", b)
	}
}

func main() {
	// getting port to read GPS coords from
	port := "/dev/ttyUSB3"
	if len(os.Args) > 1 {
		port = os.Args[1]
	}

	file, err := os.Open(port)
	if err != nil {
		log.Fatal(err)
	}

	defer file.Close()

	go send()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "$GPRMC") {
			m, err := nmea.Parse(line)
			if err == nil {
				gps := m.(nmea.GPRMC)

				coordsChannel <- latLng{Lat: float64(gps.Latitude), Lng: float64(gps.Longitude)}
			}
		}
	}
}
