# End-to-end test of Admin statistics: Order -> Payment -> Restaurant -> Delivery -> Admin.
# Needs: docker compose up -d kafka kafka-init mongo, plus order (:9001), restaurant (:9002),
#        payment (:9003), delivery (:9004) AND admin (:9006) services running.
# Best on a clean state (docker compose down -v), because older PENDING deliveries are served first.
param(
    [string]$OrderBase = "http://localhost:9001",
    [string]$RestBase  = "http://localhost:9002",
    [string]$DelBase   = "http://localhost:9004",
    [string]$AdminBase = "http://localhost:9006"
)
$ErrorActionPreference = "Stop"   # stop at the first real error instead of continuing with blank values

function PostJson($url, $obj) { Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body ($obj | ConvertTo-Json -Depth 5) }
function NewOrder($rid, $qty) {
    PostJson "$OrderBase/orders" @{
        customerId = "cust-45"; restaurantId = $rid
        items = @(@{ itemId = "m-1"; name = "Kapana"; qty = $qty; price = 40.0 })
        deliveryAddress = "12 Independence Ave, Windhoek"
    }
}
function OrderStatus($id) { (Invoke-RestMethod "$OrderBase/orders/$id").status }
function DelStatus($id)   { (Invoke-RestMethod "$DelBase/deliveries?orderId=$id").status }
function DelId($id)       { (Invoke-RestMethod "$DelBase/deliveries?orderId=$id").deliveryId }

"--- set up a restaurant with 20 Kapana in stock ---"
$rest = PostJson "$RestBase/restaurants" @{ name = "Kapana Corner"; address = "Katutura, Windhoek"; openTime = "08:00"; closeTime = "22:00" }
$rid = $rest.restaurantId
PostJson "$RestBase/restaurants/$rid/menu" @{ itemId = "m-1"; name = "Kapana"; price = 40.0; stock = 20 } | Out-Null
"restaurant $rid"

$before = Invoke-RestMethod "$AdminBase/stats/deliveries"
"deliveries completed so far (whole platform): $($before.completed)"

"--- place order A (2 x 40 = 80) and order B (3 x 40 = 120) ---"
$a = NewOrder $rid 2
$b = NewOrder $rid 3
Start-Sleep 5
"order A -> $(OrderStatus $a.orderId)   (expect CONFIRMED)"
"order B -> $(OrderStatus $b.orderId)   (expect CONFIRMED)"

"--- cancel order B ---"
Invoke-RestMethod -Method Post -Uri "$OrderBase/orders/$($b.orderId)/cancel" | Out-Null
Start-Sleep 3
"order B -> $(OrderStatus $b.orderId)   (expect CANCELLED)"

"--- kitchen prepares order A, a driver delivers it ---"
Invoke-RestMethod -Method Post -Uri "$RestBase/kitchen/orders/$($a.orderId)/preparing" | Out-Null; Start-Sleep 2
Invoke-RestMethod -Method Post -Uri "$RestBase/kitchen/orders/$($a.orderId)/ready" | Out-Null; Start-Sleep 3
PostJson "$DelBase/drivers" @{ name = "Johannes"; phone = "+264 81 000 0000" } | Out-Null
$delivered = $false
foreach ($i in 1..10) {
    Start-Sleep 1
    if ((DelStatus $a.orderId) -eq "ASSIGNED") { $delivered = $true; break }
}
if ($delivered) {
    Invoke-RestMethod -Method Post -Uri "$DelBase/deliveries/$(DelId $a.orderId)/complete" | Out-Null
    Start-Sleep 4
    "order A -> $(OrderStatus $a.orderId)   (expect DELIVERED)"
} else {
    "delivery for order A was not assigned: older PENDING deliveries are ahead of it in the queue."
    "Run docker compose down -v, restart the services and rerun this test."
}

"--- Admin statistics for this restaurant ---"
$s = Invoke-RestMethod "$AdminBase/stats/restaurants/$rid"
"ordersPlaced      -> $($s.ordersPlaced)   (expect 2)"
"ordersCancelled   -> $($s.ordersCancelled)   (expect 1)"
"ordersDelivered   -> $($s.ordersDelivered)   (expect 1)"
"cancellationRate  -> $($s.cancellationRate)   (expect 0.5)"
"revenue           -> $($s.revenue)   (expect 80)"
"averageOrderValue -> $($s.averageOrderValue)   (expect 80)"
"top item          -> $($s.topItems[0].name) x$($s.topItems[0].qty)   (expect Kapana x2)"

"--- Admin delivery statistics (whole platform) ---"
$after = Invoke-RestMethod "$AdminBase/stats/deliveries"
"completed         -> $($after.completed)   (expect $($before.completed + 1))"
"average minutes   -> $($after.averageMinutes)   fastest $($after.fastestMinutes)   slowest $($after.slowestMinutes)"

"--- overview ---"
Invoke-RestMethod "$AdminBase/stats/overview" | Format-List
