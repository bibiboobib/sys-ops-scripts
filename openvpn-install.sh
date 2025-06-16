#!/bin/sh
# POSIX-compliant OpenVPN server installer for Linux and Unix systems
# Adapted from https://github.com/angristan/openvpn-install
# Supports Debian, Ubuntu, CentOS, Fedora, Arch, Rocky, Alma, Oracle, Amazon Linux, FreeBSD

# Exit on error
set -e

# Check if running as root
is_root() {
    if [ "$(id -u)" -ne 0 ]; then
        return 1
    fi
}

# Check if TUN device is available
tun_available() {
    if [ ! -e /dev/net/tun ]; then
        return 1
    fi
}

# Detect operating system
check_os() {
    OS=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|raspbian)
                OS="debian"
                ;;
            fedora)
                OS="fedora"
                ;;
            centos|rocky|almalinux)
                OS="centos"
                ;;
            ol)
                OS="oracle"
                ;;
            amzn)
                OS="amzn"
                ;;
            arch)
                OS="arch"
                ;;
            *)
                OS="unknown"
                ;;
        esac
    elif [ -f /etc/arch-release ]; then
        OS="arch"
    elif uname -s | grep -q FreeBSD; then
        OS="freebsd"
    else
        echo "Unsupported OS. Supported: Debian, Ubuntu, Fedora, CentOS, Rocky, Alma, Oracle, Amazon Linux, Arch, FreeBSD."
        exit 1
    fi
}

# Initial checks
initial_check() {
    if ! is_root; then
        echo "This script must be run as root."
        exit 1
    fi
    if ! tun_available; then
        echo "TUN device is not available."
        exit 1
    fi
    check_os
}

# Install package manager dependencies
install_deps() {
    case "$OS" in
        debian)
            apt-get update
            apt-get install -y openvpn iptables openssl wget ca-certificates curl
            ;;
        fedora)
            dnf install -y openvpn iptables openssl wget ca-certificates curl
            ;;
        centos|oracle)
            yum install -y epel-release
            yum install -y openvpn iptables openssl wget ca-certificates curl
            ;;
        amzn)
            yum install -y openvpn iptables openssl wget ca-certificates curl
            ;;
        arch)
            pacman -Syu --noconfirm openvpn iptables openssl wget ca-certificates curl
            ;;
        freebsd)
            pkg install -y openvpn iptables openssl wget ca-certificates curl
            ;;
        *)
            echo "Cannot install dependencies for unknown OS."
            exit 1
            ;;
    esac
}

# Install Unbound (DNS resolver)
install_unbound() {
    if [ ! -f /etc/unbound/unbound.conf ]; then
        case "$OS" in
            debian)
                apt-get install -y unbound
                ;;
            fedora)
                dnf install -y unbound
                ;;
            centos|oracle|amzn)
                yum install -y unbound
                ;;
            arch)
                pacman -Syu --noconfirm unbound
                ;;
            freebsd)
                pkg install -y unbound
                ;;
            *)
                echo "Unbound installation not supported on this OS."
                return 1
                ;;
        esac

        # Basic Unbound configuration
        echo 'interface: 10.8.0.1
access-control: 10.8.0.1/24 allow
hide-identity: yes
hide-version: yes
use-caps-for-id: yes
prefetch: yes' >> /etc/unbound/unbound.conf

        if [ "$IPV6_SUPPORT" = "y" ]; then
            echo 'interface: fd42:42:42:42::1
access-control: fd42:42:42:42::/112 allow' >> /etc/unbound/unbound.conf
        fi

        # Enable and start Unbound
        if command -v systemctl >/dev/null 2>&1; then
            systemctl enable unbound
            systemctl restart unbound
        elif command -v service >/dev/null 2>&1; then
            service unbound enable || true
            service unbound restart || true
        elif [ "$OS" = "freebsd" ]; then
            sysrc unbound_enable="YES"
            service unbound restart
        fi
    fi
}

