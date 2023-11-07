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
    awkScript := "{print \\\"{\\\\\\\"local_address\\\\\\\": \\\\\\\"\\\"$4\\\"\\\\\\\", \\\\\\\"foreign_address\\\\\\\": \\\\\\\"\\\"$5\\\"\\\\\\\", \\\\\\\"process\\\\\\\": \\\\\\\"\\\"$7\\\"\\\\\\\"}\\\"}"
    cmd := "sudo netstat -anp | grep ':8080' | grep ESTABLISHED | awk '" + awkScript + "' | jq -s ."

    out, err := exec.Command("bash", "-c", cmd).Output()
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    fmt.Fprintf(w, "%s", out)
}

func main() {
    http.HandleFunc("/netstat", handler) 

    fmt.Println("Server is running on port 8899...")
    log.Fatal(http.ListenAndServe(":8899", nil)) 
}
' > serverInfoGoV2.go


echo '
[Unit]
Description=My Go App

[Service]
ExecStart=/usr/bin/go run /root/serverInfoGoV2.go

Restart=always
User=root
Group=root
Environment=PATH=/usr/bin:/usr/local/bin
Environment=OTHER_ENV_VARS=any_value

[Install]
WantedBy=multi-user.target
' > /etc/systemd/system/serverInfoGoV2.service

sudo systemctl enable serverInfoGoV2.service
sudo systemctl stop serverInfoGoV2.service
sudo systemctl start serverInfoGoV2.service
