sudo apt install golang-go

cat << 'EOF' > serverInfoV1.go
package main

import (
    "bufio"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"
    "os/exec"
    "strconv"
    "strings"
    "syscall"
    "time"
)

type SystemInfo struct {
    IPs              []string `json:"ips"`
    TotalRAM         uint64   `json:"total_ram_bytes"`
    UsedRAM          uint64   `json:"used_ram_bytes"`
    CPUUsage         float64  `json:"cpu_usage_percent"`
    CPUCoreCount     int      `json:"cpu_core_count"`
    ReceivedBytes    uint64   `json:"received_bytes"`
    TransmittedBytes uint64   `json:"transmitted_bytes"`
}

func getRAMInfo() (uint64, uint64, error) {
    var stat syscall.Sysinfo_t
    err := syscall.Sysinfo(&stat)
    if err != nil {
        return 0, 0, err
    }

    totalRamBytes := stat.Totalram * uint64(stat.Unit)
    usedRamBytes := (stat.Totalram - stat.Freeram) * uint64(stat.Unit)
    return totalRamBytes, usedRamBytes, nil
}

func getCPUCoreCount() (int, error) {
    file, err := os.Open("/proc/cpuinfo")
    if err != nil {
        return 0, err
    }
    defer file.Close()

    coreCount := 0
    scanner := bufio.NewScanner(file)
    for scanner.Scan() {
        if strings.HasPrefix(scanner.Text(), "processor") {
            coreCount++
        }
    }

    if err := scanner.Err(); err != nil {
        return 0, err
    }

    return coreCount, nil
}

func getCPUUsage() (float64, error) {
    idleTime1, totalTime1, err := readCPUStat()
    if err != nil {
        return 0, err
    }

    time.Sleep(500 * time.Millisecond)

    idleTime2, totalTime2, err := readCPUStat()
    if err != nil {
        return 0, err
    }

    idleDelta := idleTime2 - idleTime1
    totalDelta := totalTime2 - totalTime1

    cpuUsage := 100.0 * (1.0 - float64(idleDelta)/float64(totalDelta))
    return cpuUsage, nil
}

func readCPUStat() (idleTime, totalTime int64, err error) {
    file, err := os.Open("/proc/stat")
    if err != nil {
        return 0, 0, err
    }
    defer file.Close()

    scanner := bufio.NewScanner(file)
    if !scanner.Scan() {
        return 0, 0, fmt.Errorf("failed to read /proc/stat")
    }

    fields := strings.Fields(scanner.Text())
    if len(fields) < 5 {
        return 0, 0, fmt.Errorf("unexpected format in /proc/stat")
    }

    var total int64
    for _, field := range fields[1:] {
        val, err := strconv.ParseInt(field, 10, 64)
        if err != nil {
            return 0, 0, err
        }
        total += val
    }

    idle, err := strconv.ParseInt(fields[4], 10, 64)
    if err != nil {
        return 0, 0, err
    }

    return idle, total, nil
}

func getNetworkTraffic(interfaceName string) (uint64, uint64, error) {
    file, err := os.Open("/proc/net/dev")
    if err != nil {
        return 0, 0, err
    }
    defer file.Close()

    var receivedBytes, transmittedBytes uint64
    scanner := bufio.NewScanner(file)
    for scanner.Scan() {
        line := scanner.Text()
        if strings.Contains(line, interfaceName) {
            fields := strings.Fields(line)
            if len(fields) >= 10 {
                received, err := strconv.ParseUint(fields[1], 10, 64)
                if err != nil {
                    return 0, 0, err
                }
                transmitted, err := strconv.ParseUint(fields[9], 10, 64)
                if err != nil {
                    return 0, 0, err
                }
                receivedBytes = received
                transmittedBytes = transmitted
                break
            }
        }
    }

    if err := scanner.Err(); err != nil {
        return 0, 0, err
    }

    return receivedBytes, transmittedBytes, nil
}


EOF


cat << 'EOF' > /etc/systemd/system/serverInfoV1.service
[Unit]
Description=My Go App

[Service]
ExecStart=/usr/bin/go run /root/serverInfoV1.go

Restart=always
User=root
Group=root
Environment=PATH=/usr/bin:/usr/local/bin
Environment=OTHER_ENV_VARS=any_value

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable serverInfoV1.service
sudo systemctl stop serverInfoV1.service
sudo systemctl start serverInfoV1.service