# Resolve public IP
resolve_public_ip() {
    PUBLIC_IP=""
    CURL_FLAGS=""
    if [ "$IPV6_SUPPORT" = "y" ]; then
        CURL_FLAGS=""
    else
        CURL_FLAGS="-4"
    fi

    PUBLIC_IP=$(curl -f -m 5 -s $CURL_FLAGS https://api.seeip.org 2>/dev/null) || true
    [ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(curl -f -m 5 -s $CURL_FLAGS https://ifconfig.me 2>/dev/null) || true
    [ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(curl -f -m 5 -s $CURL_FLAGS https://api.ipify.org 2>/dev/null) || true

    if [ -z "$PUBLIC_IP" ]; then
        echo "Could not resolve public IP."
        exit 1
    fi
    echo "$PUBLIC_IP"
}

# Install OpenVPN
install_openvpn() {
    # Default settings for auto-install
    if [ "$AUTO_INSTALL" = "y" ]; then
        APPROVE_INSTALL="y"
        APPROVE_IP="y"
        IPV6_SUPPORT="n"
        PORT="1194"
        PROTOCOL="udp"
        DNS="1"
        COMPRESSION_ENABLED="n"
        CUSTOMIZE_ENC="n"
        CLIENT="client"
        PASS="1"
        ENDPOINT=$(resolve_public_ip)
    else
        # Ask user for configuration
        echo "Welcome to the OpenVPN installer!"
        echo "I need to know the IPv4 address for OpenVPN."
        IP=$(ifconfig | grep 'inet ' | awk '{print $2}' | head -1)
        if [ -z "$IP" ]; then
            IP=$(ifconfig | grep 'inet6 ' | awk '{print $2}' | head -1)
        fi
        printf "IP address [%s]: " "$IP"
        read IP_INPUT
        [ -n "$IP_INPUT" ] && IP="$IP_INPUT"

        if echo "$IP" | grep -E '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
            echo "Server is behind NAT. Enter public IP or hostname."
            ENDPOINT=$(resolve_public_ip)
            printf "Public IP or hostname [%s]: " "$ENDPOINT"
            read ENDPOINT_INPUT
            [ -n "$ENDPOINT_INPUT" ] && ENDPOINT="$ENDPOINT_INPUT"
        fi

        echo "Enable IPv6 support? [y/n]: "
        read IPV6_SUPPORT
        case "$IPV6_SUPPORT" in
            [Yy]*) IPV6_SUPPORT="y" ;;
            *) IPV6_SUPPORT="n" ;;
        esac

        echo "Port for OpenVPN [1194]: "
        read PORT
        [ -z "$PORT" ] && PORT="1194"

        echo "Protocol (1: UDP, 2: TCP) [1]: "
        read PROTOCOL_CHOICE
        case "$PROTOCOL_CHOICE" in
            2) PROTOCOL="tcp" ;;
            *) PROTOCOL="udp" ;;
        esac

        echo "DNS resolvers (1: System, 2: Unbound, 3: Cloudflare) [1]: "
        read DNS
        [ -z "$DNS" ] && DNS="1"
    fi

    # Install dependencies
    install_deps

    # Find network interface
    NIC=$(route | grep default | awk '{print $8}' | head -1)
    if [ -z "$NIC" ] && [ "$IPV6_SUPPORT" = "y" ]; then
        NIC=$(route -A inet6 | grep default | awk '{print $NF}' | head -1)
    fi
    [ -z "$NIC" ] && echo "Warning: Could not detect network interface."

    # Install OpenVPN if not present
    if [ ! -f /etc/openvpn/server.conf ]; then
        mkdir -p /etc/openvpn
        # Install easy-rsa
        if [ ! -d /etc/openvpn/easy-rsa ]; then
            wget -q -O /tmp/easy-rsa.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.2/EasyRSA-3.1.2.tgz
            mkdir -p /etc/openvpn/easy-rsa
            tar xzf /tmp/easy-rsa.tgz --strip-components=1 -C /etc/openvpn/easy-rsa
            rm /tmp/easy-rsa.tgz
        fi

        # Configure easy-rsa
        cd /etc/openvpn/easy-rsa || exit 1
        ./easyrsa init-pki
        ./easyrsa --batch build-ca nopass
        ./easyrsa --batch build-server-full server nopass
        ./easyrsa gen-crl
        cp pki/ca.crt pki/private/ca.key pki/issued/server.crt pki/private/server.key pki/crl.pem /etc/openvpn
        chmod 644 /etc/openvpn/crl.pem

        # Generate server.conf
        echo "port $PORT
proto $PROTOCOL
dev tun
user nobody
group nobody
persist-key
persist-tun
server 10.8.0.0 255.255.255.0
ca ca.crt
cert server.crt
key server.key
crl-verify crl.pem
cipher AES-128-GCM
tls-server
tls-version-min 1.2
verb 3" > /etc/openvpn/server.conf

        if [ "$DNS" = "2" ]; then
            install_unbound
            echo 'push "dhcp-option DNS 10.8.0.1"' >> /etc/openvpn/server.conf
        else
            echo 'push "dhcp-option DNS 1.1.1.1"' >> /etc/openvpn/server.conf
        fi

        # Enable IP forwarding
        echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf
        sysctl -p /etc/sysctl.d/99-openvpn.conf

        # Configure iptables
        mkdir -p /etc/iptables
        echo "#!/bin/sh
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $NIC -j MASQUERADE
iptables -A INPUT -i tun0 -j ACCEPT
iptables -A FORWARD -i $NIC -o tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o $NIC -j ACCEPT
iptables -A INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" > /etc/iptables/add-openvpn-rules.sh

        echo "#!/bin/sh
iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o $NIC -j MASQUERADE
iptables -D INPUT -i tun0 -j ACCEPT
iptables -D FORWARD -i $NIC -o tun0 -j ACCEPT
iptables -D FORWARD -i tun0 -o $NIC -j ACCEPT
iptables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" > /etc/iptables/rm-openvpn-rules.sh

        chmod +x /etc/iptables/add-openvpn-rules.sh
        chmod +x /etc/iptables/rm-openvpn-rules.sh
        sh /etc/iptables/add-openvpn-rules.sh

        # Enable and start OpenVPN
        if command -v systemctl >/dev/null 2>&1; then
            systemctl enable openvpn@server
            systemctl start openvpn@server
        elif command -v service >/dev/null 2>&1; then
            service openvpn enable || true
            service openvpn start || true
        elif [ "$OS" = "freebsd" ]; then
            sysrc openvpn_enable="YES"
            service openvpn start
        fi
    fi

    # Create client configuration
    new_client
}

# Create new client
new_client() {
    echo "Enter client name (alphanumeric, underscore, dash): "
    read CLIENT
    if ! echo "$CLIENT" | grep -E '^[a-zA-Z0-9_-]+$'; then
        echo "Invalid client name."
        exit 1
    fi

    cd /etc/openvpn/easy-rsa || exit 1
    ./easyrsa --batch build-client-full "$CLIENT" nopass
    echo "Client $CLIENT added."

    echo "client
proto $PROTOCOL
remote $IP $PORT
dev tun
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-128-GCM
tls-client
tls-version-min 1.2
verb 3
<ca>" > "/root/$CLIENT.ovpn"
    cat /etc/openvpn/ca.crt >> "/root/$CLIENT.ovpn"
    echo "</ca>
<cert>" >> "/root/$CLIENT.ovpn"
    awk '/BEGIN/,/END CERTIFICATE/' "pki/issued/$CLIENT.crt" >> "/root/$CLIENT.ovpn"
    echo "</cert>
<key>" >> "/root/$CLIENT.ovpn"
    cat "pki/private/$CLIENT.key" >> "/root/$CLIENT.ovpn"
    echo "</key>"

    echo "Client configuration saved to /root/$CLIENT.ovpn"
}

# Main
if [ -f /etc/openvpn/server.conf ] && [ "$AUTO_INSTALL" != "y" ]; then
    echo "OpenVPN is already installed. Run script again to add clients."
    exit 0
else
    install_openvpn
fi
