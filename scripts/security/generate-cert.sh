#!/bin/bash
#==============================================================================
# Flatnet Self-Signed Certificate Generator
# Phase 4, Stage 3: Security
#
# Generates self-signed TLS certificates for development and internal use.
# For production, use certificates from a trusted CA.
#==============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_OUTPUT_DIR="/mnt/f/flatnet/config/ssl"

# Certificate defaults
DEFAULT_CN="flatnet.local"
DEFAULT_ORG="Flatnet"
DEFAULT_COUNTRY="JP"
DEFAULT_DAYS=365
# RSA key size: 2048 is minimum for security, 4096 recommended for long-term
DEFAULT_KEY_SIZE=2048
MINIMUM_KEY_SIZE=2048

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#------------------------------------------------------------------------------
# Functions
#------------------------------------------------------------------------------

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generate self-signed TLS certificates for Flatnet.

Options:
    -o, --output DIR     Output directory (default: ${DEFAULT_OUTPUT_DIR})
    -n, --cn NAME        Common Name (default: ${DEFAULT_CN})
    -d, --days DAYS      Validity period in days (default: ${DEFAULT_DAYS})
    -k, --key-size SIZE  RSA key size in bits (default: ${DEFAULT_KEY_SIZE}, min: ${MINIMUM_KEY_SIZE})
    --san NAMES          Subject Alternative Names (comma-separated)
    --ca                 Generate CA certificate and server certificate
    -f, --force          Overwrite existing certificates
    -h, --help           Show this help message

Examples:
    # Generate basic self-signed certificate
    $(basename "$0")

    # Generate with custom settings
    $(basename "$0") -n myserver.local -d 730 -o /path/to/ssl

    # Generate with SANs
    $(basename "$0") --san "localhost,192.168.1.100,*.flatnet.local"

    # Generate CA and server certificate
    $(basename "$0") --ca
EOF
    exit 0
}

check_openssl() {
    if ! command -v openssl &> /dev/null; then
        echo -e "${RED}Error: OpenSSL is not installed.${NC}"
        echo "Install with: sudo apt-get install openssl"
        exit 1
    fi
}

validate_key_size() {
    local size="$1"
    if ! [[ "$size" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Key size must be a number.${NC}"
        exit 1
    fi
    if [ "$size" -lt "$MINIMUM_KEY_SIZE" ]; then
        echo -e "${RED}Error: Key size must be at least ${MINIMUM_KEY_SIZE} bits.${NC}"
        echo "Recommended: 2048 (acceptable) or 4096 (stronger)"
        exit 1
    fi
    if [ "$size" -gt 8192 ]; then
        echo -e "${YELLOW}Warning: Key sizes above 4096 bits may cause performance issues.${NC}"
    fi
}

generate_simple_cert() {
    local output_dir="$1"
    local cn="$2"
    local days="$3"
    local key_size="$4"

    echo -e "${BLUE}Generating self-signed certificate...${NC}"
    echo ""
    echo "Common Name: ${cn}"
    echo "Validity: ${days} days"
    echo "Key Size: ${key_size} bits"
    echo "Output: ${output_dir}"
    echo ""

    openssl req -x509 -nodes -days "${days}" -newkey "rsa:${key_size}" \
        -keyout "${output_dir}/server.key" \
        -out "${output_dir}/server.crt" \
        -subj "/CN=${cn}/O=${DEFAULT_ORG}/C=${DEFAULT_COUNTRY}"

    # Set permissions
    chmod 600 "${output_dir}/server.key"
    chmod 644 "${output_dir}/server.crt"

    echo -e "${GREEN}Certificate generated successfully!${NC}"
}

generate_san_cert() {
    local output_dir="$1"
    local cn="$2"
    local days="$3"
    local key_size="$4"
    local san_list="$5"

    echo -e "${BLUE}Generating certificate with SANs...${NC}"
    echo ""
    echo "Common Name: ${cn}"
    echo "SANs: ${san_list}"
    echo "Validity: ${days} days"
    echo "Key Size: ${key_size} bits"
    echo "Output: ${output_dir}"
    echo ""

    # Create temporary OpenSSL config
    local config_file=$(mktemp /tmp/openssl_XXXXXX.cnf)
    # Cleanup handled by trap in main

    # Build SAN section
    local san_section=""
    local counter=1

    IFS=',' read -ra SAN_ARRAY <<< "$san_list"
    for san in "${SAN_ARRAY[@]}"; do
        san=$(echo "$san" | xargs)  # Trim whitespace
        if [[ "$san" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            san_section+="IP.${counter} = ${san}\n"
        else
            san_section+="DNS.${counter} = ${san}\n"
        fi
        ((counter++))
    done

    cat > "${config_file}" << EOF
[req]
default_bits = ${key_size}
distinguished_name = req_distinguished_name
req_extensions = v3_req
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = ${DEFAULT_COUNTRY}
O = ${DEFAULT_ORG}
CN = ${cn}

[v3_req]
subjectAltName = @alt_names
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
$(echo -e "$san_section")
EOF

    # Generate certificate
    openssl req -x509 -nodes -days "${days}" -newkey "rsa:${key_size}" \
        -keyout "${output_dir}/server.key" \
        -out "${output_dir}/server.crt" \
        -config "${config_file}"

    # Set permissions
    chmod 600 "${output_dir}/server.key"
    chmod 644 "${output_dir}/server.crt"

    echo -e "${GREEN}Certificate with SANs generated successfully!${NC}"
}

generate_ca_and_server() {
    local output_dir="$1"
    local cn="$2"
    local days="$3"
    local key_size="$4"

    echo -e "${BLUE}Generating CA and server certificates...${NC}"
    echo ""

    # Generate CA certificate
    echo "Step 1: Generating CA certificate..."
    openssl req -x509 -nodes -days $((days * 3)) -newkey "rsa:${key_size}" \
        -keyout "${output_dir}/ca.key" \
        -out "${output_dir}/ca.crt" \
        -subj "/CN=Flatnet CA/O=${DEFAULT_ORG}/C=${DEFAULT_COUNTRY}"

    # Generate server private key
    echo "Step 2: Generating server private key..."
    openssl genrsa -out "${output_dir}/server.key" "${key_size}"

    # Generate CSR
    echo "Step 3: Generating certificate signing request..."
    openssl req -new \
        -key "${output_dir}/server.key" \
        -out "${output_dir}/server.csr" \
        -subj "/CN=${cn}/O=${DEFAULT_ORG}/C=${DEFAULT_COUNTRY}"

    # Create extensions file
    local ext_file=$(mktemp /tmp/ext_XXXXXX.cnf)
    # Cleanup handled by trap in main

    cat > "${ext_file}" << EOF
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:${cn},DNS:localhost,IP:127.0.0.1
EOF

    # Sign with CA
    echo "Step 4: Signing server certificate with CA..."
    openssl x509 -req -days "${days}" \
        -in "${output_dir}/server.csr" \
        -CA "${output_dir}/ca.crt" \
        -CAkey "${output_dir}/ca.key" \
        -CAcreateserial \
        -out "${output_dir}/server.crt" \
        -extfile "${ext_file}"

    # Clean up CSR
    rm -f "${output_dir}/server.csr"

    # Set permissions
    chmod 600 "${output_dir}/ca.key"
    chmod 644 "${output_dir}/ca.crt"
    chmod 600 "${output_dir}/server.key"
    chmod 644 "${output_dir}/server.crt"

    echo ""
    echo -e "${GREEN}CA and server certificates generated successfully!${NC}"
    echo ""
    echo "To trust the CA on Windows:"
    echo "  Import ${output_dir}/ca.crt to 'Trusted Root Certification Authorities'"
}

display_cert_info() {
    local cert_file="$1"

    echo ""
    echo "Certificate Details:"
    echo "-------------------"
    openssl x509 -noout -subject -issuer -dates -in "${cert_file}" 2>/dev/null || true

    echo ""
    echo "Subject Alternative Names:"
    openssl x509 -noout -ext subjectAltName -in "${cert_file}" 2>/dev/null || echo "(none)"
}

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------

OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
CN="${DEFAULT_CN}"
DAYS="${DEFAULT_DAYS}"
KEY_SIZE="${DEFAULT_KEY_SIZE}"
SAN_LIST=""
CA_MODE=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -n|--cn)
            CN="$2"
            shift 2
            ;;
        -d|--days)
            DAYS="$2"
            shift 2
            ;;
        -k|--key-size)
            KEY_SIZE="$2"
            shift 2
            ;;
        --san)
            SAN_LIST="$2"
            shift 2
            ;;
        --ca)
            CA_MODE=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

