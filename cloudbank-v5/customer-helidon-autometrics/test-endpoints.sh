#!/bin/bash

# Base URL for the Customer Helidon Service
BASE_URL="http://localhost:8080/api/v1/customer"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Testing Customer Helidon Endpoints at $BASE_URL"
echo "------------------------------------------------"

# 1. Create a Customer
echo -e "\n1. Creating a new customer..."
CREATE_PAYLOAD='{"customerId": "test-user-001", "customerName": "Test User", "customerEmail": "test@example.com", "customerOtherDetails": "Initial Details"}'
echo "Payload: $CREATE_PAYLOAD"

curl -s -X POST "$BASE_URL" \
     -H "Content-Type: application/json" \
     -d "$CREATE_PAYLOAD" -v

echo -e "\n(Check status code above - expects 201 Created)"

# 2. Get All Customers
echo -e "\n2. Getting all customers..."
curl -s -X GET "$BASE_URL" | python3 -m json.tool

# 3. Get Customer by ID
echo -e "\n3. Getting customer by ID (test-user-001)..."
curl -s -X GET "$BASE_URL/test-user-001" | python3 -m json.tool

# 4. Get Customer by Name
echo -e "\n4. Getting customer by Name (Test)..."
curl -s -X GET "$BASE_URL/name/Test" | python3 -m json.tool

# 5. Get Customer by Email
echo -e "\n5. Getting customer by Email (test@example.com)..."
curl -s -X GET "$BASE_URL/byemail/test@example.com" | python3 -m json.tool

# 6. Update Customer
echo -e "\n6. Updating customer..."
UPDATE_PAYLOAD='{"customerId": "test-user-001", "customerName": "Test User Updated", "customerEmail": "updated@example.com", "customerOtherDetails": "Updated Details"}'
echo "Payload: $UPDATE_PAYLOAD"

curl -s -X PUT "$BASE_URL/test-user-001" \
     -H "Content-Type: application/json" \
     -d "$UPDATE_PAYLOAD" | python3 -m json.tool

# 7. Verify Update
echo -e "\n7. Verifying update (Get by ID)..."
curl -s -X GET "$BASE_URL/test-user-001" | python3 -m json.tool

# 8. Apply for Loan (Expect 418 I'm a teapot)
echo -e "\n8. Applying for loan (amount 5000)..."
curl -s -X POST "$BASE_URL/applyLoan/5000" -v 2>&1 | grep "< HTTP"

# 9. Delete Customer
echo -e "\n9. Deleting customer..."
curl -s -X DELETE "$BASE_URL/test-user-001" -v

echo -e "\n(Check status code above - expects 204 No Content)"

# 10. Verify Deletion
echo -e "\n10. Verifying deletion (Get by ID - Expect 404)..."
curl -s -X GET "$BASE_URL/test-user-001" -v 2>&1 | grep "< HTTP"

echo -e "\n${GREEN}Test Sequence Complete${NC}"
