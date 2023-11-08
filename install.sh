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
    "net"
)

type SystemInfo struct {
    IPs                  []string `json:"ips"`
    TotalRAM             uint64   `json:"total_ram_bytes"`
    UsedRAM              uint64   `json:"used_ram_bytes"`
    CPUUsage             float64  `json:"cpu_usage_percent"`
    CPUCoreCount         int      `json:"cpu_core_count"`
    ReceivedBytes        uint64   `json:"received_bytes"`
    TransmittedBytes     uint64   `json:"transmitted_bytes"`
    InstantReceivedBytes uint64   `json:"instant_received_bytes"`
    InstantTransmittedBytes uint64 `json:"instant_transmitted_bytes"`
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

func getInstantNetworkTraffic(interfaceName string, sampleDuration time.Duration) (uint64, uint64, error) {
    receivedBytes1, transmittedBytes1, err := getNetworkTraffic(interfaceName)
    if err != nil {
        return 0, 0, err
    }

    time.Sleep(sampleDuration)

    receivedBytes2, transmittedBytes2, err := getNetworkTraffic(interfaceName)
    if err != nil {
        return 0, 0, err
    }

    receivedDelta := receivedBytes2 - receivedBytes1
    transmittedDelta := transmittedBytes2 - transmittedBytes1

    return receivedDelta, transmittedDelta, nil
}

func handler(w http.ResponseWriter, r *http.Request) {
    port := r.URL.Query().Get("port")
    ipAddress := r.URL.Query().Get("ip")
    ipEnterface := "eth0"
    
    // Get a list of all interfaces.
    interfaces, err := net.Interfaces()
    if err != nil {
        fmt.Println(err)
        return
    }

    // Iterate over all interfaces and print their details.
    for _, interf := range interfaces {
        fmt.Printf("Name: %v\n", interf.Name)
        fmt.Printf("Hardware Address: %v\n", interf.HardwareAddr)
        fmt.Printf("Flags: %v\n", interf.Flags)

        // Get all the addresses assigned to this interface.
        addresses, err := interf.Addrs()
        if err != nil {
            fmt.Println(err)
            continue
        }

        for _, addr := range addresses {
             parts := strings.Split(addr.String(), "/")
             ipAddress_ := parts[0]


            if(ipAddress_ == ipAddress){
               fmt.Printf("FIND: %v\n", interf.Name)
               ipEnterface = interf.Name
            }
        }
        fmt.Println()
    }
    // endddd
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

    systemInfo.ReceivedBytes, systemInfo.TransmittedBytes, err = getNetworkTraffic(ipEnterface)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    // اضافه کردن ترافیک شبکه در لحظه
    sampleDuration := 1000 * time.Millisecond
    systemInfo.InstantReceivedBytes, systemInfo.InstantTransmittedBytes, err = getInstantNetworkTraffic(ipEnterface, sampleDuration)
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
