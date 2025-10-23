#!/bin/bash
set -e
OUTDIR="$(pwd)/certs"
mkdir -p "$OUTDIR"
cd "$OUTDIR"

# Tạo Root CA
echo "🔑 Generating ECDSA Root CA..."
cat > root_ca.cnf <<EOF
[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

openssl ecparam -name prime256v1 -genkey -noout -out root_ca.key
openssl req -new -x509 -days 7300 -key root_ca.key \
  -subj "/C=VN/ST=HCM/L=HCM/O=RootCA/CN=RootCA" \
  -sha256 -out root_ca.crt \
  -config root_ca.cnf -extensions v3_ca

echo "✅ Generated Root CA cert: root_ca.crt"

# Tạo Intermediate CA cho tổ chức (ca_org.crt)
echo "🔑 Generating ECDSA Intermediate CA for organization..."
cat > ca_org.cnf <<EOF
[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

openssl ecparam -name prime256v1 -genkey -noout -out ca_org.key
openssl req -new -key ca_org.key -subj "/C=VN/ST=HCM/L=HCM/O=LabCA/CN=LabCA" -out ca_org.csr
openssl x509 -req -in ca_org.csr -CA root_ca.crt -CAkey root_ca.key -CAcreateserial \
  -out ca_org.crt -days 3650 -sha256 -extfile ca_org.cnf -extensions v3_ca

echo "✅ Generated Intermediate CA cert: ca_org.crt"

# Tạo cert chung cho 3 broker với SAN chứa các IP LAN
echo "Generating shared broker cert with LAN IPs..."
openssl ecparam -name prime256v1 -genkey -noout -out broker.key
openssl req -new -key broker.key -subj "/CN=broker" -out broker.csr

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
openssl ecparam -name prime256v1 -genkey -noout -out haproxy_backend.key
openssl req -new -key haproxy_backend.key -subj "/CN=mqtt.haproxy.lab" -out haproxy_backend.csr

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
openssl ecparam -name prime256v1 -genkey -noout -out express.key
openssl req -new -key express.key -subj "/CN=express.lab" -out express.csr
openssl x509 -req -in express.csr -CA ca_org.crt -CAkey ca_org.key -CAcreateserial \
  -out express.crt -days 825 -sha256

# Tạo Intermediate CA cho client (ca_client.crt)
echo "🔑 Generating ECDSA Intermediate CA for clients..."
cat > ca_client.cnf <<EOF
[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

openssl ecparam -name prime256v1 -genkey -noout -out ca_client.key
openssl req -new -key ca_client.key -subj "/C=VN/ST=HCM/L=HCM/O=IoTCA/CN=IoTCA" -out ca_client.csr
openssl x509 -req -in ca_client.csr -CA root_ca.crt -CAkey root_ca.key -CAcreateserial \
  -out ca_client.crt -days 3650 -sha256 -extfile ca_client.cnf -extensions v3_ca

echo "✅ Generated Intermediate CA cert: ca_client.crt"

echo "Generating client certs..."
openssl ecparam -name prime256v1 -genkey -noout -out haproxy_frontend.key
openssl req -new -key haproxy_frontend.key -subj "/CN=haproxy_frontend.lab" -out haproxy_frontend.csr
openssl x509 -req -in haproxy_frontend.csr -CA ca_client.crt -CAkey ca_client.key -CAcreateserial \
  -out haproxy_frontend.crt -days 825 -sha256 -extfile haproxy_san.cnf -extensions v3_req

echo "Generating 3 IoT client certs..."
for i in 1 2 3; do
  openssl ecparam -name prime256v1 -genkey -noout -out client${i}.key
  openssl req -new -key client${i}.key -subj "/CN=device-${i}" -out client${i}.csr
  openssl x509 -req -in client${i}.csr -CA ca_client.crt -CAkey ca_client.key -CAcreateserial \
    -out client${i}.crt -days 825 -sha256
  
  mkdir -p client${i}
  # cp ca_client.crt client${i}
  mv client${i}.crt client${i}.key client${i}.csr client${i}
  cat ca_client.crt root_ca.crt > client${i}/ca_bundle.crt
done

# Tạo chuỗi CA (ca_bundle.crt) cho các thành phần
echo "🔑 Generating CA bundles..."

mkdir -p broker
cat ca_org.crt root_ca.crt > broker/ca_bundle.crt
mv broker.crt broker.key broker.csr broker_san.cnf broker

mkdir -p haproxy_backend
cat ca_org.crt root_ca.crt > haproxy_backend/ca_bundle.crt
cat haproxy_backend.crt haproxy_backend.key >> haproxy_backend.pem
mv haproxy_backend.crt haproxy_backend.key haproxy_backend.csr haproxy_san.cnf haproxy_backend.pem haproxy_backend

mkdir -p express
cat ca_org.crt root_ca.crt > express/ca_bundle.crt
mv express.crt express.key express.csr express

mkdir -p haproxy_frontend
cat ca_client.crt root_ca.crt > haproxy_frontend/ca_bundle.crt
cat haproxy_frontend.crt haproxy_frontend.key >> haproxy_frontend.pem
mv haproxy_frontend.crt haproxy_frontend.key haproxy_frontend.csr haproxy_frontend.pem haproxy_frontend

mkdir -p ca_org ca_client root_ca
mv ca_org.crt ca_org.key ca_org.srl ca_org
mv ca_client.crt ca_client.key ca_client.srl ca_client
mv root_ca.crt root_ca.key root_ca.srl root_ca

# echo "Generating AES key..."
# openssl rand -base64 32 > aes_shared.key

echo "All certs generated in $OUTDIR"
ls -l "$OUTDIR"