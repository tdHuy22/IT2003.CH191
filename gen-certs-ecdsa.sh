#!/bin/bash
set -e
OUTDIR="$(pwd)/certs"
mkdir -p "$OUTDIR"
cd "$OUTDIR"

echo "🔑 Generating ECDSA CA for organization..."

cat > ca_org.cnf <<EOF
[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

openssl ecparam -name secp384r1 -genkey -noout -out ca_org.key
openssl req -new -x509 -days 3650 -key ca_org.key \
  -subj "/C=VN/ST=HCM/L=HCM/O=LabCA/CN=LabCA" \
  -sha256 -out ca_org.crt \
  -config ca_org.cnf -extensions v3_ca

echo "✅ Generated CA cert: ca_org.crt"

# Tạo cert chung cho 3 broker với SAN chứa các IP LAN
echo "Generating shared broker cert with LAN IPs..."
openssl ecparam -name secp256r1 -genkey -noout -out broker.key
openssl req -new -key broker.key -subj "/CN=broker" -out broker.csr

# SAN cho broker bao gồm cả IP LAN
cat > broker_san.cnf <<EOF
[ v3_req ]
subjectAltName = @alt_names
[ alt_names ]
DNS.1 = broker
DNS.2 = mqtt.broker.lab
DNS.3 = mqtt.broker
DNS.4 = broker1
DNS.5 = broker2
DNS.6 = broker3
IP.1 = 127.0.0.1
EOF

openssl x509 -req -in broker.csr -CA ca_org.crt -CAkey ca_org.key -CAcreateserial \
  -out broker.crt -days 825 -sha256 -extfile broker_san.cnf -extensions v3_req

echo "Generating haproxy cert (for TLS re-encryption)..."
openssl ecparam -name secp256r1 -genkey -noout -out haproxy_backend.key
openssl req -new -key haproxy_backend.key -subj "/CN=mqtt.haproxy.lab" -out haproxy_backend.csr

# HAProxy có SAN với IP LAN 10.0.0.10
cat > haproxy_san.cnf <<EOF
[ v3_req ]
subjectAltName = @alt_names
[ alt_names ]
DNS.1 = mqtt.haproxy.lab
DNS.2 = mqtt.haproxy
DNS.3 = haproxy
IP.1 = 127.0.0.1
IP.2 = 192.168.2.100
EOF

openssl x509 -req -in haproxy_backend.csr -CA ca_org.crt -CAkey ca_org.key -CAcreateserial \
  -out haproxy_backend.crt -days 825 -sha256 -extfile haproxy_san.cnf -extensions v3_req

echo "Generating backend certs..."
openssl ecparam -name secp256r1 -genkey -noout -out express.key
openssl req -new -key express.key -subj "/CN=express.lab" -out express.csr
openssl x509 -req -in express.csr -CA ca_org.crt -CAkey ca_org.key -CAcreateserial \
  -out express.crt -days 825 -sha256

echo "🔑 Generating ECDSA CA for clients..."

cat > ca_client.cnf <<EOF
[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

openssl ecparam -name secp384r1 -genkey -noout -out ca_client.key
openssl req -new -x509 -days 3650 -key ca_client.key \
  -subj "/C=VN/ST=HCM/L=HCM/O=IoTCA/CN=IoTCA" \
  -sha256 -out ca_client.crt \
  -config ca_client.cnf -extensions v3_ca

echo "✅ Generated client CA cert: ca_client.crt"

echo "Generating client certs..."
openssl ecparam -name secp256r1 -genkey -noout -out haproxy_frontend.key
openssl req -new -key haproxy_frontend.key -subj "/CN=haproxy_frontend.lab" -out haproxy_frontend.csr
openssl x509 -req -in haproxy_frontend.csr -CA ca_client.crt -CAkey ca_client.key -CAcreateserial \
  -out haproxy_frontend.crt -days 825 -sha256 -extfile haproxy_san.cnf -extensions v3_req

echo "Generating 3 IoT client certs..."
for i in 1 2 3; do
  openssl ecparam -name secp256r1 -genkey -noout -out client${i}.key
  openssl req -new -key client${i}.key -subj "/CN=device-${i}" -out client${i}.csr
  openssl x509 -req -in client${i}.csr -CA ca_client.crt -CAkey ca_client.key -CAcreateserial \
    -out client${i}.crt -days 825 -sha256
  
  mkdir -p client${i}
  cp ca_client.crt client${i}
  mv client${i}.crt client${i}.key client${i}.csr client${i}
done

mkdir -p broker
cp ca_org.crt broker
mv broker.crt broker.key broker.csr broker_san.cnf broker

mkdir -p haproxy_backend
cp ca_org.crt haproxy_backend
cat haproxy_backend.crt haproxy_backend.key >> haproxy_backend.pem
mv haproxy_backend.crt haproxy_backend.key haproxy_backend.csr haproxy_san.cnf haproxy_backend.pem haproxy_backend

mkdir -p express
cp ca_org.crt express
mv express.crt express.key express.csr express

mkdir -p haproxy_frontend
cp ca_client.crt haproxy_frontend
cat haproxy_frontend.crt haproxy_frontend.key >> haproxy_frontend.pem
mv haproxy_frontend.crt haproxy_frontend.key haproxy_frontend.csr haproxy_frontend.pem haproxy_frontend

mkdir -p ca_org ca_client
mv ca_org.crt ca_org.key ca_org.srl ca_org
mv ca_client.crt ca_client.key ca_client.srl ca_client

# echo "Generating AES key..."
# openssl rand -base64 32 > aes_shared.key


echo "All certs generated in $OUTDIR"
ls -l "$OUTDIR"