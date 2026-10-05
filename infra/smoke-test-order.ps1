# PowerShell version of smoke-test-order.sh
# Needs: docker compose up -d kafka kafka-init mongo  AND  order-service running (bal run) on :9001
param([string]$Base = "http://localhost:9001")

function Pub($topic, $key, $obj) {
    $json = $obj | ConvertTo-Json -Compress -Depth 5
    "$key|$json" | docker exec -i kafka /opt/kafka/bin/kafka-console-producer.sh `
        --bootstrap-server localhost:9092 --topic $topic `
        --property parse.key=true --property "key.separator=|" | Out-Null
}
function Status($id) { (Invoke-RestMethod "$Base/orders/$id").status }

$body = @{
    customerId = "cust-45"; restaurantId = "rest-7"
    items = @(@{ itemId = "m-1"; name = "Kapana"; qty = 2; price = 40.0 })
    deliveryAddress = "12 Independence Ave, Windhoek"
} | ConvertTo-Json -Depth 5
$order = Invoke-RestMethod -Method Post -Uri "$Base/orders" -ContentType "application/json" -Body $body
$id = $order.orderId
"created $id -> $(Status $id)   (expect CREATED)"

Pub "payments.completed" $id @{ orderId = $id; paymentId = "pay-1"; amount = 80.0; status = "COMPLETED" }; Start-Sleep 2
"after payment   -> $(Status $id)   (expect CONFIRMED)"
Pub "orders.status.updated" $id @{ orderId = $id; restaurantId = "rest-7"; status = "PREPARING" }; Start-Sleep 2
"kitchen         -> $(Status $id)   (expect PREPARING)"
Pub "orders.status.updated" $id @{ orderId = $id; restaurantId = "rest-7"; status = "READY" }; Start-Sleep 2
"kitchen         -> $(Status $id)   (expect READY)"
Pub "delivery.assigned" $id @{ orderId = $id; deliveryId = "del-1"; driverId = "drv-2" }; Start-Sleep 2
"driver          -> $(Status $id)   (expect OUT_FOR_DELIVERY)"
Pub "delivery.completed" $id @{ orderId = $id; deliveryId = "del-1"; driverId = "drv-2"; durationMinutes = 22 }; Start-Sleep 2
"delivered       -> $(Status $id)   (expect DELIVERED)"

""; "history:"; Invoke-RestMethod "$Base/orders/$id/history" | Format-Table fromStatus, toStatus, reason

try {
    Invoke-RestMethod -Method Post -Uri "$Base/orders/$id/cancel" | Out-Null
    "cancel after delivery -> unexpectedly succeeded"
} catch {
    "cancel after delivery -> HTTP $($_.Exception.Response.StatusCode.value__)   (expect 409)"
}
