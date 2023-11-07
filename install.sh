sudo apt install golang-go

cat << 'EOF' > serverInfoV1.go
package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os/exec"
    "strconv"
    "strings"
)

// تعریف ساختار برای فرمت خروجی JSON
type IPList struct {
    IPs []string `json:"ips"`
}

func handler(w http.ResponseWriter, r *http.Request) {
    port := r.URL.Query().Get("port")

    // اعتبارسنجی ساده برای پورت
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

    // تبدیل خروجی به رشته و سپس تقسیم آن به خطوط
    outputLines := strings.Split(string(out), "\n")

    // ایجاد یک نمونه از ساختار IPList
    ipList := IPList{}

    // انتخاب فقط خطوط غیر خالی و ذخیره آنها در ساختار IPList
    for _, line := range outputLines {
        if line != "" {
            ipList.IPs = append(ipList.IPs, line)
        }
    }

    // فرمت به JSON
    jsonOutput, err := json.Marshal(ipList)
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
