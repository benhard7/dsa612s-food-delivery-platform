# End-to-end test of Order <-> Payment through Kafka.
# Needs: docker compose up -d kafka kafka-init mongo, plus order-service (:9001) AND payment-service (:9003) running.
param([string]$OrderBase = "http://localhost:9001", [string]$PayBase = "http://localhost:9003")

function NewOrder($qty, $price) {
    $body = @{
        customerId = "cust-45"; restaurantId = "rest-7"
        items = @(@{ itemId = "m-1"; name = "Kapana"; qty = $qty; price = $price })
        deliveryAddress = "12 Independence Ave, Windhoek"
    } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Method Post -Uri "$OrderBase/orders" -ContentType "application/json" -Body $body
}
function OrderStatus($id) { (Invoke-RestMethod "$OrderBase/orders/$id").status }
function PayStatus($id)   { (Invoke-RestMethod "$PayBase/payments?orderId=$id").status }

"--- normal order (total 80) ---"
$ok = NewOrder 2 40.0
Start-Sleep 5
"order   -> $(OrderStatus $ok.orderId)   (expect CONFIRMED)"
"payment -> $(PayStatus $ok.orderId)   (expect COMPLETED)"

"--- over-limit order (total 6000) ---"
$big = NewOrder 3 2000.0
Start-Sleep 5
"order   -> $(OrderStatus $big.orderId)   (expect CANCELLED)"
"payment -> $(PayStatus $big.orderId)   (expect FAILED)"

"--- cancel the paid order -> refund ---"
Invoke-RestMethod -Method Post -Uri "$OrderBase/orders/$($ok.orderId)/cancel" | Out-Null
Start-Sleep 4
"order   -> $(OrderStatus $ok.orderId)   (expect CANCELLED)"
"payment -> $(PayStatus $ok.orderId)   (expect REFUNDED)"
