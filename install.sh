sudo apt install golang-go

echo '
package main

import (
    "fmt"
    "log"
    "net/http"
    "os/exec"
)

func handler(w http.ResponseWriter, r *http.Request) {
    cmd := `sudo netstat -anp | grep ':8080' | grep ESTABLISHED | awk '{print "{\"ip\": \""$5"\"}"}' | jq -s .`
    out, err := exec.Command("bash", "-c", cmd).Output()
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    fmt.Fprintf(w, "%s", out)
}

func main() {
    http.HandleFunc("/netstat", handler) 

    fmt.Println("Server is running on port 8891...")
    log.Fatal(http.ListenAndServe(":8891", nil)) 
}
' > serverInfoV1.go


echo '
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
' > /etc/systemd/system/serverInfoV1.service

sudo systemctl enable serverInfoV1.service
sudo systemctl stop serverInfoV1.service
sudo systemctl start serverInfoV1.service
