package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"strings"

	nmea "github.com/adrianmo/go-nmea"
)

func main() {
	file, err := os.Open("/dev/ttyUSB3")
	if err != nil {
		log.Fatal(err)
	}

	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "$GPRMC") {
			m, err := nmea.Parse(line)
			if err == nil {
				gps := m.(nmea.GPRMC)
				fmt.Printf("Lat: %f, Lng: %f\n", gps.Latitude, gps.Longitude)
			}
		}
	}
}
