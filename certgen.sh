#!/bin/sh
# SelfSign Certificate Generate Script for Rancher

PUBIP=`curl -s http://169.254.169.254/latest/meta-data/public-ipv4`
echo $PUBIP
HIP=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
echo $HIP
RNS=cattle-system
DIR=certs

rm -rf $DIR
mkdir $DIR

# Create the conf file
cat > "${DIR}/openssl.cnf" << EOF
[req]
default_bits = 2048
encrypt_key  = no
default_md   = sha256
prompt       = no
utf8         = yes
distinguished_name = req_distinguished_name
req_extensions     = v3_req
[req_distinguished_name]
C = IN
ST = WB
L = Kolkata
O = CloudCafe
OU = ITDivision
CN = rancher.$PUBIP.nip.io
[v3_req]
basicConstraints     = CA:FALSE
subjectKeyIdentifier = hash
keyUsage             = digitalSignature, keyEncipherment
extendedKeyUsage     = clientAuth, serverAuth
subjectAltName       = @alt_names
[alt_names]
DNS.1 = *.$RNS.svc.cluster.local
DNS.2 = rancher.$PUBIP.nip.io
DNS.3 = rancher.$HIP.nip.io
DNS.4 = localhost
IP = 127.0.0.1
EOF

#Generate CA Certificate

#Generate private Key
openssl genrsa -out "${DIR}/ca.key" 2048

#Generate CA CRT
openssl req -new -x509 -days 3650 -key "${DIR}/ca.key" -out "${DIR}/ca.crt" -subj "/C=IN/ST=WB/L=Kolkata/O=CloudCafe/CN=cluster.local"

#Generate CA CSR
openssl req -new -sha256 -key "${DIR}/ca.key" -out "${DIR}/ca.csr" -subj "/C=IN/ST=WB/L=Kolkata/O=CloudCafe/CN=cluster.local"

#Generate CA Certificate (10 years)
openssl x509 -signkey "${DIR}/ca.key" -in "${DIR}/ca.csr" -req -days 3650 -out "${DIR}/rootca.pem"

#--------------------------------------------------------------------------------------------------------------------#

#Generate Intermediary CA Certificate

#Generate private Key
openssl genrsa -out "${DIR}/intermca.key" 2048

#Create Intermediary CA CSR
openssl req -new -sha256 -key "${DIR}/intermca.key" -out "${DIR}/intermca.csr" -subj "/C=IN/ST=WB/L=Kolkata/O=CloudCafe/CN=cluster.local"

#Generate Server Certificate (10 years)
openssl x509 -req -in "${DIR}/intermca.csr" -CA "${DIR}/rootca.pem" -CAkey "${DIR}/ca.key" -CAcreateserial -out "${DIR}/intermca.pem" -days 3650 -sha256

#----------------------------------------------------------------------------------------------------------------------#

#Generate Listener/Server Certificate signed by CA

# Generate the private key for the server.
openssl genrsa -out "${DIR}/server.key" 2048

# Generate a CSR using the configuration and the key just generated.
# We will give this CSR to our CA to sign.
openssl req \
  -new -key "${DIR}/server.key" \
  -out "${DIR}/server.csr" \
  -config "${DIR}/openssl.cnf"

# Sign the CSR with our CA. This will generate a new certificate that is signed by our CA.
openssl x509 \
  -req \
  -days 120 \
  -in "${DIR}/server.csr" \
  -CA "${DIR}/rootca.pem" \
  -CAkey "${DIR}/ca.key" \
  -CAcreateserial \
  -extensions v3_req \
  -extfile "${DIR}/openssl.cnf" \
  -out "${DIR}/server.crt"

# (Optional) Verify the certificate.
openssl x509 -in "${DIR}/server.crt" -noout -text

# View All Certificate
echo ""

echo "CA Certificate"
echo "--------------"
echo ""
openssl x509 -text -noout -in "${DIR}/ca.crt"

echo ""

echo "Server/Listerner Certificate"
echo "---------------------"
echo ""
openssl x509 -text -noout -in "${DIR}/server.crt"

# Create Full Chain
cat "${DIR}/server.crt" "${DIR}/intermca.pem" "${DIR}/rootca.pem" > "${DIR}/server.pem"

# Preparing for Rancher Only
cp "${DIR}/rootca.pem" "${DIR}/cacerts.pem"
cp "${DIR}/server.pem" "${DIR}/cert.pem"
cp "${DIR}/server.key" "${DIR}/key.pem"