# Cleanup function for temporary files
cleanup_temp_files() {
    rm -f /tmp/openssl_*.cnf /tmp/ext_*.cnf 2>/dev/null || true
}
trap cleanup_temp_files EXIT

echo "========================================"
echo "Flatnet Certificate Generator"
echo "========================================"
echo ""

# Check OpenSSL
check_openssl
echo "OpenSSL version: $(openssl version)"
echo ""

# Validate key size
validate_key_size "${KEY_SIZE}"

# Create output directory
if [ ! -d "${OUTPUT_DIR}" ]; then
    echo "Creating directory: ${OUTPUT_DIR}"
    mkdir -p "${OUTPUT_DIR}"
fi

# Check for existing certificates
if [ -f "${OUTPUT_DIR}/server.crt" ] && [ "${FORCE}" != true ]; then
    echo -e "${YELLOW}Warning: Certificate already exists at ${OUTPUT_DIR}/server.crt${NC}"
    echo ""
    echo "Current certificate details:"
    display_cert_info "${OUTPUT_DIR}/server.crt"
    echo ""
    echo "To regenerate, use -f or --force to overwrite existing certificate."
    exit 0
fi

# Generate certificates
if [ "${CA_MODE}" = true ]; then
    generate_ca_and_server "${OUTPUT_DIR}" "${CN}" "${DAYS}" "${KEY_SIZE}"
elif [ -n "${SAN_LIST}" ]; then
    generate_san_cert "${OUTPUT_DIR}" "${CN}" "${DAYS}" "${KEY_SIZE}" "${SAN_LIST}"
else
    generate_simple_cert "${OUTPUT_DIR}" "${CN}" "${DAYS}" "${KEY_SIZE}"
fi

# Display certificate info
display_cert_info "${OUTPUT_DIR}/server.crt"

echo ""
echo "========================================"
echo "Files Generated:"
echo "========================================"
ls -la "${OUTPUT_DIR}"/*.crt "${OUTPUT_DIR}"/*.key 2>/dev/null || true

echo ""
echo -e "${YELLOW}Note: This is a self-signed certificate.${NC}"
echo "Browsers will show security warnings until the certificate is trusted."
echo ""
echo "To use with OpenResty, add to nginx.conf:"
echo "  ssl_certificate ${OUTPUT_DIR}/server.crt;"
echo "  ssl_certificate_key ${OUTPUT_DIR}/server.key;"
