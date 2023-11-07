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
    IPs          []string `json:"ips"`
    TotalRAM     uint64   `json:"total_ram_bytes"`
    UsedRAM      uint64   `json:"used_ram_bytes"`
    CPUUsage     float64  `json:"cpu_usage_percent"`
    CPUCoreCount int      `json:"cpu_core_count"`
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

func handler(w http.ResponseWriter, r *http.Request) {
    port := r.URL.Query().Get("port")

    if _, err := strconv.Atoi(port); err != nil {
        http.Error(w, "Invalid port", http.StatusBadRequest)
        return
    }

    cmdString := fmt.Sprintf(`sudo netstat -anp | grep ':%s' | grep ESTABLISHED | awk '{print $5}' | cut -d':' -f1 | sort | uniq`, port)
    out, err := exec.Command("bash", "-c", cmdString).Output()
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    outputLines := strings.Split(string(out), "\n")

    systemInfo := SystemInfo{}

    for _, line := range outputLines {
        if line != "" {
            systemInfo.IPs = append(systemInfo.IPs, line)
        }
    }

    systemInfo.TotalRAM, systemInfo.UsedRAM, err = getRAMInfo()
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    systemInfo.CPUCoreCount, err = getCPUCoreCount()
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    systemInfo.CPUUsage, err = getCPUUsage()
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    jsonOutput, err := json.Marshal(systemInfo)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    fmt.Fprintf(w, "%s", jsonOutput)
}

func main() {
    http.HandleFunc("/netstat", handler)

    fmt.Println("Server is running on port 8891...")
    log.Fatal(http.ListenAndServe(":8891", nil))
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
