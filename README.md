Inside /csce465-agentsec/hw4

A common frustration I had was that after random commands involving docker, but normally the first time I run a command, my VM freezes up for anywhere from 5 to 10 minutes. In the worst cases I would wait 20 minutes and quit out to restart.

ran setup commands
sudo apt remove -y docker.io docker-compose docker-compose-v2 \
containerd runc 2>/dev/null || true
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF_DOCKER
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF_DOCKER
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"

sudo apt install -y nmap tcpdump tshark netcat-openbsd
sudo add-apt-repository -y ppa:oisf/suricata-stable
sudo apt update
sudo apt install -y suricata
sudo usermod -aG suricata "$USER"

Declined to send packets, then logged out and back in
There was an API error with the permissions when running docker, fixed with consultation with AI and added a new
group docker, which seemed to fix the issue
Unfortunately whenever I open a new terminal window I also have to do newgrp docker

Inside the homework directory, I created the files needed for the lab. These included a Dockerfile, a Docker Compose configuration, a fake secret token, a mock skill script, a Python C2 server, and two HTML pages. One HTML page was a normal webpage, while the other contained the course marker and an injected instruction. The mock skill was designed to start a listener on port 9009 and recognize the exfiltration trigger.

The Docker Compose configuration sets up three containers on a private bridge network called hw4net. The network uses the subnet 172.30.0.0/24 and the bridge interface is named br-hw4. The containers use the following addresses:

agent-node: 172.30.0.10
web-lab: 172.30.0.40
mock-c2: 172.30.0.66
I started the containers using:
docker compose up -d --build
and checked that everything was running with:
docker compose ps

inspected the Docker network to verify the subnet and container IP addresses:
docker network inspect hw4_hw4net

To test the mock skill, I ran:
docker compose exec agent-node sh /app/mock_skill.sh exfiltrate-course-file

checked the C2 container to see whether it had received a file:
docker compose exec mock-c2 ls -lh /data/received.bin

also checked the contents using Python:
docker compose exec mock-c2 python -c "print(open('/data/received.bin','rb').read())"

To compare the files, I used SHA-256:
sha256sum fake_secrets.txt
docker compose exec mock-c2 sha256sum /data/received.bin

For Task 2, I first started the mock skill without an argument so that the listener would remain active:
docker compose exec agent-node sh /app/mock_skill.sh

i left that running and opened another terminal to scan agent-node:
nmap -sT -p 9009 172.30.0.10

The scan showed that TCP port 9009 was open. Nmap identified it as pichat, which is just its service-name guess based on the port number. This confirmed that the mock skill had opened an unexpected network listener.
started a packet capture on the Docker bridge interface:
sudo tcpdump -i br-hw4 -s 0 -w hw4-malicious-new.pcap 'net 172.30.0.0/24'

while the capture was running, I requested the adversarial webpage from agent-node:
docker compose exec agent-node curl http://172.30.0.40:8000/adversarial.html

The capture reported 17 packets captured, 17 packets received by the filter, and 0 packets dropped by the kernel. The resulting file was approximately 2.0 KB.

I checked the HTTP traffic using:
tshark -r hw4-malicious-new.pcap -Y http
This showed a GET request for /adversarial.html from 172.30.0.10 to 172.30.0.40, followed by an HTTP 200 OK response.

To get the timestamps, IP addresses, ports, HTTP methods, and requested URIs, I ran:
tshark -r hw4-malicious-new.pcap \
-T fields \
-e frame.time \
-e ip.src \
-e tcp.srcport \
-e ip.dst \
-e tcp.dstport \
-e http.request.method \
-e http.request.uri

I then identified the TCP stream associated with the adversarial webpage:
tshark -r hw4-malicious-new.pcap \
-Y 'http.request.uri == "/adversarial.html"' \
-T fields -e tcp.stream

This returned stream 0. I reconstructed the conversation using:
tshark -r hw4-malicious-new.pcap -q -z follow,tcp,ascii,0
The reconstructed traffic showed agent-node (172.30.0.10:55262) requesting /adversarial.html from web-lab (172.30.0.40:8000). The server returned HTTP 200 OK and the full HTML page, including the course marker and injected instruction. This gave me actual packet-level evidence of the adversarial webpage being retrieved.

I also created a separate packet capture for normal traffic so I could compare it against the adversarial capture. I started another tcpdump session:
sudo tcpdump -i br-hw4 -s 0 -w hw4-clean.pcap 'net 172.30.0.0/24'

In another terminal, I requested the normal webpage:
docker compose exec agent-node curl http://172.30.0.40:8000/benign.html

Once the request finished, I returned to the tcpdump terminal and did ctrl+c to stop the capture.

I checked that the file was created and inspected its HTTP traffic:
ls -lh hw4-clean.pcap
tshark -r hw4-clean.pcap -Y http
The output showed a GET request for /benign.html from agent-node (172.30.0.10) to web-lab (172.30.0.40), followed by an HTTP 200 OK response

Created firewall.sh and firewall-reset.sh to configure a stateful firewall using the DOCKER-USER chain and the iptables-nft backend.

Loaded bridge filtering so Docker container-to-container traffic would pass through iptables:
sudo modprobe br_netfilter
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1

Configured the firewall to:
Allow established and related connections.
Allow agent-node to connect to web-lab on TCP port 8000.
Log and drop connections from agent-node to mock-c2 on TCP port 8080.
Drop all other new outbound connections from agent-node.
Leave unrelated Docker traffic unchanged.

Applied and checked the firewall:
sudo ./firewall.sh
sudo iptables -L HW4-AGENT-EGRESS -n -v
Verified the five required tests:

Benign webpage fetch: HTTP 200, allowed.

Mock C2 exfiltration: blocked; firewall counters and kernel logs confirmed dropped packets.

Unapproved port 8080 connection: timed out, blocked.

Existing TCP 9009 listener: returned the CSCE465 banner, allowed.

Unrelated Docker traffic: returned HTTP 204, unaffected.

Checked firewall counters and kernel logs:
sudo iptables -L HW4-AGENT-EGRESS -n -v
sudo journalctl -k --no-pager | grep 'HW4-C2-DROP'

