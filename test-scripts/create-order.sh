#!/usr/bin/env bash
# Creates a test order visible to couriers (status: WaitingForCourier).
# Usage: ./create-order.sh [BASE_URL]
# Default BASE_URL: http://localhost:8095

set -euo pipefail

BASE_URL="${1:-http://localhost:8095}"
API="$BASE_URL/api/v1"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${YELLOW}[→]${NC} $*"; }
fail() { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

extract() { echo "$1" | grep -o "\"$2\":\"[^\"]*\"" | head -1 | cut -d'"' -f4; }

# ── 1. Admin login ────────────────────────────────────────────────────────────
info "Logging in as admin..."
LOGIN_RESP=$(curl -sf -X POST "$API/auth/login-generic" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@owndelivery.local","password":"AdminPass123!"}') \
  || fail "Admin login failed. Is the API running at $BASE_URL?"

ADMIN_TOKEN=$(extract "$LOGIN_RESP" "token")
[[ -n "$ADMIN_TOKEN" ]] || fail "Could not extract token from: $LOGIN_RESP"
log "Admin token obtained."
AUTH="Authorization: Bearer $ADMIN_TOKEN"

# ── 2. Create customer ────────────────────────────────────────────────────────
info "Creating test customer..."
TIMESTAMP=$(date +%s)
CUSTOMER_RESP=$(curl -sf -X POST "$API/admin/customers" \
  -H "Content-Type: application/json" \
  -H "$AUTH" \
  -d "{
    \"firstName\": \"Test\",
    \"lastName\": \"Customer\",
    \"email\": \"customer_${TIMESTAMP}@test.local\",
    \"password\": \"CustomerPass123!\",
    \"phoneNumber\": \"+38050${TIMESTAMP: -7}\",
    \"preferredDeliveryAddress\": \"Kyiv, Khreshchatyk 1\"
  }") || fail "Failed to create customer."

CUSTOMER_ID=$(extract "$CUSTOMER_RESP" "id")
[[ -n "$CUSTOMER_ID" ]] || fail "Could not extract customerId from: $CUSTOMER_RESP"
log "Customer created: $CUSTOMER_ID"

# ── 3. Pick existing tariff ───────────────────────────────────────────────────
info "Fetching existing tariff..."
TARIFF_RESP=$(curl -sf "$API/admin/tariffs?skip=0&take=1&isActive=true" \
  -H "$AUTH") || fail "Failed to fetch tariffs."

TARIFF_ID=$(extract "$TARIFF_RESP" "id")
[[ -n "$TARIFF_ID" ]] || fail "No active tariffs found. Create one first."
log "Using tariff: $TARIFF_ID"

# ── 4. Create order ───────────────────────────────────────────────────────────
info "Creating order..."
ORDER_RESP=$(curl -sf -X POST "$API/admin/orders" \
  -H "Content-Type: application/json" \
  -H "$AUTH" \
  -d "{
    \"customerId\": \"$CUSTOMER_ID\",
    \"tariffId\": \"$TARIFF_ID\",
    \"pickupAddress\": {
      \"city\": \"Kyiv\",
      \"street\": \"Khreshchatyk\",
      \"buildingNumber\": \"1\",
      \"postalCode\": \"01001\",
      \"latitude\": 50.4501,
      \"longitude\": 30.5234,
      \"apartmentNumber\": \"12\",
      \"description\": \"Entrance from the yard\"
    },
    \"deliveryAddress\": {
      \"city\": \"Kyiv\",
      \"street\": \"Saksahanskoho\",
      \"buildingNumber\": \"25\",
      \"postalCode\": \"01033\",
      \"latitude\": 50.4389,
      \"longitude\": 30.5155,
      \"apartmentNumber\": \"45\",
      \"description\": \"Call on arrival\"
    },
    \"weight\": 2.5,
    \"dimensions\": {\"width\": 20, \"length\": 30, \"height\": 15},
    \"description\": \"Test package\",
    \"specialInstructions\": \"Do not bend\",
    \"status\": 0
  }") || fail "Failed to create order."

ORDER_ID=$(extract "$ORDER_RESP" "id")
[[ -n "$ORDER_ID" ]] || fail "Could not extract orderId from: $ORDER_RESP"
log "Order created: $ORDER_ID"

# ── 5. Move order to WaitingForCourier ────────────────────────────────────────
info "Setting order status to WaitingForCourier (2)..."
curl -sf -X PATCH "$API/admin/orders/$ORDER_ID/status" \
  -H "Content-Type: application/json" \
  -H "$AUTH" \
  -d '{"newStatus": 2, "reason": "Ready for pickup"}' > /dev/null \
  || fail "Failed to update order status."
log "Order is now visible to couriers."

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Order ready for courier pickup"
echo "  Order ID   : $ORDER_ID"
echo "  Customer ID: $CUSTOMER_ID"
echo "  Tariff ID  : $TARIFF_ID"
echo ""
echo "  Couriers can see it at:"
echo "  GET $API/orders/available"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"