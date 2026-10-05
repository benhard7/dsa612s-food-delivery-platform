# End-to-end test of the whole chain: Order -> Payment -> Restaurant -> Delivery.
# Needs: docker compose up -d kafka kafka-init mongo, plus order (:9001), restaurant (:9002),
#        payment (:9003) AND delivery (:9004) services running.
param(
    [string]$OrderBase = "http://localhost:9001",
    [string]$RestBase  = "http://localhost:9002",
    [string]$DelBase   = "http://localhost:9004"
)
$ErrorActionPreference = "Stop"   # stop at the first real error

function PostJson($url, $obj) { Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body ($obj | ConvertTo-Json -Depth 5) }
function PutJson($url, $obj)  { Invoke-RestMethod -Method Put  -Uri $url -ContentType "application/json" -Body ($obj | ConvertTo-Json -Depth 5) }
function NewOrder($rid, $qty) {
    PostJson "$OrderBase/orders" @{
        customerId = "cust-45"; restaurantId = $rid
        items = @(@{ itemId = "m-1"; name = "Kapana"; qty = $qty; price = 40.0 })
        deliveryAddress = "12 Independence Ave, Windhoek"
    }
}
function OrderStatus($id)    { (Invoke-RestMethod "$OrderBase/orders/$id").status }
function DelStatus($id)      { (Invoke-RestMethod "$DelBase/deliveries?orderId=$id").status }
function DelId($id)          { (Invoke-RestMethod "$DelBase/deliveries?orderId=$id").deliveryId }
function DriverStatus($did)  { (Invoke-RestMethod "$DelBase/drivers/$did").status }
function ReadyOrder($rid) {   # place an order and drive it to READY through the kitchen
    $o = NewOrder $rid 1
    Start-Sleep 5
    Invoke-RestMethod -Method Post -Uri "$RestBase/kitchen/orders/$($o.orderId)/preparing" | Out-Null; Start-Sleep 2
    Invoke-RestMethod -Method Post -Uri "$RestBase/kitchen/orders/$($o.orderId)/ready" | Out-Null; Start-Sleep 3
    $o
}

"--- set up restaurant (stock 20) ---"
$rest = PostJson "$RestBase/restaurants" @{ name = "Kapana Corner"; address = "Katutura, Windhoek"; openTime = "08:00"; closeTime = "22:00" }
$rid = $rest.restaurantId
PostJson "$RestBase/restaurants/$rid/menu" @{ itemId = "m-1"; name = "Kapana"; price = 40.0; stock = 20 } | Out-Null

# Clean slate: earlier test runs leave READY orders / open deliveries behind, and the delivery
# service picks them up (orders.ready is replayed from the start). Clear them out first.
"--- clean slate: clearing leftover deliveries from earlier runs ---"
foreach ($d in @(Invoke-RestMethod "$DelBase/deliveries?status=PENDING")) {
    if ($d.orderId) { try { Invoke-RestMethod -Method Post -Uri "$OrderBase/orders/$($d.orderId)/cancel" | Out-Null } catch { } }
}
Start-Sleep 3
foreach ($d in @(Invoke-RestMethod "$DelBase/deliveries?status=ASSIGNED")) {
    if ($d.deliveryId) { try { Invoke-RestMethod -Method Post -Uri "$DelBase/deliveries/$($d.deliveryId)/complete" | Out-Null } catch { } }
}
Start-Sleep 3

# Make sure nobody is free so the first delivery has to wait
foreach ($d in @(Invoke-RestMethod "$DelBase/drivers?status=AVAILABLE")) {
    if ($d.driverId) { PutJson "$DelBase/drivers/$($d.driverId)/status" @{ status = "OFFLINE" } | Out-Null }
}

"--- order 1 reaches READY while no driver is on shift ---"
$o1 = ReadyOrder $rid
"order    -> $(OrderStatus $o1.orderId)   (expect READY)"
"delivery -> $(DelStatus $o1.orderId)   (expect PENDING)"

"--- a driver comes on shift ---"
$drv = PostJson "$DelBase/drivers" @{ name = "Johannes"; phone = "+264 81 000 0000" }
Start-Sleep 3
"delivery -> $(DelStatus $o1.orderId)   (expect ASSIGNED)"
"order    -> $(OrderStatus $o1.orderId)   (expect OUT_FOR_DELIVERY)"
"driver   -> $(DriverStatus $drv.driverId)   (expect BUSY)"

"--- driver position + drop-off ---"
$did = DelId $o1.orderId
$loc = PutJson "$DelBase/deliveries/$did/location" @{ lat = -22.5609; lng = 17.0658 }
"location -> $($loc.lat), $($loc.lng)"
$done = Invoke-RestMethod -Method Post -Uri "$DelBase/deliveries/$did/complete"
Start-Sleep 3
"delivery -> $($done.status) after $($done.durationMinutes) min   (expect COMPLETED)"
"order    -> $(OrderStatus $o1.orderId)   (expect DELIVERED)"
"driver   -> $(DriverStatus $drv.driverId)   (expect AVAILABLE)"

"--- order 2 is cancelled while its delivery is waiting ---"
PutJson "$DelBase/drivers/$($drv.driverId)/status" @{ status = "OFFLINE" } | Out-Null
$o2 = ReadyOrder $rid
"delivery -> $(DelStatus $o2.orderId)   (expect PENDING)"
Invoke-RestMethod -Method Post -Uri "$OrderBase/orders/$($o2.orderId)/cancel" | Out-Null
Start-Sleep 3
"order    -> $(OrderStatus $o2.orderId)   (expect CANCELLED)"
"delivery -> $(DelStatus $o2.orderId)   (expect CANCELLED)"
